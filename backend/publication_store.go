package main

import (
	"crypto/rand"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"time"
)

type publishedScore struct {
	PlayerID   string `json:"player_id"`
	RunID      string `json:"run_id"`
	SongID     string `json:"song_id"`
	Difficulty string `json:"difficulty"`
	Revision   string `json:"revision"`
	BoardID    string `json:"board_id"`
	Score      int    `json:"score"`
	MaxCombo   int    `json:"max_combo"`
	AchievedAt int64  `json:"achieved_at"`
	Units      int    `json:"units"`
}

type publicationJob struct {
	Key        string         `json:"key"`
	Payload    publishedScore `json:"payload"`
	Status     string         `json:"status"`
	EngineID   string         `json:"engine_id"`
	TxHash     string         `json:"tx_hash"`
	Generation int64          `json:"generation"`
	FromBlock  int64          `json:"from_block"`
	ErrorCode  string         `json:"error_code"`
	Lease      string         `json:"-"`
}

func publicationTarget(c config) string {
	if !c.LeaderboardEnabled {
		return ""
	}
	return fmt.Sprintf("%s/%s/%d/%s", c.EngineURL, c.EngineProjectID, c.LeaderboardChainID, c.LeaderboardAddress)
}

func publicationParameters(params map[string]interface{}, target, owner string, sequence int64, b personalBest) error {
	params["publish_target"], params["publish_job"], params["publish_board"], params["publish_payload"], params["publish_sequence"] = target, "", "", "", sequence
	if target == "" {
		return nil
	}
	chart, ok := rewardCharts[b.SongID+"/"+b.Difficulty]
	if !ok || chart.Revision != b.Revision || !validHex(owner, 16) || !validHex(b.RunID, 16) || b.Score < 0 || b.Score > 1000000 || b.MaxCombo < 1 || b.MaxCombo > chart.Units || b.AchievedAt <= 0 {
		return errors.New("invalid leaderboard publication")
	}
	// The existing contract accepts 500,000+ scores. Lower momentum scores still
	// earn progression and an off-chain ranking, without an invalid transaction.
	if b.Score < 500000 {
		params["publish_target"] = ""
		return nil
	}
	board, err := chartBoardKey(b.SongID, b.Difficulty, b.Revision)
	if err != nil {
		return err
	}
	payload := publishedScore{PlayerID: owner, RunID: b.RunID, SongID: b.SongID, Difficulty: b.Difficulty, Revision: b.Revision, BoardID: board, Score: b.Score, MaxCombo: b.MaxCombo, AchievedAt: b.AchievedAt, Units: chart.Units}
	data, err := json.Marshal(payload)
	if err != nil {
		return err
	}
	sum := sha256.Sum256([]byte(target + "/" + owner + "/" + b.RunID))
	params["publish_job"], params["publish_board"], params["publish_payload"] = hex.EncodeToString(sum[:]), board, string(data)
	return nil
}

// Strict order within each account/chart preserves achievement tie timestamps.
func (s *graphStore) claimPublication(target string, now time.Time) (publicationJob, bool, error) {
	random := make([]byte, 16)
	if _, err := rand.Read(random); err != nil {
		return publicationJob{}, false, err
	}
	lease := hex.EncodeToString(random)
	query := `MATCH(j:LeaderboardPublication {target:$target})
WHERE j.next_attempt_at<=$now AND j.lease_until<=$now
OPTIONAL MATCH(older:LeaderboardPublication {target:$target})
WHERE older.owner=j.owner AND older.board=j.board AND older.status<>'confirmed'
AND (older.sequence<j.sequence OR (older.sequence=j.sequence AND older.key<j.key))
WITH j,count(older) AS prior WHERE prior=0
WITH j ORDER BY CASE WHEN j.status='confirmed' THEN 1 ELSE 0 END,j.next_attempt_at,j.created_at,j.key LIMIT 1
SET j.lease_token=$lease,j.lease_until=$until
RETURN j.key,j.payload,j.status,j.engine_id,j.tx_hash,j.generation,j.from_block,j.error_code`
	r, err := s.query(query, map[string]interface{}{"target": target, "now": now.UnixMilli(), "until": now.Add(2 * time.Minute).UnixMilli(), "lease": lease})
	if err != nil {
		return publicationJob{}, false, err
	}
	if !r.Next() {
		return publicationJob{}, false, nil
	}
	job, err := decodePublication(r.Record().Values())
	job.Lease = lease
	return job, true, err
}

func decodePublication(values []interface{}) (publicationJob, error) {
	if len(values) != 8 {
		return publicationJob{}, errors.New("invalid publication row")
	}
	text := func(index int) string { value, _ := values[index].(string); return value }
	job := publicationJob{Key: text(0), Status: text(2), EngineID: text(3), TxHash: text(4), ErrorCode: text(7)}
	job.Generation, _ = values[5].(int64)
	job.FromBlock, _ = values[6].(int64)
	err := json.Unmarshal([]byte(text(1)), &job.Payload)
	return job, err
}

func (s *graphStore) savePublication(j publicationJob, next time.Time) error {
	_, err := s.query(`MATCH(j:LeaderboardPublication {key:$key}) WHERE j.lease_token=$lease
SET j.status=$status,j.engine_id=$engine,j.tx_hash=$hash,j.generation=$generation,j.from_block=$from,
j.error_code=$error,j.next_attempt_at=$next,j.lease_until=0,
j.confirmed_at=CASE WHEN $status='confirmed' THEN $now ELSE coalesce(j.confirmed_at,0) END RETURN j.key`, map[string]interface{}{
		"key": j.Key, "lease": j.Lease, "status": j.Status, "engine": j.EngineID, "hash": j.TxHash, "generation": j.Generation, "from": j.FromBlock,
		"error": j.ErrorCode, "next": next.UnixMilli(), "now": time.Now().UnixMilli()})
	return err
}

func (s *graphStore) backfillPublications(target string) error {
	r, err := s.query(`MATCH(u:User)-[:HAS_PERSONAL_BEST]->(b:PersonalBest {verification:2})
RETURN u.id,b.song_id,b.difficulty,b.revision,b.score,b.max_combo,b.achieved_at,b.run_id,coalesce(b.replay_version,0)`, nil)
	if err != nil {
		return err
	}
	for r.Next() {
		row := r.Record()
		text := func(i int) string { v, _ := row.GetByIndex(i); s, _ := v.(string); return s }
		number := func(i int) int64 { v, _ := row.GetByIndex(i); n, _ := v.(int64); return n }
		b := personalBest{SongID: text(1), Difficulty: text(2), Revision: text(3), Score: int(number(4)), MaxCombo: int(number(5)), AchievedAt: number(6), RunID: text(7)}
		if !supportedReplayVersion(int(number(8))) {
			provenVersion := 0
			progress, _, readErr := s.ReadProgress(text(0))
			if readErr != nil {
				return readErr
			}
			proven := false
			for _, receipt := range progress.Receipts {
				if receipt.RunID == b.RunID && receipt.Ranked && supportedReplayVersion(receipt.Verification) {
					proven = true
					provenVersion = receipt.Verification
					break
				}
			}
			if !proven {
				continue
			}
			if _, writeErr := s.query(`MATCH(b:PersonalBest {key:$key,run_id:$run}) SET b.replay_version=$version RETURN b.key`, map[string]interface{}{"version": provenVersion, "key": text(0) + "/" + b.SongID + "/" + b.Difficulty, "run": b.RunID}); writeErr != nil {
				return writeErr
			}
		}
		params := map[string]interface{}{"id": text(0), "achieved": b.AchievedAt}
		if err := publicationParameters(params, target, text(0), 0, b); err != nil {
			continue
		} // legacy revisions/evidence stay off-chain.
		if params["publish_target"] == "" {
			continue
		}
		_, err = s.query(`MERGE(j:LeaderboardPublication {key:$publish_job})
ON CREATE SET j.target=$publish_target,j.owner=$id,j.board=$publish_board,j.payload=$publish_payload,
j.sequence=0,j.created_at=$achieved,j.status='pending',j.next_attempt_at=0,j.lease_until=0,
j.engine_id='',j.tx_hash='',j.generation=0,j.error_code='',j.from_block=0 RETURN j.key`, params)
		if err != nil {
			return err
		}
	}
	return nil
}

func (s *graphStore) publicationFor(target, owner, board string) (*publicationJob, error) {
	r, err := s.query(`MATCH(j:LeaderboardPublication {target:$target,owner:$owner,board:$board})
RETURN j.key,j.payload,j.status,j.engine_id,j.tx_hash,j.generation,j.from_block,j.error_code
ORDER BY j.sequence DESC,j.created_at DESC LIMIT 1`, map[string]interface{}{"target": target, "owner": owner, "board": board})
	if err != nil {
		return nil, err
	}
	if !r.Next() {
		return nil, nil
	}
	j, err := decodePublication(r.Record().Values())
	return &j, err
}
