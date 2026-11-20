package ipatoolbridge

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/majd/ipatool/v2/pkg/appstore"
	"github.com/schollz/progressbar/v3"
)

// ProgressListener is implemented in Swift to receive live download progress updates.
type ProgressListener interface {
	OnProgress(downloadID string, downloadedBytes int64, totalBytes int64, percent float64, stage string)
}

// DownloadResultDTO is returned by Download as JSON.
type DownloadResultDTO struct {
	FilePath string `json:"filePath"`
	FileName string `json:"fileName"`
	FileSize int64  `json:"fileSize"`
}

// Download acquires a free license if needed, downloads the .ipa for the given app
// (and optional externalVersionID), replicates SINF, and saves it into outputDir.
func (c *Client) Download(
	downloadID string,
	accountID string,
	appID int64,
	bundleID string,
	appName string,
	price float64,
	externalVersionID string,
	platformName string,
	outputDir string,
	purchaseIfNeeded bool,
	listener ProgressListener,
) (string, error) {
	st, acc, err := c.loadAccount(accountID)
	if err != nil {
		return "", err
	}

	platform, err := parsePlatformOrDefault(platformName)
	if err != nil {
		return "", err
	}

	if err := os.MkdirAll(outputDir, 0o755); err != nil {
		return "", fmt.Errorf("create output dir: %w", err)
	}

	ctx, cancel := context.WithCancel(context.Background())
	c.mu.Lock()
	c.activeCancels[downloadID] = cancel
	c.mu.Unlock()

	defer func() {
		cancel()
		c.mu.Lock()
		delete(c.activeCancels, downloadID)
		c.mu.Unlock()
	}()

	app := appstore.App{
		ID:       appID,
		BundleID: bundleID,
		Name:     appName,
		Price:    price,
	}

	notify := func(downloaded, total int64, pct float64, stage string) {
		if listener != nil {
			listener.OnProgress(downloadID, downloaded, total, pct, stage)
		}
	}

	notify(0, 0, 0, "preparing")

	bar := progressbar.NewOptions64(
		-1,
		progressbar.OptionSetWriter(io.Discard),
		progressbar.OptionThrottle(150*time.Millisecond),
	)

	stopProgress := make(chan struct{})
	go func() {
		ticker := time.NewTicker(200 * time.Millisecond)
		defer ticker.Stop()
		for {
			select {
			case <-stopProgress:
				return
			case <-ticker.C:
				state := bar.State()
				notify(int64(state.CurrentBytes), state.Max, state.CurrentPercent, "downloading")
			}
		}
	}()

	runDownload := func() (appstore.DownloadOutput, error) {
		return st.Download(appstore.DownloadInput{
			Context:           ctx,
			Account:           acc,
			App:               app,
			OutputPath:        outputDir,
			Progress:          bar,
			ExternalVersionID: strings.TrimSpace(externalVersionID),
			Platform:          platform,
		})
	}

	out, err := runDownload()
	if err != nil && errors.Is(err, appstore.ErrLicenseRequired) && purchaseIfNeeded && price == 0 {
		notify(0, 0, 0, "acquiring_license")
		if pErr := st.Purchase(appstore.PurchaseInput{
			Account:  acc,
			App:      app,
			Platform: platform,
		}); pErr != nil && !errors.Is(pErr, appstore.ErrLicenseAlreadyExists) {
			close(stopProgress)
			return "", fmt.Errorf("failed to acquire free license: %w", pErr)
		}
		out, err = runDownload()
	}

	close(stopProgress)

	if err != nil {
		return "", fmt.Errorf("download failed: %w", err)
	}

	if len(out.Sinfs) > 0 {
		notify(0, 0, 0.98, "patching_sinf")
		if err := st.ReplicateSinf(appstore.ReplicateSinfInput{
			Sinfs:       out.Sinfs,
			PackagePath: out.DestinationPath,
		}); err != nil {
			return "", fmt.Errorf("replicate sinf failed: %w", err)
		}
	}

	var size int64
	if fi, statErr := os.Stat(out.DestinationPath); statErr == nil {
		size = fi.Size()
	}

	notify(size, size, 1.0, "completed")

	res := DownloadResultDTO{
		FilePath: out.DestinationPath,
		FileName: filepath.Base(out.DestinationPath),
		FileSize: size,
	}
	b, err := json.Marshal(res)
	return string(b), err
}

// CancelDownload cancels an in-flight download by its downloadID.
func (c *Client) CancelDownload(downloadID string) {
	c.mu.Lock()
	cancel, ok := c.activeCancels[downloadID]
	c.mu.Unlock()
	if ok {
		cancel()
	}
}
