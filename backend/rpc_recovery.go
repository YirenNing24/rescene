package main

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/url"
	"strings"
	"sync"
	"time"
)

// Persisted with each job; FromBlock remains the original submission boundary.
type recoveryState struct {
	NextBlock         int64 `json:"next_block,omitempty"`
	Failures          uint8 `json:"failures,omitempty"`
	EngineLookupAfter int64 `json:"engine_lookup_after,omitempty"`
}

// Engine transaction history is a shortcut, never a requirement for recovery.
// A pruned/missing Engine record must still be recoverable from chain evidence.
func recoveryEngineHash(r *recoveryState, lookup func() (enginePublicationTx, error)) (string, error) {
	now := time.Now()
	if now.UnixMilli() < r.EngineLookupAfter {
		return "", nil
	}
	r.EngineLookupAfter = now.Add(10 * time.Minute).UnixMilli()
	tx, err := lookup()
	if err != nil {
		if strings.Contains(err.Error(), "mismatch") {
			return "", err
		}
		return "", nil
	}
	if validHex(tx.Hash, 32) {
		return tx.Hash, nil
	}
	return "", nil
}

func encodeRecovery(r recoveryState) string { b, _ := json.Marshal(r); return string(b) }
func decodeRecovery(v any) recoveryState {
	var r recoveryState
	if s, ok := v.(string); ok {
		_ = json.Unmarshal([]byte(s), &r)
	}
	return r
}

type recoveryWait struct {
	Until time.Time
	Code  string
}

func (e *recoveryWait) Error() string { return e.Code }

type rpcHTTPError struct {
	Status int
	Body   []byte
}

func (e *rpcHTTPError) Error() string { return "rpc_http_unavailable" }

// All clients for an endpoint share one budget, including per-item shop clients.
// This is deliberately separate from the two-second local queue ticker.
type rpcRecoveryGate struct {
	mu                     sync.Mutex
	nextScan, blockedUntil time.Time
	logsBlockedUntil       time.Time
}

var rpcRecoveryGates sync.Map

func (p *publicationClient) recoveryGate() *rpcRecoveryGate {
	g, _ := rpcRecoveryGates.LoadOrStore(p.cfg.LeaderboardRPC, &rpcRecoveryGate{})
	return g.(*rpcRecoveryGate)
}
func (p *publicationClient) rpcCoolingDown() bool {
	g := p.recoveryGate()
	g.mu.Lock()
	defer g.mu.Unlock()
	return time.Now().Before(g.blockedUntil)
}
func (p *publicationClient) rpcProviderError(status int, body []byte) error {
	text := strings.ToLower(string(body))
	code, delay := "", time.Duration(0)
	switch {
	case strings.Contains(text, "free tier"), strings.Contains(text, "free-tier"), strings.Contains(text, "block range"), strings.Contains(text, "block-range"), strings.Contains(text, "too many blocks"), strings.Contains(text, "plan limit"):
		code, delay = "rpc_plan_limit", time.Hour
	case status == 401 || status == 403:
		code, delay = "rpc_authorization_failed", time.Hour
	case status == 429 || strings.Contains(text, "rate limit") || strings.Contains(text, "compute units"):
		code, delay = "rpc_rate_limited", time.Minute
	}
	if code == "" {
		return errors.New("rpc_unavailable")
	}
	g := p.recoveryGate()
	g.mu.Lock()
	defer g.mu.Unlock()
	until := time.Now().Add(delay)
	if code == "rpc_plan_limit" {
		if until.After(g.logsBlockedUntil) {
			g.logsBlockedUntil = until
		}
		return &recoveryWait{Until: g.logsBlockedUntil, Code: code}
	}
	if until.After(g.blockedUntil) {
		g.blockedUntil = until
	}
	return &recoveryWait{Until: g.blockedUntil, Code: code}
}
func (p *publicationClient) scanInterval() time.Duration {
	if p.cfg.RPCLogScanInterval > 0 {
		return p.cfg.RPCLogScanInterval
	}
	return 30 * time.Second
}
func (p *publicationClient) logBlockRange() int64 {
	if p.cfg.RPCLogBlockRange > 0 {
		return p.cfg.RPCLogBlockRange
	}
	u, _ := url.Parse(p.cfg.LeaderboardRPC)
	if u != nil && (strings.HasSuffix(strings.ToLower(u.Hostname()), ".alchemy.com") || strings.EqualFold(u.Hostname(), "alchemy.com")) {
		return 10
	}
	return 2048
}

// One bounded page per claim, at a confirmed height, with no catch-up loop.
// Reserve the shared budget BEFORE requesting the head; waiting costs no RPC.
func (p *publicationClient) recoveryLogs(ctx context.Context, r *recoveryState, origin, confirmations int64, address string, topics []string) ([]scoreLog, error) {
	if origin <= 0 {
		return nil, errors.New("recovery_scan_boundary_missing")
	}
	g := p.recoveryGate()
	now := time.Now()
	g.mu.Lock()
	until := g.nextScan
	if g.blockedUntil.After(until) {
		until = g.blockedUntil
	}
	if g.logsBlockedUntil.After(until) {
		until = g.logsBlockedUntil
	}
	if now.Before(until) {
		g.mu.Unlock()
		return nil, &recoveryWait{Until: maxTime(until, now.Add(time.Minute)), Code: "recovery_scan_pending"}
	}
	g.nextScan = now.Add(p.scanInterval())
	g.mu.Unlock()
	head, err := p.head(ctx)
	if err != nil {
		return nil, err
	}
	head -= max(confirmations, 1) - 1
	from := max(origin, r.NextBlock)
	if from > head {
		return nil, &recoveryWait{Until: now.Add(time.Minute), Code: "recovery_scan_pending"}
	}
	end := from + min(p.logBlockRange()-1, head-from)
	var logs []scoreLog
	err = p.rpc(ctx, "eth_getLogs", []any{map[string]any{"address": address, "fromBlock": fmt.Sprintf("0x%x", from), "toBlock": fmt.Sprintf("0x%x", end), "topics": topics}}, &logs)
	if err != nil {
		return nil, err
	}
	r.NextBlock = end + 1 // Only successful, confirmed pages advance the durable cursor.
	return logs, nil
}

func recoveryNext(r *recoveryState, err error, normal time.Time) time.Time {
	if err == nil {
		r.Failures = 0
		return normal
	}
	var wait *recoveryWait
	if errors.As(err, &wait) {
		return wait.Until
	}
	r.Failures = min(r.Failures, 5) + 1
	return time.Now().Add(min(30*time.Second*time.Duration(1<<uint(r.Failures-1)), 15*time.Minute))
}
func maxTime(a, b time.Time) time.Time {
	if a.After(b) {
		return a
	}
	return b
}
func recoveryPending(err error) bool {
	var wait *recoveryWait
	return errors.As(err, &wait) && wait.Code == "recovery_scan_pending"
}
func scanPending() error {
	return &recoveryWait{Until: time.Now().Add(time.Minute), Code: "recovery_scan_pending"}
}
