package main

import (
	"context"
	"time"
)

// Demand is coalesced, never retried by an idle timer in the default mode.
// Each authenticated player action/refresh permits one durable queue step.
type chainDemand struct{ requests chan struct{} }

func newChainDemand() chainDemand { return chainDemand{requests: make(chan struct{}, 1)} }
func (d *chainDemand) request() {
	if d == nil || d.requests == nil {
		return
	}
	select {
	case d.requests <- struct{}{}:
	default:
	}
}
func runChainWorker(ctx context.Context, d *chainDemand, background bool, process func()) {
	var ticks <-chan time.Time
	if background {
		ticker := time.NewTicker(2 * time.Second)
		defer ticker.Stop()
		ticks = ticker.C
		process()
	}
	for {
		select {
		case <-ctx.Done():
			return
		case <-d.requests:
			if ctx.Err() == nil {
				process()
			}
		case <-ticks:
			if ctx.Err() == nil {
				process()
			}
		}
	}
}
func (a *api) requestChainWork() {
	if a.starlight != nil {
		a.starlight.demand.request()
	}
	if a.eventRewards != nil {
		a.eventRewards.demand.request()
	}
	if a.publications != nil {
		a.publications.demand.request()
	}
	if a.shop != nil {
		a.shop.demand.request()
	}
}
