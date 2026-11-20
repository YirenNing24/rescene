package main

import (
	"bytes"
	"context"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"github.com/gofiber/fiber/v3"
	"io"
	"net/http"
	"strings"
	"testing"
	"time"
)

type pulseFixture struct {
	f            *shopFixture
	store        *graphStore
	owner        string
	cards        map[int64]pulseCard
	deck         [5]int64
	releaseDecks map[int][5]int64
	sold         [45]int64
	jobs         map[string]shopJob
	txs          map[string]enginePublicationTx
	outcomes     map[string]int64
	next         int64
	sales        bool
	bad          bool
}

func newPulseTest(t *testing.T) (*graphStore, *api, *pulseFixture, *fiber.App, string, string) {
	s, a, f, app, token, owner := cardProgressAPI(t)
	f.cfg.PulseRouter = "0x" + strings.Repeat("a", 40)
	f.cfg.LegacyCardsRouter = "0x" + strings.Repeat("b", 40)
	f.balance = 100000
	p := &pulseFixture{f: f, store: s, owner: owner, cards: map[int64]pulseCard{}, releaseDecks: map[int][5]int64{}, jobs: map[string]shopJob{}, txs: map[string]enginePublicationTx{}, outcomes: map[string]int64{}, next: 14, sales: true}
	f.pulse = p
	a.config = f.cfg
	a.shop.client = newShopClient(f.cfg)
	app.Post("/api/v1/collection/quote", a.quotePulseCard)
	app.Post("/api/v1/collection/action", a.actPulseCard)
	app.Post("/api/v1/shop/purchase", a.buyItem)
	app.Get("/api/v1/shop/catalog", a.shopCatalog)
	app.Post("/api/v1/runs/:id/abandon", a.abandonRun)
	return s, a, p, app, token, owner
}
func (p *pulseFixture) add(member int, level, stars int) int64 {
	id := p.next
	p.next++
	p.cards[id] = pulseCard{TokenID: id, Member: member % 5, SetIndex: member/5 + 1, Rarity: 5, BaseScoreBP: 800, BaseRecoveryBP: 8, Skill: member%5 + 1, Level: level, Stars: stars, Revision: 1}
	p.f.cardOwned[id] = 1
	return id
}
func (p *pulseFixture) current(id int64) pulseCard {
	c := p.cards[id]
	c.ScoreBP = c.BaseScoreBP * (10000 + (c.Level-1)*2000/99) / 10000
	c.RecoveryPPM = c.BaseRecoveryBP * 100 * (10000 + (c.Level-1)*2000/99) / 10000
	deck := p.deck
	if c.SetIndex > 1 {
		deck = p.releaseDecks[c.SetIndex]
	}
	if c.Member >= 0 && c.Member < 5 && deck[c.Member] == id && id > 0 {
		c.Flags |= 2
	}
	return c
}
func (p *pulseFixture) serve(w http.ResponseWriter, r *http.Request) bool {
	if strings.HasPrefix(r.URL.Path, "/v1/transactions/pulse-") {
		for _, tx := range p.txs {
			if "/v1/transactions/"+tx.ID == r.URL.Path {
				_ = json.NewEncoder(w).Encode(map[string]any{"transaction": tx})
				return true
			}
		}
		return false
	}
	raw, _ := io.ReadAll(r.Body)
	r.Body = io.NopCloser(bytes.NewReader(raw))
	if r.URL.Path == "/v1/contracts/write" {
		var body struct {
			ChainID                                      int64
			ContractAddress, WalletAddress, FunctionName string
			Args                                         []string
		}
		_ = json.Unmarshal(raw, &body)
		if body.ContractAddress != p.f.cfg.PulseRouter {
			return false
		}
		key := strings.TrimPrefix(body.Args[0], "0x")
		job, err := p.store.shopOperation(key, p.owner)
		if err != nil || job == nil {
			http.Error(w, "operation missing", 500)
			return true
		}
		spec, _ := pulseSpec(newShopClient(p.f.cfg), *job)
		if spec.Method != body.FunctionName || strings.Join(spec.Args, "|") != strings.Join(body.Args, "|") {
			http.Error(w, "spec mismatch", 400)
			return true
		}
		identity := r.Header.Get("Idempotency-Key")
		tx, ok := p.txs[identity]
		if !ok {
			tx = enginePublicationTx{ID: fmt.Sprintf("pulse-%d", len(p.txs)+1), AppID: p.f.cfg.EngineProjectID, ChainID: body.ChainID, ContractAddress: body.ContractAddress, WalletAddress: body.WalletAddress, Method: body.FunctionName, Args: body.Args, Status: "confirmed", Hash: fmt.Sprintf("0x%064x", 1000+len(p.txs))}
			if _, exists := p.jobs[key]; !exists {
				p.f.head += 3
				p.f.blocks[key] = p.f.head - 2
				p.apply(job)
				p.jobs[key] = *job
				p.f.hashes[key] = tx.Hash
			}
			p.txs[identity] = tx
		}
		if p.f.lost {
			p.f.lost = false
			w.WriteHeader(503)
			fmt.Fprint(w, `{"error":"unavailable"}`)
			return true
		}
		_ = json.NewEncoder(w).Encode(map[string]any{"transaction": tx})
		return true
	}
	var req struct {
		Method string
		Params []json.RawMessage
	}
	if json.Unmarshal(raw, &req) != nil {
		return false
	}
	var result any
	handled := false
	if req.Method == "eth_call" {
		var call struct{ To, Data string }
		_ = json.Unmarshal(req.Params[0], &call)
		if call.To == p.f.cfg.MarketplaceCollection && (strings.HasPrefix(call.Data, selector("hasRole(bytes32,address)")) || call.Data == selector("uriFrozen()")) {
			value := int64(1)
			if call.Data == selector("uriFrozen()") {
				value = 0
			}
			_ = json.NewEncoder(w).Encode(map[string]any{"jsonrpc": "2.0", "id": 1, "result": "0x" + hexWord(value)})
			return true
		}
		if call.To == "0xcA11bde05977b3631167028862bE2a173976CA11" && strings.HasPrefix(call.Data, selector("aggregate((address,bytes)[])")) {
			values := []int64{0}
			if p.sales {
				values[0] = 1
			}
			values = append(values, p.sold[:]...)
			values = append(values, 10000, 10000, 10000)
			encoded := "0x" + hexWord(100) + hexWord(64) + hexWord(int64(len(values)))
			for i := range values {
				encoded += hexWord(int64(len(values)*32 + i*64))
			}
			for _, v := range values {
				encoded += hexWord(32) + hexWord(v)
			}
			_ = json.NewEncoder(w).Encode(map[string]any{"jsonrpc": "2.0", "id": 1, "result": encoded})
			return true
		}
		if call.To != p.f.cfg.PulseRouter {
			return false
		}
		d := call.Data
		words := "0x" + d[10:]
		arg := func(i int) int64 { value, _ := wordInt(words, i); return value }
		handled = true
		switch {
		case d == selector("unitPrice()"):
			result = "0x" + hex.EncodeToString(starlightRaw(450).FillBytes(make([]byte, 32)))
		case d == selector("RELEASE_COUNT()"):
			result = "0x" + hexWord(9)
		case strings.HasPrefix(d, selector("cardSet(uint256)")):
			result = "0x" + hexWord(int64(max(1, p.cards[arg(0)].SetIndex)))
		case strings.HasPrefix(d, selector("initialLESold(uint256)")):
			result = "0x" + hexWord(p.sold[arg(0)])
		case d == selector("VERSION()"):

			result = "0x" + hexWord(2)
		case d == selector("operator()"):
			result = "0x" + addressWord(p.f.cfg.StarlightTreasury)
		case d == selector("token()"):
			result = "0x" + addressWord(p.f.cfg.StarlightToken)
		case d == selector("items()"):
			result = "0x" + addressWord(p.f.cfg.MarketplaceCollection)
		case strings.HasPrefix(d, selector("materialIds(uint256)")):
			result = "0x" + hexWord(cardMaterials[arg(0)].TokenID)
		case strings.HasPrefix(d, selector("materialStock(uint256)")):
			result = "0x" + hexWord(10000)
		case d == selector("salesEnabled()"):
			if p.sales {
				result = "0x" + hexWord(1)
			} else {
				result = "0x" + hexWord(0)
			}
		case d == selector("count()"):
			result = "0x" + hexWord(p.next-14)
		case strings.HasPrefix(d, selector("tokenIds(uint256,uint256)")):
			count := min(arg(1), max(0, p.next-14-arg(0)))
			encoded := "0x" + hexWord(32) + hexWord(count)
			for i := int64(0); i < count; i++ {
				encoded += hexWord(14 + arg(0) + i)
			}
			result = encoded
		case strings.HasPrefix(d, selector("deck(address,uint256)")):
			encoded := "0x"
			deck := p.deck
			if arg(1) > 1 {
				deck = p.releaseDecks[int(arg(1))]
			}
			for _, id := range deck {
				if p.f.cardOwned[id] < 1 {
					id = 0
				}
				encoded += hexWord(id)
			}
			result = encoded
		case strings.HasPrefix(d, selector("viewCard(address,uint256)")):
			c := p.current(arg(1))
			v := []int64{int64(c.Member), int64(c.Rarity), int64(c.BaseScoreBP), int64(c.BaseRecoveryBP), int64(c.Skill), int64(c.XP), int64(c.Level), int64(c.Stars), int64(c.Progress), c.Revision, 0, int64(c.Flags), int64(c.ScoreBP), int64(c.RecoveryPPM)}
			if c.Burned {
				v[10] = 1
			}
			encoded := "0x"
			for _, n := range v {
				encoded += hexWord(n)
			}
			result = encoded
		case strings.HasPrefix(d, selector("actions(bytes32)")):
			result = "0x" + hexWord(0)
			if j, ok := p.jobs[d[10:]]; ok {
				result, _ = pulseDigest(j)
			}
		default:
			handled = false
		}
	}
	if req.Method == "eth_getLogs" {
		var filter struct {
			Address string
			Topics  []string
		}
		_ = json.Unmarshal(req.Params[0], &filter)
		if filter.Address == p.f.cfg.PulseRouter {
			logs := []scoreLog{}
			if len(filter.Topics) > 1 {
				if j, ok := p.jobs[strings.TrimPrefix(filter.Topics[1], "0x")]; ok {
					logs = append(logs, p.logs(j)[0])
				}
			}
			result = logs
			handled = true
		}
	}
	if req.Method == "eth_getTransactionReceipt" {
		var hash string
		_ = json.Unmarshal(req.Params[0], &hash)
		for key, j := range p.jobs {
			if p.f.hashes[key] == hash {
				logs := p.logs(j)
				if p.bad {
					logs = logs[:1]
				}
				result = publicationReceipt{Status: "0x1", TxHash: hash, BlockNumber: fmt.Sprintf("0x%x", p.f.blocks[key]), BlockHash: "0x" + strings.Repeat("c", 64), Logs: logs}
				handled = true
				break
			}
		}
	}
	if !handled {
		return false
	}
	_ = json.NewEncoder(w).Encode(map[string]any{"jsonrpc": "2.0", "id": 1, "result": result})
	return true
}
func (p *pulseFixture) apply(j *shopJob) {
	token, _ := pulseToken(j.CardID)
	c := p.cards[token]
	switch j.Kind {
	case "pulse_buy":
		id := p.add(j.Pulse.Request.Member, 1, 1)
		p.sold[j.Pulse.Request.Member]++
		c = p.cards[id]
		c.BaseScoreBP = j.Pulse.Score
		c.BaseRecoveryBP = j.Pulse.Recovery
		c.Skill = j.Pulse.Skill
		p.cards[id] = c
		j.CardID = pulseID(id)
		p.f.payments++
		p.f.balance -= 450
	case "pulse_material":
		material, _ := materialByID(j.ItemID)
		p.f.cardOwned[material.TokenID] += int64(j.Quantity)
		p.f.balance -= int64(material.Price * j.Quantity)
		p.f.payments++
		p.outcomes[j.Key] = int64(j.Quantity)
	case "pulse_refine":
		material, _ := materialByID(j.ItemID)
		result, _ := resolveCardUpgrade(c.Level, c.XP, material.XP, j.Pulse.Roll)
		c.Level = result.After
		c.XP = result.XP
		c.Revision++
		p.cards[token] = c
		p.f.cardOwned[material.TokenID]--
		p.f.burns++
		if result.Attempted {
			p.outcomes[j.Key] = 1
		}
		if result.Succeeded {
			p.outcomes[j.Key] = 2
		}
	case "pulse_star":
		for _, id := range j.Pulse.Request.Donors {
			donor, _ := pulseToken(id)
			d := p.cards[donor]
			d.Burned = true
			d.Revision++
			p.cards[donor] = d
			p.f.cardOwned[donor] = 0
			p.f.burns++
		}
		var wasted int
		c.Stars, c.Progress, wasted = pulseStarPreview(c.Stars, c.Progress, len(j.Pulse.Request.Donors))
		c.Revision++
		p.cards[token] = c
		p.outcomes[j.Key] = int64(wasted)
	case "pulse_lock":
		if j.Pulse.Request.Locked {
			c.Flags |= 1
			p.outcomes[j.Key] = 1
		} else {
			c.Flags &^= 1
		}
		c.Revision++
		p.cards[token] = c
	case "pulse_equip":
		number := releaseNumber(j.Pulse.Request.SetID)
		if number == 1 {
			p.deck[j.Pulse.Request.Member] = token
		} else {
			deck := p.releaseDecks[number]
			deck[j.Pulse.Request.Member] = token
			p.releaseDecks[number] = deck
		}
		p.outcomes[j.Key] = int64(j.Pulse.Request.Member)
	}
}
func (p *pulseFixture) logs(j shopJob) []scoreLog {
	id, _ := pulseToken(j.CardID)
	if j.Kind == "pulse_material" {
		mat, _ := materialByID(j.ItemID)
		id = mat.TokenID
	}
	result := hexWord(p.outcomes[j.Key])
	if j.Kind == "pulse_buy" {
		result = hex.EncodeToString(starlightRaw(450).FillBytes(make([]byte, 32)))
	}
	event := scoreLog{Address: p.f.cfg.PulseRouter, Topics: []string{pulseActionTopic, "0x" + j.Key, "0x" + addressWord(j.Wallet), "0x" + hexWord(id)}, Data: "0x" + hexWord(pulseKind(j.Kind)) + result, TxHash: p.f.hashes[j.Key]}
	logs := []scoreLog{event}
	transfer := func(token, quantity int64, from, to string) {
		logs = append(logs, scoreLog{Address: p.f.cfg.MarketplaceCollection, Topics: []string{itemTransferTopic, "0x" + addressWord(p.f.cfg.PulseRouter), "0x" + addressWord(from), "0x" + addressWord(to)}, Data: "0x" + hexWord(token) + hexWord(quantity)})
	}
	zero := "0x" + strings.Repeat("0", 40)
	if j.Kind == "pulse_buy" {
		transfer(id, 1, zero, j.Wallet)
	}
	if j.Kind == "pulse_material" {
		transfer(id, int64(j.Quantity), p.f.cfg.StarlightTreasury, j.Wallet)
	}
	if j.Kind == "pulse_buy" || j.Kind == "pulse_material" {
		logs = append(logs, scoreLog{Address: p.f.cfg.StarlightToken, Topics: []string{tokenTransferTopic, "0x" + addressWord(j.Wallet), "0x" + addressWord(p.f.cfg.StarlightTreasury)}, Data: "0x" + hex.EncodeToString(starlightRaw(pulsePayment(j)).FillBytes(make([]byte, 32)))})
	}
	if j.Kind == "pulse_refine" {
		material, _ := materialByID(j.ItemID)
		transfer(material.TokenID, 1, j.Wallet, zero)
	}
	if j.Kind == "pulse_star" {
		for _, id := range j.Pulse.Request.Donors {
			token, _ := pulseToken(id)
			transfer(token, 1, j.Wallet, zero)
		}
	}
	return logs
}
func finishPulse(t *testing.T, s *graphStore, a *api, p *pulseFixture, key string) *shopJob {
	t.Helper()
	for range 20 {
		job, ok, err := s.claimShop(shopTarget(p.f.cfg))
		if err != nil || !ok {
			t.Fatal("claim", err)
		}
		releaseScanBudget(a.shop.client.star.p) // Advance the test scan clock without sleeping.
		err = a.shop.advance(context.Background(), &job)
		if err != nil && err.Error() != "upstream_unavailable" {
			t.Fatal("advance", err)
		}
		if job.Status == "confirmed" || job.Status == "failed" {
			if err = s.finishShop(job); err != nil {
				t.Fatal(err)
			}
			break
		}
		if err = s.saveShop(job, time.Now().Add(-time.Second)); err != nil {
			t.Fatal(err)
		}
	}
	j, err := s.shopOperation(key, p.owner)
	if err != nil || j == nil || j.Status != "confirmed" {
		t.Fatal("card action did not confirm", err)
	}
	return j
}
func quotePulse(t *testing.T, app *fiber.App, token string, body map[string]any) map[string]any {
	t.Helper()
	status, data, _ := request(t, app, "POST", "/api/v1/collection/quote", body, token)
	requireStatus(t, status, 200)
	return data["quote"].(map[string]any)
}
func submitPulse(t *testing.T, app *fiber.App, token string, body map[string]any, quote map[string]any, nonce int) {
	t.Helper()
	body["request_id"] = fmt.Sprintf("%032x", nonce)
	body["quote_hash"] = quote["hash"]
	body["acknowledge_warning"] = true
	status, _, _ := request(t, app, "POST", "/api/v1/collection/action", body, token)
	requireStatus(t, status, 200)
}
