package ipatoolbridge

import (
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"sync"

	"github.com/majd/ipatool/v2/pkg/keychain"
)

// fileKeychain is a sandbox-safe, per-account keychain implementation backed
// by a JSON file inside the iOS app's Application Support directory.
// It implements github.com/majd/ipatool/v2/pkg/keychain.Keychain.
type fileKeychain struct {
	mu   sync.RWMutex
	path string
}

func newFileKeychain(path string) keychain.Keychain {
	return &fileKeychain{path: path}
}

func (k *fileKeychain) load() (map[string][]byte, error) {
	data, err := os.ReadFile(k.path)
	if err != nil {
		if errors.Is(err, os.ErrNotExist) {
			return map[string][]byte{}, nil
		}
		return nil, err
	}
	var store map[string][]byte
	if err := json.Unmarshal(data, &store); err != nil {
		return map[string][]byte{}, nil
	}
	if store == nil {
		store = map[string][]byte{}
	}
	return store, nil
}

func (k *fileKeychain) save(store map[string][]byte) error {
	if err := os.MkdirAll(filepath.Dir(k.path), 0o700); err != nil {
		return err
	}
	data, err := json.MarshalIndent(store, "", "  ")
	if err != nil {
		return err
	}
	tmpPath := k.path + ".tmp"
	if err := os.WriteFile(tmpPath, data, 0o600); err != nil {
		return err
	}
	return os.Rename(tmpPath, k.path)
}

func (k *fileKeychain) Get(key string) ([]byte, error) {
	k.mu.RLock()
	defer k.mu.RUnlock()

	store, err := k.load()
	if err != nil {
		return nil, err
	}
	val, ok := store[key]
	if !ok {
		return nil, os.ErrNotExist
	}
	out := make([]byte, len(val))
	copy(out, val)
	return out, nil
}

func (k *fileKeychain) Set(key string, data []byte) error {
	k.mu.Lock()
	defer k.mu.Unlock()

	store, err := k.load()
	if err != nil {
		return err
	}
	cp := make([]byte, len(data))
	copy(cp, data)
	store[key] = cp
	return k.save(store)
}

func (k *fileKeychain) Remove(key string) error {
	k.mu.Lock()
	defer k.mu.Unlock()

	store, err := k.load()
	if err != nil {
		return err
	}
	delete(store, key)
	return k.save(store)
}
