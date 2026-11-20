package ipatoolbridge

import (
	"encoding/json"
	"fmt"
	"strings"

	"github.com/majd/ipatool/v2/pkg/appstore"
)

// AppDTO represents an App Store application for Swift.
type AppDTO struct {
	ID        int64    `json:"id"`
	BundleID  string   `json:"bundleId"`
	Name      string   `json:"name"`
	Version   string   `json:"version"`
	Price     float64  `json:"price"`
	Platforms []string `json:"platforms,omitempty"`
}

func toAppDTO(a appstore.App) AppDTO {
	platforms := make([]string, 0, len(a.Platforms))
	for _, p := range a.Platforms {
		platforms = append(platforms, string(p))
	}
	return AppDTO{
		ID:        a.ID,
		BundleID:  a.BundleID,
		Name:      a.Name,
		Version:   a.Version,
		Price:     a.Price,
		Platforms: platforms,
	}
}

func parsePlatformOrDefault(raw string) (appstore.Platform, error) {
	if strings.TrimSpace(raw) == "" {
		return appstore.PlatformIPhone, nil
	}
	return appstore.ParsePlatform(raw)
}

// Search searches the App Store using the given account and optional storefront override
// (e.g. "143441" for US, "143471" for VN). Pass "" to use the account's default storefront.
func (c *Client) Search(accountID, term, storefrontOverride, platformName string, limit int) (string, error) {
	st, acc, err := c.loadAccount(accountID)
	if err != nil {
		return "", err
	}
	if strings.TrimSpace(storefrontOverride) != "" {
		acc.StoreFront = strings.TrimSpace(storefrontOverride)
	}

	platform, err := parsePlatformOrDefault(platformName)
	if err != nil {
		return "", err
	}
	if limit <= 0 {
		limit = 20
	}

	out, err := st.Search(appstore.SearchInput{
		Account:  acc,
		Term:     strings.TrimSpace(term),
		Limit:    int64(limit),
		Platform: platform,
	})
	if err != nil {
		return "", fmt.Errorf("search failed: %w", err)
	}

	results := make([]AppDTO, 0, len(out.Results))
	for _, a := range out.Results {
		results = append(results, toAppDTO(a))
	}

	b, err := json.Marshal(results)
	return string(b), err
}

// Lookup fetches a single app by bundleID or numeric appID.
func (c *Client) Lookup(accountID, bundleID string, appID int64, storefrontOverride, platformName string) (string, error) {
	st, acc, err := c.loadAccount(accountID)
	if err != nil {
		return "", err
	}
	if strings.TrimSpace(storefrontOverride) != "" {
		acc.StoreFront = strings.TrimSpace(storefrontOverride)
	}

	platform, err := parsePlatformOrDefault(platformName)
	if err != nil {
		return "", err
	}

	out, err := st.Lookup(appstore.LookupInput{
		Account:  acc,
		AppID:    appID,
		BundleID: strings.TrimSpace(bundleID),
		Platform: platform,
	})
	if err != nil {
		return "", fmt.Errorf("lookup failed: %w", err)
	}

	dto := toAppDTO(out.App)
	b, err := json.Marshal(dto)
	return string(b), err
}
