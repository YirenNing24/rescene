package main

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"math/big"
	"strings"
)

var pulseActionTopic = hashHex([]byte("CardAction(bytes32,address,uint256,uint256,uint256)"))

func secureRange(lo, hi int) (int, error) {
	n, err := rand.Int(rand.Reader, big.NewInt(int64(hi-lo+1)))
	if err != nil {
		return 0, err
	}
	return lo + int(n.Int64()), nil
}
func (c *shopClient) pulsePreflight(ctx context.Context) error {
	if c.cfg.PulseRouter == "" {
		return errPulseState
	}
	block, err := c.pulseBlock(ctx)
	if err != nil {
		return err
	}
	for _, binding := range []struct{ signature, address string }{{"operator()", c.cfg.StarlightTreasury}, {"token()", c.cfg.StarlightToken}, {"items()", c.cfg.MarketplaceCollection}} {
		raw, err := c.pulseRead(ctx, block, binding.signature, "")
		if err != nil {
			return err
		}
		if !strings.EqualFold(raw, "0x"+addressWord(binding.address)) {
			return errors.New("card contract mismatch")
		}
	}
	raw, err := c.pulseRead(ctx, block, "VERSION()", "")
	if err != nil {
		return err
	}
	version, err := wordInt(raw, 0)
	if err != nil || version != 2 {
		return errors.New("card contract version mismatch")
	}
	if c.cfg.CardReleases {
		raw, e := c.pulseRead(ctx, block, "RELEASE_COUNT()", "")
		n, decodeErr := wordInt(raw, 0)
		if e != nil || decodeErr != nil || n != 9 {
			return errors.New("card release contract mismatch")
		}
	}
	priceRaw, err := c.pulseRead(ctx, block, "unitPrice()", "")
	if err != nil {
		return err
	}
	price, err := uint256Hex(priceRaw)
	if err != nil || price.Cmp(starlightRaw(450)) != 0 {
		return errors.New("card price mismatch")
	}
	for i, material := range cardMaterials {
		raw, err = c.pulseRead(ctx, block, "materialIds(uint256)", hexWord(int64(i)))
		if err != nil {
			return err
		}
		id, e := wordInt(raw, 0)
		if e != nil || id != material.TokenID {
			return errors.New("card materials mismatch")
		}
	}
	for _, role := range []string{"MINTER_ROLE", "METADATA_ROLE"} {
		raw, err := c.call(ctx, c.cfg.MarketplaceCollection, "hasRole(bytes32,address)", strings.TrimPrefix(hashHex([]byte(role)), "0x")+addressWord(c.cfg.PulseRouter))
		if err != nil {
			return err
		}
		allowed, err := wordInt(raw, 0)
		if err != nil || allowed != 1 {
			return errors.New("card collection role missing")
		}
	}
	frozen, err := c.call(ctx, c.cfg.MarketplaceCollection, "uriFrozen()", "")
	if err != nil {
		return err
	}
	value, err := wordInt(frozen, 0)
	if err != nil || value != 0 {
		return errors.New("card metadata is frozen")
	}
	return nil
}
func pulseSpec(c *shopClient, j shopJob) (shopCall, error) {
	p := j.Pulse
	if p == nil {
		return shopCall{}, errPulseState
	}
	wallet := c.cfg.StarlightTreasury
	if j.Stage == "gas" {
		return shopCall{c.cfg.ShopRouter, wallet, "fundGas", shopGasAmount, []string{"0x" + j.Key, j.Wallet}}, nil
	}
	if j.Stage == "approve" {
		if j.Kind == "pulse_buy" || j.Kind == "pulse_material" {
			return shopCall{c.cfg.StarlightToken, j.Wallet, "approve", "0", []string{c.cfg.PulseRouter, starlightRaw(pulsePayment(j)).String()}}, nil
		}
		return shopCall{c.cfg.MarketplaceCollection, j.Wallet, "setApprovalForAll", "0", []string{c.cfg.PulseRouter, "true"}}, nil
	}
	args := []string{"0x" + j.Key, j.Wallet}
	method := ""
	token, _ := pulseToken(j.CardID)
	switch j.Kind {
	case "pulse_buy":
		method = "purchase"
		args = append(args, fmt.Sprint(p.Request.Member), fmt.Sprint(p.Score), fmt.Sprint(p.Recovery), fmt.Sprint(p.Skill))
	case "pulse_material":
		method = "purchaseMaterial"
		material, _ := materialByID(j.ItemID)
		args = append(args, fmt.Sprint(material.TokenID), fmt.Sprint(j.Quantity))
	case "pulse_refine":
		method = "refine"
		material, ok := materialByID(j.ItemID)
		if !ok {
			return shopCall{}, errPulseState
		}
		args = append(args, fmt.Sprint(token), fmt.Sprint(material.TokenID), fmt.Sprint(p.Roll), fmt.Sprint(p.Revision))
	case "pulse_star":
		method = "starUpgrade"
		donors := []string{}
		for _, id := range p.Request.Donors {
			token, ok := pulseToken(id)
			if !ok {
				return shopCall{}, errPulseState
			}
			donors = append(donors, fmt.Sprint(token))
		}
		data, _ := json.Marshal(donors)
		args = append(args, fmt.Sprint(token), string(data), fmt.Sprint(p.Revision))
	case "pulse_lock":
		method = "protect"
		args = append(args, fmt.Sprint(token), fmt.Sprint(p.Request.Locked), fmt.Sprint(p.Revision))
	case "pulse_equip":
		method = "equip"
		args = append(args, fmt.Sprint(releaseNumber(p.Request.SetID)), fmt.Sprint(p.Request.Member), fmt.Sprint(token))
	default:
		return shopCall{}, errPulseState
	}
	return shopCall{c.cfg.PulseRouter, wallet, method, "0", args}, nil
}
func pulseDigest(j shopJob) (string, error) {
	p := j.Pulse
	if p == nil {
		return "", errPulseState
	}
	token, _ := pulseToken(j.CardID)
	words := ""
	switch j.Kind {
	case "pulse_buy":
		words = hexWord(1) + addressWord(j.Wallet) + hexWord(int64(p.Request.Member)) + hexWord(int64(p.Score)) + hexWord(int64(p.Recovery)) + hexWord(int64(p.Skill))
	case "pulse_material":
		material, _ := materialByID(j.ItemID)
		words = hexWord(7) + addressWord(j.Wallet) + hexWord(material.TokenID) + hexWord(int64(j.Quantity))
	case "pulse_refine":
		material, ok := materialByID(j.ItemID)
		if !ok {
			return "", errPulseState
		}
		words = hexWord(3) + addressWord(j.Wallet) + hexWord(token) + hexWord(material.TokenID) + hexWord(int64(p.Roll)) + hexWord(p.Revision)
	case "pulse_star":
		words = hexWord(4) + addressWord(j.Wallet) + hexWord(token) + hexWord(160) + hexWord(p.Revision) + hexWord(int64(len(p.Request.Donors)))
		for _, id := range p.Request.Donors {
			value, ok := pulseToken(id)
			if !ok {
				return "", errPulseState
			}
			words += hexWord(value)
		}
	case "pulse_lock":
		value := int64(0)
		if p.Request.Locked {
			value = 1
		}
		words = hexWord(5) + addressWord(j.Wallet) + hexWord(token) + hexWord(value) + hexWord(p.Revision)
	case "pulse_equip":
		words = hexWord(6) + addressWord(j.Wallet) + hexWord(int64(releaseNumber(p.Request.SetID))) + hexWord(int64(p.Request.Member)) + hexWord(token)
	default:
		return "", errPulseState
	}
	data, err := hex.DecodeString(words)
	if err != nil {
		return "", err
	}
	return hashHex(data), nil
}
func (c *shopClient) pulseProcessed(ctx context.Context, j shopJob) (bool, error) {
	raw, err := c.call(ctx, c.cfg.PulseRouter, "actions(bytes32)", j.Key)
	if err != nil {
		return false, err
	}
	if raw == "0x"+strings.Repeat("0", 64) {
		return false, nil
	}
	expected, err := pulseDigest(j)
	if err != nil {
		return false, err
	}
	if !strings.EqualFold(raw, expected) {
		return false, errors.New("card operation mismatch")
	}
	return true, nil
}
func pulseKind(kind string) int64 {
	return map[string]int64{"pulse_buy": 1, "pulse_refine": 3, "pulse_star": 4, "pulse_lock": 5, "pulse_equip": 6, "pulse_material": 7}[kind]
}
func (c *shopClient) pulseEvent(log scoreLog, j shopJob) bool {
	if log.Removed || !strings.EqualFold(log.Address, c.cfg.PulseRouter) || len(log.Topics) != 4 || log.Topics[0] != pulseActionTopic || log.Topics[1] != "0x"+j.Key || log.Topics[2] != "0x"+addressWord(j.Wallet) || len(log.Data) != 130 {
		return false
	}
	kind, err := wordInt(log.Data, 0)
	if err != nil || kind != pulseKind(j.Kind) {
		return false
	}
	id, err := wordInt(log.Topics[3], 0)
	if err != nil {
		return false
	}
	if j.Kind == "pulse_buy" {
		return id > 0
	}
	if j.Kind == "pulse_material" {
		material, _ := materialByID(j.ItemID)
		return id == material.TokenID
	}
	token, _ := pulseToken(j.CardID)
	return token == id
}
func (c *shopClient) pulseConfirmed(ctx context.Context, j *shopJob) (bool, error) {
	if j.TxHash == "" {
		head, err := c.star.p.head(ctx)
		if err != nil {
			return false, err
		}
		for scanned := 0; j.FromBlock <= head && scanned < 8; scanned++ {
			end := min(head, j.FromBlock+2047)
			var logs []scoreLog
			err = c.star.p.rpc(ctx, "eth_getLogs", []any{map[string]any{"address": c.cfg.PulseRouter, "fromBlock": fmt.Sprintf("0x%x", j.FromBlock), "toBlock": fmt.Sprintf("0x%x", end), "topics": []string{pulseActionTopic, "0x" + j.Key, "0x" + addressWord(j.Wallet)}}}, &logs)
			if err != nil {
				return false, err
			}
			for _, log := range logs {
				if c.pulseEvent(log, *j) {
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
		return false, errors.New("card receipt mismatch")
	}
	var event *scoreLog
	for i := range r.Logs {
		if c.pulseEvent(r.Logs[i], *j) {
			if event != nil {
				return false, errors.New("duplicate card action event")
			}
			event = &r.Logs[i]
		}
	}
	if event == nil {
		j.TxHash = ""
		return false, nil
	}
	token, err := wordInt(event.Topics[3], 0)
	if err != nil {
		return false, err
	}
	result := int64(0)
	if j.Kind != "pulse_buy" {
		result, err = wordInt(event.Data, 1)
		if err != nil {
			return false, err
		}
	} else if event.Data != "0x"+hexWord(1)+hex.EncodeToString(starlightRaw(pulsePayment(*j)).FillBytes(make([]byte, 32))) {
		return false, errors.New("card price mismatch")
	}
	burned := map[int64]int{}
	minted, payment := false, false
	delivered := false
	for _, log := range r.Logs {
		if log.Removed {
			continue
		}
		if strings.EqualFold(log.Address, c.cfg.MarketplaceCollection) && len(log.Topics) == 4 && log.Topics[0] == itemTransferTopic {
			id, e1 := wordInt(log.Data, 0)
			amount, e2 := wordInt(log.Data, 1)
			if e1 != nil || e2 != nil {
				continue
			}
			if amount == 1 && log.Topics[2] == "0x"+addressWord(j.Wallet) && log.Topics[3] == "0x"+strings.Repeat("0", 64) {
				burned[id]++
			}
			if j.Kind == "pulse_material" && id == token && amount == int64(j.Quantity) && log.Topics[2] == "0x"+addressWord(c.cfg.StarlightTreasury) && log.Topics[3] == "0x"+addressWord(j.Wallet) {
				delivered = true
			}
			if amount == 1 && id == token && log.Topics[2] == "0x"+strings.Repeat("0", 64) && log.Topics[3] == "0x"+addressWord(j.Wallet) {
				minted = true
			}
		}
		if strings.EqualFold(log.Address, c.cfg.StarlightToken) && len(log.Topics) == 3 && log.Topics[0] == tokenTransferTopic && log.Topics[1] == "0x"+addressWord(j.Wallet) && log.Topics[2] == "0x"+addressWord(c.cfg.StarlightTreasury) && log.Data == "0x"+hex.EncodeToString(starlightRaw(pulsePayment(*j)).FillBytes(make([]byte, 32))) {
			payment = true
		}
	}
	switch j.Kind {
	case "pulse_buy":
		if !minted || !payment {
			return false, errors.New("card delivery/payment mismatch")
		}
	case "pulse_material":
		if !delivered || !payment || result != int64(j.Quantity) {
			return false, errors.New("material delivery/payment mismatch")
		}
	case "pulse_refine":
		material, _ := materialByID(j.ItemID)
		if burned[material.TokenID] != 1 || len(burned) != 1 || result < 0 || result > 2 {
			return false, errors.New("refinement receipt mismatch")
		}
	case "pulse_star":
		if len(burned) != len(j.Pulse.Request.Donors) || result != int64(j.Pulse.Quote.Wasted) {
			return false, errors.New("sacrifice receipt mismatch")
		}
		for _, id := range j.Pulse.Request.Donors {
			donor, _ := pulseToken(id)
			if burned[donor] != 1 {
				return false, errors.New("sacrifice donor mismatch")
			}
		}
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
	if canonical == nil || !strings.EqualFold(canonical.Hash, r.BlockHash) {
		return false, nil
	}
	if j.Kind == "pulse_buy" {
		j.CardID = pulseID(token)
	}
	if j.Kind == "pulse_refine" {
		value := result == 2
		j.LevelUpgraded = &value
		j.UpgradeAttempted = result > 0
		j.LevelAfter = j.LevelBefore
		if value {
			j.LevelAfter++
		}
		j.TrainingXP = j.Pulse.Quote.AddedXP
	}
	return true, nil
}
func (s *shopService) advancePulse(ctx context.Context, j *shopJob) error {
	c := s.client
	if j.Router != c.cfg.PulseRouter || j.Pulse == nil {
		return errPulseState
	}
	processed, err := c.pulseProcessed(ctx, *j)
	if err != nil {
		return err
	}
	if processed {
		if j.Stage != "execute" {
			j.TxHash = ""
		}
		ok, err := c.pulseConfirmed(ctx, j)
		if err != nil {
			return err
		}
		if ok {
			j.Status = "confirmed"
			j.Error = ""
		}
		return nil
	}
	if j.EngineID != "" {
		tx, err := c.transaction(ctx, *j)
		if err != nil {
			return err
		}
		switch tx.Status {
		case "queued", "signing", "submitted", "retrying":
			return nil
		case "confirmed":
			j.EngineID = ""
			j.TxHash = ""
			j.Generation = 0
			if j.Stage == "gas" {
				j.Stage = "approve"
			} else if j.Stage == "approve" {
				j.Stage = "execute"
			}
			return nil
		case "failed":
			j.EngineID = ""
			j.TxHash = ""
			j.Generation++
			if j.Generation >= 3 {
				j.Status = "failed"
				j.Error = "The card action could not complete. Refresh your Collection."
			}
			return nil
		default:
			return errors.New("card transaction status unavailable")
		}
	}
	if j.Kind == "pulse_lock" || j.Kind == "pulse_equip" {
		j.Stage = "execute"
	}
	switch j.Stage {
	case "gas":
		var raw string
		if err = c.star.p.rpc(ctx, "eth_getBalance", []string{j.Wallet, "latest"}, &raw); err != nil {
			return err
		}
		amount, ok := newBigQuantity(raw)
		if !ok {
			return errPulseState
		}
		if amount.Cmp(gasThreshold) >= 0 {
			j.Stage = "approve"
			return nil
		}
	case "approve":
		if j.Kind == "pulse_buy" || j.Kind == "pulse_material" {
			n, err := c.number(ctx, c.cfg.StarlightToken, "allowance(address,address)", addressWord(j.Wallet)+addressWord(c.cfg.PulseRouter))
			if err != nil {
				return err
			}
			if n.Cmp(starlightRaw(pulsePayment(*j))) >= 0 {
				j.Stage = "execute"
				return nil
			}
		} else {
			n, err := c.number(ctx, c.cfg.MarketplaceCollection, "isApprovedForAll(address,address)", addressWord(j.Wallet)+addressWord(c.cfg.PulseRouter))
			if err != nil {
				return err
			}
			if n.Sign() > 0 {
				j.Stage = "execute"
				return nil
			}
		}
	case "execute":
		if !j.ExecuteStarted {
			if j.Kind != "pulse_buy" && j.Kind != "pulse_material" {
				p, _, err := s.store.ReadProgress(j.Owner)
				if err != nil {
					return err
				}
				a := api{shop: s, config: c.cfg}
				fresh, err := a.pulsePreview(ctx, p, j.Wallet, j.Pulse.Request, j.Key)
				if err != nil {
					var validation progressError
					if errors.As(err, &validation) {
						j.Status = "failed"
						j.Error = "The cards changed before this action. Nothing was consumed."
						return nil
					}
					return err
				}
				if fresh.Quote.Hash != j.Pulse.Quote.Hash {
					j.Status = "failed"
					j.Error = "The cards changed. Review another preview; nothing was consumed."
					return nil
				}
			}
			j.ExecuteStarted = true
			return nil
		}
	default:
		return errPulseState
	}
	tx, err := c.enqueue(ctx, *j)
	if err != nil {
		return err
	}
	j.EngineID = tx.ID
	j.TxHash = tx.Hash
	return nil
}

func pulsePayment(j shopJob) int64 {
	if j.Kind == "pulse_buy" {
		return 450
	}
	material, ok := materialByID(j.ItemID)
	if !ok {
		return 0
	}
	return int64(material.Price * j.Quantity)
}
