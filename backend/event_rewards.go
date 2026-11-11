package main

import (
	"context"
	"errors"
	"strings"
	"time"
)

// Item grants use the same leased, receipt-verified delivery protocol as STARL,
// with a separate outbox and a supply-backed ERC-1155 router. The on-chain reward
// ID prevents duplicate transfers even after a lost Engine response or restart.
type eventRewardStore struct{ *graphStore }

func (s eventRewardStore) claimStarlight(target string, now time.Time) (starlightJob, bool, error) {
	return s.claimReward("EventItemReward", target, now)
}
func (s eventRewardStore) saveStarlight(j starlightJob, next time.Time) error {
	return s.saveReward("EventItemReward", j, next)
}
func eventRewardTarget(c config) string {
	return hashHex([]byte(strings.Join([]string{c.EngineProjectID, c.EventRewardRouter, c.MarketplaceCollection, c.StarlightTreasury}, "/")))
}
func eventItemsWrite(params map[string]interface{}, target, owner string, sequence, amount int64) string {
	temporary := map[string]interface{}{}
	starlightParameters(temporary, target, owner, sequence, amount)
	for key, value := range temporary {
		params[strings.Replace(key, "star_", "item_", 1)] = value
	}
	return strings.ReplaceAll(strings.ReplaceAll(strings.ReplaceAll(starlightWriteQuery, "StarlightPayout", "EventItemReward"), "EARNED_STARLIGHT", "EARNED_EVENT_ITEM"), "$star_", "$item_")
}
func startEventRewards(store userStore, c config) (*starlightService, error) {
	if c.EventRewardRouter == "" {
		return nil, nil
	}
	db, ok := store.(*graphStore)
	if !ok {
		return nil, errors.New("Event reward storage unavailable")
	}
	if !c.StarlightEnabled || !validHex(c.EventRewardRouter, 20) {
		return nil, errors.New("Event rewards require STARL/managed wallets and an item router")
	}
	cfg := c
	cfg.StarlightDistributor = c.EventRewardRouter
	cfg.StarlightToken = c.MarketplaceCollection
	ctx, cancel := context.WithCancel(context.Background())
	client := newStarlightClient(cfg)
	client.item = true
	s := &starlightService{store: eventRewardStore{db}, client: client, target: eventRewardTarget(c), ctx: ctx, cancel: cancel}
	s.wg.Add(1)
	go s.run()
	return s, nil
}
