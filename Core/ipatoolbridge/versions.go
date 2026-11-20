package ipatoolbridge

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"time"

	"github.com/majd/ipatool/v2/pkg/appstore"
)

// VersionHistoryDTO is returned by ListVersions.
type VersionHistoryDTO struct {
	LatestVersionID string   `json:"latestVersionId"`
	VersionIDs      []string `json:"versionIds"`
}

// VersionMetadataDTO is returned by GetVersionMetadata.
type VersionMetadataDTO struct {
	VersionID      string `json:"versionId"`
	DisplayVersion string `json:"displayVersion"`
	ReleaseDate    string `json:"releaseDate,omitempty"`
}

// ListVersions returns all external version identifiers for an app.
// If the account does not yet own a free license and purchaseIfNeeded is true,
// it acquires the free license automatically before listing versions.
func (c *Client) ListVersions(accountID string, appID int64, bundleID string, price float64, platformName string, purchaseIfNeeded bool) (string, error) {
	st, acc, err := c.loadAccount(accountID)
	if err != nil {
		return "", err
	}

	platform, err := parsePlatformOrDefault(platformName)
	if err != nil {
		return "", err
	}

	app := appstore.App{
		ID:       appID,
		BundleID: bundleID,
		Price:    price,
	}

	ctx, cancel := context.WithTimeout(context.Background(), 45*time.Second)
	defer cancel()

	out, err := st.ListVersions(appstore.ListVersionsInput{
		Context:  ctx,
		Account:  acc,
		App:      app,
		Platform: platform,
	})
	if err != nil && errors.Is(err, appstore.ErrLicenseRequired) && purchaseIfNeeded && price == 0 {
		if pErr := st.Purchase(appstore.PurchaseInput{
			Account:  acc,
			App:      app,
			Platform: platform,
		}); pErr != nil && !errors.Is(pErr, appstore.ErrLicenseAlreadyExists) {
			return "", fmt.Errorf("failed to acquire free license: %w", pErr)
		}
		out, err = st.ListVersions(appstore.ListVersionsInput{
			Context:  ctx,
			Account:  acc,
			App:      app,
			Platform: platform,
		})
	}
	if err != nil {
		return "", fmt.Errorf("list versions failed: %w", err)
	}

	dto := VersionHistoryDTO{
		LatestVersionID: out.LatestExternalVersionID,
		VersionIDs:      out.ExternalVersionIdentifiers,
	}
	b, err := json.Marshal(dto)
	return string(b), err
}

// GetVersionMetadata resolves the human-readable display version (e.g. "1.2.3")
// and release date for a specific externalVersionID.
func (c *Client) GetVersionMetadata(accountID string, appID int64, bundleID, versionID, platformName string) (string, error) {
	st, acc, err := c.loadAccount(accountID)
	if err != nil {
		return "", err
	}

	platform, err := parsePlatformOrDefault(platformName)
	if err != nil {
		return "", err
	}

	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()

	out, err := st.GetVersionMetadata(appstore.GetVersionMetadataInput{
		Context:   ctx,
		Account:   acc,
		App:       appstore.App{ID: appID, BundleID: bundleID},
		VersionID: versionID,
		Platform:  platform,
	})
	if err != nil {
		return "", fmt.Errorf("get version metadata failed: %w", err)
	}

	dto := VersionMetadataDTO{
		VersionID:      versionID,
		DisplayVersion: out.DisplayVersion,
	}
	if !out.ReleaseDate.IsZero() {
		dto.ReleaseDate = out.ReleaseDate.Format(time.RFC3339)
	}

	b, err := json.Marshal(dto)
	return string(b), err
}
