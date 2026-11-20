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
	if err := os.MkdirAll(filepath.Join(baseDir, "accounts"), 0o700); err != nil {
		return nil, fmt.Errorf("create accounts dir: %w", err)
	}

	return &Client{
		baseDir:       baseDir,
		os:            operatingsystem.New(),
		machine:       newIOSMachine(baseDir),
		stores:        make(map[string]appstore.AppStore),
		activeCancels: make(map[string]context.CancelFunc),
	}, nil
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

// Login authenticates an Apple ID (with optional 6-digit 2FA authCode).
// Returns JSON-encoded LoginResponseDTO.
func (c *Client) Login(email, password, authCode string) (string, error) {
	email = strings.TrimSpace(email)
	if email == "" || password == "" {
		return "", errors.New("email and password are required")
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
