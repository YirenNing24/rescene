package main

import (
	"bytes"
	"context"
	"crypto/rand"
	_ "embed"
	"encoding/hex"
	"encoding/json"
	"errors"
	"io"
	"math"
	"time"

	"github.com/gofiber/fiber/v3"
)

//go:embed charts.json
var chartJSON []byte

type rewardChart struct {
	SongID     string       `json:"song_id"`
	Title      string       `json:"title"`
	Revision   string       `json:"revision"`
	Difficulty string       `json:"difficulty"`
	Duration   float64      `json:"duration"`
	Units      int          `json:"units"`
	Notes      []replayNote `json:"notes"`
}

var rewardCharts = func() map[string]rewardChart {
	var list []rewardChart
	if err := json.Unmarshal(chartJSON, &list); err != nil {
		panic(err)
	}
	result := make(map[string]rewardChart)
	for _, item := range list {
		result[item.SongID+"/"+item.Difficulty] = item
	}
	return result
}()

type runTicket struct {
	Rival         *runRival      `json:"rival,omitempty"`
	Events        []eventTicket  `json:"events,omitempty"`
	Card          *cardLoadout   `json:"card,omitempty"`
	Deck          []*cardLoadout `json:"deck,omitempty"`
	DeckIDs       []string       `json:"deck_ids,omitempty"`
	SetID         string         `json:"set_id,omitempty"`
	RequestID     string         `json:"request_id,omitempty"`
	ID            string         `json:"id"`
	SongID        string         `json:"song_id"`
	Difficulty    string         `json:"difficulty"`
	StartedAt     int64          `json:"started_at"`
	Revision      string         `json:"revision,omitempty"`
	ReplayVersion int            `json:"replay_version,omitempty"`
}
type runResult struct {
	Score    int            `json:"score"`
	MaxCombo int            `json:"max_combo"`
	Counts   map[string]int `json:"counts"`
	Trace    string         `json:"trace,omitempty"`
	Replay   *inputReplay   `json:"replay,omitempty"`
}
type receipt struct {
	BaseScore      int          `json:"base_score,omitempty"`
	CardBonus      int          `json:"card_bonus,omitempty"`
	Card           *cardLoadout `json:"card,omitempty"`
	RunID          string       `json:"run_id"`
	XP             int          `json:"xp"`
	Starlight      int          `json:"starlight"`
	FirstClear     bool         `json:"first_clear"`
	LevelBefore    int          `json:"level_before"`
	LevelAfter     int          `json:"level_after"`
	Unlocks        []string     `json:"unlocks"`
	Ranked         bool         `json:"ranked"`
	Verification   int          `json:"verification,omitempty"`
	UnrankedReason string       `json:"unranked_reason,omitempty"`
}
type dailyProgress struct {
	Day     string          `json:"day"`
	Clears  int             `json:"clears"`
	Score   int64           `json:"score"`
	Claimed map[string]bool `json:"claimed"`
}
type progression struct {
	MasterySeeded     bool                           `json:"mastery_seeded,omitempty"`
	Coop              map[string]*weeklyContribution `json:"coop,omitempty"`
	Mastery           map[string]*songMastery        `json:"mastery,omitempty"`
	Events            map[string]*eventProgress      `json:"events,omitempty"`
	eventItems        int64
	eventItemTarget   string
	cardLease         *cardLeaseRequest
	cardRelease       string
	EquippedCard      string `json:"equipped_card,omitempty"`
	ShopActive        string `json:"shop_active,omitempty"`
	ShopLast          string `json:"shop_last,omitempty"`
	shopNew           *shopJob
	shopFinish        *shopJob
	shopTarget        string
	challengeStarted  int64
	rankedBest        *personalBest
	publicationTarget string
	starlightTarget   string
	starlightAward    int64
	StarlightAccrued  map[string]int64 `json:"starlight_accrued,omitempty"`
	XP                int64            `json:"xp"`
	Starlight         int64            `json:"starlight"`
	Clears            int              `json:"clears"`
	BestAccuracy      int              `json:"best_accuracy"`
	MaxCombo          int              `json:"max_combo"`
	FullCombos        int              `json:"full_combos"`
	Charts            map[string]bool  `json:"charts"`
	Claimed           map[string]bool  `json:"claimed"`
	Daily             dailyProgress    `json:"daily"`
	Login             loginProgress    `json:"login"`
	Energy            *energyProgress  `json:"energy,omitempty"`
	Title             string           `json:"title"`
	Frame             string           `json:"frame"`
	Active            *runTicket       `json:"active,omitempty"`
	Starts            []runTicket      `json:"starts,omitempty"`
	Receipts          []receipt        `json:"receipts"`
}
type mission struct {
	ID          string `json:"id"`
	Name        string `json:"name"`
	Description string `json:"description"`
	Scope       string `json:"scope"`
	Target      int64  `json:"target"`
	Progress    int64  `json:"progress"`
	XP          int    `json:"xp"`
	Starlight   int    `json:"starlight"`
	Claimed     bool   `json:"claimed"`
}
type cosmetic struct {
	ID          string `json:"id"`
	Name        string `json:"name"`
	Kind        string `json:"kind"`
	Requirement string `json:"requirement"`
	Level       int    `json:"level"`
	Color       string `json:"color"`
	Unlocked    bool   `json:"unlocked"`
	Equipped    bool   `json:"equipped"`
}

func (p *progression) normalize(now time.Time) {
	p.recoverEnergy(now)
	if p.Charts == nil {
		p.Charts = map[string]bool{}
	}
	if p.Claimed == nil {
		p.Claimed = map[string]bool{}
	}
	if p.Daily.Day != now.UTC().Format("2006-01-02") {
		p.Daily = dailyProgress{Day: now.UTC().Format("2006-01-02")}
	}
	if p.Daily.Claimed == nil {
		p.Daily.Claimed = map[string]bool{}
	}
	if p.Title == "" {
		p.Title = "first_scene"
	}
	if p.Frame == "" {
		p.Frame = "pearl"
	}
}
func levelFor(xp int64) (int, int64, int64) {
	level, floor := 1, int64(0)
	for level < 100 {
		cost := int64(200 + (level-1)*100)
		if xp < floor+cost {
			return level, xp - floor, cost
		}
		floor += cost
		level++
	}
	return 100, 0, 0
}
func missions(p progression) []mission {
	items := []mission{
		{ID: "daily_one", Name: "Today's opening act", Description: "Clear 1 song in Free Play.", Scope: "daily", Target: 1, Progress: int64(p.Daily.Clears), XP: 75, Starlight: 50},
		{ID: "daily_three", Name: "Encore, encore", Description: "Clear 3 songs in Free Play.", Scope: "daily", Target: 3, Progress: int64(p.Daily.Clears), XP: 150, Starlight: 100},
		{ID: "daily_score", Name: "A million little beats", Description: "Earn 1,000,000 total score today.", Scope: "daily", Target: 1000000, Progress: p.Daily.Score, XP: 100, Starlight: 75},
		{ID: "first_clear", Name: "Your first scene", Description: "Clear your first song.", Scope: "lifetime", Target: 1, Progress: int64(p.Clears), XP: 100, Starlight: 50},
		{ID: "five_clears", Name: "Finding your rhythm", Description: "Clear 5 songs.", Scope: "lifetime", Target: 5, Progress: int64(p.Clears), XP: 250, Starlight: 150},
		{ID: "accuracy", Name: "In every beat", Description: "Clear a song with at least 90% accuracy.", Scope: "lifetime", Target: 1, XP: 150, Starlight: 100},
		{ID: "combo", Name: "Hold the spotlight", Description: "Reach a combo of 100 in a cleared song.", Scope: "lifetime", Target: 100, Progress: int64(p.MaxCombo), XP: 200, Starlight: 150},
		{ID: "full_combo", Name: "Perfect harmony", Description: "Clear a song without a miss.", Scope: "lifetime", Target: 1, Progress: int64(p.FullCombos), XP: 150, Starlight: 100},
	}
	if p.BestAccuracy >= 9000 {
		items[5].Progress = 1
	}
	for i := range items {
		m := &items[i]
		m.Progress = min(m.Progress, m.Target)
		m.Claimed = p.Claimed[m.ID]
		if m.Scope == "daily" {
			m.Claimed = p.Daily.Claimed[m.ID]
		}
	}
	return items
}
func cosmetics(p progression) []cosmetic {
	level, _, _ := levelFor(p.XP)
	items := []cosmetic{
		{ID: "first_scene", Name: "First Scene", Kind: "title", Requirement: "Available from the start", Level: 1},
		{ID: "rising_star", Name: "Rising Star", Kind: "title", Requirement: "Reach level 2", Level: 2},
		{ID: "scene_maker", Name: "Scene Maker", Kind: "title", Requirement: "Reach level 5", Level: 5},
		{ID: "scene_stealer", Name: "Scene Stealer", Kind: "title", Requirement: "Reach level 10", Level: 10},
		{ID: "perfect_harmony", Name: "Perfect Harmony", Kind: "title", Requirement: "Clear a song with a full combo", Level: 101},
		{ID: "song_specialist", Name: "Song Specialist", Kind: "title", Requirement: "Complete all mastery goals for a song", Level: 101},
		{ID: "pearl", Name: "Pearl", Kind: "frame", Requirement: "Available from the start", Level: 1, Color: "c7bbff"},
		{ID: "rose_mist", Name: "Rose Mist", Kind: "frame", Requirement: "Reach level 3", Level: 3, Color: "e3b5ce"},
		{ID: "frost", Name: "Frost", Kind: "frame", Requirement: "Reach level 7", Level: 7, Color: "addce8"},
	}
	for i := range items {
		c := &items[i]
		c.Unlocked = level >= c.Level || (c.ID == "perfect_harmony" && p.FullCombos > 0) || (c.ID == "song_specialist" && masteredSongs(p) > 0)
		c.Equipped = c.ID == p.Title || c.ID == p.Frame
	}
	return items
}
func progressionView(p progression, now time.Time) fiber.Map {
	p.normalize(now)
	level, current, needed := levelFor(p.XP)
	return fiber.Map{"server_time": now.UTC().Format(time.RFC3339Nano), "energy": energyView(p, now), "xp": p.XP, "level": level, "level_xp": current, "level_cost": needed, "starlight": p.Starlight, "clears": p.Clears, "best_accuracy": p.BestAccuracy, "full_combos": p.FullCombos, "charts_cleared": len(p.Charts), "max_combo": p.MaxCombo, "day": p.Daily.Day, "daily_reset_at": now.UTC().Truncate(24 * time.Hour).Add(24 * time.Hour).Format(time.RFC3339), "daily_login": loginView(p.Login, now), "missions": missions(p), "unlocks": cosmetics(p), "title": p.Title, "frame": p.Frame, "equipped_card": p.EquippedCard, "mastery": p.Mastery, "mastered_songs": masteredSongs(p)}
}

type progressStore interface {
	ReadProgress(string) (progression, int64, error)
	WriteProgress(string, int64, progression) (bool, error)
}

func (s *graphStore) ReadProgress(id string) (progression, int64, error) {
	result, err := s.query(`MATCH (u:User {id:$id}) MERGE (p:Progression {owner:$id}) ON CREATE SET p.version=0, p.payload='{}' MERGE (u)-[:HAS_PROGRESSION]->(p) RETURN p.payload,p.version`, map[string]interface{}{"id": id})
	if err != nil {
		return progression{}, 0, err
	}
	if !result.Next() {
		return progression{}, 0, errNotFound
	}
	r := result.Record()
	payload, _ := r.GetByIndex(0)
	version, _ := r.GetByIndex(1)
	var p progression
	text, ok := payload.(string)
	if !ok {
		return p, 0, errors.New("invalid progression payload")
	}
	if err = json.Unmarshal([]byte(text), &p); err != nil {
		return p, 0, err
	}
	v, ok := version.(int64)
	if !ok {
		return p, 0, errors.New("invalid progression version")
	}
	return p, v, nil
}
func (s *graphStore) WriteProgress(id string, version int64, p progression) (bool, error) {
	payload, err := json.Marshal(p)
	if err != nil {
		return false, err
	}
	query := `MATCH (p:Progression {owner:$id}) WHERE p.version=$version SET p.payload=$payload,p.version=p.version+1 `
	params := map[string]interface{}{"id": id, "version": version, "payload": string(payload)}
	if p.cardLease != nil && len(p.cardLease.Keys) > 0 {
		lease := p.cardLease
		params["lease_keys"], params["lease_now"], params["lease_operation"], params["lease_run"], params["lease_until"] = lease.Keys, time.Now().UnixMilli(), lease.Operation, lease.RunID, lease.Until
		params["lease_allow_owner"] = ""
		if lease.ForRun {
			params["lease_allow_owner"] = id
		}
		query = `MATCH(p:Progression {owner:$id}) WHERE p.version=$version ` + cardLeaseGuard + `SET p.payload=$payload,p.version=p.version+1 `
	}
	if p.shopFinish != nil {
		j := p.shopFinish
		params["shop_key"], params["shop_payload"], params["shop_status"] = j.Key, encodeShopJob(*j), j.Status
		query = `MATCH(p:Progression {owner:$id}),(j:ShopOperation {key:$shop_key,owner:$id}) WHERE p.version=$version AND j.status='pending' SET p.payload=$payload,p.version=p.version+1,j.payload=$shop_payload,j.status=$shop_status,j.lease_until=0 `
	}
	if p.rankedBest != nil {
		query += bestWriteQuery
		p.rankedBest.parameters(params)
		if err := publicationParameters(params, p.publicationTarget, id, version+1, *p.rankedBest); err != nil {
			return false, err
		}
	}
	if p.rankedBest != nil && p.challengeStarted > 0 {
		params["challenge_start"] = p.challengeStarted
		query += challengeScoreWriteSafe
	}
	if p.starlightAward > 0 && p.starlightTarget != "" {
		query += starlightWriteQuery
		starlightParameters(params, p.starlightTarget, id, version+1, p.starlightAward)
	}
	if p.eventItems > 0 {
		query += eventItemsWrite(params, p.eventItemTarget, id, version+1, p.eventItems)
	}
	if p.shopNew != nil {
		params["shop_key"], params["shop_payload"], params["shop_target"], params["shop_now"] = p.shopNew.Key, encodeShopJob(*p.shopNew), p.shopTarget, time.Now().UnixMilli()
		query += shopCreateQuery
	}
	if p.cardRelease != "" {
		params["release_run"] = p.cardRelease
		query += cardLeaseReleaseRun
	}
	if p.cardLease != nil && len(p.cardLease.Keys) > 0 {
		if p.cardLease.ForRun {
			query += cardLeaseRunWrite
		} else {
			query += cardLeaseOperationWrite
		}
	}
	if p.shopFinish != nil {
		query += cardLeaseReleaseOperation
	}
	result, err := s.query(query+` RETURN p.version`, params)
	if err != nil {
		return false, err
	}
	return result.Next(), nil
}

type progressError struct {
	status  int
	message string
}

func (e progressError) Error() string  { return e.message }
func badProgress(message string) error { return progressError{409, message} }

func (a *api) mutateProgress(c fiber.Ctx, mutate func(*progression, time.Time) (any, error)) error {
	store, ok := a.store.(progressStore)
	if !ok {
		return failure(c, 503, "unavailable", "Progression is unavailable.")
	}
	id := c.Locals("user").(user).ID
	for attempt := 0; attempt < 20; attempt++ {
		p, version, err := store.ReadProgress(id)
		if err != nil {
			return err
		}
		now := time.Now().UTC()
		p.normalize(now)
		p.publicationTarget = publicationTarget(a.config)
		reward, err := mutate(&p, now)
		if err != nil {
			var pe progressError
			if errors.As(err, &pe) {
				return failure(c, pe.status, "progression_error", pe.message)
			}
			return err
		}
		if _, err = prepareStarlight(&p, a.config); err != nil {
			return err
		}
		written, err := store.WriteProgress(id, version, p)
		if err != nil {
			return err
		}
		if written {
			return c.JSON(fiber.Map{"progression": a.progressionView(p, now), "reward": reward})
		}
	}
	return failure(c, 503, "retry", "Progress is busy. Please try again.")
}
func decodeProgressBody(c fiber.Ctx, into any) error {
	decoder := json.NewDecoder(bytes.NewReader(c.Body()))
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(into); err != nil {
		return fiber.NewError(400, "Invalid progression request.")
	}
	if err := decoder.Decode(new(any)); err != io.EOF {
		return fiber.NewError(400, "Send one JSON object.")
	}
	return nil
}
func (a *api) getProgress(c fiber.Ctx) error {
	store, ok := a.store.(progressStore)
	if !ok {
		return failure(c, 503, "unavailable", "Progression is unavailable.")
	}
	id := c.Locals("user").(user).ID
	for attempt := 0; attempt < 20; attempt++ {
		p, version, err := store.ReadProgress(id)
		if err != nil {
			return err
		}
		existed := p.Energy != nil
		var before energyProgress
		if existed {
			before = *p.Energy
		}
		now := time.Now().UTC()
		p.normalize(now)
		seeded := false
		if !p.MasterySeeded {
			if scores, available := a.store.(scoreStore); available {
				bests, scoreErr := scores.ReadBests(id)
				if scoreErr != nil {
					return scoreErr
				}
				seedMastery(&p, bests)
				seeded = true
			}
		}
		accrued, err := prepareStarlight(&p, a.config)
		if err != nil {
			return err
		}
		if existed && before == *p.Energy && !accrued && !seeded {
			return c.JSON(fiber.Map{"progression": a.progressionView(p, now)})
		}
		written, err := store.WriteProgress(id, version, p)
		if err != nil {
			return err
		}
		if written {
			return c.JSON(fiber.Map{"progression": a.progressionView(p, now)})
		}
	}
	return failure(c, 503, "retry", "Energy is syncing. Please try again.")
}
func (a *api) startRun(c fiber.Ctx) error {
	var body struct {
		RequestID     string `json:"request_id"`
		SongID        string `json:"song_id"`
		Difficulty    string `json:"difficulty"`
		Revision      string `json:"revision"`
		ReplayVersion int    `json:"replay_version"`
	}
	if err := decodeProgressBody(c, &body); err != nil {
		return err
	}
	chart, ok := rewardCharts[body.SongID+"/"+body.Difficulty]
	if !ok {
		return failure(c, 400, "invalid_chart", "Choose an available song and difficulty.")
	}
	if body.Revision != "" && body.Revision != chart.Revision {
		return failure(c, 409, "chart_changed", "This chart has changed. Update the game before ranking this song.")
	}
	if !supportedReplayVersion(body.ReplayVersion) {
		return failure(c, 400, "replay_version", "Update the game to use a supported replay version.")
	}
	if body.Revision == "" {
		return failure(c, 400, "chart_required", "Input validation requires a chart revision.")
	}
	if body.RequestID != "" && !validHex(body.RequestID, 16) {
		return failure(c, 400, "invalid_request_id", "Use a valid run request ID.")
	}
	var rival *runRival
	if db, ok := a.store.(*graphStore); ok {
		// Rival availability must not prevent an otherwise valid run.
		rival, _ = db.rivalTarget(c.Locals("user").(user).ID, chart)
	}
	id := make([]byte, 16)
	if _, err := rand.Read(id); err != nil {
		return err
	}
	return a.mutateProgress(c, func(p *progression, now time.Time) (any, error) {
		if body.RequestID != "" {
			for _, existing := range p.Starts {
				if existing.RequestID != body.RequestID {
					continue
				}
				if existing.SongID != body.SongID || existing.Difficulty != body.Difficulty || existing.Revision != body.Revision || existing.ReplayVersion != body.ReplayVersion {
					return nil, badProgress("This run request ID belongs to a different song attempt.")
				}
				if p.Active == nil || p.Active.ID != existing.ID || now.UnixMilli()-existing.StartedAt > int64((2*time.Hour).Milliseconds()) {
					return nil, badProgress("This run request has expired. Start a new attempt.")
				}
				return existing, nil
			}
		}
		var loadout *cardLoadout
		var deck []*cardLoadout
		var deckIDs []string
		setID := songSets[body.SongID]
		if a.config.PulseRouter != "" && (setID == "pulse" || a.config.CardReleases && releaseNumber(setID) > 0) {
			if p.ShopActive != "" {
				return nil, badProgress("Your card/item action is still processing. Please wait before starting.")
			}
			wallet, err := a.shopWallet(c)
			if err != nil {
				return nil, progressError{503, "Your card ownership is updating."}
			}
			ctx, cancel := context.WithTimeout(c.Context(), 12*time.Second)
			deck, deckIDs, err = a.shop.client.pulseDeck(ctx, 0, wallet.Address, setID)
			cancel()
			if err != nil {
				return nil, progressError{503, "Your song-set deck is updating. Please retry."}
			}
			busy, err := a.pulseBusy(deckIDs, c.Locals("user").(user).ID, "")
			if err != nil {
				return nil, err
			}
			if len(busy) > 0 {
				return nil, badProgress("An equipped card is in use or being upgraded. Please wait.")
			}
			loadout = combinedPulseCards(deck)
		}
		if err := p.spendEnergy(now); err != nil {
			return nil, err
		}
		if p.Active != nil {
			p.cardRelease = p.Active.ID
		}
		p.Active = &runTicket{Rival: rival, Events: eventTickets(body.SongID, now), Card: loadout, Deck: deck, DeckIDs: deckIDs, SetID: setID, RequestID: body.RequestID, ID: hex.EncodeToString(id), SongID: body.SongID, Difficulty: body.Difficulty, StartedAt: now.UnixMilli(), Revision: body.Revision, ReplayVersion: body.ReplayVersion}
		if len(deckIDs) > 0 {
			p.cardLease = &cardLeaseRequest{Keys: pulseLeaseKeys(a.config, deckIDs), RunID: p.Active.ID, Until: now.Add(2 * time.Hour).UnixMilli(), ForRun: true}
		}
		if body.RequestID != "" {
			p.Starts = append(p.Starts, *p.Active)
			if len(p.Starts) > 32 {
				p.Starts = p.Starts[len(p.Starts)-32:]
			}
		}
		return p.Active, nil
	})
}
func validateResult(result runResult, chart rewardChart, replayScored bool) error {
	if len(result.Counts) != 4 {
		return badProgress("Invalid judgment totals.")
	}
	total := 0
	for _, kind := range []string{"PERFECT", "GREAT", "GOOD", "MISS"} {
		n, ok := result.Counts[kind]
		if !ok || n < 0 || n > chart.Units {
			return badProgress("Invalid judgments.")
		}
		total += n
	}
	if total != chart.Units || result.MaxCombo < 0 || result.MaxCombo > total-result.Counts["MISS"] {
		return badProgress("Result does not match this chart.")
	}
	if total > result.Counts["MISS"] && result.MaxCombo == 0 {
		return badProgress("Invalid combo.")
	}
	if result.Counts["MISS"] == 0 && result.MaxCombo != total {
		return badProgress("Invalid full combo.")
	}
	// At least one hit streak must contain ceil(hits / (misses + 1)) units.
	if hits := total - result.Counts["MISS"]; result.MaxCombo < (hits+result.Counts["MISS"])/(result.Counts["MISS"]+1) {
		return badProgress("Impossible combo for these judgments.")
	}
	// The judge gives 1.0 / 0.8 / 0.5 / 0.0 per scoring unit.
	computed := int(math.Round(1000000 * float64(result.Counts["PERFECT"]*10+result.Counts["GREAT"]*8+result.Counts["GOOD"]*5) / float64(total*10)))
	// Current runs are verified against ordered inputs below, since a momentum
	// score depends on where misses occur. Legacy in-flight runs retain old math.
	if (!replayScored && abs(result.Score-computed) > 1) || result.Score < 0 || result.Score > 1000000 {
		return badProgress("Score does not match the judgments.")
	}
	return nil
}
func abs(n int) int {
	if n < 0 {
		return -n
	}
	return n
}
func (a *api) completeRun(c fiber.Ctx) error {
	var result runResult
	if err := decodeProgressBody(c, &result); err != nil {
		return err
	}
	runID := c.Params("id")
	var checked *replayJudge
	return a.mutateProgress(c, func(p *progression, now time.Time) (any, error) {
		for _, existing := range p.Receipts {
			if existing.RunID == runID {
				return existing, nil
			}
		}
		if p.Active == nil || p.Active.ID != runID {
			return nil, badProgress("This run is no longer available for rewards.")
		}
		run := p.Active
		chart, ok := rewardCharts[run.SongID+"/"+run.Difficulty]
		if !ok {
			return nil, badProgress("Chart unavailable.")
		}
		elapsed := now.Sub(time.UnixMilli(run.StartedAt)).Seconds()
		if elapsed < chart.Duration-1 {
			return nil, badProgress("The song has not finished yet.")
		}
		if elapsed > 7200 {
			return nil, badProgress("This run has expired.")
		}
		if err := validateResult(result, chart, supportedReplayVersion(run.ReplayVersion)); err != nil {
			return nil, err
		}
		ranked := false
		if supportedReplayVersion(run.ReplayVersion) {
			if run.Revision != chart.Revision {
				return nil, badProgress("This chart changed during the run. Start a new attempt.")
			}
			if checked == nil {
				select {
				case a.replaySlots <- struct{}{}:
				default:
					return nil, progressError{503, "Replay verification is busy. Please retry."}
				}
				var err error
				checked, err = verifyInputReplay(result.Replay, *run, chart)
				<-a.replaySlots
				if err != nil {
					return nil, err
				}
			}
			if err := checked.matches(result, chart, run.Card); err != nil {
				return nil, err
			}
			result.Score = checked.score(chart.Units)
			result.Counts = checked.counts
			result.MaxCombo = checked.maxCombo
			ranked = !checked.paused
		}
		accuracyScore := canonicalScore(result.Counts, chart.Units)
		if accuracyScore < 500000 {
			return nil, badProgress("Reach 50% accuracy to earn clear rewards.")
		}
		before, _, _ := levelFor(p.XP)
		prior := cosmetics(*p)
		if checked != nil {
			advanceMastery(p, *run, result.Counts, accuracyScore)
		}
		difficulty := map[string]int{"Easy": 0, "Normal": 1, "Hard": 2, "Ultra Hard": 3}[run.Difficulty]
		key := run.SongID + "/" + run.Difficulty
		first := !p.Charts[key]
		rewardScore := result.Score
		if checked != nil {
			rewardScore = momentumScore(checked.trace.String(), chart.Units)
		}
		xp := 80 + difficulty*25 + rewardScore/50000
		stars := 30 + difficulty*10 + rewardScore/100000
		if first {
			xp += 40
			stars += 20
		}
		p.XP += int64(xp)
		p.Starlight += int64(stars)
		p.Clears++
		p.Charts[key] = true
		p.BestAccuracy = max(p.BestAccuracy, accuracyScore/100)
		p.MaxCombo = max(p.MaxCombo, result.MaxCombo)
		if result.Counts["MISS"] == 0 {
			p.FullCombos++
		}
		p.Daily.Clears++
		p.Daily.Score += int64(rewardScore)
		after, _, _ := levelFor(p.XP)
		unlocked := []string{}
		for i, item := range cosmetics(*p) {
			if item.Unlocked && !prior[i].Unlocked {
				unlocked = append(unlocked, item.Name)
			}
		}
		reward := receipt{BaseScore: rewardScore, CardBonus: result.Score - rewardScore, Card: run.Card, RunID: runID, XP: xp, Starlight: stars, FirstClear: first, LevelBefore: before, LevelAfter: after, Unlocks: unlocked, Ranked: ranked}
		if checked != nil {
			reward.Verification = run.ReplayVersion
			if checked.paused {
				reward.UnrankedReason = "paused"
			}
		}
		if ranked {
			advanceEvents(p, *run, result, now)
			advanceCoop(p, *run, result)
			p.challengeStarted = run.StartedAt
			p.rankedBest = &personalBest{ReplayVersion: run.ReplayVersion, SongID: run.SongID, Difficulty: run.Difficulty, Revision: chart.Revision, Score: result.Score, Accuracy: float64(accuracyScore) / 10000, MaxCombo: result.MaxCombo, AchievedAt: now.UnixMilli(), RunID: runID}
		}
		p.Receipts = append(p.Receipts, reward)
		if len(p.Receipts) > 32 {
			p.Receipts = p.Receipts[len(p.Receipts)-32:]
		}
		p.cardRelease = runID
		p.Active = nil
		return reward, nil
	})
}
func (a *api) claimMission(c fiber.Ctx) error {
	var body struct {
		Day string `json:"day"`
	}
	if err := decodeProgressBody(c, &body); err != nil {
		return err
	}
	return a.mutateProgress(c, func(p *progression, now time.Time) (any, error) {
		for _, m := range missions(*p) {
			if m.ID != c.Params("id") {
				continue
			}
			if m.Scope == "daily" && body.Day != p.Daily.Day {
				return nil, badProgress("This daily mission has reset. Refresh your missions.")
			}
			if m.Claimed {
				return nil, badProgress("This reward has already been claimed.")
			}
			if m.Progress < m.Target {
				return nil, badProgress("Complete the mission before claiming its reward.")
			}
			before, _, _ := levelFor(p.XP)
			prior := cosmetics(*p)
			p.XP += int64(m.XP)
			p.Starlight += int64(m.Starlight)
			if m.Scope == "daily" {
				p.Daily.Claimed[m.ID] = true
			} else {
				p.Claimed[m.ID] = true
			}
			after, _, _ := levelFor(p.XP)
			unlocks := []string{}
			for i, item := range cosmetics(*p) {
				if item.Unlocked && !prior[i].Unlocked {
					unlocks = append(unlocks, item.Name)
				}
			}
			return receipt{XP: m.XP, Starlight: m.Starlight, LevelBefore: before, LevelAfter: after, Unlocks: unlocks}, nil
		}
		return nil, progressError{404, "Mission not found."}
	})
}
func (a *api) equipCosmetic(c fiber.Ctx) error {
	var body struct {
		ID string `json:"id"`
	}
	if err := decodeProgressBody(c, &body); err != nil {
		return err
	}
	return a.mutateProgress(c, func(p *progression, now time.Time) (any, error) {
		for _, item := range cosmetics(*p) {
			if item.ID != body.ID {
				continue
			}
			if !item.Unlocked {
				return nil, badProgress("Unlock this reward before equipping it.")
			}
			if item.Kind == "title" {
				p.Title = item.ID
			} else {
				p.Frame = item.ID
			}
			return nil, nil
		}
		return nil, progressError{404, "Reward not found."}
	})
}

// Abandoning releases deck protections without refunding the attempt's energy.
// An old/out-of-order abandon can never cancel a newer run.
func (a *api) abandonRun(c fiber.Ctx) error {
	id := c.Params("id")
	if !validHex(id, 16) {
		return failure(c, 400, "invalid_run", "Choose a valid run.")
	}
	return a.mutateProgress(c, func(p *progression, _ time.Time) (any, error) {
		if p.Active != nil && p.Active.ID == id {
			p.cardRelease = id
			p.Active = nil
		}
		return fiber.Map{"run_id": id, "abandoned": true}, nil
	})
}
