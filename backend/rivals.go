package main

// A run pins its target at start. Only current-revision verified scores from
// mutual, unblocked friends can be selected; your own verified best is fallback.
type runRival struct {
	Label  string `json:"label"`
	Score  int    `json:"score"`
	Kind   string `json:"kind"`
	UserID string `json:"user_id,omitempty"`
}

func (s *graphStore) rivalTarget(owner string, chart rewardChart) (*runRival, error) {
	params := map[string]interface{}{"id": owner, "chart_key": chart.SongID + "/" + chart.Difficulty + "/" + chart.Revision}
	own, err := s.scoreRows(`MATCH(u:User {id:$id})-[:HAS_PERSONAL_BEST]->(b:PersonalBest {chart_key:$chart_key,verification:2}) WHERE coalesce(b.quarantined,false)=false `+bestFields+` LIMIT 1`, params, 0)
	if err != nil {
		return nil, err
	}
	threshold := -1
	var target *runRival
	if len(own) > 0 {
		threshold = own[0].Score
		target = &runRival{Label: "YOUR BEST", Score: threshold, Kind: "personal"}
	}
	params["threshold"] = threshold
	friends, err := s.scoreRows(`MATCH(me:User {id:$id})-[:FOLLOWS]->(u:User)-[:FOLLOWS]->(me) MATCH(u)-[:HAS_PERSONAL_BEST]->(b:PersonalBest {chart_key:$chart_key,verification:2}) OPTIONAL MATCH(me)-[block:BLOCKS]-(u) WITH u,b,count(block) AS blocks WHERE blocks=0 AND coalesce(b.quarantined,false)=false AND b.score>$threshold `+bestFields+` ORDER BY b.score ASC,b.max_combo ASC,u.id ASC LIMIT 1`, params, 0)
	if err != nil {
		return nil, err
	}
	if len(friends) > 0 {
		f := friends[0]
		target = &runRival{Label: f.Username, Score: f.Score, Kind: "friend", UserID: f.UserID}
	}
	return target, nil
}
