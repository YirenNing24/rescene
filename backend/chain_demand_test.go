package main

import (
	"context"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

func TestChainWorkerOnlyRunsOnDemand(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	demand := newChainDemand()
	calls := make(chan struct{}, 10)
	done := make(chan struct{})
	go func() { defer close(done); runChainWorker(ctx, &demand, false, func() { calls <- struct{}{} }) }()
	select {
	case <-calls:
		t.Fatal("worker polled at startup")
	case <-time.After(100 * time.Millisecond):
	}
	demand.request()
	select {
	case <-calls:
	case <-time.After(time.Second):
		t.Fatal("player demand did not run worker")
	}
	select {
	case <-calls:
		t.Fatal("worker retried without new demand")
	case <-time.After(150 * time.Millisecond):
	}
	demand.request()
	select {
	case <-calls:
	case <-time.After(time.Second):
		t.Fatal("second demand did not run worker")
	}
	cancel()
	select {
	case <-done:
	case <-time.After(time.Second):
		t.Fatal("idle worker did not shut down")
	}
}

func TestChainDemandCoalescesRequests(t *testing.T) {
	d := newChainDemand()
	for range 100 {
		d.request()
	}
	if len(d.requests) != 1 {
		t.Fatal("unbounded request queue")
	}
}

func TestEmptyAndFinalizedQueuesMakeNoOnChainCalls(t *testing.T) {
	s := testStore(t)
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		t.Error("idle/finalized worker made a network call")
		w.WriteHeader(500)
	}))
	defer server.Close()
	cfg := starlightTestConfig()
	cfg.LeaderboardRPC = server.URL
	cfg.StarlightRPC = server.URL
	cfg.EngineURL = server.URL
	pub := &publicationService{store: s, client: newPublicationClient(cfg), target: "demand-test", ctx: context.Background()}
	star := &starlightService{store: s, client: newStarlightClient(cfg), target: "demand-test", ctx: context.Background()}
	shop := &shopService{store: s, client: newShopClient(cfg), ctx: context.Background()}
	for range 3 {
		if err := pub.process(); err != nil {
			t.Fatal(err)
		}
		if err := star.process(); err != nil {
			t.Fatal(err)
		}
		if err := shop.process(); err != nil {
			t.Fatal(err)
		}
	}
	_, err := s.query(`CREATE(j:LeaderboardPublication {key:'audit',target:'demand-test',owner:'owner',board:'board',payload:'{}',sequence:0,created_at:0,status:'confirmed',next_attempt_at:0,lease_until:0,engine_id:'',tx_hash:'',generation:0,from_block:100,error_code:''}) RETURN j.key`, nil)
	if err != nil {
		t.Fatal(err)
	}
	_, err = s.query(`CREATE(j:StarlightPayout {key:$key,target:'demand-test',owner:'owner',amount:10,recipient:'',status:'confirmed',sequence:0,created_at:0,next_attempt_at:0,lease_until:0,engine_id:'',tx_hash:'',generation:0,from_block:100,error_code:''}) RETURN j.key`, map[string]interface{}{"key": strings.Repeat("a", 64)})
	if err != nil {
		t.Fatal(err)
	}
	if err = pub.process(); err != nil {
		t.Fatal(err)
	}
	if err = star.process(); err != nil {
		t.Fatal(err)
	}
	if pub.ready || star.ready || shop.ready {
		t.Fatal("preflight ran without actionable work")
	}
}
