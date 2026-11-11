package main

import (
	"context"
	_ "embed"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"math/big"
	"net/url"
	"strings"
)

//go:embed shop_abi.json
var shopABIJSON []byte
var shopABIs = func() map[string]json.RawMessage {
	var m map[string]json.RawMessage
	if json.Unmarshal(shopABIJSON, &m) != nil {
		panic("shop ABI invalid")
	}
	return m
}()

const drinkPrice = 100
const shopGasAmount = "50000000000000"

var purchasedTopic = hashHex([]byte("Purchased(bytes32,address,uint256,uint256)"))
var enhancedTopic = hashHex([]byte("Enhanced(bytes32,address,uint256,uint256)"))
var consumedTopic = hashHex([]byte("Consumed(bytes32,address,uint256)"))
var itemTransferTopic = hashHex([]byte("TransferSingle(address,address,address,uint256,uint256)"))

type shopClient struct {
	cfg    config
	star   *starlightClient
	itemID string
}

func newShopClient(c config) *shopClient { return &shopClient{cfg: c, star: newStarlightClient(c)} }
func (c *shopClient) call(ctx context.Context, address, signature, words string) (string, error) {
	return c.star.call(ctx, address, selector(signature)+words)
}
func (c *shopClient) number(ctx context.Context, address, signature, words string) (*big.Int, error) {
	raw, err := c.call(ctx, address, signature, words)
	if err != nil {
		return nil, err
	}
	return uint256Hex(raw)
}
func hexWord(n int64) string { return hex.EncodeToString(word(n)) }
func (c *shopClient) owned(ctx context.Context, wallet string) (int64, error) {
	// Only inventory in a sufficiently confirmed canonical block is spendable in UI.
	head, err := c.star.p.head(ctx)
	if err != nil {
		return 0, err
	}
	block := head - c.cfg.StarlightConfirmations + 1
	if block < 0 {
		return 0, errors.New("shop_chain_unavailable")
	}
	var out string
	err = c.star.p.rpc(ctx, "eth_call", []any{map[string]string{"to": c.cfg.MarketplaceCollection, "data": selector("balanceOf(address,uint256)") + addressWord(wallet) + hexWord(c.cfg.ShopTokenID)}, fmt.Sprintf("0x%x", block)}, &out)
	if err != nil {
		return 0, err
	}
	n, err := uint256Hex(out)
	if err != nil || !n.IsInt64() {
		return 0, errors.New("shop_balance_invalid")
	}
	return n.Int64(), nil
}

// Snapshot every item in a single confirmed block. One ERC-1155 batch read
// avoids a separate head/balance round trip for each collection card.
func (c *shopClient) ownedItems(ctx context.Context, wallet string) (map[string]int64, error) {
	ids := c.inventoryIDs()
	if len(ids) == 1 {
		quantity, err := c.owned(ctx, wallet)
		return map[string]int64{ids[0]: quantity}, err
	}
	head, err := c.star.p.head(ctx)
	if err != nil {
		return nil, err
	}
	block := head - c.cfg.StarlightConfirmations + 1
	if block < 0 {
		return nil, errors.New("shop_chain_unavailable")
	}
	n := int64(len(ids))
	// ABI: two dynamic-array offsets, accounts array, then token IDs array.
	accounts := hexWord(n) + strings.Repeat(addressWord(wallet), len(ids))
	tokens := hexWord(n)
	for _, id := range ids {
		item, err := c.forItem(id)
		if err != nil {
			return nil, err
		}
		tokens += hexWord(item.cfg.ShopTokenID)
	}
	data := selector("balanceOfBatch(address[],uint256[])") + hexWord(64) + hexWord(96+n*32) + accounts + tokens
	var out string
	if err = c.star.p.rpc(ctx, "eth_call", []any{map[string]string{"to": c.cfg.MarketplaceCollection, "data": data}, fmt.Sprintf("0x%x", block)}, &out); err != nil {
		return nil, err
	}
	bytes, err := hex.DecodeString(strings.TrimPrefix(out, "0x"))
	if err != nil || len(bytes) != (len(ids)+2)*32 {
		return nil, errors.New("shop_balance_invalid")
	}
	offset, e1 := wordInt(out, 0)
	count, e2 := wordInt(out, 1)
	if e1 != nil || e2 != nil || offset != 32 || count != n {
		return nil, errors.New("shop_balance_invalid")
	}
	quantities := make(map[string]int64, len(ids))
	for i, id := range ids {
		quantity, err := wordInt(out, i+2)
		if err != nil || quantity < 0 {
			return nil, errors.New("shop_balance_invalid")
		}
		quantities[id] = quantity
	}
	return quantities, nil
}

type drinkListing struct {
	Stock      int64
	Price      *big.Int
	Start, End int64
}

func (c *shopClient) listing(ctx context.Context) (drinkListing, error) {
	raw, err := c.call(ctx, c.cfg.MarketplaceAddress, "getListing(uint256)", hexWord(c.cfg.ShopListingID))
	if err != nil {
		return drinkListing{}, err
	}
	bytes, err := hex.DecodeString(strings.TrimPrefix(raw, "0x"))
	if err != nil || len(bytes) != 12*32 {
		return drinkListing{}, errors.New("shop_listing_invalid")
	}
	n := func(i int) (int64, error) { return wordInt(raw, i) }
	id, e1 := n(0)
	item, e2 := n(1)
	stock, e3 := n(2)
	start, e4 := n(4)
	end, e5 := n(5)
	kind, e6 := n(9)
	status, e7 := n(10)
	reserved, e8 := n(11)
	price := new(big.Int).SetBytes(bytes[96:128])
	addr := func(i int) string { return "0x" + hex.EncodeToString(bytes[i*32+12:(i+1)*32]) }
	if e1 != nil || e2 != nil || e3 != nil || e4 != nil || e5 != nil || e6 != nil || e7 != nil || e8 != nil || id != c.cfg.ShopListingID || item != c.cfg.ShopTokenID || stock < 0 || kind != 1 || (status != 1 && !(status == 2 && stock == 0)) || reserved != 0 || price.Cmp(starlightRaw(int64(c.price()))) != 0 || !strings.EqualFold(addr(6), c.cfg.StarlightTreasury) || !strings.EqualFold(addr(7), c.cfg.MarketplaceCollection) || !strings.EqualFold(addr(8), c.cfg.StarlightToken) {
		return drinkListing{}, errors.New("shop_listing_changed")
	}
	return drinkListing{stock, price, start, end}, nil
}
func (c *shopClient) preflight(ctx context.Context) error {
	if err := c.star.preflight(ctx); err != nil {
		return err
	}
	for _, v := range []struct{ name, address string }{{"operator()", c.cfg.StarlightTreasury}, {"token()", c.cfg.StarlightToken}, {"items()", c.cfg.MarketplaceCollection}, {"market()", c.cfg.MarketplaceAddress}} {
		raw, err := c.call(ctx, c.cfg.ShopRouter, v.name, "")
		if err != nil {
			return err
		}
		if !strings.EqualFold(raw, "0x"+addressWord(v.address)) {
			return errors.New("shop_router_mismatch")
		}
	}
	for _, v := range []struct {
		name  string
		value int64
	}{{"tokenId()", c.firstID(c.cfg.ShopTokenID)}, {"listingId()", c.firstID(c.cfg.ShopListingID)}} {
		raw, err := c.number(ctx, c.cfg.ShopRouter, v.name, "")
		if err != nil {
			return err
		}
		if !raw.IsInt64() || raw.Int64() != v.value {
			return errors.New("shop_router_mismatch")
		}
	}
	price, err := c.number(ctx, c.cfg.ShopRouter, "unitPrice()", "")
	if err != nil {
		return err
	}
	if price.Cmp(starlightRaw(int64(c.price()))) != 0 {
		return errors.New("shop_price_mismatch")
	}
	return nil
}

type shopCall struct {
	Address, Wallet, Method, Value string
	Args                           []string
}

func (c *shopClient) spec(j shopJob) shopCall {
	if pulseActive(j) {
		spec, _ := pulseSpec(c, j)
		return spec
	}
	switch j.Stage {
	case "gas":
		return shopCall{c.cfg.ShopRouter, c.cfg.StarlightTreasury, "fundGas", shopGasAmount, []string{"0x" + j.Key, j.Wallet}}
	case "approve":
		if j.Kind == "buy" {
			return shopCall{c.cfg.StarlightToken, j.Wallet, "approve", "0", []string{c.cfg.ShopRouter, starlightRaw(int64(j.Quantity * c.price())).String()}}
		}
		return shopCall{c.cfg.MarketplaceCollection, j.Wallet, "setApprovalForAll", "0", []string{c.cfg.ShopRouter, "true"}}
	default:
		if j.Kind == "buy" {
			if c.isCard() || c.isMaterial() {
				method := "purchaseItem"
				if c.legacy() {
					method = "purchaseCard"
				}
				return shopCall{c.cfg.ShopRouter, c.cfg.StarlightTreasury, method, "0", []string{"0x" + j.Key, j.Wallet, fmt.Sprint(j.Quantity), fmt.Sprint(c.cfg.ShopTokenID)}}
			}
			return shopCall{c.cfg.ShopRouter, c.cfg.StarlightTreasury, "purchase", "0", []string{"0x" + j.Key, j.Wallet, fmt.Sprint(j.Quantity)}}
		}
		if j.Kind == "enhance" {
			card, _ := cardByID(j.CardID)
			return shopCall{c.cfg.ShopRouter, c.cfg.StarlightTreasury, "enhance", "0", []string{"0x" + j.Key, j.Wallet, fmt.Sprint(c.cfg.ShopTokenID), fmt.Sprint(card.TokenID)}}
		}
		return shopCall{c.cfg.ShopRouter, c.cfg.StarlightTreasury, "consume", "0", []string{"0x" + j.Key, j.Wallet}}
	}
}
func (c *shopClient) validateTransaction(tx enginePublicationTx, j shopJob) error {
	s := c.spec(j)
	if tx.ID == "" || tx.AppID != c.cfg.EngineProjectID || tx.ChainID != c.cfg.StarlightChainID || !strings.EqualFold(tx.ContractAddress, s.Address) || !strings.EqualFold(tx.WalletAddress, s.Wallet) || tx.Method != s.Method || strings.Join(tx.Args, "\x00") != strings.Join(s.Args, "\x00") {
		return errors.New("shop_transaction_mismatch")
	}
	return nil
}
func (c *shopClient) enqueue(ctx context.Context, j shopJob) (enginePublicationTx, error) {
	s := c.spec(j)
	var out struct {
		Transaction enginePublicationTx `json:"transaction"`
	}
	err := c.star.p.json(ctx, "POST", c.cfg.EngineURL+"/v1/contracts/write", map[string]any{"chainId": c.cfg.StarlightChainID, "contractAddress": s.Address, "walletAddress": s.Wallet, "functionName": s.Method, "abi": operationABI(j, s.Method), "args": s.Args, "value": s.Value}, fmt.Sprintf("rescene/shop/%s/%s/%d", j.Key, j.Stage, j.Generation), &out)
	if err == nil {
		err = c.validateTransaction(out.Transaction, j)
	}
	return out.Transaction, err
}
func (c *shopClient) transaction(ctx context.Context, j shopJob) (enginePublicationTx, error) {
	var out struct {
		Transaction enginePublicationTx `json:"transaction"`
	}
	err := c.star.p.json(ctx, "GET", c.cfg.EngineURL+"/v1/transactions/"+url.PathEscape(j.EngineID), nil, "read", &out)
	if err == nil {
		err = c.validateTransaction(out.Transaction, j)
	}
	return out.Transaction, err
}
func (c *shopClient) processed(ctx context.Context, j shopJob) (bool, error) {
	method := "purchases(bytes32)"
	expected := ""
	if j.Kind == "buy" {
		words := addressWord(j.Wallet) + hexWord(int64(j.Quantity))
		if c.isCard() || c.isMaterial() {
			words += hexWord(c.cfg.ShopTokenID)
		}
		raw, _ := hex.DecodeString(words)
		expected = hashHex(raw)
	} else if j.Kind == "enhance" {
		card, ok := cardByID(j.CardID)
		if !ok || card.Legacy || !c.isMaterial() {
			return false, errors.New("invalid_enhancement")
		}
		method = "enhancements(bytes32)"
		raw, _ := hex.DecodeString(addressWord(j.Wallet) + hexWord(c.cfg.ShopTokenID) + hexWord(card.TokenID))
		expected = hashHex(raw)
	} else {
		method = "consumptions(bytes32)"
		expected = "0x" + addressWord(j.Wallet)
	}
	raw, err := c.call(ctx, c.cfg.ShopRouter, method, j.Key)
	if err != nil {
		return false, err
	}
	if raw == "0x"+strings.Repeat("0", 64) {
		return false, nil
	}
	if !strings.EqualFold(raw, expected) {
		return false, errors.New("shop_operation_mismatch")
	}
	return true, nil
}
func (c *shopClient) eventMatches(log scoreLog, j shopJob) bool {
	if log.Removed || !strings.EqualFold(log.Address, c.cfg.ShopRouter) || len(log.Topics) < 3 || !strings.EqualFold(log.Topics[1], "0x"+j.Key) || !strings.EqualFold(log.Topics[2], "0x"+addressWord(j.Wallet)) {
		return false
	}
	if j.Kind == "buy" {
		return len(log.Topics) == 3 && log.Topics[0] == purchasedTopic && log.Data == "0x"+hexWord(int64(j.Quantity))+hex.EncodeToString(starlightRaw(int64(j.Quantity*c.price())).FillBytes(make([]byte, 32)))
	}
	if j.Kind == "enhance" {
		card, ok := cardByID(j.CardID)
		return ok && !card.Legacy && len(log.Topics) == 3 && log.Topics[0] == enhancedTopic && log.Data == "0x"+hexWord(c.cfg.ShopTokenID)+hexWord(card.TokenID)
	}
	return len(log.Topics) == 4 && log.Topics[0] == consumedTopic && log.Topics[3] == "0x"+hexWord(c.cfg.ShopTokenID)
}
func (c *shopClient) confirmed(ctx context.Context, j *shopJob) (bool, error) {
	if j.TxHash == "" {
		head, err := c.star.p.head(ctx)
		if err != nil {
			return false, err
		}
		for scanned := 0; j.FromBlock <= head && scanned < 8; scanned++ {
			end := min(head, j.FromBlock+2047)
			var logs []scoreLog
			topic := purchasedTopic
			if j.Kind == "consume" {
				topic = consumedTopic
			} else if j.Kind == "enhance" {
				topic = enhancedTopic
			}
			err = c.star.p.rpc(ctx, "eth_getLogs", []any{map[string]any{"address": c.cfg.ShopRouter, "fromBlock": fmt.Sprintf("0x%x", j.FromBlock), "toBlock": fmt.Sprintf("0x%x", end), "topics": []string{topic, "0x" + j.Key, "0x" + addressWord(j.Wallet)}}}, &logs)
			if err != nil {
				return false, err
			}
			for _, log := range logs {
				if c.eventMatches(log, *j) {
					j.TxHash = log.TxHash
					break
				}
			}
			if j.TxHash != "" || end == head {
				break
			}
			j.FromBlock = end + 1
		}
	}
	if !validHex(j.TxHash, 32) {
		return false, nil
	}
	var r *publicationReceipt
	if err := c.star.p.rpc(ctx, "eth_getTransactionReceipt", []any{j.TxHash}, &r); err != nil {
		return false, err
	}
	if r == nil || r.Status != "0x1" {
		return false, nil
	}
	if !strings.EqualFold(r.TxHash, j.TxHash) {
		return false, errors.New("shop_receipt_mismatch")
	}
	event, delivery, payment := false, false, j.Kind != "buy"
	for _, log := range r.Logs {
		if c.eventMatches(log, *j) {
			event = true
		}
		if log.Removed {
			continue
		}
		if strings.EqualFold(log.Address, c.cfg.MarketplaceCollection) && len(log.Topics) == 4 && log.Topics[0] == itemTransferTopic {
			from, to, n := c.cfg.StarlightTreasury, j.Wallet, int64(j.Quantity)
			if j.Kind != "buy" {
				from, to, n = j.Wallet, "0x"+strings.Repeat("0", 40), 1
			}
			if log.Topics[2] == "0x"+addressWord(from) && log.Topics[3] == "0x"+addressWord(to) && log.Data == "0x"+hexWord(c.cfg.ShopTokenID)+hexWord(n) {
				delivery = true
			}
		}
		if j.Kind == "buy" && strings.EqualFold(log.Address, c.cfg.StarlightToken) && len(log.Topics) == 3 && log.Topics[0] == tokenTransferTopic && log.Topics[1] == "0x"+addressWord(j.Wallet) && log.Topics[2] == "0x"+addressWord(c.cfg.ShopRouter) && log.Data == "0x"+hex.EncodeToString(starlightRaw(int64(j.Quantity*c.price())).FillBytes(make([]byte, 32))) {
			payment = true
		}
	}
	if !event || !delivery || !payment {
		if !event {
			// A retry can confirm an idempotent no-op after the first transaction
			// paid/delivered. Recover the original event instead of trusting this hash.
			j.TxHash = ""
			return false, nil
		}
		return false, errors.New("shop_receipt_mismatch")
	}
	block, err := parseQuantity(r.BlockNumber)
	if err != nil {
		return false, err
	}
	head, err := c.star.p.head(ctx)
	if err != nil {
		return false, err
	}
	if head < block+c.cfg.StarlightConfirmations-1 {
		return false, nil
	}
	var canonical *struct {
		Hash string `json:"hash"`
	}
	if err = c.star.p.rpc(ctx, "eth_getBlockByNumber", []any{r.BlockNumber, false}, &canonical); err != nil {
		return false, err
	}
	return canonical != nil && strings.EqualFold(canonical.Hash, r.BlockHash), nil
}

var gasThreshold = big.NewInt(10000000000000)

func newBigQuantity(raw string) (*big.Int, bool) {
	if !strings.HasPrefix(raw, "0x") {
		return nil, false
	}
	n, ok := new(big.Int).SetString(raw[2:], 16)
	return n, ok && n.Sign() >= 0 && n.BitLen() <= 256
}
