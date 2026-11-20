package main

import (
	"crypto/rand"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"fmt"
	"math"
	"time"
)

type starlightJob struct {
	Recovery                                                          recoveryState
	Key, Owner, Recipient, Status, EngineID, TxHash, ErrorCode, Lease string
	Amount, Sequence, Generation, FromBlock                           int64
}

func starlightAsset(c config) string {
	sum := sha256.Sum256([]byte(fmt.Sprintf("%s/%d/%s", c.EngineProjectID, c.StarlightChainID, c.StarlightToken)))
	return hex.EncodeToString(sum[:])
}
func starlightTarget(c config) string {
	return fmt.Sprintf("%s/%s/%s", starlightAsset(c), c.StarlightDistributor, c.StarlightTreasury)
}

// The high-water mark is per token, so changing RPC/Engine URLs or the router
// cannot re-grant the player's historical earnings. Currency spending must use
// the on-chain wallet balance; Starlight remains the lifetime earned ledger.
func prepareStarlight(p *progression, c config) (bool, error) {
	if !c.StarlightEnabled {
		return false, nil
	}
	asset := starlightAsset(c)
	if p.StarlightAccrued == nil {
		p.StarlightAccrued = map[string]int64{}
	}
	previous, exists := p.StarlightAccrued[asset]
	if p.Starlight < 0 || previous < 0 || p.Starlight < previous {
		return false, errors.New("invalid_starlight_ledger")
	}
	p.starlightTarget = starlightTarget(c)
	p.starlightAward = p.Starlight - previous
	p.StarlightAccrued[asset] = p.Starlight
	return !exists || p.starlightAward > 0, nil
}

const starlightWriteQuery = `WITH p MATCH(u:User {id:$id})
MERGE(j:StarlightPayout {key:$star_key})
ON CREATE SET j.target=$star_target,j.owner=$id,j.amount=$star_amount,j.sequence=$star_sequence,
j.recipient='',j.created_at=$star_now,j.status='pending',j.next_attempt_at=0,j.lease_until=0,
j.engine_id='',j.tx_hash='',j.generation=0,j.from_block=0,j.error_code=''
MERGE(u)-[:EARNED_STARLIGHT]->(j)
`

func starlightParameters(params map[string]interface{}, target, owner string, sequence, amount int64) {
	sum := sha256.Sum256([]byte(target + "/" + owner + "/" + fmt.Sprint(sequence)))
	params["star_key"], params["star_target"], params["star_sequence"], params["star_amount"], params["star_now"] = hex.EncodeToString(sum[:]), target, sequence, amount, time.Now().UnixMilli()
}

const starlightFields = ` RETURN j.key,j.owner,j.amount,j.recipient,j.status,j.engine_id,j.tx_hash,j.generation,j.from_block,j.error_code,j.sequence,coalesce(j.recovery,'{}')`

func (s *graphStore) claimStarlight(target string, now time.Time) (starlightJob, bool, error) {
	return s.claimReward("StarlightPayout", target, now)
}
func (s *graphStore) claimReward(label, target string, now time.Time) (starlightJob, bool, error) {
	random := make([]byte, 16)
	if _, err := rand.Read(random); err != nil {
		return starlightJob{}, false, err
	}
	lease := hex.EncodeToString(random)
	r, err := s.query(`MATCH(j:`+label+` {target:$target}) WHERE j.lease_until<=$now AND j.next_attempt_at<=$now
OPTIONAL MATCH(older:`+label+` {target:$target}) WHERE older.owner=j.owner AND older.sequence<j.sequence AND older.status<>'confirmed'
WITH j,count(older) AS prior WHERE prior=0
WITH j ORDER BY CASE WHEN j.status='confirmed' THEN 1 ELSE 0 END,j.next_attempt_at,j.created_at,j.key LIMIT 1
SET j.lease_token=$lease,j.lease_until=$until`+starlightFields, map[string]interface{}{"target": target, "now": now.UnixMilli(), "until": now.Add(2 * time.Minute).UnixMilli(), "lease": lease})
	if err != nil {
		return starlightJob{}, false, err
	}
	if !r.Next() {
		return starlightJob{}, false, nil
	}
	row := r.Record().Values()
	if len(row) != 12 {
		return starlightJob{}, false, errors.New("invalid_starlight_job")
	}
	text := func(i int) string { v, _ := row[i].(string); return v }
	number := func(i int) int64 { v, _ := row[i].(int64); return v }
	j := starlightJob{Key: text(0), Owner: text(1), Amount: number(2), Recipient: text(3), Status: text(4), EngineID: text(5), TxHash: text(6), Generation: number(7), FromBlock: number(8), ErrorCode: text(9), Sequence: number(10), Lease: lease, Recovery: decodeRecovery(row[11])}
	if !validHex(j.Key, 32) || j.Amount <= 0 || j.Owner == "" {
		return j, false, errors.New("invalid_starlight_job")
	}
	return j, true, nil
}
func (s *graphStore) saveStarlight(j starlightJob, next time.Time) error {
	return s.saveReward("StarlightPayout", j, next)
}
func (s *graphStore) saveReward(label string, j starlightJob, next time.Time) error {
	_, err := s.query(`MATCH(j:`+label+` {key:$key}) WHERE j.lease_token=$lease
SET j.recipient=$recipient,j.status=$status,j.engine_id=$engine,j.tx_hash=$hash,j.generation=$generation,j.from_block=$from,
j.error_code=$error,j.recovery=$recovery,j.next_attempt_at=$next,j.lease_until=0 RETURN j.key`, map[string]interface{}{"key": j.Key, "lease": j.Lease, "recipient": j.Recipient, "status": j.Status, "engine": j.EngineID, "hash": j.TxHash, "generation": j.Generation, "from": j.FromBlock, "error": j.ErrorCode, "recovery": encodeRecovery(j.Recovery), "next": next.UnixMilli()})
	return err
}
func (s *graphStore) backfillStarlight(c config) error {
	r, err := s.query(`MATCH(p:Progression) RETURN p.owner`, nil)
	if err != nil {
		return err
	}
	owners := []string{}
	for r.Next() {
		v, _ := r.Record().GetByIndex(0)
		if owner, ok := v.(string); ok {
			owners = append(owners, owner)
		}
	}
	for _, owner := range owners {
		done := false
		for range 20 {
			p, v, err := s.ReadProgress(owner)
			if err != nil {
				return err
			}
			changed, err := prepareStarlight(&p, c)
			if err != nil {
				return err
			}
			if !changed {
				done = true
				break
			}
			written, err := s.WriteProgress(owner, v, p)
			if err != nil {
				return err
			}
			if written {
				done = true
				break
			}
		}
		if !done {
			return errors.New("starlight_migration_busy")
		}
	}
	return nil
}
func (s *graphStore) pendingStarlight(target, owner string) (int64, error) {
	r, err := s.query(`MATCH(j:StarlightPayout {target:$target,owner:$owner}) WHERE j.status<>'confirmed' RETURN j.amount`, map[string]interface{}{"target": target, "owner": owner})
	if err != nil {
		return 0, err
	}
	// FalkorDB SUM returns a float; monetary totals must remain exact integers.
	var total int64
	for r.Next() {
		v, _ := r.Record().GetByIndex(0)
		n, ok := v.(int64)
		if !ok || n < 0 || n > math.MaxInt64-total {
			return 0, errors.New("invalid_starlight_pending")
		}
		total += n
	}
	return total, nil
}
