package main

import (
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"errors"
	"strings"
	"time"
)

type shopJob struct {
	Recovery         recoveryState `json:"-"`
	Pulse            *pulseIntent  `json:"-"`
	Router           string        `json:"-"`
	CardID           string        `json:"card_id,omitempty"`
	TrainingXP       int           `json:"training_xp,omitempty"`
	LevelBefore      int           `json:"level_before,omitempty"`
	LevelAfter       int           `json:"level_after,omitempty"`
	SuccessChance    int           `json:"success_chance_bp,omitempty"`
	UpgradeAttempted bool          `json:"upgrade_attempted,omitempty"`
	LevelUpgraded    *bool         `json:"level_upgraded,omitempty"`
	UpgradeRoll      int           `json:"-"`
	ItemID           string        `json:"item_id,omitempty"`
	Key              string        `json:"key"`
	Owner            string        `json:"-"`
	RequestID        string        `json:"request_id"`
	Kind             string        `json:"kind"`
	Wallet           string        `json:"-"`
	Quantity         int           `json:"quantity"`
	Status           string        `json:"status"`
	Stage            string        `json:"stage"`
	EngineID         string        `json:"-"`
	TxHash           string        `json:"transaction_hash,omitempty"`
	FromBlock        int64         `json:"-"`
	Generation       int64         `json:"-"`
	Error            string        `json:"message,omitempty"`
	Restored         int           `json:"energy_restored,omitempty"`
	Lease            string        `json:"-"`
	ExecuteStarted   bool          `json:"-"`
}

// Private fields are persisted separately from their deliberately small API view.
type storedShopJob struct {
	Recovery                recoveryState
	Job                     shopJob `json:"job"`
	Owner, Wallet, EngineID string
	Router                  string
	FromBlock, Generation   int64
	ExecuteStarted          bool
	UpgradeRoll             int
	Pulse                   *pulseIntent
}

func encodeShopJob(j shopJob) string {
	b, _ := json.Marshal(storedShopJob{Recovery: j.Recovery, Job: j, Owner: j.Owner, Wallet: j.Wallet, EngineID: j.EngineID, Router: j.Router, FromBlock: j.FromBlock, Generation: j.Generation, ExecuteStarted: j.ExecuteStarted, UpgradeRoll: j.UpgradeRoll, Pulse: j.Pulse})
	return string(b)
}
func decodeShopJob(text string) (shopJob, error) {
	var v storedShopJob
	err := json.Unmarshal([]byte(text), &v)
	j := v.Job
	j.Recovery = v.Recovery
	j.Owner, j.Wallet, j.EngineID, j.FromBlock, j.Generation = v.Owner, v.Wallet, v.EngineID, v.FromBlock, v.Generation
	j.ExecuteStarted = v.ExecuteStarted
	j.Router = v.Router
	j.UpgradeRoll = v.UpgradeRoll
	j.Pulse = v.Pulse
	return j, err
}
func shopTarget(c config) string {
	return hashHex([]byte(strings.Join([]string{c.EngineProjectID, c.ShopRouter, c.MarketplaceAddress, c.MarketplaceCollection, c.StarlightToken}, "/")))
}
func shopKey(c config, owner, request string) string {
	return strings.TrimPrefix(hashHex([]byte(shopTarget(c)+"/"+owner+"/"+request)), "0x")
}

const shopCreateQuery = `WITH p MATCH(u:User {id:$id}) MERGE(j:ShopOperation {key:$shop_key})
ON CREATE SET j.owner=$id,j.target=$shop_target,j.payload=$shop_payload,j.status='pending',j.lease_until=0,j.next_at=0,j.created_at=$shop_now
MERGE(u)-[:HAS_SHOP_OPERATION]->(j) `

func (s *graphStore) shopOperation(key, owner string) (*shopJob, error) {
	r, err := s.query(`MATCH(j:ShopOperation {key:$key,owner:$owner}) RETURN j.payload`, map[string]interface{}{"key": key, "owner": owner})
	if err != nil {
		return nil, err
	}
	if !r.Next() {
		return nil, nil
	}
	v, _ := r.Record().GetByIndex(0)
	text, ok := v.(string)
	if !ok {
		return nil, errors.New("invalid shop operation")
	}
	j, err := decodeShopJob(text)
	return &j, err
}
func (s *graphStore) claimShop(target string) (shopJob, bool, error) {
	random := make([]byte, 16)
	if _, err := rand.Read(random); err != nil {
		return shopJob{}, false, err
	}
	lease := hex.EncodeToString(random)
	now := time.Now()
	r, err := s.query(`MATCH(j:ShopOperation {target:$target}) WHERE j.status='pending' AND j.lease_until<=$now AND j.next_at<=$now WITH j ORDER BY j.next_at,j.created_at LIMIT 1 SET j.lease_token=$lease,j.lease_until=$until RETURN j.payload`, map[string]interface{}{"target": target, "now": now.UnixMilli(), "until": now.Add(2 * time.Minute).UnixMilli(), "lease": lease})
	if err != nil || !r.Next() {
		return shopJob{}, false, err
	}
	v, _ := r.Record().GetByIndex(0)
	text, ok := v.(string)
	if !ok {
		return shopJob{}, false, errors.New("invalid shop operation")
	}
	j, err := decodeShopJob(text)
	j.Lease = lease
	return j, true, err
}
func (s *graphStore) saveShop(j shopJob, next time.Time) error {
	_, err := s.query(`MATCH(j:ShopOperation {key:$key}) WHERE j.lease_token=$lease AND j.status='pending' SET j.payload=$payload,j.next_at=$next,j.lease_until=0 RETURN j.key`, map[string]interface{}{"key": j.Key, "lease": j.Lease, "payload": encodeShopJob(j), "next": next.UnixMilli()})
	return err
}
func (s *graphStore) finishShop(j shopJob) error {
	for range 20 {
		stored, err := s.shopOperation(j.Key, j.Owner)
		if err != nil {
			return err
		}
		if stored == nil {
			return errors.New("shop operation missing")
		}
		if stored.Status == "confirmed" || stored.Status == "failed" {
			return nil
		}
		p, v, err := s.ReadProgress(j.Owner)
		if err != nil {
			return err
		}
		p.normalize(time.Now())
		if p.ShopActive != j.Key {
			return errors.New("shop operation conflict")
		}
		if j.Status == "confirmed" && j.Kind == "consume" {
			before := p.Energy.Current
			p.Energy.Current = min(energyCap, before+5)
			if p.Energy.Current == energyCap {
				p.Energy.NextAt = 0
			}
			j.Restored = p.Energy.Current - before
		}

		p.ShopActive = ""
		p.ShopLast = j.Key
		p.shopFinish = &j
		written, err := s.WriteProgress(j.Owner, v, p)
		if err != nil {
			return err
		}
		if written {
			return nil
		}
	}
	return errors.New("shop progression busy")
}
