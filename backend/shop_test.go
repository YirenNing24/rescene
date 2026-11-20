package main

import (
	"context"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"github.com/gofiber/fiber/v3"
	"golang.org/x/crypto/bcrypt"
	"net/http"
	"net/http/httptest"
	"os"
	"strconv"
	"strings"
	"sync"
	"testing"
	"time"
)

type shopFixture struct {
	head                            int64
	blocks                          map[string]int64
	pulse                           *pulseFixture
	cfg                             config
	server                          *httptest.Server
	balance, owned, payments, burns int64
	cardOwned                       map[int64]int64
	records                         map[string]shopJob
	hashes                          map[string]string
	txs                             map[string]enginePublicationTx
	lost, wrong                     bool
}

func newShopFixture(t *testing.T) *shopFixture {
	f := &shopFixture{head: 120, blocks: map[string]int64{}, cfg: starlightTestConfig(), balance: 500, cardOwned: map[int64]int64{}, records: map[string]shopJob{}, hashes: map[string]string{}, txs: map[string]enginePublicationTx{}}
	f.cfg.ShopEnabled = true
	f.cfg.CardsRouter = "0x" + strings.Repeat("9", 40)
	f.cfg.ShopRouter = "0x" + strings.Repeat("6", 40)
	f.cfg.MarketplaceEnabled = true
	f.cfg.MarketplaceAddress = "0x" + strings.Repeat("7", 40)
	f.cfg.MarketplaceCollection = "0x" + strings.Repeat("8", 40)
	f.server = httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		if f.pulse != nil && f.pulse.serve(w, r) {
			return
		}
		if r.URL.Path == "/v1/contracts/write" {
			var b struct {
				ChainID                                      int64
				ContractAddress, WalletAddress, FunctionName string
				Args                                         []string
			}
			_ = json.NewDecoder(r.Body).Decode(&b)
			if r.Header.Get("X-GMR-Engine-Key") != "star-key" {
				t.Error("missing server credential")
			}
			identity := r.Header.Get("Idempotency-Key")
			tx, ok := f.txs[identity]
			if !ok {
				tx = enginePublicationTx{ID: fmt.Sprint(len(f.txs) + 1), AppID: f.cfg.EngineProjectID, ChainID: b.ChainID, ContractAddress: b.ContractAddress, WalletAddress: b.WalletAddress, Method: b.FunctionName, Args: b.Args, Status: "confirmed", Hash: fmt.Sprintf("0x%064x", len(f.txs)+1)}
				if b.FunctionName == "purchase" || b.FunctionName == "purchaseCard" || b.FunctionName == "purchaseItem" || b.FunctionName == "enhance" || b.FunctionName == "consume" {
					id := strings.TrimPrefix(b.Args[0], "0x")
					if _, exists := f.records[id]; !exists {
						j := shopJob{Key: id, Wallet: b.Args[1], Quantity: 1, Kind: "buy"}
						if b.FunctionName == "purchaseCard" || b.FunctionName == "purchaseItem" {
							tid, _ := strconv.ParseInt(b.Args[3], 10, 64)
							for _, card := range memberCards {
								if card.TokenID == tid {
									j.ItemID = card.ID
								}
							}
							for _, mat := range cardMaterials {
								if mat.TokenID == tid {
									j.ItemID = mat.ID
								}
							}
							j.Quantity, _ = strconv.Atoi(b.Args[2])
							f.payments++
							itemClient, _ := newShopClient(f.cfg).forItem(j.ItemID)
							f.balance -= int64(itemClient.price() * j.Quantity)
							f.cardOwned[tid] += int64(j.Quantity)
						} else if b.FunctionName == "enhance" {
							mid, _ := strconv.ParseInt(b.Args[2], 10, 64)
							cid, _ := strconv.ParseInt(b.Args[3], 10, 64)
							for _, mat := range cardMaterials {
								if mat.TokenID == mid {
									j.ItemID = mat.ID
								}
							}
							for _, card := range memberCards {
								if card.TokenID == cid {
									j.CardID = card.ID
								}
							}
							j.Kind = "enhance"
							f.burns++
							f.cardOwned[mid]--
						} else if b.FunctionName == "purchase" {
							f.payments++
							f.balance -= 100
							f.owned++
						} else {
							j.Kind = "consume"
							f.burns++
							f.owned--
						}
						f.head += 3
						f.blocks[id] = f.head - 2
						f.records[id] = j
						f.hashes[id] = tx.Hash
					}
				}
				f.txs[identity] = tx
			}
			if f.lost && (b.FunctionName == "purchase" || b.FunctionName == "purchaseCard" || b.FunctionName == "purchaseItem" || b.FunctionName == "enhance") {
				f.lost = false
				w.WriteHeader(503)
				fmt.Fprint(w, `{"error":"private upstream details"}`)
				return
			}
			_ = json.NewEncoder(w).Encode(map[string]any{"transaction": tx})
			return
		}
		if strings.HasPrefix(r.URL.Path, "/v1/transactions/") {
			for _, tx := range f.txs {
				if strings.TrimPrefix(r.URL.Path, "/v1/transactions/") == tx.ID {
					_ = json.NewEncoder(w).Encode(map[string]any{"transaction": tx})
					return
				}
			}
			w.WriteHeader(404)
			return
		}
		var req struct {
			Method string
			Params []json.RawMessage
		}
		_ = json.NewDecoder(r.Body).Decode(&req)
		var result any
		switch req.Method {
		case "eth_blockNumber":
			result = fmt.Sprintf("0x%x", f.head)
		case "eth_getBalance":
			result = "0x100000000000000"
		case "eth_call":
			var call struct{ To, Data string }
			_ = json.Unmarshal(req.Params[0], &call)
			d := call.Data
			switch {
			case strings.HasPrefix(d, selector("getListing(uint256)")):
				id, _ := wordInt("0x"+d[10:], 0)
				price := int64(100)
				if id > 0 {
					price = 450
				}
				for _, mat := range cardMaterials {
					if mat.TokenID == id {
						price = int64(mat.Price)
					}
				}
				result = "0x" + hexWord(id) + hexWord(id) + hexWord(10000) + hex.EncodeToString(starlightRaw(price).FillBytes(make([]byte, 32))) + hexWord(0) + hexWord(2082758400) + addressWord(f.cfg.StarlightTreasury) + addressWord(f.cfg.MarketplaceCollection) + addressWord(f.cfg.StarlightToken) + hexWord(1) + hexWord(1) + hexWord(0)
			case strings.HasPrefix(d, selector("balanceOfBatch(address[],uint256[])")):
				tokenOffset, _ := wordInt("0x"+d[10:], 1)
				n, _ := wordInt("0x"+d[10:], int(tokenOffset/32))
				raw := "0x" + hexWord(32) + hexWord(n)
				for i := range int(n) {
					tid, _ := wordInt("0x"+d[10:], int(tokenOffset/32)+1+i)
					quantity := f.cardOwned[tid]
					if tid == 0 {
						quantity = f.owned
					}
					raw += hexWord(quantity)
				}
				result = raw
			case strings.HasPrefix(d, selector("balanceOf(address,uint256)")):
				id, _ := wordInt("0x"+d[10:], 1)
				owned := f.owned
				if id > 0 {
					owned = f.cardOwned[id]
				}
				result = "0x" + hexWord(owned)
			case strings.HasPrefix(d, selector("balanceOf(address)")):
				result = "0x" + hex.EncodeToString(starlightRaw(f.balance).FillBytes(make([]byte, 32)))
			case strings.HasPrefix(d, selector("allowance(address,address)")):
				result = "0x" + hex.EncodeToString(starlightRaw(100000).FillBytes(make([]byte, 32)))
			case strings.HasPrefix(d, selector("isApprovedForAll(address,address)")):
				result = "0x" + hexWord(1)
			case strings.HasPrefix(d, selector("purchases(bytes32)")), strings.HasPrefix(d, selector("enhancements(bytes32)")), strings.HasPrefix(d, selector("consumptions(bytes32)")):
				result = "0x" + strings.Repeat("0", 64)
				if j, ok := f.records[d[10:]]; ok {
					if j.Kind == "buy" {
						words := addressWord(j.Wallet) + hexWord(int64(j.Quantity))
						if card, ok := cardByID(j.ItemID); ok {
							words += hexWord(card.TokenID)
						} else if mat, ok := materialByID(j.ItemID); ok {
							words += hexWord(mat.TokenID)
						}
						bytes, _ := hex.DecodeString(words)
						result = hashHex(bytes)
					} else if j.Kind == "enhance" {
						card, _ := cardByID(j.CardID)
						mat, _ := materialByID(j.ItemID)
						raw, _ := hex.DecodeString(addressWord(j.Wallet) + hexWord(mat.TokenID) + hexWord(card.TokenID))
						result = hashHex(raw)
					} else {
						result = "0x" + addressWord(j.Wallet)
					}
				}
			default:
				t.Error("unexpected eth_call", d)
				w.WriteHeader(400)
				return
			}
		case "eth_getLogs":
			var filter struct{ Topics []string }
			_ = json.Unmarshal(req.Params[0], &filter)
			logs := []scoreLog{}
			if j, ok := f.records[strings.TrimPrefix(filter.Topics[1], "0x")]; ok {
				logs = append(logs, f.logs(j)[0])
			}
			result = logs
		case "eth_getTransactionReceipt":
			var hash string
			_ = json.Unmarshal(req.Params[0], &hash)
			for id, j := range f.records {
				if f.hashes[id] == hash {
					logs := f.logs(j)
					if f.wrong {
						logs = logs[:1]
					}
					result = publicationReceipt{Status: "0x1", TxHash: hash, BlockNumber: fmt.Sprintf("0x%x", f.blocks[id]), BlockHash: "0x" + strings.Repeat("c", 64), Logs: logs}
				}
			}
		case "eth_getBlockByNumber":
			result = map[string]string{"hash": "0x" + strings.Repeat("c", 64)}
		default:
			t.Error("unexpected RPC", req.Method)
			w.WriteHeader(400)
			return
		}
		_ = json.NewEncoder(w).Encode(map[string]any{"jsonrpc": "2.0", "id": 1, "result": result})
	}))
	t.Cleanup(f.server.Close)
	f.cfg.EngineURL = f.server.URL
	f.cfg.StarlightRPC = f.server.URL + "/rpc"
	return f
}
func (f *shopFixture) logs(j shopJob) []scoreLog {
	client, err := newShopClient(f.cfg).forItem(j.ItemID)
	if err != nil {
		panic(err)
	}
	amount := "0x" + hex.EncodeToString(starlightRaw(int64(client.price()*j.Quantity)).FillBytes(make([]byte, 32)))
	event := scoreLog{Address: client.cfg.ShopRouter, Topics: []string{purchasedTopic, "0x" + j.Key, "0x" + addressWord(j.Wallet)}, Data: "0x" + hexWord(int64(j.Quantity)) + amount[2:], TxHash: f.hashes[j.Key]}
	from, to := f.cfg.StarlightTreasury, j.Wallet
	if j.Kind == "enhance" {
		card, _ := cardByID(j.CardID)
		event.Topics = []string{enhancedTopic, "0x" + j.Key, "0x" + addressWord(j.Wallet)}
		event.Data = "0x" + hexWord(client.cfg.ShopTokenID) + hexWord(card.TokenID)
		from, to = j.Wallet, "0x"+strings.Repeat("0", 40)
	}
	if j.Kind == "consume" {
		event.Topics = []string{consumedTopic, "0x" + j.Key, "0x" + addressWord(j.Wallet), "0x" + hexWord(0)}
		event.Data = "0x"
		from, to = j.Wallet, "0x"+strings.Repeat("0", 40)
	}
	return []scoreLog{event, {Address: f.cfg.MarketplaceCollection, Topics: []string{itemTransferTopic, "0x" + addressWord(client.cfg.ShopRouter), "0x" + addressWord(from), "0x" + addressWord(to)}, Data: "0x" + hexWord(client.cfg.ShopTokenID) + hexWord(int64(j.Quantity))}, {Address: f.cfg.StarlightToken, Topics: []string{tokenTransferTopic, "0x" + addressWord(j.Wallet), "0x" + addressWord(client.cfg.ShopRouter)}, Data: amount}}
}
func shopRequest(id int, kind string) map[string]any {
	b := map[string]any{"request_id": fmt.Sprintf("%032x", id), "item_id": "energy_drink", "quantity": 1}
	if kind == "buy" {
		b["expected_total"] = "100"
	}
	return b
}
func TestShopConfirmedDeliveryAndOnceOnlyEnergy(t *testing.T) {
	s := testStore(t)
	base := testApp(t, s)
	token, owner := progressAccount(t, base, "shopplayer")
	f := newShopFixture(t)
	wallet := "0x" + strings.Repeat("4", 40)
	_, err := s.ReadWallet(owner, f.cfg.EngineProjectID, f.cfg.EngineURL)
	if err != nil {
		t.Fatal(err)
	}
	_, _ = s.ClaimWallet(owner, f.cfg.EngineProjectID, f.cfg.EngineURL, "lease", time.Now())
	_, err = s.SaveWallet(owner, f.cfg.EngineProjectID, f.cfg.EngineURL, "lease", walletInfo{ID: "managed-player", Address: wallet, Status: "ready"})
	if err != nil {
		t.Fatal(err)
	}
	a := &api{store: s, config: f.cfg}
	a.shop = &shopService{store: s, client: newShopClient(f.cfg)}
	app := fiber.New(fiber.Config{ErrorHandler: func(c fiber.Ctx, e error) error { return failure(c, 400, "bad_request", "Invalid request.") }})
	app.Use(a.authenticate)
	app.Get("/api/v1/inventory", a.getInventory)
	app.Post("/api/v1/shop/purchase", a.buyItem)
	app.Post("/api/v1/inventory/consume", a.consumeItem)
	status, _, _ := request(t, app, "GET", "/api/v1/inventory", nil, "")
	requireStatus(t, status, 401)
	forged := shopRequest(1, "buy")
	forged["recipient"] = f.cfg.StarlightTreasury
	status, _, _ = request(t, app, "POST", "/api/v1/shop/purchase", forged, token)
	requireStatus(t, status, 400)
	var wg sync.WaitGroup
	for range 4 {
		wg.Add(1)
		go func() {
			defer wg.Done()
			code, _, _ := request(t, app, "POST", "/api/v1/shop/purchase", shopRequest(1, "buy"), token)
			requireStatus(t, code, 200)
		}()
	}
	wg.Wait()
	run := func(id int) {
		t.Helper()
		key := shopKey(f.cfg, owner, fmt.Sprintf("%032x", id))
		for range 12 {
			j, err := s.shopOperation(key, owner)
			if err != nil {
				t.Fatal(err)
			}
			if j.Status == "confirmed" {
				return
			}
			job, ok, err := s.claimShop(shopTarget(f.cfg))
			if err != nil || !ok {
				t.Fatal("claim", err)
			}
			releaseScanBudget(a.shop.client.star.p) // Advance the test scan clock without sleeping.
			err = a.shop.advance(context.Background(), &job)
			if err != nil && err.Error() != "upstream_unavailable" {
				t.Fatal(err)
			}
			if job.Status == "confirmed" || job.Status == "failed" {
				if err = s.finishShop(job); err != nil {
					t.Fatal(err)
				}
			} else {
				if err = s.saveShop(job, time.Now().Add(-time.Second)); err != nil {
					t.Fatal(err)
				}
			}
		}
		t.Fatal("operation did not finish")
	}
	f.lost = true
	run(1)
	if f.payments != 1 || f.owned != 1 || f.balance != 400 {
		t.Fatal("payment or delivery wrong")
	}
	for range 2 {
		status, _, _ = request(t, app, "POST", "/api/v1/shop/purchase", shopRequest(1, "buy"), token)
		requireStatus(t, status, 200)
	}
	status, body, _ := request(t, app, "GET", "/api/v1/inventory?wallet="+f.cfg.StarlightTreasury, nil, token)
	requireStatus(t, status, 200)
	if body["items"].([]any)[0].(map[string]any)["quantity"] != float64(1) {
		t.Fatal(body)
	}
	status, _, _ = request(t, app, "POST", "/api/v1/inventory/consume", shopRequest(2, "consume"), token)
	requireStatus(t, status, 409)
	editProgress(t, s, owner, func(p *progression) {
		p.Energy.Current = 9
		p.Energy.NextAt = time.Now().Add(20 * time.Minute).UnixMilli()
	})
	for range 4 {
		wg.Add(1)
		go func() {
			defer wg.Done()
			code, _, _ := request(t, app, "POST", "/api/v1/inventory/consume", shopRequest(2, "consume"), token)
			requireStatus(t, code, 200)
		}()
	}
	wg.Wait()
	run(2)
	key := shopKey(f.cfg, owner, fmt.Sprintf("%032x", 2))
	j, _ := s.shopOperation(key, owner)
	if j.Restored != 5 || f.burns != 1 || f.owned != 0 {
		t.Fatal("burn or grant wrong", j)
	}
	for range 3 {
		status, _, _ = request(t, app, "POST", "/api/v1/inventory/consume", shopRequest(2, "consume"), token)
		requireStatus(t, status, 200)
		if err = s.finishShop(*j); err != nil {
			t.Fatal(err)
		}
	}
	p, _, _ := s.ReadProgress(owner)
	if p.Energy.Current != 14 || p.Energy.NextAt == 0 || p.ShopActive != "" {
		t.Fatal("duplicate energy grant or clock reset")
	}
	status, _, _ = request(t, app, "POST", "/api/v1/inventory/consume", shopRequest(3, "consume"), token)
	requireStatus(t, status, 409)
	buyKey := shopKey(f.cfg, owner, fmt.Sprintf("%032x", 1))
	bad := f.records[buyKey]
	bad.TxHash = f.hashes[buyKey]
	f.wrong = true
	if ok, err := a.shop.client.confirmed(context.Background(), &bad); err == nil || ok {
		t.Fatal("missing delivery/payment receipt accepted")
	}
}

func TestShopLiveTestnetPurchaseAndConsume(t *testing.T) {
	if os.Getenv("SHOP_LIVE_TEST") != "true" {
		t.Skip("explicit testnet checkout smoke test; transfers 100 treasury STARL to an isolated test wallet")
	}
	cfg, err := loadConfig()
	if err != nil {
		t.Fatal(err)
	}
	if !cfg.ShopEnabled || cfg.StarlightChainID != 421614 || cfg.EngineProjectID != "7fe1ecf2-b715-43bc-ba03-3f0a1149bc5d" {
		t.Fatal("expected RESCENE testnet configuration")
	}
	cfg.LeaderboardEnabled = false
	s := testStore(t)
	cfg.Secret = testConfig().Secret
	app, err := newApp(s, cfg, bcrypt.MinCost)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = app.Shutdown() })
	token, owner := progressAccount(t, app, fmt.Sprintf("shop_test_%d", time.Now().Unix()))
	var wallet walletInfo
	for range 45 {
		wallet, err = s.ReadWallet(owner, cfg.EngineProjectID, cfg.EngineURL)
		if err == nil && wallet.Status == "ready" {
			break
		}
		time.Sleep(time.Second)
	}
	if wallet.Status != "ready" {
		t.Fatal("test managed wallet not ready")
	}
	client := newStarlightClient(cfg)
	head, err := client.p.head(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	funding := starlightJob{Key: strings.TrimPrefix(hashHex([]byte("energy-shop-test/"+owner)), "0x"), Owner: owner, Recipient: wallet.Address, Amount: 100, FromBlock: head}
	tx, err := client.enqueue(context.Background(), funding)
	if err != nil {
		t.Fatal(err)
	}
	funding.TxHash = tx.Hash
	funded := false
	for range 60 {
		processed, err := client.processed(context.Background(), funding)
		if err != nil {
			t.Fatal(err)
		}
		if processed {
			if funding.TxHash == "" {
				funding.TxHash, err = client.findPaid(context.Background(), &funding)
				if err != nil {
					t.Fatal(err)
				}
			}
			funded, err = client.confirmed(context.Background(), funding)
			if err != nil {
				t.Fatal(err)
			}
			if funded {
				break
			}
		}

		time.Sleep(2 * time.Second)
	}
	if !funded {
		t.Fatal("isolated test wallet funding not confirmed")
	}
	status, _, _ := request(t, app, "POST", "/api/v1/shop/purchase", shopRequest(1, "buy"), token)
	requireStatus(t, status, 200)
	wait := func(id int) *shopJob {
		t.Helper()
		for range 90 {
			j, err := s.shopOperation(shopKey(cfg, owner, fmt.Sprintf("%032x", id)), owner)
			if err != nil {
				t.Fatal(err)
			}
			if j.Status == "confirmed" {
				return j
			}
			if j.Status == "failed" {
				t.Fatal("testnet action failed", j.Error)
			}
			time.Sleep(2 * time.Second)
		}
		t.Fatal("testnet action pending too long")
		return nil
	}
	buy := wait(1)
	status, body, _ := request(t, app, "GET", "/api/v1/inventory", nil, token)
	requireStatus(t, status, 200)
	if body["items"].([]any)[0].(map[string]any)["quantity"] != float64(1) {
		t.Fatal("confirmed NFT not delivered")
	}
	for range 2 {
		status, _, _ = request(t, app, "POST", "/api/v1/shop/purchase", shopRequest(1, "buy"), token)
		requireStatus(t, status, 200)
	}
	editProgress(t, s, owner, func(p *progression) {
		p.Energy.Current = 9
		p.Energy.NextAt = time.Now().Add(20 * time.Minute).UnixMilli()
	})
	status, _, _ = request(t, app, "POST", "/api/v1/inventory/consume", shopRequest(2, "consume"), token)
	requireStatus(t, status, 200)
	consume := wait(2)
	for range 2 {
		status, _, _ = request(t, app, "POST", "/api/v1/inventory/consume", shopRequest(2, "consume"), token)
		requireStatus(t, status, 200)
	}
	status, body, _ = request(t, app, "GET", "/api/v1/inventory", nil, token)
	requireStatus(t, status, 200)
	if body["items"].([]any)[0].(map[string]any)["quantity"] != float64(0) {
		t.Fatal("consumed item not burned")
	}
	p, _, _ := s.ReadProgress(owner)
	if p.Energy.Current != 14 || consume.Restored != 5 {
		t.Fatal("energy not credited exactly once")
	}
	balance, err := client.balance(context.Background(), wallet.Address)
	if err != nil || balance.Sign() != 0 {
		t.Fatal("purchase payment was not exact", err)
	}
	result := map[string]any{"chainId": cfg.StarlightChainID, "testWallet": wallet.Address, "fundingTransaction": funding.TxHash, "purchaseTransaction": buy.TxHash, "consumeTransaction": consume.TxHash, "price": "100", "itemId": "0", "finalInventory": 0, "energyBefore": 9, "energyAfter": p.Energy.Current, "duplicateRequestsDidNotChargeOrGrantTwice": true}
	data, _ := json.MarshalIndent(result, "", "  ")
	if err = os.WriteFile("../contracts/deployments/energy-shop-live-verification.json", append(data, '\n'), 0644); err != nil {
		t.Fatal(err)
	}
	t.Logf("Confirmed 100 STARL purchase, item delivery, burn, +5 energy and duplicate-request recovery; purchase=%s consume=%s", buy.TxHash, consume.TxHash)
}

func TestShopUncertainExecutionRecoversBeforeBalanceChecks(t *testing.T) {
	cfg := starlightTestConfig()
	cfg.ShopRouter = "0x" + strings.Repeat("6", 40)
	job := shopJob{Key: strings.Repeat("a", 64), Kind: "buy", Wallet: "0x" + strings.Repeat("4", 40), Quantity: 1, Stage: "execute", Status: "pending", ExecuteStarted: true, FromBlock: 100}
	calls := 0
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		if r.URL.Path == "/v1/contracts/write" {
			calls++
			if r.Header.Get("Idempotency-Key") != "rescene/shop/"+job.Key+"/execute/0" {
				t.Error("uncertain execution changed identity")
			}
			spec := newShopClient(cfg).spec(job)
			tx := enginePublicationTx{ID: "already-queued", AppID: cfg.EngineProjectID, ChainID: cfg.StarlightChainID, ContractAddress: spec.Address, WalletAddress: spec.Wallet, Method: spec.Method, Args: spec.Args, Status: "queued"}
			_ = json.NewEncoder(w).Encode(map[string]any{"transaction": tx})
			return
		}
		var req struct {
			Method string
			Params []json.RawMessage
		}
		_ = json.NewDecoder(r.Body).Decode(&req)
		var call struct{ Data string }
		if len(req.Params) > 0 {
			_ = json.Unmarshal(req.Params[0], &call)
		}
		if req.Method != "eth_call" || !strings.HasPrefix(call.Data, selector("purchases(bytes32)")) {
			t.Error("uncertain request read a changed quote/balance before recovering its Engine ID")
		}
		_ = json.NewEncoder(w).Encode(map[string]any{"result": "0x" + strings.Repeat("0", 64)})
	}))
	defer server.Close()
	cfg.EngineURL = server.URL
	cfg.StarlightRPC = server.URL + "/rpc"
	service := &shopService{client: newShopClient(cfg)}
	if err := service.advance(context.Background(), &job); err != nil {
		t.Fatal(err)
	}
	if calls != 1 || job.EngineID != "already-queued" || job.Status != "pending" {
		t.Fatal("execution was abandoned instead of recovered")
	}
}
