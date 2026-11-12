// One-time RESCENE mainnet operator. Pins public launch code and artifacts;
// signs only through the existing project Vault wallet under its database lock.
package main

import (
	"bytes"
	"context"
	"crypto/sha256"
	_ "embed"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"github.com/techbudol1/gmr-engine/internal/config"
	"github.com/techbudol1/gmr-engine/internal/store"
	"github.com/techbudol1/gmr-engine/internal/vaultclient"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"
)

//go:embed pins.json
var pinsJSON []byte

const project = "7fe1ecf2-b715-43bc-ba03-3f0a1149bc5d"
const owner = "0x78646fedde207c4574116ac9c455b56e4091c517"
const dir = "/tmp/rescene-release-cards"

func run() error {
	if len(os.Args) != 2 || os.Args[1] != "--execute" {
		return errors.New("explicit --execute required for Elysium launch")
	}
	var pins map[string]string
	if json.Unmarshal(pinsJSON, &pins) != nil {
		return errors.New("invalid pinned manifest")
	}
	for name, want := range pins {
		data, e := os.ReadFile(filepath.Join(dir, name))
		if e != nil {
			return errors.New("launch file missing")
		}
		hash := sha256.Sum256(data)
		if hex.EncodeToString(hash[:]) != want {
			return errors.New("pinned launch file changed: " + name)
		}
	}
	cfg, e := config.Load()
	if e != nil {
		return errors.New("Engine configuration unavailable")
	}
	ctx, cancel := context.WithTimeout(context.Background(), 45*time.Minute)
	defer cancel()
	db, e := store.NewMemgraphStore(ctx, cfg.MemgraphURI, cfg.MemgraphUser, cfg.MemgraphPassword)
	if e != nil {
		return errors.New("Engine storage unavailable")
	}
	defer db.Close(context.Background())
	app, ok, e := db.GetApp(ctx, project)
	if e != nil || !ok || app.Name != "rescene-rhythm" {
		return errors.New("RESCENE project not found")
	}
	allowed := false
	for _, chain := range app.AllowedChains {
		if chain == 99901 {
			allowed = true
		}
	}
	if !allowed {
		return errors.New("Elysium not allowed")
	}
	wallet, ok, e := db.GetProjectDefaultAdminWalletSecret(ctx, project)
	if e != nil || !ok || !strings.EqualFold(wallet.Address, owner) || !vaultclient.IsReference(wallet.EncryptedPrivateKey) {
		return errors.New("expected Vault wallet unavailable")
	}
	rpc, e := cfg.RPCURL(99901)
	if e != nil {
		return errors.New("Elysium RPC unavailable")
	}
	lock, ok, e := db.AcquireWalletLock(ctx, project, owner, "rescene-release-cards-20261112", 3600)
	if e != nil || !ok {
		return errors.New("project treasury busy")
	}
	defer db.ReleaseWalletLock(context.Background(), lock.AppID, lock.WalletAddress, lock.TransactionID)
	payload := map[string]any{"mode": "launch", "chainId": 99901, "rpcUrl": rpc, "vaultAddress": wallet.Address, "vaultApiKey": cfg.VaultInternalKey, "vaultProjectId": project, "vaultUrl": cfg.VaultURL, "vaultWalletRef": wallet.EncryptedPrivateKey, "wrapper": "0xbA876237B0F021A6c6D852d6c26E107997cC5E81"}
	body, _ := json.Marshal(payload)
	cmd := exec.CommandContext(ctx, "bun", "--no-env-file", dir+"/launch.mjs")
	cmd.Stdin = bytes.NewReader(body)
	cmd.Stdout = os.Stdout
	var privateErrors bytes.Buffer
	cmd.Stderr = &privateErrors
	if cmd.Run() != nil {
		_ = os.WriteFile(dir+"/failure.private.log", privateErrors.Bytes(), 0600)
		return errors.New("Elysium launch incomplete; inspect protected journal before resuming")
	}
	var state struct {
		Status    string `json:"status"`
		Contracts map[string]struct {
			Address  string `json:"address"`
			Artifact string `json:"artifact"`
		} `json:"contracts"`
	}
	data, e := os.ReadFile(dir + "/state-launch.json")
	if e != nil || json.Unmarshal(data, &state) != nil || state.Status != "verified" {
		return errors.New("mainnet verification incomplete")
	}
	var assets map[string]struct {
		ABI json.RawMessage `json:"abi"`
	}
	data, e = os.ReadFile(dir + "/assets.json")
	if e != nil || json.Unmarshal(data, &assets) != nil {
		return errors.New("pinned ABI data unavailable")
	}
	existing, e := db.ListImportedContracts(ctx, project, 500)
	if e != nil {
		return errors.New("cannot inspect project contracts")
	}
	for key, meta := range map[string]struct{ Name, Type, Artifact string }{"releaseCards": {"RESCENE Nine Release LE Cards", "custom", "ReleaseCards"}} {
		target := state.Contracts[key].Address
		found := false
		for _, v := range existing {
			if v.ChainID == 99901 && strings.EqualFold(v.ContractAddress, target) {
				found = true
			}
		}
		if found {
			continue
		}
		abi := assets[meta.Artifact].ABI
		if key == "marketplace" {
			var joined []json.RawMessage
			for _, name := range []string{"MarketplaceV3", "DirectListingsLogic", "EnglishAuctionsLogic", "OffersLogic"} {
				var list []json.RawMessage
				_ = json.Unmarshal(assets[name].ABI, &list)
				joined = append(joined, list...)
			}
			abi, _ = json.Marshal(joined)
		}
		_, e = db.CreateImportedContract(ctx, project, store.ImportedContractInput{Name: meta.Name, ContractType: meta.Type, ContractAddress: target, ChainID: 99901, ABI: string(abi), Description: "RESCENE nine-release LE cards 2026-11-12"})
		if e != nil {
			return errors.New("mainnet deployed; contract import needs recovery")
		}
	}
	fmt.Println(`{"engineImportsVerified":true,"chainId":99901}`)
	return nil
}
func main() {
	if e := run(); e != nil {
		fmt.Fprintln(os.Stderr, e)
		os.Exit(1)
	}
}
