package main

import (
	"context"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"math/big"
	"net/url"
	"strings"
)

const starlightPayABI = `[{"type":"function","name":"pay","stateMutability":"nonpayable","inputs":[{"name":"rewardId","type":"bytes32"},{"name":"recipient","type":"address"},{"name":"amount","type":"uint256"}],"outputs":[]}]`

var starlightPaidTopic = hashHex([]byte("RewardPaid(bytes32,address,uint256)"))
var tokenTransferTopic = hashHex([]byte("Transfer(address,address,uint256)"))
var tokenScale = new(big.Int).Exp(big.NewInt(10), big.NewInt(18), nil)

func starlightRaw(amount int64) *big.Int { return new(big.Int).Mul(big.NewInt(amount), tokenScale) }
func addressWord(address string) string {
	return strings.Repeat("0", 24) + strings.ToLower(strings.TrimPrefix(address, "0x"))
}
func starlightDigest(j starlightJob) string {
	raw, _ := hex.DecodeString(addressWord(j.Recipient))
	raw = append(raw, starlightRaw(j.Amount).FillBytes(make([]byte, 32))...)
	return hashHex(raw)
}
func uint256Hex(raw string) (*big.Int, error) {
	if !strings.HasPrefix(raw, "0x") || len(raw) != 66 {
		return nil, errors.New("token_response_invalid")
	}
	bytes, err := hex.DecodeString(raw[2:])
	if err != nil {
		return nil, errors.New("token_response_invalid")
	}
	return new(big.Int).SetBytes(bytes), nil
}
func formatStarlight(raw *big.Int) string {
	whole, part := new(big.Int), new(big.Int)
	whole.QuoRem(raw, tokenScale, part)
	if part.Sign() == 0 {
		return whole.String()
	}
	return whole.String() + "." + strings.TrimRight(fmt.Sprintf("%018s", part.String()), "0")
}
func validateStarlightConfig(c config) error {
	if c.StarlightEngineKey == "" || c.EngineAPIKey == "" || c.EngineProjectID == "" || c.StarlightChainID <= 0 || c.StarlightConfirmations < 1 || c.StarlightConfirmations > 64 || !validHex(c.StarlightToken, 20) || !validHex(c.StarlightTreasury, 20) || !validHex(c.StarlightDistributor, 20) || c.StarlightToken == c.StarlightDistributor || c.StarlightTreasury == c.StarlightDistributor {
		return errors.New("Starlight requires managed wallets, project, Engine key, chain, token, treasury, distributor and confirmations")
	}
	for _, raw := range []string{c.EngineURL, c.StarlightRPC} {
		u, err := url.Parse(raw)
		if err != nil || u.Scheme != "https" || u.Host == "" || u.User != nil || u.RawQuery != "" || u.Fragment != "" {
			return errors.New("Starlight URLs must use HTTPS without credentials, query or fragment")
		}
	}
	return nil
}

type starlightClient struct {
	cfg  config
	p    *publicationClient
	item bool
}

func newStarlightClient(c config) *starlightClient {
	rpc := c
	rpc.LeaderboardRPC = c.StarlightRPC
	rpc.LeaderboardAddress = c.StarlightDistributor
	rpc.LeaderboardEngineKey = c.StarlightEngineKey
	return &starlightClient{cfg: c, p: newPublicationClient(rpc)}
}
func (s *starlightClient) call(ctx context.Context, address, data string) (string, error) {
	var out string
	err := s.p.rpc(ctx, "eth_call", []any{map[string]string{"to": address, "data": data}, "latest"}, &out)
	return out, err
}
func (s *starlightClient) raw(amount int64) *big.Int {
	if s.item {
		return big.NewInt(amount)
	}
	return starlightRaw(amount)
}
func (s *starlightClient) digest(j starlightJob) string {
	raw, _ := hex.DecodeString(addressWord(j.Recipient))
	raw = append(raw, s.raw(j.Amount).FillBytes(make([]byte, 32))...)
	return hashHex(raw)
}
func (s *starlightClient) args(j starlightJob) []string {
	return []string{"0x" + j.Key, j.Recipient, s.raw(j.Amount).String()}
}
func (s *starlightClient) balance(ctx context.Context, address string) (*big.Int, error) {
	data := selector("balanceOf(address)") + addressWord(address)
	if s.item {
		data = selector("balanceOf(address,uint256)") + addressWord(address) + hexWord(11)
	}
	value, err := s.call(ctx, s.cfg.StarlightToken, data)
	if err != nil {
		return nil, err
	}
	return uint256Hex(value)
}
func (s *starlightClient) preflight(ctx context.Context) error {
	var auth struct {
		App struct {
			ID string `json:"id"`
		} `json:"app"`
	}
	if err := s.p.json(ctx, "GET", s.cfg.EngineURL+"/v1/auth/me", nil, "read", &auth); err != nil {
		return err
	}
	if auth.App.ID != s.cfg.EngineProjectID {
		return errors.New("starlight_project_mismatch")
	}
	var chain string
	if err := s.p.rpc(ctx, "eth_chainId", []any{}, &chain); err != nil {
		return err
	}
	id, err := parseQuantity(chain)
	if err != nil || id != s.cfg.StarlightChainID {
		return errors.New("starlight_chain_mismatch")
	}
	for _, v := range []struct{ function, address string }{{"token()", s.cfg.StarlightToken}, {"treasury()", s.cfg.StarlightTreasury}} {
		out, err := s.call(ctx, s.cfg.StarlightDistributor, selector(v.function))
		if err != nil {
			return err
		}
		if !strings.EqualFold(out, "0x"+addressWord(v.address)) {
			return errors.New("starlight_distributor_mismatch")
		}
	}
	if s.item {
		value, err := s.call(ctx, s.cfg.StarlightDistributor, selector("tokenId()"))
		if err != nil {
			return err
		}
		id, e := wordInt(value, 0)
		if e != nil || id != 11 {
			return errors.New("reward_item_mismatch")
		}
		return nil
	}
	value, err := s.call(ctx, s.cfg.StarlightToken, selector("decimals()"))
	if err != nil {
		return err
	}
	n, err := wordInt(value, 0)
	if err != nil || n != 18 {
		return errors.New("starlight_decimals_mismatch")
	}
	return nil
}
func starlightArgs(j starlightJob) []string {
	return []string{"0x" + j.Key, j.Recipient, starlightRaw(j.Amount).String()}
}
func (s *starlightClient) validateTx(tx enginePublicationTx, j starlightJob) error {
	if tx.ID == "" || tx.AppID != s.cfg.EngineProjectID || tx.ChainID != s.cfg.StarlightChainID || !strings.EqualFold(tx.ContractAddress, s.cfg.StarlightDistributor) || !strings.EqualFold(tx.WalletAddress, s.cfg.StarlightTreasury) || tx.Method != "pay" || strings.Join(tx.Args, "\x00") != strings.Join(s.args(j), "\x00") {
		return errors.New("starlight_transaction_mismatch")
	}
	return nil
}
func (s *starlightClient) enqueue(ctx context.Context, j starlightJob) (enginePublicationTx, error) {
	var out struct {
		Transaction enginePublicationTx `json:"transaction"`
	}
	key := fmt.Sprintf("rescene/starlight/%s/%d", j.Key, j.Generation)
	err := s.p.json(ctx, "POST", s.cfg.EngineURL+"/v1/contracts/write", map[string]any{"chainId": s.cfg.StarlightChainID, "contractAddress": s.cfg.StarlightDistributor, "walletAddress": s.cfg.StarlightTreasury, "functionName": "pay", "abi": json.RawMessage(starlightPayABI), "args": s.args(j), "value": "0"}, key, &out)
	if err == nil {
		err = s.validateTx(out.Transaction, j)
	}
	return out.Transaction, err
}
func (s *starlightClient) transaction(ctx context.Context, j starlightJob) (enginePublicationTx, error) {
	var out struct {
		Transaction enginePublicationTx `json:"transaction"`
	}
	err := s.p.json(ctx, "GET", s.cfg.EngineURL+"/v1/transactions/"+url.PathEscape(j.EngineID), nil, "read", &out)
	if err == nil {
		err = s.validateTx(out.Transaction, j)
	}
	return out.Transaction, err
}
func (s *starlightClient) processed(ctx context.Context, j starlightJob) (bool, error) {
	value, err := s.call(ctx, s.cfg.StarlightDistributor, selector("payouts(bytes32)")+j.Key)
	if err != nil {
		return false, err
	}
	if value == "0x"+strings.Repeat("0", 64) {
		return false, nil
	}
	if !strings.EqualFold(value, s.digest(j)) {
		return false, errors.New("starlight_reward_mismatch")
	}
	return true, nil
}
func (s *starlightClient) matchesPaid(log scoreLog, j starlightJob) bool {
	return !log.Removed && strings.EqualFold(log.Address, s.cfg.StarlightDistributor) && len(log.Topics) == 3 && strings.EqualFold(log.Topics[0], starlightPaidTopic) && strings.EqualFold(log.Topics[1], "0x"+j.Key) && strings.EqualFold(log.Topics[2], "0x"+addressWord(j.Recipient)) && strings.EqualFold(log.Data, "0x"+hex.EncodeToString(s.raw(j.Amount).FillBytes(make([]byte, 32))))
}
func (s *starlightClient) confirmed(ctx context.Context, j starlightJob) (bool, error) {
	if !validHex(j.TxHash, 32) {
		return false, nil
	}
	var receipt *publicationReceipt
	if err := s.p.rpc(ctx, "eth_getTransactionReceipt", []any{j.TxHash}, &receipt); err != nil {
		return false, err
	}
	if receipt == nil || receipt.Status != "0x1" {
		return false, nil
	}
	if !strings.EqualFold(receipt.TxHash, j.TxHash) {
		return false, errors.New("starlight_receipt_mismatch")
	}
	paid, transfer := false, false
	for _, log := range receipt.Logs {
		if s.matchesPaid(log, j) {
			paid = true
		}
		if !log.Removed && strings.EqualFold(log.Address, s.cfg.StarlightToken) && len(log.Topics) == 3 && strings.EqualFold(log.Topics[0], tokenTransferTopic) && strings.EqualFold(log.Topics[1], "0x"+addressWord(s.cfg.StarlightTreasury)) && strings.EqualFold(log.Topics[2], "0x"+addressWord(j.Recipient)) && strings.EqualFold(log.Data, "0x"+hex.EncodeToString(s.raw(j.Amount).FillBytes(make([]byte, 32)))) {
			transfer = true
		}
		if s.item && !log.Removed && strings.EqualFold(log.Address, s.cfg.StarlightToken) && len(log.Topics) == 4 && strings.EqualFold(log.Topics[0], itemTransferTopic) && strings.EqualFold(log.Topics[2], "0x"+addressWord(s.cfg.StarlightTreasury)) && strings.EqualFold(log.Topics[3], "0x"+addressWord(j.Recipient)) && strings.EqualFold(log.Data, "0x"+hexWord(11)+hexWord(j.Amount)) {
			transfer = true
		}
	}
	if !paid || !transfer {
		return false, errors.New("starlight_receipt_mismatch")
	}
	block, err := parseQuantity(receipt.BlockNumber)
	if err != nil || block <= 0 {
		return false, errors.New("starlight_receipt_mismatch")
	}
	head, err := s.p.head(ctx)
	if err != nil {
		return false, err
	}
	if head < block+s.cfg.StarlightConfirmations-1 {
		return false, nil
	}
	var canonical *struct {
		Hash string `json:"hash"`
	}
	if err = s.p.rpc(ctx, "eth_getBlockByNumber", []any{receipt.BlockNumber, false}, &canonical); err != nil {
		return false, err
	}
	return canonical != nil && strings.EqualFold(canonical.Hash, receipt.BlockHash), nil
}
func (s *starlightClient) findPaid(ctx context.Context, j *starlightJob) (string, error) {
	logs, err := s.p.recoveryLogs(ctx, &j.Recovery, j.FromBlock, s.cfg.StarlightConfirmations, s.cfg.StarlightDistributor, []string{starlightPaidTopic, "0x" + j.Key, "0x" + addressWord(j.Recipient)})
	if err != nil {
		return "", err
	}
	for _, log := range logs {
		if s.matchesPaid(log, *j) && validHex(log.TxHash, 32) {
			return log.TxHash, nil
		}
	}
	return "", scanPending()
}
