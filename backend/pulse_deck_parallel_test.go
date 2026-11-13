package main

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync/atomic"
	"testing"
	"time"
)

func TestPulseDeckParallelConfirmedReads(t *testing.T) {
	var entered atomic.Int32
	allCards := make(chan struct{})
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		var body struct {
			Params []json.RawMessage
		}
		if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
			t.Error(err)
			return
		}
		var call struct{ Data string }
		var block string
		_ = json.Unmarshal(body.Params[0], &call)
		_ = json.Unmarshal(body.Params[1], &block)
		if block != "0x64" {
			t.Errorf("card snapshot changed block: %s", block)
		}
		result := "0x"
		switch {
		case strings.HasPrefix(call.Data, selector("deck(address,uint256)")):
			for i := int64(14); i < 19; i++ {
				result += hexWord(i)
			}
		case strings.HasPrefix(call.Data, selector("viewCard(address,uint256)")):
			if entered.Add(1) == 5 {
				close(allCards)
			}
			select {
			case <-allCards:
			case <-r.Context().Done():
				return
			}
			token, _ := wordInt("0x"+call.Data[10:], 1)
			for _, value := range []int64{token - 14, 5, 800, 8, 1, 0, 1, 1, 0, 1, 0, 2, 800, 800} {
				result += hexWord(value)
			}
		case strings.HasPrefix(call.Data, selector("cardSet(uint256)")):
			result += hexWord(1)
		default:
			t.Error("unexpected card RPC")
		}
		_ = json.NewEncoder(w).Encode(map[string]any{"jsonrpc": "2.0", "id": 1, "result": result})
	}))
	defer server.Close()
	cfg := starlightTestConfig()
	cfg.StarlightRPC = server.URL
	cfg.PulseRouter = "0x" + strings.Repeat("a", 40)
	cfg.CardReleases = true
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()
	cards, ids, err := newShopClient(cfg).pulseDeck(ctx, 100, "0x"+strings.Repeat("4", 40), "pulse")
	if err != nil {
		t.Fatalf("all five card reads must start together: %v", err)
	}
	for i, card := range cards {
		if card == nil || card.Member != i || ids[i] != pulseID(int64(14+i)) {
			t.Fatalf("slot %d lost its validated card", i)
		}
	}
}
