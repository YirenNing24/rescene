package main

import (
	"encoding/json"
	"os"
	"strings"
	"testing"
)

// Defaults must be one coherent deployment: the same sender nonces produced
// different contracts at overlapping addresses on the retired network.
func TestDefaultNetworkMatchesLaunchManifest(t *testing.T) {
	for _, key := range []string{"ORIGIN_ADDR", "ADMIN_GATEWAY_SECRET", "ENGINE_API_KEY", "SHOP_ENABLED", "CARDS_ENABLED", "PULSE_CARDS_ADDRESS", "EVENT_REWARD_ROUTER_ADDRESS", "STARLIGHT_ENABLED", "MARKETPLACE_ENABLED", "LEADERBOARD_ENABLED", "STARLIGHT_TOKEN_ADDRESS", "STARLIGHT_DISTRIBUTOR_ADDRESS", "STARLIGHT_CHAIN_ID", "MARKETPLACE_CHAIN_ID", "MARKETPLACE_ADDRESS", "MARKETPLACE_COLLECTION_ADDRESS", "LEADERBOARD_CHAIN_ID", "LEADERBOARD_ADDRESS", "LEADERBOARD_START_BLOCK", "LEGACY_CARDS_ROUTER_ADDRESS", "STARLIGHT_RPC_URL", "LEADERBOARD_RPC_URL"} {
		t.Setenv(key, "")
	}
	t.Setenv("JWT_SECRET", strings.Repeat("x", 64))
	c, err := loadConfig()
	if err != nil {
		t.Fatal(err)
	}
	var launch struct {
		ChainID   int64 `json:"chainId"`
		Contracts map[string]struct {
			Address string `json:"address"`
		} `json:"contracts"`
	}
	data, err := os.ReadFile("../contracts/deployments/elysium-mainnet.json")
	if err != nil {
		t.Fatal(err)
	}
	if err = json.Unmarshal(data, &launch); err != nil {
		t.Fatal(err)
	}
	if c.StarlightChainID != launch.ChainID || c.MarketplaceChainID != launch.ChainID || c.LeaderboardChainID != launch.ChainID {
		t.Fatal("network defaults disagree with launch")
	}
	for name, got := range map[string]string{"starlight": c.StarlightToken, "starlightRewards": c.StarlightDistributor, "marketplace": c.MarketplaceAddress, "erc1155": c.MarketplaceCollection, "leaderboard": c.LeaderboardAddress} {
		if want, ok := launch.Contracts[name]; !ok || !strings.EqualFold(got, want.Address) {
			t.Errorf("%s: default %s differs from manifest %s", name, got, want.Address)
		}
	}
	if c.LegacyCardsRouter != "" || c.LeaderboardStartBlock != 4774246 {
		t.Fatal("historical network settings leaked into defaults")
	}
}
