package main

import (
	"errors"
	"math"
	"time"

	"github.com/gofiber/fiber/v3"
)

// One best per account/song/difficulty. Changing a chart revision starts a new
// ranking; old versions are excluded until the player completes the new chart.
type personalBest struct {
	Verification int     `json:"verification"`
	SongID       string  `json:"song_id"`
	Difficulty   string  `json:"difficulty"`
	Revision     string  `json:"revision"`
	Score        int     `json:"score"`
	MaxCombo     int     `json:"max_combo"`
	AchievedAt   int64   `json:"achieved_at"`
	Title        string  `json:"title"`
	Accuracy     float64 `json:"accuracy"`
	Grade        string  `json:"rank"`
	RunID        string  `json:"-"`
}

// This is appended to the progression CAS in the SAME graph write. A failed
// response or a concurrent retry can never separate XP from the ranked best.
const bestWriteQuery = `WITH p MATCH (u:User {id:$id})
MERGE (b:PersonalBest {key:$best_key}) ON CREATE SET b.score=-1,b.max_combo=-1,b.revision=''
MERGE (u)-[:HAS_PERSONAL_BEST]->(b)
WITH p,u,b,(coalesce(b.verification,0)<>2 OR b.revision<>$revision OR $score>b.score OR ($score=b.score AND $combo>b.max_combo) OR (coalesce(b.replay_version,0)<>3 AND $score=b.score AND $combo=b.max_combo)) AS improved
FOREACH (write IN CASE WHEN improved THEN [1] ELSE [] END |
SET b.verification=2,b.replay_version=3,b.owner=$id,b.song_id=$song,b.difficulty=$difficulty,b.chart_key=$chart_key,b.revision=$revision,b.score=$score,b.accuracy=$accuracy,b.max_combo=$combo,b.achieved_at=$achieved,b.run_id=$run)
FOREACH (publish IN CASE WHEN improved AND $publish_target<>'' THEN [1] ELSE [] END |
MERGE (j:LeaderboardPublication {key:$publish_job})
ON CREATE SET j.target=$publish_target,j.owner=$id,j.board=$publish_board,j.payload=$publish_payload,
j.sequence=$publish_sequence,j.created_at=$achieved,j.status='pending',j.next_attempt_at=0,j.lease_until=0,
j.engine_id='',j.tx_hash='',j.generation=0,j.error_code='',j.from_block=0)
`

func (b personalBest) parameters(p map[string]interface{}) {
	p["best_key"] = p["id"].(string) + "/" + b.SongID + "/" + b.Difficulty
	p["song"], p["difficulty"], p["revision"] = b.SongID, b.Difficulty, b.Revision
	p["chart_key"] = b.SongID + "/" + b.Difficulty + "/" + b.Revision
	p["score"], p["combo"], p["achieved"], p["run"] = b.Score, b.MaxCombo, b.AchievedAt, b.RunID
	accuracy := int(math.Round(b.Accuracy * 10000))
	if accuracy == 0 {
		accuracy = b.Score
	} // Existing import/test records.
	p["accuracy"] = accuracy
}

func canonicalScore(counts map[string]int, units int) int {
	return int(math.Round(1000000 * float64(counts["PERFECT"]*10+counts["GREAT"]*8+counts["GOOD"]*5) / float64(units*10)))
}

type boardEntry struct {
	personalBest
	UserID   string `json:"user_id"`
	Username string `json:"username"`
	Position int    `json:"position"`
}
type boardResult struct {
	OnChain map[string]any `json:"on_chain,omitempty"`
	Top     []boardEntry   `json:"top"`
	Nearby  []boardEntry   `json:"nearby"`
	Me      *boardEntry    `json:"me"`
	Total   int            `json:"total"`
}
type scoreStore interface {
	ReadBests(string) ([]personalBest, error)
	ReadBoard(rewardChart, string) (boardResult, error)
}

func (b *personalBest) decorate() {
	b.Title = rewardCharts[b.SongID+"/"+b.Difficulty].Title
	b.Grade = "C"
	switch {
	case b.Accuracy >= 98:
		b.Grade = "S+"
	case b.Accuracy >= 93:
		b.Grade = "S"
	case b.Accuracy >= 85:
		b.Grade = "A"
	case b.Accuracy >= 70:
		b.Grade = "B"
	}
}

const bestFields = ` RETURN u.id,u.username,b.song_id,b.difficulty,b.revision,b.score,b.max_combo,b.achieved_at,coalesce(b.accuracy,b.score) `
const boardOrder = ` ORDER BY b.score DESC,b.max_combo DESC,b.achieved_at ASC,u.id ASC `

func (s *graphStore) scoreRows(query string, params map[string]interface{}, offset int) ([]boardEntry, error) {
	r, err := s.query(query, params)
	if err != nil {
		return nil, err
	}
	rows := []boardEntry{}
	for r.Next() {
		values := make([]interface{}, 9)
		for i := range values {
			values[i], _ = r.Record().GetByIndex(i)
		}
		id, okID := values[0].(string)
		username, okName := values[1].(string)
		song, okSong := values[2].(string)
		difficulty, okDifficulty := values[3].(string)
		revision, okRevision := values[4].(string)
		score, okScore := values[5].(int64)
		combo, okCombo := values[6].(int64)
		achieved, okAchieved := values[7].(int64)
		accuracy, okAccuracy := values[8].(int64)
		if !okID || !okName || !okSong || !okDifficulty || !okRevision || !okScore || !okCombo || !okAchieved || !okAccuracy {
			return nil, errors.New("invalid score data")
		}
		b := personalBest{Verification: 2, SongID: song, Difficulty: difficulty, Revision: revision, Score: int(score), Accuracy: float64(accuracy) / 10000, MaxCombo: int(combo), AchievedAt: achieved}
		b.decorate()
		rows = append(rows, boardEntry{personalBest: b, UserID: id, Username: username, Position: offset + len(rows) + 1})
	}
	return rows, nil
}

func (s *graphStore) ReadBests(id string) ([]personalBest, error) {
	rows, err := s.scoreRows(`MATCH (u:User {id:$id})-[:HAS_PERSONAL_BEST]->(b:PersonalBest {verification:2}) WHERE coalesce(b.quarantined,false)=false `+bestFields+boardOrder+` LIMIT 128`, map[string]interface{}{"id": id}, 0)
	if err != nil {
		return nil, err
	}
	result := []personalBest{}
	for _, row := range rows {
		chart, ok := rewardCharts[row.SongID+"/"+row.Difficulty]
		if ok && row.Revision == chart.Revision {
			result = append(result, row.personalBest)
		}
	}
	return result, nil
}

func (s *graphStore) countScores(query string, params map[string]interface{}) (int, error) {
	r, err := s.query(query+` RETURN count(b)`, params)
	if err != nil {
		return 0, err
	}
	if !r.Next() {
		return 0, nil
	}
	v, _ := r.Record().GetByIndex(0)
	n, ok := v.(int64)
	if !ok {
		return 0, errors.New("invalid ranking count")
	}
	return int(n), nil
}

func (s *graphStore) ReadBoard(chart rewardChart, id string) (boardResult, error) {
	result := boardResult{Top: []boardEntry{}, Nearby: []boardEntry{}}
	params := map[string]interface{}{"chart_key": chart.SongID + "/" + chart.Difficulty + "/" + chart.Revision, "id": id, "offset": 0}
	match := `MATCH (u:User)-[:HAS_PERSONAL_BEST]->(b:PersonalBest {chart_key:$chart_key,verification:2}) `
	var err error
	result.Top, err = s.scoreRows(match+` WHERE coalesce(b.quarantined,false)=false `+bestFields+boardOrder+` LIMIT 25`, params, 0)
	if err != nil {
		return result, err
	}
	result.Total, err = s.countScores(match+` WHERE coalesce(b.quarantined,false)=false `, params)
	if err != nil {
		return result, err
	}
	me, err := s.scoreRows(match+` WHERE coalesce(b.quarantined,false)=false AND u.id=$id `+bestFields, params, 0)
	if err != nil || len(me) == 0 {
		return result, err
	}
	self := me[0]
	params["score"], params["combo"], params["achieved"] = self.Score, self.MaxCombo, self.AchievedAt
	ahead := `WHERE coalesce(b.quarantined,false)=false AND (b.score>$score OR (b.score=$score AND b.max_combo>$combo) OR (b.score=$score AND b.max_combo=$combo AND b.achieved_at<$achieved) OR (b.score=$score AND b.max_combo=$combo AND b.achieved_at=$achieved AND u.id<$id))`
	n, err := s.countScores(match+ahead, params)
	if err != nil {
		return result, err
	}
	self.Position = n + 1
	result.Me = &self
	offset := max(0, self.Position-3)
	params["offset"] = offset
	result.Nearby, err = s.scoreRows(match+` WHERE coalesce(b.quarantined,false)=false `+bestFields+boardOrder+` SKIP $offset LIMIT 5`, params, offset)
	return result, err
}

func (a *api) getRecords(c fiber.Ctx) error {
	s, ok := a.store.(scoreStore)
	if !ok {
		return failure(c, 503, "unavailable", "Records are unavailable.")
	}
	rows, err := s.ReadBests(c.Locals("user").(user).ID)
	if err != nil {
		return err
	}
	return c.JSON(fiber.Map{"records": rows})
}
func (a *api) getLeaderboard(c fiber.Ctx) error {
	chart, ok := rewardCharts[c.Query("song_id")+"/"+c.Query("difficulty")]
	if !ok {
		return failure(c, 400, "invalid_chart", "Choose an available song and difficulty.")
	}
	s, ok := a.store.(scoreStore)
	if !ok {
		return failure(c, 503, "unavailable", "Rankings are unavailable.")
	}
	board, err := s.ReadBoard(chart, c.Locals("user").(user).ID)
	if err != nil {
		return err
	}
	if a.config.LeaderboardEnabled {
		if ps, ok := a.store.(publicationStore); ok {
			key, keyErr := chartBoardKey(chart.SongID, chart.Difficulty, chart.Revision)
			if keyErr == nil {
				job, readErr := ps.publicationFor(publicationTarget(a.config), c.Locals("user").(user).ID, key)
				if readErr == nil {
					board.OnChain = publicationView(a.config, job)
				}
			}
		}
	}
	return c.JSON(fiber.Map{"leaderboard": board, "song_id": chart.SongID, "difficulty": chart.Difficulty, "revision": chart.Revision})
}
func (a *api) getPlayer(c fiber.Ctx) error {
	u, err := a.store.ByID(c.Params("id"))
	if errors.Is(err, errNotFound) {
		return failure(c, 404, "not_found", "Player not found.")
	}
	if err != nil {
		return err
	}
	ps, ok := a.store.(progressStore)
	if !ok {
		return failure(c, 503, "unavailable", "Profiles are unavailable.")
	}
	p, _, err := ps.ReadProgress(u.ID)
	if err != nil {
		return err
	}
	p.normalize(time.Now())
	level, current, cost := levelFor(p.XP)
	title, frame := "First Scene", "c7bbff"
	for _, item := range cosmetics(p) {
		if item.Equipped {
			if item.Kind == "title" {
				title = item.Name
			} else if item.Kind == "frame" {
				frame = item.Color
			}
		}
	}
	ss, ok := a.store.(scoreStore)
	if !ok {
		return failure(c, 503, "unavailable", "Records are unavailable.")
	}
	records, err := ss.ReadBests(u.ID)
	if err != nil {
		return err
	}
	// Public whitelist: no password hash, wallet, balances, mission state or tokens.
	media := mediaView(u.ID, profileMedia{Gallery: []string{}})
	social := fiber.Map{}
	if store, ok := a.store.(socialStore); ok {
		counts, readErr := store.SocialCounts(u.ID)
		if readErr != nil {
			return readErr
		}
		social["counts"] = counts
		if viewer := c.Locals("user").(user).ID; viewer != u.ID {
			peers, readErr := store.SocialPlayers(viewer, "peer", "", "", u.ID, false, 1)
			if readErr != nil {
				return readErr
			}
			if len(peers) > 0 {
				social["relationship"] = peers[0]
			}
		}
	}
	if store, ok := a.store.(profileMediaStore); ok {
		photos, readErr := store.ReadProfileMedia(u.ID)
		if readErr != nil {
			return readErr
		}
		media = mediaView(u.ID, photos)
	}
	return c.JSON(fiber.Map{"profile": fiber.Map{"id": u.ID, "username": u.Username, "created_at": u.CreatedAt, "media": media, "social": social, "records": records, "progression": fiber.Map{"xp": p.XP, "level": level, "level_xp": current, "level_cost": cost, "clears": p.Clears, "best_accuracy": p.BestAccuracy, "max_combo": p.MaxCombo, "full_combos": p.FullCombos, "title_name": title, "frame_color": frame, "equipped_card": a.verifiedMemberCard(c.Context(), u.ID, p.EquippedCard)}}})
}
