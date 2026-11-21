package ipatoolbridge

import (
	"encoding/json"
	"fmt"
	"net/http"
	"net/url"
	"strconv"
	"strings"
	"time"

	"github.com/majd/ipatool/v2/pkg/appstore"
)

// AppDTO represents an App Store application for Swift.
type AppDTO struct {
	ID         int64    `json:"id"`
	BundleID   string   `json:"bundleId"`
	Name       string   `json:"name"`
	Version    string   `json:"version"`
	Price      float64  `json:"price"`
	ArtworkURL string   `json:"artworkUrl,omitempty"`
	SellerName string   `json:"sellerName,omitempty"`
	Platforms  []string `json:"platforms,omitempty"`
}

var catalogHTTPClient = &http.Client{Timeout: 6 * time.Second}

func enrichAppDTOsWithArtwork(apps []AppDTO) {
	if len(apps) == 0 {
		return
	}
	ids := make([]string, 0, len(apps))
	for _, a := range apps {
		if a.ID > 0 {
			ids = append(ids, strconv.FormatInt(a.ID, 10))
		}
	}
	if len(ids) == 0 {
		return
	}

	params := url.Values{}
	params.Set("id", strings.Join(ids, ","))
	req, err := http.NewRequest(http.MethodGet, "https://itunes.apple.com/lookup?"+params.Encode(), nil)
	if err != nil {
		return
	}
	resp, err := catalogHTTPClient.Do(req)
	if err != nil {
		return
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return
	}

	var payload struct {
		Results []struct {
			TrackID       int64  `json:"trackId"`
			ArtworkURL100 string `json:"artworkUrl100"`
			ArtworkURL512 string `json:"artworkUrl512"`
			ArtworkURL60  string `json:"artworkUrl60"`
			ArtistName    string `json:"artistName"`
			SellerName    string `json:"sellerName"`
		} `json:"results"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&payload); err != nil {
		return
	}

	byID := make(map[int64]struct {
		artwork string
		seller  string
	}, len(payload.Results))
	for _, item := range payload.Results {
		art := item.ArtworkURL100
		if art == "" {
			art = item.ArtworkURL512
		}
		if art == "" {
			art = item.ArtworkURL60
		}
		seller := item.ArtistName
		if seller == "" {
			seller = item.SellerName
		}
		byID[item.TrackID] = struct {
			artwork string
			seller  string
		}{artwork: art, seller: seller}
	}

	for i := range apps {
		if meta, ok := byID[apps[i].ID]; ok {
			apps[i].ArtworkURL = meta.artwork
			apps[i].SellerName = meta.seller
		}
	}
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
	enrichAppDTOsWithArtwork(results)

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

	items := []AppDTO{toAppDTO(out.App)}
	enrichAppDTOsWithArtwork(items)
	b, err := json.Marshal(items[0])
	return string(b), err
}
