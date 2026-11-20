package main

import (
	"bytes"
	"context"
	"encoding/binary"
	"encoding/hex"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"net/url"
	"strconv"
	"strings"
	"time"

	"golang.org/x/crypto/sha3"
)

func validHex(text string, size int) bool {
	data, err := hex.DecodeString(strings.TrimPrefix(text, "0x"))
	return err == nil && len(data) == size && !bytes.Equal(data, make([]byte, size))
}
func hashHex(data []byte) string {
	h := sha3.NewLegacyKeccak256()
	_, _ = h.Write(data)
	return "0x" + hex.EncodeToString(h.Sum(nil))
}
func word(n int64) []byte {
	result := make([]byte, 32)
	binary.BigEndian.PutUint64(result[24:], uint64(n))
	return result
}
func selector(signature string) string { return hashHex([]byte(signature))[:10] }
func chartBoardKey(song, difficulty, revision string) (string, error) {
	index, ok := map[string]int64{"Easy": 0, "Normal": 1, "Hard": 2, "Ultra Hard": 3}[difficulty]
	if !ok || !validHex(revision, 32) {
		return "", errors.New("invalid chart identity")
	}
	rev, _ := hex.DecodeString(strings.TrimPrefix(revision, "0x"))
	data := append(word(96), word(index)...)
	data = append(data, rev...)
	data = append(data, word(int64(len(song)))...)
	data = append(data, []byte(song)...)
	data = append(data, make([]byte, (32-len(song)%32)%32)...)
	return hashHex(data), nil
}

func validatePublisherConfig(c config) error {
	if !validHex(c.LeaderboardAddress, 20) || !validHex(c.LeaderboardPublisher, 20) || c.LeaderboardChainID <= 0 || c.LeaderboardConfirmations < 1 || c.LeaderboardConfirmations > 64 || c.LeaderboardEngineKey == "" || c.EngineProjectID == "" {
		return errors.New("leaderboard integration requires contract, publisher, chain, confirmations, project and server-only Engine key")
	}
	for _, raw := range []string{c.EngineURL, c.LeaderboardRPC} {
		u, err := url.Parse(raw)
		if err != nil || u.Host == "" || u.User != nil || u.Fragment != "" || u.Scheme != "https" {
			return errors.New("leaderboard Engine and RPC URLs must use HTTPS without credentials or fragments")
		}
	}
	return nil
}

const submitScoreABI = `[{"type":"function","name":"submitScore","stateMutability":"nonpayable","inputs":[{"name":"boardId","type":"bytes32"},{"name":"entry","type":"tuple","components":[{"name":"playerId","type":"bytes16"},{"name":"runId","type":"bytes16"},{"name":"score","type":"uint32"},{"name":"maxCombo","type":"uint32"},{"name":"achievedAt","type":"uint64"}]}],"outputs":[]}]`
const registerBoardABI = `[{"type":"function","name":"registerBoard","stateMutability":"nonpayable","inputs":[{"name":"songId","type":"string"},{"name":"difficulty","type":"uint8"},{"name":"revision","type":"bytes32"},{"name":"units","type":"uint32"}],"outputs":[{"name":"boardId","type":"bytes32"}]}]`

type publicationClient struct {
	cfg  config
	http *http.Client
}

func newPublicationClient(c config) *publicationClient {
	return &publicationClient{cfg: c, http: &http.Client{Timeout: 10 * time.Second, CheckRedirect: func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse }}}
}
func (p *publicationClient) json(ctx context.Context, method, address string, body any, key string, out any) error {
	var reader io.Reader
	if body != nil {
		data, err := json.Marshal(body)
		if err != nil {
			return errors.New("request_invalid")
		}
		reader = bytes.NewReader(data)
	}
	req, err := http.NewRequestWithContext(ctx, method, address, reader)
	if err != nil {
		return errors.New("request_invalid")
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("User-Agent", "Mozilla/5.0 (compatible; RESCENE-Rhythm-Backend/0.1)")
	if key != "" {
		req.Header.Set("X-GMR-Engine-Key", p.cfg.LeaderboardEngineKey)
		if key != "read" {
			req.Header.Set("Idempotency-Key", key)
		}
	}
	res, err := p.http.Do(req)
	if err != nil {
		return errors.New("network_unavailable")
	}
	defer res.Body.Close()
	data, err := io.ReadAll(io.LimitReader(res.Body, 1048577))
	if err != nil || len(data) > 1048576 {
		return errors.New("response_invalid")
	}
	if res.StatusCode < 200 || res.StatusCode >= 300 {
		if key == "" {
			return &rpcHTTPError{Status: res.StatusCode, Body: data}
		}
		if res.StatusCode == 401 || res.StatusCode == 403 {
			return errors.New("engine_authorization_failed")
		}
		return errors.New("upstream_unavailable")
	}
	if json.Unmarshal(data, out) != nil {
		return errors.New("response_invalid")
	}
	return nil
}
func (p *publicationClient) rpc(ctx context.Context, method string, params any, out any) error {
	g := p.recoveryGate()
	g.mu.Lock()
	until := g.blockedUntil
	if method == "eth_getLogs" && g.logsBlockedUntil.After(until) {
		until = g.logsBlockedUntil
	}
	g.mu.Unlock()
	if time.Now().Before(until) {
		return &recoveryWait{Until: until, Code: "rpc_provider_cooldown"}
	}
	var result struct {
		Result json.RawMessage `json:"result"`
		Error  json.RawMessage `json:"error"`
	}
	if err := p.json(ctx, "POST", p.cfg.LeaderboardRPC, map[string]any{"jsonrpc": "2.0", "id": 1, "method": method, "params": params}, "", &result); err != nil {
		var upstream *rpcHTTPError
		if errors.As(err, &upstream) {
			return p.rpcProviderError(upstream.Status, upstream.Body)
		}
		return err
	}
	if len(result.Error) > 0 && string(result.Error) != "null" {
		return p.rpcProviderError(200, result.Error)
	}
	if len(result.Result) == 0 || json.Unmarshal(result.Result, out) != nil {
		return errors.New("rpc_response_invalid")
	}
	return nil
}
func (p *publicationClient) ethCall(ctx context.Context, data string) (string, error) {
	var out string
	err := p.rpc(ctx, "eth_call", []any{map[string]string{"to": p.cfg.LeaderboardAddress, "data": data}, "latest"}, &out)
	return out, err
}
func parseQuantity(text string) (int64, error) {
	return strconv.ParseInt(strings.TrimPrefix(text, "0x"), 16, 64)
}
func (p *publicationClient) head(ctx context.Context) (int64, error) {
	var value string
	if err := p.rpc(ctx, "eth_blockNumber", []any{}, &value); err != nil {
		return 0, err
	}
	return parseQuantity(value)
}
func wordInt(data string, index int) (int64, error) {
	raw, err := hex.DecodeString(strings.TrimPrefix(data, "0x"))
	if err != nil || len(raw) < 32*(index+1) {
		return 0, errors.New("rpc_response_invalid")
	}
	field := raw[index*32 : (index+1)*32]
	if !bytes.Equal(field[:24], make([]byte, 24)) {
		return 0, errors.New("rpc_response_invalid")
	}
	n := binary.BigEndian.Uint64(field[24:])
	if n > 1<<63-1 {
		return 0, errors.New("rpc_response_invalid")
	}
	return int64(n), nil
}
func paddedID(id string) string { return strings.TrimPrefix(id, "0x") + strings.Repeat("0", 32) }
func (p *publicationClient) processed(ctx context.Context, j publicationJob) (bool, error) {
	data, err := p.ethCall(ctx, selector("processedRuns(bytes16,bytes16)")+paddedID(j.Payload.PlayerID)+paddedID(j.Payload.RunID))
	if err != nil {
		return false, err
	}
	n, err := wordInt(data, 0)
	return n == 1, err
}

type enginePublicationTx struct {
	ID              string   `json:"id"`
	AppID           string   `json:"appId"`
	ChainID         int64    `json:"chainId"`
	ContractAddress string   `json:"contractAddress"`
	WalletAddress   string   `json:"walletAddress"`
	Method          string   `json:"method"`
	Args            []string `json:"args"`
	Status          string   `json:"status"`
	Hash            string   `json:"transactionHash"`
}

func scoreArgs(j publicationJob) []string {
	b := j.Payload
	entry, _ := json.Marshal(map[string]any{"playerId": "0x" + b.PlayerID, "runId": "0x" + b.RunID, "score": b.Score, "maxCombo": b.MaxCombo, "achievedAt": b.AchievedAt})
	return []string{b.BoardID, string(entry)}
}
func (p *publicationClient) checkEngineTx(tx enginePublicationTx, method string, args []string) error {
	if tx.ID == "" || tx.AppID != p.cfg.EngineProjectID || tx.ChainID != p.cfg.LeaderboardChainID || !strings.EqualFold(tx.ContractAddress, p.cfg.LeaderboardAddress) || !strings.EqualFold(tx.WalletAddress, p.cfg.LeaderboardPublisher) || tx.Method != method || strings.Join(tx.Args, "\x00") != strings.Join(args, "\x00") {
		return errors.New("engine_response_mismatch")
	}
	return nil
}
func (p *publicationClient) enqueue(ctx context.Context, key, method, abi string, args []string) (enginePublicationTx, error) {
	var out struct {
		Transaction enginePublicationTx `json:"transaction"`
	}
	err := p.json(ctx, "POST", p.cfg.EngineURL+"/v1/contracts/write", map[string]any{"chainId": p.cfg.LeaderboardChainID, "contractAddress": p.cfg.LeaderboardAddress, "walletAddress": p.cfg.LeaderboardPublisher, "functionName": method, "abi": json.RawMessage(abi), "args": args, "value": "0"}, key, &out)
	if err == nil {
		err = p.checkEngineTx(out.Transaction, method, args)
	}
	return out.Transaction, err
}
func (p *publicationClient) transaction(ctx context.Context, j publicationJob) (enginePublicationTx, error) {
	var out struct {
		Transaction enginePublicationTx `json:"transaction"`
	}
	err := p.json(ctx, "GET", p.cfg.EngineURL+"/v1/transactions/"+url.PathEscape(j.EngineID), nil, "read", &out)
	if err == nil {
		err = p.checkEngineTx(out.Transaction, "submitScore", scoreArgs(j))
	}
	return out.Transaction, err
}

type scoreLog struct {
	Address string   `json:"address"`
	Topics  []string `json:"topics"`
	Data    string   `json:"data"`
	TxHash  string   `json:"transactionHash"`
	Removed bool     `json:"removed"`
}
type publicationReceipt struct {
	Status      string     `json:"status"`
	TxHash      string     `json:"transactionHash"`
	BlockHash   string     `json:"blockHash"`
	BlockNumber string     `json:"blockNumber"`
	Logs        []scoreLog `json:"logs"`
}

var scoreProcessedTopic = hashHex([]byte("ScoreProcessed(bytes32,bytes16,bytes16,uint32,uint32,uint64,bool)"))

func (p *publicationClient) matchesLog(log scoreLog, j publicationJob) bool {
	b := j.Payload
	if log.Removed || !strings.EqualFold(log.Address, p.cfg.LeaderboardAddress) || len(log.Topics) != 4 || !strings.EqualFold(log.Topics[0], scoreProcessedTopic) || !strings.EqualFold(log.Topics[1], b.BoardID) || !strings.EqualFold(log.Topics[2], "0x"+paddedID(b.PlayerID)) || !strings.EqualFold(log.Topics[3], "0x"+paddedID(b.RunID)) {
		return false
	}
	score, e1 := wordInt(log.Data, 0)
	combo, e2 := wordInt(log.Data, 1)
	at, e3 := wordInt(log.Data, 2)
	return e1 == nil && e2 == nil && e3 == nil && score == int64(b.Score) && combo == int64(b.MaxCombo) && at == b.AchievedAt
}
func (p *publicationClient) confirmed(ctx context.Context, j publicationJob) (bool, error) {
	if !validHex(j.TxHash, 32) {
		return false, nil
	}
	var receipt *publicationReceipt
	if err := p.rpc(ctx, "eth_getTransactionReceipt", []any{j.TxHash}, &receipt); err != nil {
		return false, err
	}
	if receipt == nil || receipt.Status != "0x1" {
		return false, nil
	}
	if !strings.EqualFold(receipt.TxHash, j.TxHash) {
		return false, errors.New("receipt_mismatch")
	}
	found := false
	for _, log := range receipt.Logs {
		if p.matchesLog(log, j) {
			found = true
			break
		}
	}
	if !found {
		return false, errors.New("receipt_mismatch")
	}
	block, err := parseQuantity(receipt.BlockNumber)
	if err != nil {
		return false, errors.New("receipt_mismatch")
	}
	head, err := p.head(ctx)
	if err != nil {
		return false, err
	}
	if head < block+p.cfg.LeaderboardConfirmations-1 {
		return false, nil
	}
	var canonical struct {
		Hash string `json:"hash"`
	}
	if err = p.rpc(ctx, "eth_getBlockByNumber", []any{receipt.BlockNumber, false}, &canonical); err != nil {
		return false, err
	}
	return strings.EqualFold(canonical.Hash, receipt.BlockHash), nil
}
func (p *publicationClient) findPublished(ctx context.Context, j *publicationJob) (string, error) {
	from := j.FromBlock
	if from == 0 {
		from = p.cfg.LeaderboardStartBlock
	}
	logs, err := p.recoveryLogs(ctx, &j.Recovery, from, p.cfg.LeaderboardConfirmations, p.cfg.LeaderboardAddress, []string{scoreProcessedTopic, j.Payload.BoardID, "0x" + paddedID(j.Payload.PlayerID), "0x" + paddedID(j.Payload.RunID)})
	if err != nil {
		return "", err
	}
	for _, log := range logs {
		if p.matchesLog(log, *j) && validHex(log.TxHash, 32) {
			return log.TxHash, nil
		}
	}
	return "", scanPending()
}

func (p *publicationClient) preflight(ctx context.Context) error {
	var auth struct {
		App struct {
			ID string `json:"id"`
		} `json:"app"`
	}
	if err := p.json(ctx, "GET", p.cfg.EngineURL+"/v1/auth/me", nil, "read", &auth); err != nil {
		return err
	}
	if auth.App.ID != p.cfg.EngineProjectID {
		return errors.New("engine_project_mismatch")
	}
	var chain string
	if err := p.rpc(ctx, "eth_chainId", []any{}, &chain); err != nil {
		return err
	}
	n, err := parseQuantity(chain)
	if err != nil || n != p.cfg.LeaderboardChainID {
		return errors.New("chain_mismatch")
	}
	role := strings.TrimPrefix(hashHex([]byte("PUBLISHER_ROLE")), "0x")
	address := strings.Repeat("0", 24) + strings.TrimPrefix(p.cfg.LeaderboardPublisher, "0x")
	data, err := p.ethCall(ctx, selector("hasRole(bytes32,address)")+role+address)
	if err != nil {
		return err
	}
	enabled, err := wordInt(data, 0)
	if err != nil || enabled != 1 {
		return errors.New("publisher_role_missing")
	}
	return nil
}
