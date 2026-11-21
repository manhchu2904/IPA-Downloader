package ipatoolbridge

import (
	"crypto/rand"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"sync"

	"github.com/majd/ipatool/v2/pkg/util/machine"
)

// iosMachine implements github.com/majd/ipatool/v2/pkg/util/machine.Machine
// with a stable, persisted virtual MAC address inside the iOS sandbox so that
// Apple's guid / machineID remains consistent across app launches.
type iosMachine struct {
	mu       sync.Mutex
	baseDir  string
	macCache string
}

var _ machine.Machine = (*iosMachine)(nil)

func newIOSMachine(baseDir string) *iosMachine {
	return &iosMachine{baseDir: baseDir}
}

func (m *iosMachine) MacAddress() (string, error) {
	m.mu.Lock()
	defer m.mu.Unlock()

	if m.macCache != "" {
		return m.macCache, nil
	}

	idPath := filepath.Join(m.baseDir, "device_mac.txt")
	if raw, err := os.ReadFile(idPath); err == nil {
		trimmed := strings.TrimSpace(string(raw))
		if len(trimmed) == 17 {
			m.macCache = trimmed
			return m.macCache, nil
		}
	}

	var b [6]byte
	if _, err := rand.Read(b[:]); err != nil {
		return "", fmt.Errorf("generate virtual mac: %w", err)
	}
	// Locally administered, unicast MAC address
	b[0] = (b[0] | 0x02) & 0xfe
	mac := fmt.Sprintf("%02X:%02X:%02X:%02X:%02X:%02X", b[0], b[1], b[2], b[3], b[4], b[5])

	_ = os.MkdirAll(m.baseDir, 0o700)
	_ = os.WriteFile(idPath, []byte(mac), 0o600)
	m.macCache = mac
	return mac, nil
}

func (m *iosMachine) HomeDirectory() string {
	return m.baseDir
}

func (m *iosMachine) ReadPassword(_ int) ([]byte, error) {
	return nil, errors.New("interactive terminal password prompt is not supported on iOS")
}
