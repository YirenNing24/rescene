package main

import (
	"context"
	"errors"
	"math/big"
	"net/url"
	"strings"
	"sync"
	"time"

	"github.com/gofiber/fiber/v3"
)

// Contract status is read-only; checkout is restricted to the configured real item.
type marketplaceStatus struct {
	Status            string `json:"status"`
	ChainID           int64  `json:"chain_id"`
	ContractAddress   string `json:"contract_address"`
	CollectionAddress string `json:"collection_address"`
	TotalListings     string `json:"total_listings,omitempty"`
	CheckedAt         string `json:"checked_at,omitempty"`
	CheckoutEnabled   bool   `json:"checkout_enabled"`
	PaymentToken      string `json:"payment_token_address,omitempty"`
	PaymentSymbol     string `json:"payment_symbol,omitempty"`
	ShopRouter        string `json:"shop_router_address,omitempty"`
}

type marketplaceService struct {
	cfg     config
	client  *publicationClient
	mu      sync.Mutex
	cached  marketplaceStatus
	lastErr error
	expires time.Time
}

func validateMarketplaceConfig(c config) error {
	u, err := url.Parse(c.EngineURL)
	if err != nil || u.Scheme != "https" || u.Host == "" || u.User != nil || u.RawQuery != "" || u.Fragment != "" {
		return errors.New("marketplace Engine URL must use HTTPS without credentials, query or fragment")
	}
	if c.MarketplaceEngineKey == "" || c.EngineProjectID == "" || c.MarketplaceChainID <= 0 || !validHex(c.MarketplaceAddress, 20) || !validHex(c.MarketplaceCollection, 20) {
		return errors.New("marketplace requires project, contracts:read Engine key, chain, marketplace and collection addresses")
	}
	return nil
}

func newMarketplaceService(c config) *marketplaceService {
	// A separate client/key avoids giving the leaderboard publisher additional scopes.
	clientConfig := c
	clientConfig.LeaderboardEngineKey = c.MarketplaceEngineKey
	return &marketplaceService{cfg: c, client: newPublicationClient(clientConfig)}
}

func (m *marketplaceService) read(ctx context.Context, function, outputType string) (string, error) {
	var response struct {
		Result struct {
			Result string `json:"result"`
		} `json:"result"`
	}
	abi := []any{map[string]any{"type": "function", "name": function, "stateMutability": "view", "inputs": []any{}, "outputs": []any{map[string]string{"name": "", "type": outputType}}}}
	err := m.client.json(ctx, "POST", m.cfg.EngineURL+"/v1/contracts/read", map[string]any{"chainId": m.cfg.MarketplaceChainID, "contractAddress": m.cfg.MarketplaceAddress, "functionName": function, "abi": abi, "args": []string{}}, "read", &response)
	return response.Result.Result, err
}

func (m *marketplaceService) status(ctx context.Context) (marketplaceStatus, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	if time.Now().Before(m.expires) {
		return m.cached, m.lastErr
	}
	out := marketplaceStatus{Status: "not_configured", ChainID: m.cfg.MarketplaceChainID, ContractAddress: m.cfg.MarketplaceAddress, CollectionAddress: m.cfg.MarketplaceCollection}
	if m.cfg.StarlightEnabled && m.cfg.StarlightChainID == m.cfg.MarketplaceChainID {
		out.PaymentToken, out.PaymentSymbol = m.cfg.StarlightToken, "STARL"
		if m.cfg.ShopEnabled {
			out.CheckoutEnabled = true
			out.ShopRouter = m.cfg.ShopRouter
		}
	}
	if !m.cfg.MarketplaceEnabled {
		return out, nil
	}
	ctx, cancel := context.WithTimeout(ctx, 6*time.Second)
	defer cancel()
	out.Status = "unavailable"
	err := m.verify(ctx, &out)
	// Never serve stale successful reads as a fresh connection after a failure.
	m.cached, m.lastErr = out, err
	m.expires = time.Now().Add(30 * time.Second)
	if err != nil {
		m.expires = time.Now().Add(5 * time.Second)
	}
	return out, err
}

func (m *marketplaceService) verify(ctx context.Context, out *marketplaceStatus) error {
	var chain struct {
		Result string `json:"result"`
	}
	if err := m.client.json(ctx, "POST", m.cfg.EngineURL+"/v1/rpc/read", map[string]any{"chainId": m.cfg.MarketplaceChainID, "method": "eth_chainId", "params": []any{}}, "read", &chain); err != nil {
		return err
	}
	chainID, err := parseQuantity(chain.Result)
	if err != nil || chainID != m.cfg.MarketplaceChainID {
		return errors.New("marketplace_chain_mismatch")
	}
	kind, err := m.read(ctx, "contractType", "bytes32")
	if err != nil {
		return err
	}
	if strings.ToLower(kind) != "0x4d61726b6574706c616365563300000000000000000000000000000000000000" {
		return errors.New("marketplace_contract_mismatch")
	}
	count, err := m.read(ctx, "totalListings", "uint256")
	if err != nil {
		return err
	}
	n, ok := new(big.Int).SetString(count, 10)
	if !ok || n.Sign() < 0 || n.BitLen() > 256 || n.String() != count {
		return errors.New("marketplace_response_invalid")
	}
	out.Status, out.TotalListings, out.CheckedAt = "connected", count, time.Now().UTC().Format(time.RFC3339)
	return nil
}

func (a *api) getMarketplace(c fiber.Ctx) error {
	status, err := a.marketplace.status(c.Context())
	if err != nil {
		// Do not leak upstream errors, keys, or return an unavailable count as zero.
		return c.Status(503).JSON(fiber.Map{"marketplace": status, "error": fiber.Map{"code": "marketplace_unavailable", "message": "The marketplace is temporarily unavailable. Please try again later."}})
	}
	return c.JSON(fiber.Map{"marketplace": status})
}
