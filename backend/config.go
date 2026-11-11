package main

import (
	"crypto/rand"
	"encoding/hex"
	"errors"
	"net/url"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"time"
)

type config struct {
	EventRewardRouter                                                                         string
	EdgeSecret, OriginAddr                                                                    string
	Addr, DatabaseURL, Graph                                                                  string
	Secret                                                                                    []byte
	TokenTTL                                                                                  time.Duration
	EngineURL, EngineAPIKey, EngineProjectID                                                  string
	LeaderboardEnabled                                                                        bool
	LeaderboardAddress, LeaderboardRPC, LeaderboardPublisher, LeaderboardEngineKey            string
	LeaderboardChainID, LeaderboardConfirmations, LeaderboardStartBlock                       int64
	MarketplaceEnabled                                                                        bool
	MarketplaceAddress, MarketplaceCollection, MarketplaceEngineKey                           string
	MarketplaceChainID                                                                        int64
	StarlightEnabled                                                                          bool
	StarlightToken, StarlightTreasury, StarlightDistributor, StarlightEngineKey, StarlightRPC string
	StarlightChainID, StarlightConfirmations                                                  int64
	ShopEnabled                                                                               bool
	ShopRouter                                                                                string
	ShopTokenID, ShopListingID                                                                int64
	CardsEnabled                                                                              bool
	CardsRouter                                                                               string
	LegacyCardsRouter                                                                         string
	PulseRouter                                                                               string
	MediaDir                                                                                  string
	AdminKey, AdminOwner, AdminBootstrap                                                      string
}

func env(key, fallback string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return fallback
}

func loadConfig() (config, error) {
	c := config{Addr: env("ADDR", "127.0.0.1:8080"), DatabaseURL: env("FALKORDB_URL", "redis://127.0.0.1:6379"), Graph: env("FALKORDB_GRAPH", "rescene"), TokenTTL: time.Hour}
	c.EdgeSecret = os.Getenv("ORIGIN_EDGE_SECRET")
	c.OriginAddr = os.Getenv("ORIGIN_ADDR")
	if c.OriginAddr != "" && len(c.EdgeSecret) < 32 {
		return c, errors.New("Origin requires a private edge credential of at least 32 bytes")
	}
	c.AdminKey = os.Getenv("ADMIN_GATEWAY_SECRET")
	c.AdminOwner = env("ADMIN_OWNER_EMAIL", "paulanthonyarriola@gmail.com")
	c.AdminBootstrap = os.Getenv("ADMIN_BOOTSTRAP_KEY")
	if c.AdminKey != "" && len(c.AdminKey) < 32 {
		return c, errors.New("ADMIN_GATEWAY_SECRET must be at least 32 characters")
	}
	c.MediaDir = env("PROFILE_MEDIA_DIR", "data/profile_media")
	c.EngineURL = strings.TrimRight(env("ENGINE_BASE_URL", "https://engine.fluentxverse.com"), "/")
	c.EngineAPIKey = strings.TrimSpace(os.Getenv("ENGINE_API_KEY"))
	c.EngineProjectID = strings.TrimSpace(os.Getenv("ENGINE_PROJECT_ID"))
	var shopErr error
	c.ShopEnabled, shopErr = strconv.ParseBool(env("SHOP_ENABLED", "false"))
	if shopErr != nil {
		return c, errors.New("SHOP_ENABLED must be true or false")
	}
	c.ShopRouter = strings.ToLower(os.Getenv("SHOP_ROUTER_ADDRESS"))
	c.CardsEnabled, shopErr = strconv.ParseBool(env("CARDS_ENABLED", "false"))
	if shopErr != nil {
		return c, errors.New("CARDS_ENABLED must be true or false")
	}
	c.CardsRouter = strings.ToLower(os.Getenv("CARDS_ROUTER_ADDRESS"))
	c.PulseRouter = strings.ToLower(os.Getenv("PULSE_CARDS_ADDRESS"))
	c.EventRewardRouter = strings.ToLower(os.Getenv("EVENT_REWARD_ROUTER_ADDRESS"))
	if c.EventRewardRouter != "" && (!validHex(c.EventRewardRouter, 20) || !c.ShopEnabled) {
		return c, errors.New("Event rewards require an enabled shop and a valid router address")
	}
	if c.PulseRouter != "" && (!validHex(c.PulseRouter, 20) || !c.CardsEnabled || !c.ShopEnabled) {
		return c, errors.New("PULSE_CARDS_ADDRESS requires enabled cards/shop and a valid address")
	}
	c.LegacyCardsRouter = strings.ToLower(os.Getenv("LEGACY_CARDS_ROUTER_ADDRESS"))
	c.ShopTokenID, shopErr = strconv.ParseInt(env("SHOP_TOKEN_ID", "0"), 10, 64)
	if shopErr != nil || c.ShopTokenID < 0 {
		return c, errors.New("SHOP_TOKEN_ID must be nonnegative")
	}
	c.ShopListingID, shopErr = strconv.ParseInt(env("SHOP_LISTING_ID", "0"), 10, 64)
	if shopErr != nil || c.ShopListingID < 0 {
		return c, errors.New("SHOP_LISTING_ID must be nonnegative")
	}
	var starlightErr error
	c.StarlightEnabled, starlightErr = strconv.ParseBool(env("STARLIGHT_ENABLED", "false"))
	if starlightErr != nil {
		return c, errors.New("STARLIGHT_ENABLED must be true or false")
	}
	c.StarlightToken = strings.ToLower(env("STARLIGHT_TOKEN_ADDRESS", "0x910fc4146af825cb949fad284af62d3896c7cbbc"))
	c.StarlightTreasury = strings.ToLower(env("STARLIGHT_TREASURY_ADDRESS", "0x78646fedde207c4574116ac9c455b56e4091c517"))
	c.StarlightDistributor = strings.ToLower(env("STARLIGHT_DISTRIBUTOR_ADDRESS", "0x0464d7f767babcef6a800ea797ea085d69551081"))
	c.StarlightEngineKey = strings.TrimSpace(env("STARLIGHT_ENGINE_API_KEY", c.EngineAPIKey))
	c.StarlightRPC = env("STARLIGHT_RPC_URL", "https://rpc.elysium.kinetiq.xyz")
	c.StarlightChainID, starlightErr = strconv.ParseInt(env("STARLIGHT_CHAIN_ID", "99901"), 10, 64)
	if starlightErr != nil {
		return c, errors.New("STARLIGHT_CHAIN_ID must be an integer")
	}
	// Historical First Scene inventory exists only on the original test network.
	if c.LegacyCardsRouter == "" && c.StarlightChainID == 421614 {
		c.LegacyCardsRouter = "0xa8e3dd8cf231da2bf318e0e6c3486c11b6d1acb7"
	}
	c.StarlightConfirmations, starlightErr = strconv.ParseInt(env("STARLIGHT_CONFIRMATIONS", "3"), 10, 64)
	if starlightErr != nil {
		return c, errors.New("STARLIGHT_CONFIRMATIONS must be an integer")
	}
	if c.StarlightEnabled {
		if err := validateStarlightConfig(c); err != nil {
			return c, err
		}
	}
	var marketplaceErr error
	c.MarketplaceEnabled, marketplaceErr = strconv.ParseBool(env("MARKETPLACE_ENABLED", "false"))
	if marketplaceErr != nil {
		return c, errors.New("MARKETPLACE_ENABLED must be true or false")
	}
	c.MarketplaceAddress = strings.ToLower(env("MARKETPLACE_ADDRESS", "0xb5cc39d72012345198bf17c56c1bbb4adad60933"))
	c.MarketplaceCollection = strings.ToLower(env("MARKETPLACE_COLLECTION_ADDRESS", "0x792508772bc395d038c87e7b7b0d05c55deb0706"))
	c.MarketplaceChainID, marketplaceErr = strconv.ParseInt(env("MARKETPLACE_CHAIN_ID", "99901"), 10, 64)
	if marketplaceErr != nil {
		return c, errors.New("MARKETPLACE_CHAIN_ID must be an integer")
	}
	c.MarketplaceEngineKey = strings.TrimSpace(env("MARKETPLACE_ENGINE_API_KEY", c.EngineAPIKey))
	if c.MarketplaceEnabled {
		if err := validateMarketplaceConfig(c); err != nil {
			return c, err
		}
	}
	var enabledErr error
	c.LeaderboardEnabled, enabledErr = strconv.ParseBool(env("LEADERBOARD_ENABLED", "false"))
	if enabledErr != nil {
		return c, errors.New("LEADERBOARD_ENABLED must be true or false")
	}
	c.LeaderboardAddress = strings.ToLower(env("LEADERBOARD_ADDRESS", "0xc0bb3f4190d5732878536fc15c75c712e9966d33"))
	c.LeaderboardPublisher = strings.ToLower(env("LEADERBOARD_PUBLISHER", "0x78646fedde207c4574116ac9c455b56e4091c517"))
	c.LeaderboardRPC = env("LEADERBOARD_RPC_URL", "https://rpc.elysium.kinetiq.xyz")
	c.LeaderboardEngineKey = strings.TrimSpace(os.Getenv("LEADERBOARD_ENGINE_API_KEY"))
	c.LeaderboardChainID, _ = strconv.ParseInt(env("LEADERBOARD_CHAIN_ID", "99901"), 10, 64)
	c.LeaderboardStartBlock, _ = strconv.ParseInt(env("LEADERBOARD_START_BLOCK", "4774246"), 10, 64)
	c.LeaderboardConfirmations, _ = strconv.ParseInt(env("LEADERBOARD_CONFIRMATIONS", "3"), 10, 64)
	if c.LeaderboardEnabled {
		if err := validatePublisherConfig(c); err != nil {
			return c, err
		}
	}
	if c.EngineAPIKey != "" {
		parsed, err := url.Parse(c.EngineURL)
		if err != nil || parsed.Scheme != "https" || parsed.Host == "" || parsed.User != nil || parsed.RawQuery != "" || parsed.Fragment != "" {
			return c, errors.New("ENGINE_BASE_URL must be an HTTPS URL without credentials, query or fragment")
		}
		if c.EngineProjectID == "" {
			return c, errors.New("ENGINE_PROJECT_ID is required when wallet integration is enabled")
		}
	}
	var err error
	c.TokenTTL, err = time.ParseDuration(env("JWT_TTL", "1h"))
	if err != nil || c.TokenTTL < time.Minute || c.TokenTTL > 24*time.Hour {
		return c, errors.New("JWT_TTL must be between 1m and 24h")
	}
	c.Secret = []byte(os.Getenv("JWT_SECRET"))
	if len(c.Secret) == 0 {
		if env("APP_ENV", "development") != "development" {
			return c, errors.New("JWT_SECRET is required outside development")
		}
		// Development-only key, retained across restarts and never included in the game.
		dir := env("DATA_DIR", "./data")
		if err = os.MkdirAll(dir, 0700); err != nil {
			return c, err
		}
		path := filepath.Join(dir, "jwt.key")
		c.Secret, err = os.ReadFile(path)
		if os.IsNotExist(err) {
			key := make([]byte, 32)
			if _, err = rand.Read(key); err != nil {
				return c, err
			}
			file, openErr := os.OpenFile(path, os.O_WRONLY|os.O_CREATE|os.O_EXCL, 0600)
			if openErr != nil {
				return c, openErr
			}
			c.Secret = []byte(hex.EncodeToString(key))
			_, err = file.Write(c.Secret)
			closeErr := file.Close()
			if err == nil {
				err = closeErr
			}
		}
		if err != nil {
			return c, err
		}
	}
	if len(c.Secret) < 32 {
		return c, errors.New("JWT_SECRET must contain at least 32 random bytes")
	}
	if c.ShopEnabled && (!c.StarlightEnabled || !c.MarketplaceEnabled || !validHex(c.ShopRouter, 20) || c.MarketplaceChainID != c.StarlightChainID) {
		return c, errors.New("Shop requires STARL, MarketplaceV3, managed wallets and router on the same chain")
	}
	if c.CardsEnabled && (!c.ShopEnabled || !validHex(c.CardsRouter, 20) || strings.EqualFold(c.CardsRouter, c.ShopRouter)) {
		return c, errors.New("Cards require the enabled shop and a separate member card router")
	}
	return c, nil
}
