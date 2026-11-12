package main

import (
	"math"
	"sort"
	"strings"
)

const replayVersion = 4

// Timing rules are pinned to the server-issued ticket. Keep installed v3 APKs
// on their original rules while v4 gets slightly more forgiving collection.
type replayRules struct {
	perfect, great, hit, trace, release float64
}

func supportedReplayVersion(version int) bool { return version == 3 || version == replayVersion }
func rulesForReplay(version int) replayRules {
	if version == 3 {
		return replayRules{0.045, 0.09, 0.15, 0.62, 0.12}
	}
	return replayRules{0.06, 0.105, 0.18, 0.72, 0.16}
}

const replayHz = int64(120)
const maxReplayEvents = 24000

type replayPoint struct {
	At   float64 `json:"at"`
	Lane float64 `json:"lane"`
}
type replayNote struct {
	Time        float64       `json:"time"`
	Duration    float64       `json:"duration"`
	Lane        float64       `json:"lane"`
	Kind        string        `json:"kind"`
	Curve       []replayPoint `json:"curve"`
	Checkpoints []float64     `json:"checkpoints"`
}
type inputReplay struct {
	Version  int       `json:"version"`
	RunID    string    `json:"run_id"`
	Revision string    `json:"revision"`
	EndUS    int64     `json:"end_us"`
	Events   [][]int64 `json:"events"`
}
type replayState struct {
	replayNote
	state, owner, next int
	gap                float64
	regrab             bool
	perfect            bool
}
type replayPointer struct {
	lane     float64
	keyboard bool
}
type replayJudge struct {
	rules                 replayRules
	notes                 []replayState
	pointers              map[int]replayPointer
	counts                map[string]int
	combo, maxCombo, life int
	battle                *cardBattle
	cardPoints            int64
	duration              float64
	timeUS, tick          int64
	trace                 strings.Builder
	paused, dead          bool
}

func newReplayJudge(chart rewardChart, version int) *replayJudge {
	j := &replayJudge{rules: rulesForReplay(version), pointers: map[int]replayPointer{}, counts: map[string]int{"PERFECT": 0, "GREAT": 0, "GOOD": 0, "MISS": 0}, life: 1000000, battle: newCardBattle(nil), duration: chart.Duration, timeUS: -150000, tick: -18}
	for _, note := range chart.Notes {
		j.notes = append(j.notes, replayState{replayNote: note, owner: -999})
	}
	return j
}
func (n replayNote) laneAt(t float64) float64 {
	if n.Kind != "slide" || len(n.Curve) < 2 {
		return n.Lane
	}
	p := math.Max(0, math.Min(1, (t-n.Time)/math.Max(n.Duration, 0.001)))
	for i := 1; i < len(n.Curve); i++ {
		if p <= n.Curve[i].At {
			a, b := n.Curve[i-1], n.Curve[i]
			f := math.Max(0, math.Min(1, (p-a.At)/math.Max(0.001, b.At-a.At)))
			f = f * f * (3 - 2*f)
			return a.Lane + (b.Lane-a.Lane)*f
		}
	}
	return n.Curve[len(n.Curve)-1].Lane
}
func (j *replayJudge) hit(kind string, head bool, completed int, perfect bool) {
	if j.dead {
		return
	}
	j.counts[kind]++
	j.combo++
	j.maxCombo = max(j.maxCombo, j.combo)
	weight := map[string]int{"PERFECT": 10, "GREAT": 8, "GOOD": 5}[kind]
	points, heal := j.battle.hit(weight, j.combo, head, completed, perfect, float64(j.timeUS)/1000000, j.duration, j.life)
	j.cardPoints += points
	switch kind {
	case "PERFECT":
		j.trace.WriteByte('P')
		j.life = min(1000000, j.life+5000+heal)
	case "GREAT":
		j.trace.WriteByte('R')
		j.life = min(1000000, j.life+5000+heal)
	case "GOOD":
		j.trace.WriteByte('G')
		j.life = max(0, j.life-12000)
	}
	if j.life == 0 {
		j.dead = true
	}
}
func (j *replayJudge) miss(n *replayState, units int) {
	n.state = 3
	j.counts["MISS"] += max(0, units)
	j.trace.WriteString(strings.Repeat("M", max(0, units)))
	j.combo = 0
	j.battle.miss()
	j.life = max(0, j.life-45000)
	if j.life == 0 {
		j.dead = true
	}
}
func (j *replayJudge) advance(us int64) {
	for (j.tick+1)*1000000 <= us*replayHz {
		j.tick++
		if j.dead {
			continue
		}
		t := float64(j.tick) / float64(replayHz)
		for i := range j.notes {
			n := &j.notes[i]
			if n.Time > t {
				break
			}
			if n.state == 0 && t > n.Time+j.rules.hit {
				j.miss(n, 1+len(n.Checkpoints))
			} else if n.state == 1 {
				lane := n.laneAt(t)
				p, held := j.pointers[n.owner]
				valid := held && math.Abs(p.lane-lane) <= j.rules.trace
				if n.owner <= -100 && !valid {
					ids := make([]int, 0, len(j.pointers))
					for id := range j.pointers {
						ids = append(ids, id)
					}
					sort.Ints(ids)
					for _, id := range ids {
						p := j.pointers[id]
						if p.keyboard && math.Abs(p.lane-lane) <= j.rules.trace {
							n.owner = id
							valid = true
							break
						}
					}
				}
				if valid {
					n.gap = 0
				} else {
					n.gap += 1.0 / float64(replayHz)
				}
				if n.gap > j.rules.release {
					j.miss(n, len(n.Checkpoints)-n.next)
					continue
				}
				for n.next < len(n.Checkpoints) && t >= n.Checkpoints[n.next] {
					completed := 0
					if n.next == len(n.Checkpoints)-1 {
						completed = 1 + len(n.Checkpoints)
					}
					j.timeUS = int64(math.Round(t * 1000000))
					j.hit("PERFECT", false, completed, n.perfect)
					n.next++
				}
				if n.next >= len(n.Checkpoints) {
					n.state = 2
				}
			}
			if j.dead {
				break
			}
		}
	}
	j.timeUS = us
}
func (j *replayJudge) press(id int, lane float64) {
	if j.dead {
		return
	}
	j.pointers[id] = replayPointer{lane: lane, keyboard: id <= -100}
	best, nearest := -1, j.rules.hit+0.001
	t := float64(j.timeUS) / 1000000
	for i, n := range j.notes {
		if n.state != 0 || math.Abs(n.Lane-lane) > j.rules.trace {
			continue
		}
		d := math.Abs(n.Time - t)
		if d <= j.rules.hit && d < nearest {
			best, nearest = i, d
		}
	}
	if best < 0 {
		for i := range j.notes {
			n := &j.notes[i]
			if n.state == 1 && n.regrab && math.Abs(n.laneAt(t)-lane) <= j.rules.trace {
				n.owner = id
				n.regrab = false
				n.gap = 0
				return
			}
		}
		return
	}
	kind := "GOOD"
	if nearest <= j.rules.perfect {
		kind = "PERFECT"
	} else if nearest <= j.rules.great {
		kind = "GREAT"
	}
	j.hit(kind, true, 0, false)
	j.notes[best].perfect = kind == "PERFECT"
	n := &j.notes[best]
	if n.Kind == "tap" {
		n.state = 2
	} else {
		n.state = 1
		n.owner = id
		n.gap = 0
	}
}
func (j *replayJudge) suspend() {
	j.paused = true
	clear(j.pointers)
	for i := range j.notes {
		n := &j.notes[i]
		if n.state == 1 {
			n.gap = -0.2
			n.regrab = true
		}
	}
}
func (j *replayJudge) finish(us int64) {
	j.advance(us)
	for i := range j.notes {
		n := &j.notes[i]
		if n.state == 0 {
			j.miss(n, 1+len(n.Checkpoints))
		} else if n.state == 1 {
			j.miss(n, len(n.Checkpoints)-n.next)
		}
	}
}

func verifyInputReplay(r *inputReplay, run runTicket, chart rewardChart) (*replayJudge, error) {
	if r == nil || !supportedReplayVersion(run.ReplayVersion) || r.Version != run.ReplayVersion || r.RunID != run.ID || r.Revision != run.Revision {
		return nil, badProgress("This run requires its own versioned input replay.")
	}
	durationUS := int64(math.Round(chart.Duration * 1000000))
	// Allow the UI's ±150ms calibration plus 5ms for codec duration rounding.
	if r.EndUS < durationUS-155000 || r.EndUS > durationUS+155000 || len(r.Events) > maxReplayEvents || len(chart.Notes) == 0 || chart.Duration > 300 {
		return nil, badProgress("Invalid replay duration or size.")
	}
	j := newReplayJudge(chart, run.ReplayVersion)
	j.battle = newCardBattle(run.Card)
	for _, event := range r.Events {
		if len(event) != 4 {
			return nil, badProgress("Invalid replay event.")
		}
		us, kind, id, x := event[0], event[1], event[2], event[3]
		if us < j.timeUS || us > r.EndUS {
			return nil, badProgress("Replay input times must be ordered within the song.")
		}
		j.advance(us)
		if kind == 3 {
			if id != 0 || x != 0 {
				return nil, badProgress("Invalid replay pause.")
			}
			j.suspend()
			continue
		}
		if !(id >= 0 && id <= 31 || id == -1 || id >= -104 && id <= -100) {
			return nil, badProgress("Invalid replay pointer.")
		}
		pointer, held := j.pointers[int(id)]
		switch kind {
		case 0:
			if held || len(j.pointers) >= 10 || x < -10000 || x > 50000 {
				return nil, badProgress("Invalid replay press.")
			}
			if id <= -100 && x != (-id-100)*10000 {
				return nil, badProgress("Keyboard input does not match its lane.")
			}
			j.press(int(id), float64(x)/10000)
		case 1:
			if !held || id <= -100 || !(x >= -10000 && x <= 50000 || x == -100000) {
				return nil, badProgress("Invalid replay movement.")
			}
			pointer.lane = float64(x) / 10000
			j.pointers[int(id)] = pointer
		case 2:
			if !held || x != 0 {
				return nil, badProgress("Invalid replay release.")
			}
			delete(j.pointers, int(id))
		default:
			return nil, badProgress("Unknown replay action.")
		}
	}
	j.finish(r.EndUS)
	if j.dead {
		return nil, badProgress("Replay did not survive to the end of the stage.")
	}
	return j, nil
}

func (j *replayJudge) matches(result runResult, chart rewardChart, cards ...*cardLoadout) error {
	var card *cardLoadout
	if len(cards) > 0 {
		card = cards[0]
	}
	_ = card
	if abs(result.Score-j.score(chart.Units)) > 1 || result.MaxCombo != j.maxCombo {
		return badProgress("Result does not match the server's input replay.")
	}
	for kind, count := range j.counts {
		if result.Counts[kind] != count {
			return badProgress("Judgments do not match the input replay.")
		}
	}
	if result.Trace != "" && result.Trace != j.trace.String() {
		return badProgress("Judgment order does not match the input replay.")
	}
	return nil
}

func (j *replayJudge) score(units int) int { return cardPointsScore(j.cardPoints, units) }
