package main

import (
	"context"
	"fmt"
	"reflect"
	"strings"
	"testing"
	"time"
)

func TestPulsePurchaseAndMaterialCheckout(t *testing.T) {
	s, a, f, app, token, owner := newPulseTest(t)
	body := map[string]any{"request_id": fmt.Sprintf("%032x", 1001), "item_id": "scene_03", "quantity": 1, "expected_total": "450"}
	status, _, _ := request(t, app, "POST", "/api/v1/shop/purchase", body, token)
	requireStatus(t, status, 200)
	key := shopKey(f.f.cfg, owner, body["request_id"].(string))
	before, _ := s.shopOperation(key, owner)
	roll := *before.Pulse
	if roll.Score < 700 || roll.Score > 1000 || roll.Recovery < 7 || roll.Recovery > 10 || roll.Skill < 1 || roll.Skill > 6 {
		t.Fatal("invalid purchase rolls")
	}
	f.f.lost = true
	j := finishPulse(t, s, a, f, key)
	if j.CardID != "pulse_14" || f.f.payments != 1 || f.f.balance != 99550 || f.f.cardOwned[14] != 1 || f.cards[14].XP != 0 || f.cards[14].Level != 1 {
		t.Fatal("incorrect unique delivery or charge")
	}
	status, _, _ = request(t, app, "POST", "/api/v1/shop/purchase", body, token)
	requireStatus(t, status, 200)
	after, _ := s.shopOperation(key, owner)
	if !reflect.DeepEqual(roll, *after.Pulse) {
		t.Fatal("retry rerolled traits")
	}
	body["item_id"] = "scene_02"
	status, _, _ = request(t, app, "POST", "/api/v1/shop/purchase", body, token)
	requireStatus(t, status, 409)
	materials := map[string]any{"request_id": fmt.Sprintf("%032x", 1002), "item_id": "prism_shards", "quantity": 2, "expected_total": "300"}
	status, _, _ = request(t, app, "POST", "/api/v1/shop/purchase", materials, token)
	requireStatus(t, status, 200)
	finishPulse(t, s, a, f, shopKey(f.f.cfg, owner, materials["request_id"].(string)))
	if f.f.cardOwned[11] != 2 || f.f.balance != 99250 || f.f.payments != 2 {
		t.Fatal("incorrect material checkout")
	}
	status, data, _ := request(t, app, "GET", "/api/v1/inventory", nil, token)
	requireStatus(t, status, 200)
	found := false
	for _, value := range data["items"].([]any) {
		item := value.(map[string]any)
		if item["id"] == "pulse_14" {
			found = true
			if item["set_id"] != "pulse" || item["member"] != "Minami" {
				t.Fatal("wrong set or member")
			}
		}
	}
	if !found {
		t.Fatal("individual card missing")
	}
}
func TestPulseStarNoInheritanceOverflowAndRetries(t *testing.T) {
	s, a, f, app, token, owner := newPulseTest(t)
	receiver := f.add(0, 42, 4)
	donorA := f.add(1, 100, 5)
	donorB := f.add(2, 80, 3)
	c := f.cards[receiver]
	c.Progress = 7
	c.XP = 200
	f.cards[receiver] = c
	d := f.cards[donorA]
	d.XP = 99999
	f.cards[donorA] = d
	d = f.cards[donorB]
	d.Progress = 4
	f.cards[donorB] = d
	body := map[string]any{"kind": "star", "card_id": pulseID(receiver), "donors": []string{pulseID(donorA), pulseID(donorB)}}
	quote := quotePulse(t, app, token, body)
	if quote["stars_after"] != float64(5) || quote["donors_wasted"] != float64(1) || len(quote["warnings"].([]any)) < 4 {
		t.Fatal("advanced donor or overflow warning missing")
	}
	body["request_id"] = fmt.Sprintf("%032x", 2001)
	body["quote_hash"] = quote["hash"]
	body["acknowledge_warning"] = false
	status, _, _ := request(t, app, "POST", "/api/v1/collection/action", body, token)
	requireStatus(t, status, 409)
	body["acknowledge_warning"] = true
	status, _, _ = request(t, app, "POST", "/api/v1/collection/action", body, token)
	requireStatus(t, status, 200)
	f.f.lost = true
	j := finishPulse(t, s, a, f, shopKey(f.f.cfg, owner, body["request_id"].(string)))
	got := f.cards[receiver]
	if got.Stars != 5 || got.Progress != 0 || got.Level != 42 || got.XP != 200 || got.Skill != c.Skill || got.BaseScoreBP != c.BaseScoreBP || f.f.burns != 2 || !f.cards[donorA].Burned || !f.cards[donorB].Burned {
		t.Fatal("donor investment inherited or burns repeated")
	}
	status, _, _ = request(t, app, "POST", "/api/v1/collection/action", body, token)
	requireStatus(t, status, 200)
	if err := s.finishShop(*j); err != nil {
		t.Fatal(err)
	}
	if f.f.burns != 2 {
		t.Fatal("retry burned again")
	}
	fresh := f.add(3, 1, 1)
	body = map[string]any{"kind": "star", "card_id": pulseID(receiver), "donors": []string{pulseID(fresh)}}
	quote = quotePulse(t, app, token, body)
	if quote["donors_wasted"] != float64(1) {
		t.Fatal("max-star excess must be warned, not rejected")
	}
	submitPulse(t, app, token, body, quote, 2002)
	finishPulse(t, s, a, f, shopKey(f.f.cfg, owner, body["request_id"].(string)))
	if !f.cards[fresh].Burned {
		t.Fatal("acknowledged excess not sacrificed")
	}
}
func TestPulseProtectionsAndStalePreview(t *testing.T) {
	_, _, f, app, token, _ := newPulseTest(t)
	receiver := f.add(0, 1, 1)
	donor := f.add(1, 1, 1)
	body := map[string]any{"kind": "star", "card_id": pulseID(receiver), "donors": []string{pulseID(donor)}}
	quote := quotePulse(t, app, token, body)
	for _, flags := range []int{1, 2, 4, 8} {
		d := f.cards[donor]
		d.Flags = flags
		f.cards[donor] = d
		status, _, _ := request(t, app, "POST", "/api/v1/collection/quote", body, token)
		requireStatus(t, status, 409)
	}
	d := f.cards[donor]
	d.Flags = 0
	d.Level = 50
	d.Revision++
	f.cards[donor] = d
	body["request_id"] = fmt.Sprintf("%032x", 3001)
	body["quote_hash"] = quote["hash"]
	body["acknowledge_warning"] = true
	status, _, _ := request(t, app, "POST", "/api/v1/collection/action", body, token)
	requireStatus(t, status, 409)
	if f.f.burns != 0 {
		t.Fatal("stale quote burned")
	}
	body["donors"] = []string{pulseID(receiver)}
	status, _, _ = request(t, app, "POST", "/api/v1/collection/quote", body, token)
	requireStatus(t, status, 409)
	body["donors"] = []string{pulseID(donor), pulseID(donor)}
	status, _, _ = request(t, app, "POST", "/api/v1/collection/quote", body, token)
	requireStatus(t, status, 409)
}
func TestPulseRefineFailureIsDurable(t *testing.T) {
	s, a, f, app, token, owner := newPulseTest(t)
	id := f.add(0, 99, 1)
	c := f.cards[id]
	c.XP = 1000
	f.cards[id] = c
	f.f.cardOwned[11] = 2
	body := map[string]any{"kind": "refine", "card_id": pulseID(id), "item_id": "prism_shards"}
	quote := quotePulse(t, app, token, body)
	if quote["success_chance_bp"] != float64(2000) {
		t.Fatal("wrong level-100 chance")
	}
	submitPulse(t, app, token, body, quote, 4001)
	job, ok, err := s.claimShop(shopTarget(f.f.cfg))
	if err != nil || !ok {
		t.Fatal(err)
	}
	job.Pulse.Roll = 9999
	if err = s.saveShop(job, time.Now().Add(-time.Second)); err != nil {
		t.Fatal(err)
	}
	f.f.lost = true
	j := finishPulse(t, s, a, f, shopKey(f.f.cfg, owner, body["request_id"].(string)))
	if j.LevelUpgraded == nil || *j.LevelUpgraded || !j.UpgradeAttempted || f.cards[id].Level != 99 || f.cards[id].XP != 1100 || f.f.cardOwned[11] != 1 || f.f.burns != 1 {
		t.Fatal("incorrect failure outcome")
	}
	status, _, _ := request(t, app, "POST", "/api/v1/collection/action", body, token)
	requireStatus(t, status, 200)
	if f.f.burns != 1 {
		t.Fatal("retry burned twice")
	}
}
func TestPulseDeckMembershipAndRunSnapshot(t *testing.T) {
	s, _, f, app, token, owner := newPulseTest(t)
	for member := 0; member < 5; member++ {
		f.deck[member] = f.add(member, 1, 1)
	}
	body := map[string]any{"kind": "equip", "set_id": "pulse", "member_index": 0, "card_id": "pulse_15"}
	status, _, _ := request(t, app, "POST", "/api/v1/collection/quote", body, token)
	requireStatus(t, status, 409)
	body["member_index"] = 1
	body["set_id"] = "glow_up"
	status, _, _ = request(t, app, "POST", "/api/v1/collection/quote", body, token)
	requireStatus(t, status, 409)
	var chart rewardChart
	for _, item := range rewardCharts {
		if songSets[item.SongID] == "pulse" && item.Difficulty == "Normal" {
			chart = item
			break
		}
	}
	if chart.SongID == "" {
		t.Fatal("missing Pulse charts")
	}
	start := map[string]any{"request_id": fmt.Sprintf("%032x", 5001), "song_id": chart.SongID, "difficulty": chart.Difficulty, "revision": chart.Revision, "replay_version": replayVersion}
	status, data, _ := request(t, app, "POST", "/api/v1/runs", start, token)
	requireStatus(t, status, 200)
	runID := data["reward"].(map[string]any)["id"].(string)
	p, _, _ := s.ReadProgress(owner)
	if len(p.Active.Deck) != 5 || p.Active.Card == nil || p.Active.Card.PerfectScoreBP != 4000 || p.Energy.Current != energyCap-1 {
		t.Fatal("five card bonuses missing from ticket")
	}
	locked := *p.Active.Card
	c := f.cards[14]
	c.Level = 100
	f.cards[14] = c
	status, _, _ = request(t, app, "POST", "/api/v1/runs", start, token)
	requireStatus(t, status, 200)
	p, _, _ = s.ReadProgress(owner)
	if *p.Active.Card != locked || p.Energy.Current != energyCap-1 {
		t.Fatal("retry changed snapshot or spent twice")
	}
	beforeXP := f.cards[14].XP
	ageRun(t, s, owner, chart)
	replay := fixtureReplay(chart, 7)
	replay.RunID = runID
	checked, err := verifyInputReplay(replay, *p.Active, chart)
	if err != nil {
		t.Fatal(err)
	}
	result := runResult{Score: checked.score(chart.Units), MaxCombo: checked.maxCombo, Counts: checked.counts, Replay: replay}
	status, _, _ = request(t, app, "POST", "/api/v1/runs/"+runID+"/complete", result, token)
	requireStatus(t, status, 200)
	if f.cards[14].XP != beforeXP {
		t.Fatal("gameplay granted card XP")
	}
	var other rewardChart
	for _, item := range rewardCharts {
		if songSets[item.SongID] != "" && songSets[item.SongID] != "pulse" {
			other = item
			break
		}
	}
	start = map[string]any{"request_id": fmt.Sprintf("%032x", 5002), "song_id": other.SongID, "difficulty": other.Difficulty, "revision": other.Revision, "replay_version": replayVersion}
	status, _, _ = request(t, app, "POST", "/api/v1/runs", start, token)
	requireStatus(t, status, 200)
	p, _, _ = s.ReadProgress(owner)
	if p.Active.Card != nil || len(p.Active.Deck) != 0 {
		t.Fatal("Pulse bonuses leaked into another set")
	}
	status, _, _ = request(t, app, "POST", "/api/v1/runs/"+runID+"/abandon", map[string]any{}, token)
	requireStatus(t, status, 200)
	current, _, _ := s.ReadProgress(owner)
	if current.Active == nil || current.Active.ID != p.Active.ID {
		t.Fatal("old abandon cancelled newer run")
	}
}
func TestPulseReceiptRequiresPaymentAndDelivery(t *testing.T) {
	s, a, f, app, token, owner := newPulseTest(t)
	body := map[string]any{"request_id": fmt.Sprintf("%032x", 6001), "item_id": "scene_01", "quantity": 1, "expected_total": "450"}
	status, _, _ := request(t, app, "POST", "/api/v1/shop/purchase", body, token)
	requireStatus(t, status, 200)
	j := finishPulse(t, s, a, f, shopKey(f.f.cfg, owner, body["request_id"].(string)))
	f.bad = true
	if ok, err := a.shop.client.pulseConfirmed(context.Background(), j); err == nil || ok {
		t.Fatal("accepted event without payment/delivery")
	}
	f.bad = false
	j.TxHash = ""
	if ok, err := a.shop.client.pulseConfirmed(context.Background(), j); err != nil || !ok {
		t.Fatal("canonical receipt recovery failed", err)
	}
	bad := *j
	bad.Wallet = "0x" + strings.Repeat("e", 40)
	if ok, err := a.shop.client.pulseProcessed(context.Background(), bad); err == nil || ok {
		t.Fatal("accepted another buyer's digest")
	}
}

func TestCardLeasesSurviveTransfersAndReleaseOnAbandon(t *testing.T) {
	s, _, f, app, token, owner := newPulseTest(t)
	for member := 0; member < 5; member++ {
		f.deck[member] = f.add(member, 1, 1)
	}
	var chart rewardChart
	for _, item := range rewardCharts {
		if songSets[item.SongID] == "pulse" {
			chart = item
			break
		}
	}
	body := map[string]any{"request_id": fmt.Sprintf("%032x", 7001), "song_id": chart.SongID, "difficulty": chart.Difficulty, "revision": chart.Revision, "replay_version": replayVersion}
	status, data, _ := request(t, app, "POST", "/api/v1/runs", body, token)
	requireStatus(t, status, 200)
	runID := data["reward"].(map[string]any)["id"].(string)
	keys := pulseLeaseKeys(f.f.cfg, []string{"pulse_14"})
	busy, err := s.busyCards(keys, "another-owner", "")
	if err != nil || len(busy) != 1 {
		t.Fatal("card run lease did not survive an owner change", err)
	}
	_, other := progressAccount(t, testApp(t, s), "secondcollector")
	p, v, err := s.ReadProgress(other)
	if err != nil {
		t.Fatal(err)
	}
	p.Active = &runTicket{ID: strings.Repeat("e", 32)}
	p.cardLease = &cardLeaseRequest{Keys: keys, RunID: p.Active.ID, Until: time.Now().Add(time.Hour).UnixMilli(), ForRun: true}
	written, err := s.WriteProgress(other, v, p)
	if err != nil || written {
		t.Fatal("atomic lease guard allowed another account to reuse the card", err)
	}
	status, _, _ = request(t, app, "POST", "/api/v1/runs/"+runID+"/abandon", map[string]any{}, token)
	requireStatus(t, status, 200)
	written, err = s.WriteProgress(other, v, p)
	if err != nil || !written {
		t.Fatal("abandon did not release lease", err)
	}
	original, _, _ := s.ReadProgress(owner)
	if original.Energy.Current != energyCap-1 {
		t.Fatal("abandon refunded energy")
	}
}
func TestPendingCardReservationDoesNotExpireOrAllowOtherRuns(t *testing.T) {
	s, a, f, app, token, owner := newPulseTest(t)
	id := f.add(0, 10, 1)
	f.f.cardOwned[11] = 1
	body := map[string]any{"kind": "refine", "card_id": pulseID(id), "item_id": "prism_shards"}
	quote := quotePulse(t, app, token, body)
	submitPulse(t, app, token, body, quote, 7101)
	keys := pulseLeaseKeys(f.f.cfg, []string{pulseID(id)})
	busy, err := s.busyCards(keys, "another-owner", "")
	if err != nil || len(busy) != 1 {
		t.Fatal("pending operation was not reserved", err)
	}
	// A stale worker lease is not permission to reuse an ambiguously submitted NFT.
	_, err = s.query(`MATCH(l:CardLease {key:$key}) SET l.run_until=0 RETURN l.key`, map[string]interface{}{"key": keys[0]})
	if err != nil {
		t.Fatal(err)
	}
	busy, err = s.busyCards(keys, "another-owner", "")
	if err != nil || len(busy) != 1 {
		t.Fatal("pending reservation expired", err)
	}
	finishPulse(t, s, a, f, shopKey(f.f.cfg, owner, body["request_id"].(string)))
	busy, err = s.busyCards(keys, "another-owner", "")
	if err != nil || len(busy) != 0 {
		t.Fatal("confirmed operation did not release reservation", err)
	}
}
