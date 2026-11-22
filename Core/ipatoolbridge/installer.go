package ipatoolbridge

import (
	"archive/zip"
	"context"
	"crypto/rand"
	"crypto/rsa"
	"crypto/sha1"
	"crypto/tls"
	"crypto/x509"
	"crypto/x509/pkix"
	"encoding/json"
	"encoding/pem"
	"fmt"
	"io"
	"log"
	"math/big"
	"net"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"sync/atomic"
	"time"

	"howett.net/plist"
)

// InstallProgressListener is implemented in Swift to receive live OTA installation status.
type InstallProgressListener interface {
	OnInstallProgress(stage string, sentBytes int64, totalBytes int64, percent float64)
}

// InstallSessionDTO contains metadata extracted from the IPA and the OTA install URLs.
type InstallSessionDTO struct {
	BundleID          string `json:"bundleId"`
	AppName           string `json:"appName"`
	Version           string `json:"version"`
	FileSize          int64  `json:"fileSize"`
	HTTPPort          int    `json:"httpPort"`
	HTTPSPort         int    `json:"httpsPort"`
	DirectITMSURL     string `json:"directItmsUrl"`
	LocalHTTPSITMSURL string `json:"localHttpsItmsUrl"`
	SafariInstallURL  string `json:"safariInstallUrl"`
	CACertURL         string `json:"caCertUrl"`
}

type ipaMetadata struct {
	BundleID    string
	AppName     string
	Version     string
	FileSize    int64
}

var (
	installerMu      sync.Mutex
	activeHTTPServer *http.Server
	activeTLSServer  *http.Server
	caDownloadedFlag int32
)

const localInstallerHost = "localhost"

// ResetInstallerCertificates deletes cached local CA and leaf certificates so a fresh pair is generated on next use.
func (c *Client) ResetInstallerCertificates() error {
	c.StopIPAInstaller()
	atomic.StoreInt32(&caDownloadedFlag, 0)
	certDir := filepath.Join(c.baseDir, "installer_certs")
	return os.RemoveAll(certDir)
}

// HasServedCACert returns true if the local ca.crt endpoint has been requested by Safari at least once in this session or recorded on disk.
func (c *Client) HasServedCACert() bool {
	if atomic.LoadInt32(&caDownloadedFlag) == 1 {
		return true
	}
	marker := filepath.Join(c.baseDir, "installer_certs", "ca_downloaded.flag")
	_, err := os.Stat(marker)
	return err == nil
}

func (c *Client) markCACertServed() {
	atomic.StoreInt32(&caDownloadedFlag, 1)
	marker := filepath.Join(c.baseDir, "installer_certs", "ca_downloaded.flag")
	_ = os.WriteFile(marker, []byte("1"), 0o600)
}

// InspectIPA reads the app bundle Info.plist inside an .ipa archive without extracting it.
func (c *Client) InspectIPA(ipaPath string) (string, error) {
	meta, err := inspectIPAFile(ipaPath)
	if err != nil {
		return "", err
	}
	dto := InstallSessionDTO{
		BundleID: meta.BundleID,
		AppName:  meta.AppName,
		Version:  meta.Version,
		FileSize: meta.FileSize,
	}
	b, err := json.Marshal(dto)
	return string(b), err
}

func inspectIPAFile(ipaPath string) (ipaMetadata, error) {
	fi, err := os.Stat(ipaPath)
	if err != nil {
		return ipaMetadata{}, fmt.Errorf("stat ipa: %w", err)
	}

	zr, err := zip.OpenReader(ipaPath)
	if err != nil {
		return ipaMetadata{}, fmt.Errorf("open ipa zip: %w", err)
	}
	defer zr.Close()

	var infoFile *zip.File
	var fallbackAppName string

	for _, f := range zr.File {
		name := filepath.ToSlash(f.Name)
		if !strings.HasPrefix(name, "Payload/") || !strings.HasSuffix(name, "/Info.plist") {
			continue
		}
		parts := strings.Split(name, "/")
		if len(parts) == 3 && strings.HasSuffix(strings.ToLower(parts[1]), ".app") {
			infoFile = f
			fallbackAppName = strings.TrimSuffix(parts[1], filepath.Ext(parts[1]))
			break
		}
	}

	if infoFile == nil {
		base := strings.TrimSuffix(filepath.Base(ipaPath), filepath.Ext(ipaPath))
		return ipaMetadata{
			BundleID: "com.unknown.app",
			AppName:  base,
			Version:  "1.0",
			FileSize: fi.Size(),
		}, nil
	}

	rc, err := infoFile.Open()
	if err != nil {
		return ipaMetadata{}, fmt.Errorf("open Info.plist: %w", err)
	}
	defer rc.Close()

	rawPlist, err := io.ReadAll(io.LimitReader(rc, 4<<20))
	if err != nil {
		return ipaMetadata{}, fmt.Errorf("read Info.plist: %w", err)
	}

	var dict map[string]any
	if _, err := plist.Unmarshal(rawPlist, &dict); err != nil {
		return ipaMetadata{}, fmt.Errorf("parse Info.plist: %w", err)
	}

	bundleID, _ := dict["CFBundleIdentifier"].(string)
	if strings.TrimSpace(bundleID) == "" {
		bundleID = "com.unknown.app"
	}

	version, _ := dict["CFBundleShortVersionString"].(string)
	if strings.TrimSpace(version) == "" {
		version, _ = dict["CFBundleVersion"].(string)
	}
	if strings.TrimSpace(version) == "" {
		version = "1.0"
	}

	appName, _ := dict["CFBundleDisplayName"].(string)
	if strings.TrimSpace(appName) == "" {
		appName, _ = dict["CFBundleName"].(string)
	}
	if strings.TrimSpace(appName) == "" {
		appName = fallbackAppName
	}

	return ipaMetadata{
		BundleID: strings.TrimSpace(bundleID),
		AppName:  strings.TrimSpace(appName),
		Version:  strings.TrimSpace(version),
		FileSize: fi.Size(),
	}, nil
}

// StartIPAInstaller launches a local HTTP + HTTPS OTA server on 127.0.0.1 to install the given .ipa via itms-services://.
func (c *Client) StartIPAInstaller(ipaPath string, listener InstallProgressListener) (string, error) {
	c.StopIPAInstaller()

	meta, err := inspectIPAFile(ipaPath)
	if err != nil {
		return "", err
	}

	caCertDER, tlsCert, err := c.ensureInstallerCertificates()
	if err != nil {
		return "", fmt.Errorf("prepare installer TLS certificates: %w", err)
	}

	httpLn, err := net.Listen("tcp", ":0")
	if err != nil {
		return "", fmt.Errorf("listen local HTTP: %w", err)
	}
	httpPort := httpLn.Addr().(*net.TCPAddr).Port

	httpsLn, err := net.Listen("tcp", ":0")
	if err != nil {
		_ = httpLn.Close()
		return "", fmt.Errorf("listen local HTTPS: %w", err)
	}
	httpsPort := httpsLn.Addr().(*net.TCPAddr).Port

	httpPayloadURL := fmt.Sprintf("http://127.0.0.1:%d/payload.ipa", httpPort)
	httpsPayloadURL := fmt.Sprintf("https://%s:%d/payload.ipa", localInstallerHost, httpsPort)
	httpsManifestURL := fmt.Sprintf("https://%s:%d/manifest.plist", localInstallerHost, httpsPort)

	// Method 1: Public HTTPS manifest generator pointing software-package to local HTTP 127.0.0.1 (no Root CA required)
	genParams := url.Values{}
	genParams.Set("bundleid", meta.BundleID)
	genParams.Set("name", meta.AppName)
	genParams.Set("version", meta.Version)
	genParams.Set("fetchurl", httpPayloadURL)
	externalManifestURL := "https://api.palera.in/genPlist?" + genParams.Encode()
	directITMSURL := "itms-services://?action=download-manifest&url=" + url.QueryEscape(externalManifestURL)

	// Method 2: 100% Local Offline HTTPS manifest (using local Root CA and localhost SNI, unescaped like Feather)
	localHTTPSITMSURL := "itms-services://?action=download-manifest&url=" + httpsManifestURL

	safariInstallURL := fmt.Sprintf("http://127.0.0.1:%d/install", httpPort)
	caCertURL := fmt.Sprintf("http://127.0.0.1:%d/ca.crt", httpPort)

	localManifestXML, err := buildOTAManifestXML(meta, httpsPayloadURL)
	if err != nil {
		_ = httpLn.Close()
		_ = httpsLn.Close()
		return "", err
	}

	httpManifestXML, err := buildOTAManifestXML(meta, httpPayloadURL)
	if err != nil {
		_ = httpLn.Close()
		_ = httpsLn.Close()
		return "", err
	}

	notify := func(stage string, sent, total int64, pct float64) {
		if listener != nil {
			listener.OnInstallProgress(stage, sent, total, pct)
		}
	}

	mux := http.NewServeMux()
	mux.HandleFunc("/ping", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte("pong"))
	})
	mux.HandleFunc("/ca.crt", func(w http.ResponseWriter, r *http.Request) {
		c.markCACertServed()
		w.Header().Set("Content-Type", "application/x-x509-ca-cert")
		w.Header().Set("Content-Disposition", "attachment; filename=\"IPADownloader-LocalCA-v2.crt\"")
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write(caCertDER)
	})
	mux.HandleFunc("/manifest.plist", func(w http.ResponseWriter, r *http.Request) {
		notify("sending_manifest", 0, meta.FileSize, 0.02)
		body := httpManifestXML
		if r.TLS != nil {
			body = localManifestXML
		}
		w.Header().Set("Content-Type", "text/xml; charset=utf-8")
		w.Header().Set("Content-Length", fmt.Sprintf("%d", len(body)))
		w.WriteHeader(http.StatusOK)
		if r.Method != http.MethodHead {
			_, _ = w.Write(body)
		}
	})
	mux.HandleFunc("/install", func(w http.ResponseWriter, r *http.Request) {
		targetITMS := directITMSURL
		if r.URL.Query().Get("mode") == "local" {
			targetITMS = localHTTPSITMSURL
		}
		w.Header().Set("Content-Type", "text/html; charset=utf-8")
		html := fmt.Sprintf(`<!DOCTYPE html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Cài đặt %s</title><meta http-equiv="refresh" content="0;url=%s"></head><body style="font-family:-apple-system,sans-serif;text-align:center;padding:40px 20px;background:#111;color:#fff;"><h3>Đang mở trình cài đặt iOS cho %s (v%s)...</h3><p><a href="%s" style="display:inline-block;margin-top:16px;padding:12px 24px;background:#0a84ff;color:#fff;border-radius:10px;text-decoration:none;font-weight:600;">Nhấn vào đây nếu hộp thoại cài đặt chưa hiện</a></p></body></html>`,
			meta.AppName, targetITMS, meta.AppName, meta.Version, targetITMS)
		_, _ = w.Write([]byte(html))
	})
	mux.HandleFunc("/payload.ipa", func(w http.ResponseWriter, r *http.Request) {
		f, err := os.Open(ipaPath)
		if err != nil {
			http.Error(w, "IPA file not found", http.StatusNotFound)
			return
		}
		defer f.Close()

		w.Header().Set("Content-Type", "application/octet-stream")
		if r.Method == http.MethodHead {
			w.Header().Set("Content-Length", fmt.Sprintf("%d", meta.FileSize))
			w.WriteHeader(http.StatusOK)
			return
		}

		notify("sending_payload", 0, meta.FileSize, 0.05)
		var counter int64
		pw := &progressResponseWriter{
			ResponseWriter: w,
			total:          meta.FileSize,
			counter:        &counter,
			onUpdate: func(sent, total int64) {
				pct := 0.0
				if total > 0 {
					pct = float64(sent) / float64(total)
				}
				notify("sending_payload", sent, total, pct)
			},
		}
		http.ServeContent(pw, r, filepath.Base(ipaPath), time.Now(), f)
		if atomic.LoadInt64(&counter) >= meta.FileSize && meta.FileSize > 0 {
			notify("completed", meta.FileSize, meta.FileSize, 1.0)
		}
	})

	httpSrv := &http.Server{Handler: mux}
	tlsConfig := &tls.Config{
		Certificates: []tls.Certificate{tlsCert},
		MinVersion:   tls.VersionTLS12,
		NextProtos:   []string{"http/1.1"},
	}
	httpsSrv := &http.Server{
		Handler:   mux,
		TLSConfig: tlsConfig,
		ErrorLog: log.New(&tlsLogWriter{onMessage: func(msg string) {
			notify("tls_error:"+msg, 0, meta.FileSize, 0)
		}}, "", 0),
	}

	installerMu.Lock()
	activeHTTPServer = httpSrv
	activeTLSServer = httpsSrv
	installerMu.Unlock()

	go func() {
		_ = httpSrv.Serve(httpLn)
	}()
	go func() {
		_ = httpsSrv.Serve(tls.NewListener(httpsLn, tlsConfig))
	}()

	notify("ready", 0, meta.FileSize, 0)

	dto := InstallSessionDTO{
		BundleID:          meta.BundleID,
		AppName:           meta.AppName,
		Version:           meta.Version,
		FileSize:          meta.FileSize,
		HTTPPort:          httpPort,
		HTTPSPort:         httpsPort,
		DirectITMSURL:     directITMSURL,
		LocalHTTPSITMSURL: localHTTPSITMSURL,
		SafariInstallURL:  safariInstallURL,
		CACertURL:         caCertURL,
	}
	b, err := json.Marshal(dto)
	return string(b), err
}

// StopIPAInstaller shuts down the local OTA HTTP/HTTPS servers.
func (c *Client) StopIPAInstaller() {
	installerMu.Lock()
	httpSrv := activeHTTPServer
	httpsSrv := activeTLSServer
	activeHTTPServer = nil
	activeTLSServer = nil
	installerMu.Unlock()

	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()
	if httpSrv != nil {
		_ = httpSrv.Shutdown(ctx)
	}
	if httpsSrv != nil {
		_ = httpsSrv.Shutdown(ctx)
	}
}

// StartCACertServer launches a lightweight local HTTP + HTTPS server on 127.0.0.1 to serve the local Root CA certificate and allow iOS SecTrust verification.
func (c *Client) StartCACertServer() (string, error) {
	c.StopIPAInstaller()

	caCertDER, tlsCert, err := c.ensureInstallerCertificates()
	if err != nil {
		return "", fmt.Errorf("prepare installer CA certificate: %w", err)
	}

	httpLn, err := net.Listen("tcp", ":0")
	if err != nil {
		return "", fmt.Errorf("listen local HTTP: %w", err)
	}
	httpPort := httpLn.Addr().(*net.TCPAddr).Port

	httpsLn, err := net.Listen("tcp", ":0")
	if err != nil {
		_ = httpLn.Close()
		return "", fmt.Errorf("listen local HTTPS: %w", err)
	}
	httpsPort := httpsLn.Addr().(*net.TCPAddr).Port

	mux := http.NewServeMux()
	mux.HandleFunc("/ping", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte("pong"))
	})
	mux.HandleFunc("/ca.crt", func(w http.ResponseWriter, r *http.Request) {
		c.markCACertServed()
		w.Header().Set("Content-Type", "application/x-x509-ca-cert")
		w.Header().Set("Content-Disposition", "attachment; filename=\"IPADownloader-LocalCA-v2.crt\"")
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write(caCertDER)
	})

	httpSrv := &http.Server{Handler: mux}
	tlsConfig := &tls.Config{
		Certificates: []tls.Certificate{tlsCert},
		MinVersion:   tls.VersionTLS12,
		NextProtos:   []string{"http/1.1"},
	}
	httpsSrv := &http.Server{
		Handler:   mux,
		TLSConfig: tlsConfig,
	}

	installerMu.Lock()
	activeHTTPServer = httpSrv
	activeTLSServer = httpsSrv
	installerMu.Unlock()

	go func() {
		_ = httpSrv.Serve(httpLn)
	}()
	go func() {
		_ = httpsSrv.Serve(tls.NewListener(httpsLn, tlsConfig))
	}()

	dto := InstallSessionDTO{
		HTTPPort:  httpPort,
		HTTPSPort: httpsPort,
		CACertURL: fmt.Sprintf("http://127.0.0.1:%d/ca.crt", httpPort),
	}
	b, err := json.Marshal(dto)
	return string(b), err
}

// GetInstallerCertChainJSON ensures the local Root CA and 127.0.0.1 leaf certificate exist on disk and returns their base64 DER representations so Swift SecTrust can evaluate iOS system trust without opening a socket.
func (c *Client) GetInstallerCertChainJSON() (string, error) {
	caDER, leafDER, err := c.ensureInstallerRawDERs()
	if err != nil {
		return "", err
	}
	payload := map[string][]byte{
		"caDer":   caDER,
		"leafDer": leafDER,
	}
	b, err := json.Marshal(payload)
	return string(b), err
}

type progressResponseWriter struct {
	http.ResponseWriter
	total      int64
	counter    *int64
	lastReport time.Time
	onUpdate   func(sent, total int64)
}

func (pw *progressResponseWriter) Write(p []byte) (int, error) {
	n, err := pw.ResponseWriter.Write(p)
	if n > 0 {
		current := atomic.AddInt64(pw.counter, int64(n))
		now := time.Now()
		if now.Sub(pw.lastReport) >= 150*time.Millisecond || current >= pw.total {
			pw.lastReport = now
			if pw.onUpdate != nil {
				pw.onUpdate(current, pw.total)
			}
		}
	}
	return n, err
}

func buildOTAManifestXML(meta ipaMetadata, packageURL string) ([]byte, error) {
	manifest := map[string]any{
		"items": []map[string]any{
			{
				"assets": []map[string]any{
					{
						"kind": "software-package",
						"url":  packageURL,
					},
				},
				"metadata": map[string]any{
					"bundle-identifier": meta.BundleID,
					"bundle-version":    meta.Version,
					"kind":              "software",
					"title":             meta.AppName,
				},
			},
		},
	}
	return plist.Marshal(manifest, plist.XMLFormat)
}

func (c *Client) ensureInstallerRawDERs() ([]byte, []byte, error) {
	caDER, pair, err := c.ensureInstallerCertificates()
	if err != nil {
		return nil, nil, err
	}
	if len(pair.Certificate) == 0 {
		return nil, nil, fmt.Errorf("empty TLS leaf certificate")
	}
	return caDER, pair.Certificate[0], nil
}

type tlsLogWriter struct {
	onMessage func(string)
}

func (w *tlsLogWriter) Write(p []byte) (int, error) {
	msg := strings.TrimSpace(string(p))
	if msg != "" && w.onMessage != nil {
		w.onMessage(msg)
	}
	return len(p), nil
}

func randomCertSerial() *big.Int {
	limit := new(big.Int).Lsh(big.NewInt(1), 128)
	n, err := rand.Int(rand.Reader, limit)
	if err != nil || n.Sign() <= 0 {
		return big.NewInt(time.Now().UnixNano())
	}
	return n
}

func (c *Client) ensureInstallerCertificates() ([]byte, tls.Certificate, error) {
	certDir := filepath.Join(c.baseDir, "installer_certs")
	if err := os.MkdirAll(certDir, 0o700); err != nil {
		return nil, tls.Certificate{}, err
	}
	caCertPath := filepath.Join(certDir, "ca.crt")
	caKeyPath := filepath.Join(certDir, "ca-key.pem")
	leafCertPath := filepath.Join(certDir, "leaf.pem")
	leafKeyPath := filepath.Join(certDir, "leaf-key.pem")
	versionFlagPath := filepath.Join(certDir, "cert_v2.flag")

	if _, err := os.Stat(versionFlagPath); err == nil {
		if caDER, err := os.ReadFile(caCertPath); err == nil {
			if pair, err := tls.LoadX509KeyPair(leafCertPath, leafKeyPath); err == nil && len(pair.Certificate) > 0 {
				if parsedLeaf, err := x509.ParseCertificate(pair.Certificate[0]); err == nil && parsedLeaf.NotAfter.After(time.Now().Add(7*24*time.Hour)) {
					return caDER, pair, nil
				}
			}
		}
	}

	now := time.Now().Add(-1 * time.Hour)
	caKey, err := rsa.GenerateKey(rand.Reader, 2048)
	if err != nil {
		return nil, tls.Certificate{}, err
	}
	caSKI := sha1.Sum(x509.MarshalPKCS1PublicKey(&caKey.PublicKey))
	caTemplate := &x509.Certificate{
		SerialNumber: randomCertSerial(),
		Subject: pkix.Name{
			CommonName:   "IPA Downloader Local Root CA v2",
			Organization: []string{"IPA Downloader"},
		},
		SubjectKeyId:          caSKI[:],
		NotBefore:             now,
		NotAfter:              now.AddDate(10, 0, 0),
		KeyUsage:              x509.KeyUsageCertSign | x509.KeyUsageCRLSign,
		BasicConstraintsValid: true,
		IsCA:                  true,
		MaxPathLenZero:        true,
	}
	caDER, err := x509.CreateCertificate(rand.Reader, caTemplate, caTemplate, &caKey.PublicKey, caKey)
	if err != nil {
		return nil, tls.Certificate{}, err
	}
	parsedCA, err := x509.ParseCertificate(caDER)
	if err != nil {
		return nil, tls.Certificate{}, err
	}

	leafKey, err := rsa.GenerateKey(rand.Reader, 2048)
	if err != nil {
		return nil, tls.Certificate{}, err
	}
	leafSKI := sha1.Sum(x509.MarshalPKCS1PublicKey(&leafKey.PublicKey))
	leafTemplate := &x509.Certificate{
		SerialNumber: randomCertSerial(),
		Subject: pkix.Name{
			CommonName:   "localhost",
			Organization: []string{"IPA Downloader"},
		},
		SubjectKeyId:          leafSKI[:],
		AuthorityKeyId:        parsedCA.SubjectKeyId,
		DNSNames:              []string{"localhost"},
		IPAddresses:           []net.IP{net.ParseIP("127.0.0.1"), net.ParseIP("::1")},
		NotBefore:             now,
		NotAfter:              now.Add(365 * 24 * time.Hour),
		KeyUsage:              x509.KeyUsageDigitalSignature | x509.KeyUsageKeyEncipherment,
		ExtKeyUsage:           []x509.ExtKeyUsage{x509.ExtKeyUsageServerAuth},
		BasicConstraintsValid: true,
	}
	leafDER, err := x509.CreateCertificate(rand.Reader, leafTemplate, parsedCA, &leafKey.PublicKey, caKey)
	if err != nil {
		return nil, tls.Certificate{}, err
	}

	leafCertPEM := pem.EncodeToMemory(&pem.Block{Type: "CERTIFICATE", Bytes: leafDER})
	caKeyPEM := pem.EncodeToMemory(&pem.Block{Type: "RSA PRIVATE KEY", Bytes: x509.MarshalPKCS1PrivateKey(caKey)})
	leafKeyPEM := pem.EncodeToMemory(&pem.Block{Type: "RSA PRIVATE KEY", Bytes: x509.MarshalPKCS1PrivateKey(leafKey)})

	_ = os.WriteFile(caCertPath, caDER, 0o600)
	_ = os.WriteFile(caKeyPath, caKeyPEM, 0o600)
	_ = os.WriteFile(leafCertPath, leafCertPEM, 0o600)
	_ = os.WriteFile(leafKeyPath, leafKeyPEM, 0o600)
	_ = os.WriteFile(versionFlagPath, []byte("v2"), 0o600)
	_ = os.Remove(filepath.Join(certDir, "ca_downloaded.flag"))
	atomic.StoreInt32(&caDownloadedFlag, 0)

	pair, err := tls.X509KeyPair(leafCertPEM, leafKeyPEM)
	if err != nil {
		return nil, tls.Certificate{}, err
	}
	return caDER, pair, nil
}
