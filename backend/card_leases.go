package main

import (
	"fmt"
	"time"
)

type cardLeaseRequest struct {
	Keys      []string
	RunID     string
	Operation string
	Until     int64
	ForRun    bool
}

func pulseLeaseKey(c config, id string) string {
	return hashHex([]byte(fmt.Sprintf("card/%d/%s/%s/%s", c.StarlightChainID, c.MarketplaceCollection, c.PulseRouter, id)))
}
func pulseLeaseKeys(c config, ids []string) []string {
	keys := []string{}
	seen := map[string]bool{}
	for _, id := range ids {
		if _, ok := pulseToken(id); ok && !seen[id] {
			seen[id] = true
			keys = append(keys, pulseLeaseKey(c, id))
		}
	}
	return keys
}
func (s *graphStore) busyCards(keys []string, allowRunOwner, ignoreOperation string) (map[string]bool, error) {
	result := map[string]bool{}
	if len(keys) == 0 {
		return result, nil
	}
	rows, err := s.query(`MATCH(l:CardLease) WHERE l.key IN $keys
OPTIONAL MATCH(j:ShopOperation {key:l.operation})
WITH l,j WHERE (coalesce(l.run_until,0)>$now AND coalesce(l.run_owner,'')<>$allow_owner) OR (j.status='pending' AND j.key<>$ignore)
RETURN DISTINCT l.key`, map[string]interface{}{"keys": keys, "now": time.Now().UnixMilli(), "allow_owner": allowRunOwner, "ignore": ignoreOperation})
	if err != nil {
		return nil, err
	}
	for rows.Next() {
		value, _ := rows.Record().GetByIndex(0)
		if key, ok := value.(string); ok {
			result[key] = true
		}
	}
	return result, nil
}
func (a *api) pulseBusy(ids []string, allowOwner, ignoreOperation string) (map[string]bool, error) {
	store, ok := a.shop.store.(interface {
		busyCards([]string, string, string) (map[string]bool, error)
	})
	if !ok {
		return nil, errPulseState
	}
	return store.busyCards(pulseLeaseKeys(a.config, ids), allowOwner, ignoreOperation)
}

// The conflict check precedes the profile CAS write in the SAME Cypher query.
// A transfer cannot make a running or ambiguously submitted card reusable in
// another account. Pending operation reservations never expire on a timer.
const cardLeaseGuard = `OPTIONAL MATCH(l:CardLease) WHERE l.key IN $lease_keys
OPTIONAL MATCH(jj:ShopOperation {key:l.operation})
WITH p,sum(CASE WHEN (coalesce(l.run_until,0)>$lease_now AND coalesce(l.run_owner,'')<>$lease_allow_owner) OR (jj.status='pending' AND jj.key<>$lease_operation) THEN 1 ELSE 0 END) AS busy
WHERE busy=0 `
const cardLeaseRunWrite = `WITH p UNWIND $lease_keys AS lease_key MERGE(l:CardLease {key:lease_key}) SET l.run_owner=$id,l.run_id=$lease_run,l.run_until=$lease_until WITH DISTINCT p `
const cardLeaseOperationWrite = `WITH p UNWIND $lease_keys AS lease_key MERGE(l:CardLease {key:lease_key}) SET l.operation=$lease_operation WITH DISTINCT p `
const cardLeaseReleaseRun = `WITH p OPTIONAL MATCH(l:CardLease {run_owner:$id,run_id:$release_run}) SET l.run_until=0 WITH DISTINCT p `
const cardLeaseReleaseOperation = `WITH p OPTIONAL MATCH(l:CardLease {operation:$shop_key}) REMOVE l.operation WITH DISTINCT p `
