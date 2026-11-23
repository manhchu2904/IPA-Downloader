package ipatoolbridge

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"sync"

	cookiejar "github.com/juju/persistent-cookiejar"
	"github.com/majd/ipatool/v2/pkg/appstore"
	"github.com/majd/ipatool/v2/pkg/util/operatingsystem"
)

// Client is the gomobile-exported entrypoint used by SwiftUI.
// All methods accept/return simple primitives or JSON strings for clean bridging.
type Client struct {
	mu           sync.Mutex
	baseDir      string
	os           operatingsystem.OperatingSystem
	machine      *iosMachine
	stores       map[string]appstore.AppStore
	activeCancels map[string]context.CancelFunc
}

// AccountDTO is serialized to JSON for Swift.
type AccountDTO struct {
	ID                  string `json:"id"`
	Email               string `json:"email"`
	Name                string `json:"name"`
	StoreFront          string `json:"storeFront"`
	DirectoryServicesID string `json:"directoryServicesId"`
	Pod                 string `json:"pod"`
}

// LoginResponseDTO indicates either success or that a 2FA code is required.
type LoginResponseDTO struct {
	Success          bool        `json:"success"`
	AuthCodeRequired bool        `json:"authCodeRequired"`
	Account          *AccountDTO `json:"account,omitempty"`
	Error            string      `json:"error,omitempty"`
}

// NewClient initializes the bridge using the iOS app's Application Support directory.
func NewClient(baseDir string) (*Client, error) {
	if baseDir == "" {
		return nil, errors.New("baseDir is required")
	}
	if err := configureSandboxEnvironment(baseDir); err != nil {
		return nil, err
	}

	return &Client{
		baseDir:       baseDir,
		os:            operatingsystem.New(),
		machine:       newIOSMachine(baseDir),
		stores:        make(map[string]appstore.AppStore),
		activeCancels: make(map[string]context.CancelFunc),
	}, nil
}

// configureSandboxEnvironment creates writable directories and sets HOME/XDG/TMPDIR
// so Go stdlib helpers like os.UserCacheDir work when launched via debugserver on iOS 26+.
func configureSandboxEnvironment(baseDir string) error {
	cachesDir := filepath.Join(baseDir, "Library", "Caches")
	configDir := filepath.Join(baseDir, "Library", "Application Support")
	tmpDir := filepath.Join(baseDir, "tmp")

	for _, dir := range []string{
		filepath.Join(baseDir, "accounts"),
		cachesDir,
		configDir,
		tmpDir,
	} {
		if err := os.MkdirAll(dir, 0o700); err != nil {
			return fmt.Errorf("create sandbox dir: %w", err)
		}
	}

	for key, val := range map[string]string{
		"HOME":            baseDir,
		"XDG_CACHE_HOME":  cachesDir,
		"XDG_CONFIG_HOME": configDir,
		"XDG_STATE_HOME":  baseDir,
		"XDG_DATA_HOME":   configDir,
	} {
		if err := os.Setenv(key, val); err != nil {
			return fmt.Errorf("set env %s: %w", key, err)
		}
	}

	if os.Getenv("TMPDIR") == "" {
		if err := os.Setenv("TMPDIR", tmpDir); err != nil {
			return fmt.Errorf("set env TMPDIR: %w", err)
		}
	}

	return nil
}

// Prepare loads the compiled Store runtime profile and downloads/caches Apple's SAP assets.
func (c *Client) Prepare() error {
	return appstore.Prepare(context.Background())
}

func accountIDFromEmail(email string) string {
	sum := sha256.Sum256([]byte(strings.ToLower(strings.TrimSpace(email))))
	return hex.EncodeToString(sum[:8])
}

func (c *Client) accountDir(accountID string) string {
	return filepath.Join(c.baseDir, "accounts", accountID)
}

func (c *Client) storeForAccount(accountID string) (appstore.AppStore, error) {
	c.mu.Lock()
	defer c.mu.Unlock()

	if st, ok := c.stores[accountID]; ok {
		return st, nil
	}

	dir := c.accountDir(accountID)
	if err := os.MkdirAll(dir, 0o700); err != nil {
		return nil, fmt.Errorf("create account dir: %w", err)
	}

	jar, err := cookiejar.New(&cookiejar.Options{
		Filename: filepath.Join(dir, "cookies.json"),
	})
	if err != nil {
		return nil, fmt.Errorf("init cookie jar: %w", err)
	}

	kc := newFileKeychain(filepath.Join(dir, "keychain.json"))
	st := appstore.NewAppStore(appstore.Args{
		CookieJar:       jar,
		Keychain:        kc,
		OperatingSystem: c.os,
		Machine:         c.machine,
	})
	c.stores[accountID] = st
	return st, nil
}

func (c *Client) loadAccount(accountID string) (appstore.AppStore, appstore.Account, error) {
	st, err := c.storeForAccount(accountID)
	if err != nil {
		return nil, appstore.Account{}, err
	}
	info, err := st.AccountInfo()
	if err != nil {
		return nil, appstore.Account{}, fmt.Errorf("account not signed in: %w", err)
	}
	return st, info.Account, nil
}

// refreshAccountToken silently re-authenticates using the stored credentials in keychain.json
// when Apple reports ErrPasswordTokenExpired (matching majd/ipatool CLI retry behavior).
func (c *Client) refreshAccountToken(st appstore.AppStore, acc appstore.Account) (appstore.Account, error) {
	if acc.Email == "" || acc.Password == "" {
		return acc, appstore.ErrPasswordTokenExpired
	}
	out, err := st.Login(appstore.LoginInput{
		Email:    acc.Email,
		Password: acc.Password,
	})
	if err != nil {
		return acc, err
	}
	return out.Account, nil
}

// acquireFreeLicense obtains a free license for app, automatically refreshing the password token
// if expired and reloading any server-corrected storefront from AccountInfo.
func (c *Client) acquireFreeLicense(st appstore.AppStore, acc appstore.Account, app appstore.App, platform appstore.Platform) (appstore.Account, error) {
	pErr := st.Purchase(appstore.PurchaseInput{
		Account:  acc,
		App:      app,
		Platform: platform,
	})
	if errors.Is(pErr, appstore.ErrPasswordTokenExpired) {
		if refreshed, rErr := c.refreshAccountToken(st, acc); rErr == nil {
			acc = refreshed
			pErr = st.Purchase(appstore.PurchaseInput{
				Account:  acc,
				App:      app,
				Platform: platform,
			})
		}
	}
	if pErr != nil && !errors.Is(pErr, appstore.ErrLicenseAlreadyExists) {
		return acc, pErr
	}
	if info, err := st.AccountInfo(); err == nil {
		acc = info.Account
	}
	return acc, nil
}

func toAccountDTO(id string, acc appstore.Account) AccountDTO {
	return AccountDTO{
		ID:                  id,
		Email:               acc.Email,
		Name:                acc.Name,
		StoreFront:          acc.StoreFront,
		DirectoryServicesID: acc.DirectoryServicesID,
		Pod:                 acc.Pod,
	}
}

func validateAppleIDInput(raw string) error {
	trimmed := strings.TrimSpace(raw)
	if trimmed == "" || strings.ContainsAny(trimmed, " \t\r\n") {
		return errors.New("Email hoặc số điện thoại không hợp lệ.")
	}
	if at := strings.IndexByte(trimmed, '@'); at > 0 {
		local := trimmed[:at]
		domain := trimmed[at+1:]
		dot := strings.LastIndexByte(domain, '.')
		if len(local) > 0 && dot > 0 && dot < len(domain)-1 && !strings.Contains(domain, "@") {
			return nil
		}
		return errors.New("Email hoặc số điện thoại không hợp lệ.")
	}
	// Phone-number Apple ID: must consist of digits (and optional '+', '-', '(', ')') with >= 7 digits
	digits := 0
	for i, r := range trimmed {
		switch {
		case r >= '0' && r <= '9':
			digits++
		case r == '+' && i == 0:
		case r == '-' || r == '(' || r == ')':
		default:
			return errors.New("Email hoặc số điện thoại không hợp lệ.")
		}
	}
	if digits < 7 {
		return errors.New("Email hoặc số điện thoại không hợp lệ.")
	}
	return nil
}

// Login authenticates an Apple ID (with optional 6-digit 2FA authCode).
// Returns JSON-encoded LoginResponseDTO.
func (c *Client) Login(email, password, authCode string) (string, error) {
	email = strings.TrimSpace(email)
	if email == "" || password == "" {
		return "", errors.New("email and password are required")
	}
	if err := validateAppleIDInput(email); err != nil {
		return "", err
	}

	id := accountIDFromEmail(email)
	st, err := c.storeForAccount(id)
	if err != nil {
		return "", err
	}

	out, err := st.Login(appstore.LoginInput{
		Email:    email,
		Password: password,
		AuthCode: strings.TrimSpace(authCode),
	})
	if err != nil {
		if errors.Is(err, appstore.ErrAuthCodeRequired) {
			resp := LoginResponseDTO{
				Success:          false,
				AuthCodeRequired: true,
			}
			b, _ := json.Marshal(resp)
			return string(b), nil
		}
		if _, infoErr := st.AccountInfo(); infoErr != nil {
			c.mu.Lock()
			delete(c.stores, id)
			c.mu.Unlock()
			_ = os.RemoveAll(c.accountDir(id))
		}
		return "", err
	}

	dto := toAccountDTO(id, out.Account)
	resp := LoginResponseDTO{
		Success: true,
		Account: &dto,
	}
	b, err := json.Marshal(resp)
	return string(b), err
}

// ListAccounts returns a JSON array of all locally stored signed-in accounts.
func (c *Client) ListAccounts() (string, error) {
	entries, err := os.ReadDir(filepath.Join(c.baseDir, "accounts"))
	if err != nil {
		if errors.Is(err, os.ErrNotExist) {
			return "[]", nil
		}
		return "", err
	}

	accounts := make([]AccountDTO, 0, len(entries))
	for _, entry := range entries {
		if !entry.IsDir() {
			continue
		}
		id := entry.Name()
		_, acc, err := c.loadAccount(id)
		if err != nil || acc.Email == "" {
			continue
		}
		accounts = append(accounts, toAccountDTO(id, acc))
	}

	b, err := json.Marshal(accounts)
	return string(b), err
}

// RemoveAccount revokes credentials and deletes local state for an account.
func (c *Client) RemoveAccount(accountID string) error {
	if st, err := c.storeForAccount(accountID); err == nil {
		_ = st.Revoke()
	}

	c.mu.Lock()
	delete(c.stores, accountID)
	c.mu.Unlock()

	return os.RemoveAll(c.accountDir(accountID))
}
