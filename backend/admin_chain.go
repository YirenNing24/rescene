package main

import (
	"context"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"github.com/gofiber/fiber/v3"
	"github.com/golang-jwt/jwt/v5"
	"golang.org/x/crypto/bcrypt"
	"math/big"
	"net/url"
	"strconv"
	"strings"
	"time"
)

func adminDocumentRole(g string) string {
	switch g {
	case "notes", "reports", "support":
		return "support"
	case "catalog", "supply-policy":
		return "economy"
	case "missions", "calendars", "events", "announcements", "assets", "chart-releases":
		return "content"
	default:
		return "operations"
	}
}
func (s *adminSystem) login(c fiber.Ctx) error {
	var b struct {
		Key string `json:"key"`
	}
	if json.Unmarshal(c.Body(), &b) != nil || len(b.Key) > 72 {
		return fiber.ErrBadRequest
	}
	rows, e := s.db.adminRows(`MATCH(a:AdminIdentity {email:$email,status:'active'}) RETURN coalesce(a.access_hash,'')`, map[string]interface{}{"email": s.who(c).Email}, "hash")
	if e != nil {
		return e
	}
	if len(rows) == 0 || bcrypt.CompareHashAndPassword([]byte(fmt.Sprint(rows[0]["hash"])), []byte(b.Key)) != nil {
		return failure(c, 401, "invalid_credentials", "The email or administrator access key is incorrect.")
	}
	token, e := jwt.NewWithClaims(jwt.SigningMethodHS256, jwt.MapClaims{"sub": s.who(c).Email, "aud": "remine-admin-gateway", "exp": time.Now().Add(8 * time.Hour).Unix(), "iat": time.Now().Unix()}).SignedString(s.key)
	if e != nil {
		return e
	}
	c.Cookie(&fiber.Cookie{Name: "__Host-remine_admin_auth", Value: token, Secure: true, HTTPOnly: true, SameSite: "Strict", Path: "/", MaxAge: 28800})
	return c.JSON(fiber.Map{"authenticated": true})
}

type adminCall struct {
	Contract string          `json:"contract"`
	Wallet   string          `json:"wallet"`
	Method   string          `json:"method"`
	ABI      json.RawMessage `json:"abi"`
	Args     []string        `json:"args"`
	Data     string          `json:"data"`
	ChainID  int64           `json:"chain_id"`
}

// The operator can only invoke typed, allowlisted methods. There is no arbitrary calldata or signing endpoint.
func buildAdminCall(contract, wallet, method string, types, args []string) (adminCall, error) {
	c := adminCall{Contract: contract, Wallet: wallet, Method: method, Args: args}
	if !validHex(contract, 20) || !validHex(wallet, 20) {
		return c, errors.New("this contract or operator wallet is not configured")
	}
	inputs := []map[string]string{}
	head, tail := "", ""
	if len(types) != len(args) {
		return c, errors.New("argument mismatch")
	}
	for i, t := range types {
		inputs = append(inputs, map[string]string{"name": fmt.Sprint("arg", i), "type": t})
		arg := args[i]
		switch {
		case t == "string":
			head += fmt.Sprintf("%064x", 32*len(types)+len(tail)/2)
			raw := hex.EncodeToString([]byte(arg))
			tail += fmt.Sprintf("%064x", len([]byte(arg))) + raw + strings.Repeat("0", (64-len(raw)%64)%64)
		case t == "address":
			if !validHex(arg, 20) || strings.Trim(arg[2:], "0") == "" {
				return c, errors.New("a nonzero recipient address is required")
			}
			head += addressWord(arg)
		case t == "bytes32":
			if !validHex(arg, 32) {
				return c, errors.New("a valid bytes32 identifier is required")
			}
			head += strings.TrimPrefix(arg, "0x")
		case t == "bool":
			if arg != "true" && arg != "false" {
				return c, errors.New("boolean argument required")
			}
			if arg == "true" {
				head += hexWord(1)
			} else {
				head += hexWord(0)
			}
		case strings.HasPrefix(t, "uint"):
			n, ok := new(big.Int).SetString(arg, 10)
			if !ok || n.Sign() < 0 || n.BitLen() > func() int {
				b, _ := strconv.Atoi(strings.TrimPrefix(t, "uint"))
				if b == 0 {
					return 256
				}
				return b
			}() {
				return c, errors.New("invalid unsigned amount")
			}
			head += fmt.Sprintf("%064x", n)
		default:
			return c, errors.New("unsupported ABI type")
		}
	}
	c.ABI = json.RawMessage(adminJSON([]any{map[string]any{"type": "function", "name": method, "stateMutability": "nonpayable", "inputs": inputs, "outputs": []any{}}}))
	c.Data = selector(method+"("+strings.Join(types, ",")+")") + head + tail
	return c, nil
}
func (s *adminSystem) adminChainSpec(kind, id string, p map[string]any) (adminCall, bool, error) {
	cfg := s.api.config
	var target, method string
	var types, args []string
	str := func(k string) string {
		if p[k] == nil {
			return ""
		}
		return fmt.Sprint(p[k])
	}
	amount := func() (string, error) {
		n := adminInt(p["amount"])
		if n < 1 || n > 1000000 {
			return "", errors.New("STARL amount must be 1–1000000 whole tokens")
		}
		return starlightRaw(n).String(), nil
	}
	switch kind {
	case "mint_item":
		token := adminInt(p["token_id"])
		qty := adminInt(p["quantity"])
		if !(token >= 0 && token <= 5 || token >= 11 && token <= 13) || qty < 1 || qty > 10000 {
			return adminCall{}, true, errors.New("mint only registered item IDs 0–5 or 11–13; quantity 1–10000")
		}
		uri := str("uri")
		if len(uri) > 2048 || !(strings.HasPrefix(uri, "https://") || strings.HasPrefix(uri, "ipfs://")) {
			return adminCall{}, true, errors.New("a reviewed HTTPS or IPFS metadata URI is required")
		}
		target = cfg.MarketplaceCollection
		method = "mintTo"
		types = []string{"address", "uint256", "string", "uint256"}
		args = []string{str("recipient"), fmt.Sprint(token), uri, fmt.Sprint(qty)}
	case "transfer_starl", "approve_allowance", "compensate_starl":
		v, e := amount()
		if e != nil {
			return adminCall{}, true, e
		}
		target = cfg.StarlightToken
		method = "transfer"
		types = []string{"address", "uint256"}
		args = []string{str("recipient"), v}
		if kind == "approve_allowance" {
			method = "approve"
			if !strings.EqualFold(str("recipient"), cfg.StarlightDistributor) && !strings.EqualFold(str("recipient"), cfg.ShopRouter) && !strings.EqualFold(str("recipient"), cfg.CardsRouter) {
				return adminCall{}, true, errors.New("allowances are restricted to configured game routers")
			}
		}
		if kind == "compensate_starl" {
			target = cfg.StarlightDistributor
			method = "pay"
			types = []string{"bytes32", "address", "uint256"}
			args = []string{hashHex([]byte("admin/" + id)), str("recipient"), v}
		}
	case "leaderboard_pause", "leaderboard_unpause":
		target = cfg.LeaderboardAddress
		method = "pause"
		if kind == "leaderboard_unpause" {
			method = "unpause"
		}
	case "board_enable":
		target = cfg.LeaderboardAddress
		method = "setBoardEnabled"
		types = []string{"bytes32", "bool"}
		args = []string{str("board_id"), str("enabled")}
	case "pulse_sales":
		target = cfg.PulseRouter
		method = "setSalesEnabled"
		types = []string{"bool"}
		args = []string{str("enabled")}
		if cfg.PulseRouter == "" {
			return adminCall{}, true, errors.New("PULSE is not configured")
		}
	case "generate_card":
		if cfg.PulseRouter == "" || s.db == nil {
			return adminCall{}, true, errors.New("PULSE is not configured")
		}
		rows, e := s.db.adminRows(`MATCH(o:AdminOperation {id:$id,kind:'generate_card'}) RETURN o.card_roll`, map[string]interface{}{"id": id}, "roll")
		if e != nil || len(rows) == 0 {
			return adminCall{}, true, errors.New("a persisted generation intent is required")
		}
		roll := adminDecode(rows[0]["roll"])
		if len(roll) != 3 {
			return adminCall{}, true, errors.New("generation traits are missing")
		}
		member, rarity := adminInt(p["member"]), adminInt(p["rarity"])
		if member < 0 || member > 4 || rarity < 0 || rarity > 5 {
			return adminCall{}, true, errors.New("invalid member or rarity")
		}
		target, method = cfg.PulseRouter, "generate"
		types = []string{"bytes32", "address", "uint256", "uint256", "uint256", "uint256", "uint256"}
		args = []string{hashHex([]byte("admin/" + id)), str("recipient"), fmt.Sprint(member), fmt.Sprint(rarity), fmt.Sprint(adminInt(roll["score_bp"])), fmt.Sprint(adminInt(roll["recovery_bp"])), fmt.Sprint(adminInt(roll["skill"]))}
	case "listing_cancel":
		target = cfg.MarketplaceAddress
		method = "cancelListing"
		types = []string{"uint256"}
		args = []string{str("listing_id")}
	case "listing_create", "listing_update":
		c, e := s.adminListingCall(kind, p)
		c.ChainID = cfg.StarlightChainID
		return c, true, e
	default:
		return adminCall{}, false, nil
	}
	c, e := buildAdminCall(target, cfg.StarlightTreasury, method, types, args)
	c.ChainID = cfg.StarlightChainID
	return c, true, e
}
func (s *adminSystem) simulateAdminChain(ctx context.Context, c adminCall) error {
	client := newStarlightClient(s.api.config)
	var chain, code, result string
	if e := client.p.rpc(ctx, "eth_chainId", []any{}, &chain); e != nil {
		return errors.New("RPC unavailable")
	}
	n, ok := new(big.Int).SetString(strings.TrimPrefix(chain, "0x"), 16)
	if !ok || n.Int64() != c.ChainID {
		return errors.New("RPC chain does not match this operation")
	}
	if e := client.p.rpc(ctx, "eth_getCode", []any{c.Contract, "latest"}, &code); e != nil || len(code) < 4 {
		return errors.New("target has no deployed contract code")
	}
	if c.Method == "generate" || c.Method == "setSalesEnabled" && len(c.Args) > 0 && c.Args[0] == "true" {
		var allocation string
		if e := client.p.rpc(ctx, "eth_call", []any{map[string]string{"to": c.Contract, "data": selector("INITIAL_LE_ALLOCATION()")}, "latest"}, &allocation); e != nil || allocation != "0x"+hexWord(50) {
			return errors.New("PULSE initial allocation must be 50 per member")
		}
	}
	if e := client.p.rpc(ctx, "eth_call", []any{map[string]string{"from": c.Wallet, "to": c.Contract, "data": c.Data}, "latest"}, &result); e != nil {
		return errors.New("contract simulation reverted or the RPC is unavailable; verify role, balance, stock and arguments")
	}
	return nil
}
func (s *adminSystem) adminEngine() *publicationClient {
	cfg := s.api.config
	cfg.LeaderboardRPC = cfg.StarlightRPC
	cfg.LeaderboardEngineKey = cfg.EngineAPIKey
	return newPublicationClient(cfg)
}
func (s *adminSystem) checkAdminTx(tx enginePublicationTx, c adminCall) error {
	if tx.ID == "" || tx.AppID != s.api.config.EngineProjectID || tx.ChainID != c.ChainID || !strings.EqualFold(tx.ContractAddress, c.Contract) || !strings.EqualFold(tx.WalletAddress, c.Wallet) || tx.Method != c.Method || strings.Join(tx.Args, "\x00") != strings.Join(c.Args, "\x00") {
		return errors.New("Engine transaction differs from the approved immutable intent")
	}
	return nil
}
func (s *adminSystem) executeAdminChain(ctx context.Context, id string, c adminCall) (any, error) {
	if e := s.simulateAdminChain(ctx, c); e != nil {
		return nil, e
	}
	// Persist the full signing intent before submitting; an ambiguous response is reconciled with the same idempotency key.
	if _, e := s.db.query(`MATCH(o:AdminOperation {id:$id}) SET o.result=$result`, map[string]interface{}{"id": id, "result": adminJSON(map[string]any{"spec": c, "idempotency_key": "rescene/admin/" + id})}); e != nil {
		return nil, e
	}
	var out struct {
		Transaction enginePublicationTx `json:"transaction"`
	}
	e := s.adminEngine().json(ctx, "POST", s.api.config.EngineURL+"/v1/contracts/write", map[string]any{"chainId": c.ChainID, "contractAddress": c.Contract, "walletAddress": c.Wallet, "functionName": c.Method, "abi": c.ABI, "args": c.Args, "value": "0"}, "rescene/admin/"+id, &out)
	if e != nil {
		return nil, e
	}
	if e = s.checkAdminTx(out.Transaction, c); e != nil {
		return nil, e
	}
	return map[string]any{"spec": c, "transaction": out.Transaction}, nil
}
func (s *adminSystem) refreshAdminChain(c fiber.Ctx, id, kind string, result map[string]any) error {
	rows, e := s.db.adminRows(`MATCH(o:AdminOperation {id:$id}) RETURN o.payload,o.status`, map[string]interface{}{"id": id}, "payload", "status")
	if e != nil || len(rows) == 0 {
		return fiber.ErrNotFound
	}
	spec, chain, e := s.adminChainSpec(kind, id, adminDecode(rows[0]["payload"]))
	if e != nil {
		return failure(c, 409, "not_ready", e.Error())
	}
	if !chain {
		return failure(c, 409, "local_review", "Review local operation state before taking further action.")
	}
	txMap, _ := result["transaction"].(map[string]any)
	txID, _ := txMap["id"].(string)
	if txID == "" {
		return failure(c, 409, "ambiguous_submission", "No verified Engine transaction ID was retained. Inspect Engine using idempotency key rescene/admin/"+id+" before any resubmission.")
	}
	ctx, cancel := context.WithTimeout(c.Context(), 12*time.Second)
	defer cancel()
	var out struct {
		Transaction enginePublicationTx `json:"transaction"`
	}
	if e = s.adminEngine().json(ctx, "GET", s.api.config.EngineURL+"/v1/transactions/"+url.PathEscape(txID), nil, "read", &out); e != nil {
		return e
	}
	if e = s.checkAdminTx(out.Transaction, spec); e != nil {
		return e
	}
	status := "submitted"
	if out.Transaction.Status == "failed" {
		status = "failed"
	}
	if validHex(out.Transaction.Hash, 32) {
		var receipt *struct {
			Status string `json:"status"`
			Block  string `json:"blockNumber"`
		}
		if e = s.adminEngine().rpc(ctx, "eth_getTransactionReceipt", []any{out.Transaction.Hash}, &receipt); e != nil {
			return e
		}
		if receipt != nil {
			if receipt.Status == "0x0" {
				status = "failed"
			} else {
				var height string
				if e = s.adminEngine().rpc(ctx, "eth_blockNumber", []any{}, &height); e != nil {
					return e
				}
				h, ok := new(big.Int).SetString(strings.TrimPrefix(height, "0x"), 16)
				b, ok2 := new(big.Int).SetString(strings.TrimPrefix(receipt.Block, "0x"), 16)
				if ok && ok2 && h.Int64()-b.Int64()+1 >= s.api.config.StarlightConfirmations {
					status = "confirmed"
				}
			}
		}
	}
	result["transaction"] = out.Transaction
	_, e = s.db.query(`MATCH(o:AdminOperation {id:$id}) SET o.status=$status,o.result=$result,o.updated_at=$now`, map[string]interface{}{"id": id, "status": status, "result": adminJSON(result), "now": time.Now().UnixMilli()})
	return e
}

func (s *adminSystem) validateAdminLocal(kind string, p map[string]any) error {
	id := fmt.Sprint(p["player_id"])
	switch kind {
	case "grant_xp", "grant_energy":
		n := adminInt(p["amount"])
		if n < 1 || n > 100000 || kind == "grant_energy" && n > energyCap {
			return errors.New("grant amount is outside the permitted range")
		}
	case "restrict_uploads", "restrict_social":
		if _, ok := p["restricted"].(bool); !ok {
			return errors.New("restricted must be a boolean")
		}
	case "quarantine_photo", "restore_photo":
		m, e := s.db.ReadProfileMedia(id)
		if e != nil || !m.contains(fmt.Sprint(p["photo_id"])) {
			return errors.New("the photo does not belong to this player")
		}
	case "quarantine_score", "restore_score":
		r, e := s.db.adminRows(`MATCH(b:PersonalBest {key:$key}) RETURN b.key`, map[string]interface{}{"key": fmt.Sprint(p["score_id"])}, "id")
		if e != nil {
			return e
		}
		if len(r) == 0 {
			return errors.New("the personal best key was not found")
		}
		return nil
	case "retry_job":
		if !map[string]bool{"shop": true, "payout": true, "score": true, "wallet": true}[fmt.Sprint(p["job_type"])] || fmt.Sprint(p["job_id"]) == "" {
			return errors.New("provide an original durable job type and key")
		}
		return nil
	case "suspend", "restore", "revoke_sessions":
	default:
		return errors.New("unsupported local operation")
	}
	if _, e := s.api.store.ByID(id); e != nil {
		return errors.New("the player was not found")
	}
	return nil
}

func (s *adminSystem) adminListingCall(kind string, p map[string]any) (adminCall, error) {
	cfg := s.api.config
	id := adminInt(p["token_id"])
	quantity := adminInt(p["quantity"])
	price := adminInt(p["price"])
	start := adminInt(p["starts_at"])
	end := adminInt(p["ends_at"])
	expected := int64(0)
	switch {
	case id == 0:
		expected = 100
	case id >= 1 && id <= 5:
		expected = 450
	default:
		for _, m := range cardMaterials {
			if m.TokenID == id {
				expected = int64(m.Price)
			}
		}
	}
	if expected == 0 || price != expected || quantity < 1 || quantity > 10000 || start < 0 || end <= start || end < time.Now().Unix() {
		return adminCall{}, errors.New("use a registered stock item, its fixed router price, quantity 1–10000 and valid Unix-second dates")
	}
	components := []map[string]string{}
	names := []string{"assetContract", "tokenId", "quantity", "currency", "pricePerToken", "startTimestamp", "endTimestamp", "reserved"}
	types := []string{"address", "uint256", "uint256", "address", "uint256", "uint128", "uint128", "bool"}
	args := []string{cfg.MarketplaceCollection, fmt.Sprint(id), fmt.Sprint(quantity), cfg.StarlightToken, starlightRaw(price).String(), fmt.Sprint(start), fmt.Sprint(end), "false"}
	tuple := map[string]any{}
	for i, name := range names {
		components = append(components, map[string]string{"name": name, "type": types[i]})
		tuple[name] = args[i]
	}
	tuple["reserved"] = false
	packed, e := buildAdminCall(cfg.MarketplaceAddress, cfg.StarlightTreasury, "createListing", types, args)
	if e != nil {
		return packed, e
	}
	method := "createListing"
	signature := "createListing((" + strings.Join(types, ",") + "))"
	inputs := []any{map[string]any{"name": "_params", "type": "tuple", "components": components}}
	engineArgs := []string{adminJSON(tuple)}
	head := ""
	if kind == "listing_update" {
		listing := fmt.Sprint(p["listing_id"])
		if listing == "" || listing == "<nil>" {
			return packed, errors.New("listing ID is required")
		}
		n, ok := new(big.Int).SetString(listing, 10)
		if !ok || n.Sign() < 0 || n.BitLen() > 256 {
			return packed, errors.New("invalid listing ID")
		}
		head = fmt.Sprintf("%064x", n)
		method = "updateListing"
		signature = "updateListing(uint256,(" + strings.Join(types, ",") + "))"
		inputs = append([]any{map[string]string{"name": "_listingId", "type": "uint256"}}, inputs...)
		engineArgs = append([]string{listing}, engineArgs...)
	}
	packed.Method = method
	packed.Args = engineArgs
	packed.Data = selector(signature) + head + packed.Data[10:]
	packed.ABI = json.RawMessage(adminJSON([]any{map[string]any{"type": "function", "name": method, "inputs": inputs, "outputs": []any{}, "stateMutability": "nonpayable"}}))
	return packed, nil
}
