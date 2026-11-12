package main

import (
	"context"
	_ "embed"
	"encoding/json"
	"errors"
	"fmt"
	"strconv"
	"strings"
)

//go:embed song_sets.json
var songSetsJSON []byte
var songSets = func() map[string]string {
	var songs []struct {
		ID    string `json:"id"`
		SetID string `json:"set_id"`
	}
	if json.Unmarshal(songSetsJSON, &songs) != nil {
		panic("invalid song sets")
	}
	out := map[string]string{}
	for _, song := range songs {
		out[song.ID] = song.SetID
	}
	return out
}()

type pulseCard struct {
	SetIndex       int   `json:"release_number"`
	TokenID        int64 `json:"token_id"`
	Member         int   `json:"member_index"`
	Rarity         int   `json:"rarity_index"`
	BaseScoreBP    int   `json:"base_score_bp"`
	BaseRecoveryBP int   `json:"base_recovery_bp"`
	Skill          int   `json:"skill_id"`
	XP             int   `json:"training_xp"`
	Level          int   `json:"level"`
	Stars          int   `json:"stars"`
	Progress       int   `json:"star_progress"`
	Revision       int64 `json:"revision"`
	Burned         bool  `json:"burned"`
	Flags          int   `json:"protection_flags"`
	ScoreBP        int   `json:"perfect_score_bp"`
	RecoveryPPM    int   `json:"recovery_ppm"`
}

var pulseMembers = []string{"Woni", "Liv", "Minami", "May", "Zena"}
var pulseRarities = []string{"Common", "Uncommon", "Rare", "Epic", "Legendary", "LE"}
var pulseSkillNames = []string{"None", "Overture", "Spotlight", "Second Wind", "Encore", "Resonance", "Overdrive"}

func pulseID(token int64) string { return fmt.Sprintf("pulse_%d", token) }
func pulseToken(id string) (int64, bool) {
	if !strings.HasPrefix(id, "pulse_") {
		return 0, false
	}
	value, err := strconv.ParseInt(strings.TrimPrefix(id, "pulse_"), 10, 64)
	return value, err == nil && value > 0 && pulseID(value) == id
}
func pulseStarPreview(stars, progress, donors int) (int, int, int) {
	progress += donors
	for stars < 5 && progress >= stars*2 {
		progress -= stars * 2
		stars++
	}
	if stars >= 5 {
		return 5, 0, progress
	}
	return stars, progress, 0
}
func (p pulseCard) loadout() *cardLoadout {
	if p.Burned || p.Level < 1 || p.Level > 100 {
		return nil
	}
	skills := [7]int{}
	if p.Skill >= 1 && p.Skill <= 6 {
		skills[p.Skill] = p.Stars
	}
	return &cardLoadout{ID: pulseID(p.TokenID), Level: p.Level, Version: 2, PerfectScoreBP: p.ScoreBP, RecoveryPPM: p.RecoveryPPM, Skills: skills, Member: p.Member}
}
func combinedPulseCards(cards []*cardLoadout) *cardLoadout {
	team := &cardLoadout{ID: "pulse_team", Version: 2, Skills: [7]int{}}
	count := 0
	for _, card := range cards {
		if card == nil || card.Version != 2 {
			continue
		}
		count++
		team.PerfectScoreBP += card.PerfectScoreBP
		team.RecoveryPPM += card.RecoveryPPM
		for skill, stars := range card.Skills {
			if skill > 0 && skill < 7 {
				team.Skills[skill] = max(team.Skills[skill], stars)
			}
		}
	}
	if count == 0 {
		return nil
	}
	team.PerfectScoreBP = min(6000, team.PerfectScoreBP)
	team.RecoveryPPM = min(6000, team.RecoveryPPM)
	return team
}
func (p pulseCard) view() map[string]any {
	number := p.SetIndex
	if number == 0 {
		number = 1
	}
	release := releaseByNumber(number)
	return map[string]any{"id": pulseID(p.TokenID), "template_id": releaseTemplate(number, p.Member), "token_id": strconv.FormatInt(p.TokenID, 10), "category": "cards", "set_id": release.SetID, "series": release.Name, "art_slug": release.Slug, "rarity": pulseRarities[p.Rarity], "member": pulseMembers[p.Member], "member_name": pulseMembers[p.Member], "member_index": p.Member, "name": pulseMembers[p.Member] + " · " + release.Name + " #" + strconv.FormatInt(p.TokenID, 10), "quantity": 1, "level": p.Level, "max_level": 100, "training_xp": p.XP, "level_xp": p.XP, "level_cost": cardLevelCost(p.Level), "success_chance_bp": cardLevelChance(p.Level), "stars": p.Stars, "star_progress": p.Progress, "star_cost": p.Stars * 2, "revision": p.Revision, "locked": p.Flags&1 != 0, "equipped": p.Flags&2 != 0, "listed": p.Flags&4 != 0, "in_use": p.Flags&8 != 0, "skill": pulseSkillNames[p.Skill], "skill_id": p.Skill, "skill_description": pulseSkillDescription(p.Skill, p.Stars), "base_score_bp": p.BaseScoreBP, "base_recovery_bp": p.BaseRecoveryBP, "stats": p.loadout()}
}
func (c *shopClient) pulseRead(ctx context.Context, block int64, signature, words string) (string, error) {
	var out string
	err := c.star.p.rpc(ctx, "eth_call", []any{map[string]string{"to": c.cfg.PulseRouter, "data": selector(signature) + words}, fmt.Sprintf("0x%x", block)}, &out)
	return out, err
}
func (c *shopClient) pulseBlock(ctx context.Context) (int64, error) {
	head, err := c.star.p.head(ctx)
	if err != nil {
		return 0, err
	}
	block := head - c.cfg.StarlightConfirmations + 1
	if block < 0 {
		return 0, errors.New("chain unavailable")
	}
	return block, nil
}
func (c *shopClient) pulseCard(ctx context.Context, block int64, wallet string, token int64) (pulseCard, error) {
	raw, err := c.pulseRead(ctx, block, "viewCard(address,uint256)", addressWord(wallet)+hexWord(token))
	if err != nil {
		return pulseCard{}, err
	}
	if len(raw) != 2+14*64 {
		return pulseCard{}, errors.New("invalid card response")
	}
	values := make([]int64, 14)
	for i := range values {
		values[i], err = wordInt(raw, i)
		if err != nil {
			return pulseCard{}, err
		}
	}
	p := pulseCard{SetIndex: 1, TokenID: token, Member: int(values[0]), Rarity: int(values[1]), BaseScoreBP: int(values[2]), BaseRecoveryBP: int(values[3]), Skill: int(values[4]), XP: int(values[5]), Level: int(values[6]), Stars: int(values[7]), Progress: int(values[8]), Revision: values[9], Burned: values[10] != 0, Flags: int(values[11]), ScoreBP: int(values[12]), RecoveryPPM: int(values[13])}
	if c.cfg.CardReleases {
		raw, err = c.pulseRead(ctx, block, "cardSet(uint256)", hexWord(token))
		if err != nil {
			return p, err
		}
		number, e := wordInt(raw, 0)
		if e != nil || number < 1 || number > 9 {
			return p, errors.New("invalid card release")
		}
		p.SetIndex = int(number)
	}
	if p.Level < 1 || p.Level > 100 || p.Member < 0 || p.Member > 4 || p.Rarity < 0 || p.Rarity > 5 || p.Stars < 1 || p.Stars > 5 || p.Skill < 0 || p.Skill > 6 || p.XP < 0 || p.Progress < 0 || p.Revision < 1 || p.ScoreBP < 0 || p.ScoreBP > 1200 || p.RecoveryPPM < 0 || p.RecoveryPPM > 1200 {
		return p, errors.New("invalid card state")
	}
	return p, nil
}
func (c *shopClient) pulseOwned(ctx context.Context, block int64, wallet string, token int64) (bool, error) {
	var raw string
	err := c.star.p.rpc(ctx, "eth_call", []any{map[string]string{"to": c.cfg.MarketplaceCollection, "data": selector("balanceOf(address,uint256)") + addressWord(wallet) + hexWord(token)}, fmt.Sprintf("0x%x", block)}, &raw)
	if err != nil {
		return false, err
	}
	n, err := uint256Hex(raw)
	return err == nil && n.IsInt64() && n.Int64() == 1, err
}
func (c *shopClient) pulseDeck(ctx context.Context, block int64, wallet string, sets ...string) ([]*cardLoadout, []string, error) {
	if block == 0 {
		var err error
		block, err = c.pulseBlock(ctx)
		if err != nil {
			return nil, nil, err
		}
	}
	number := 1
	if len(sets) > 0 {
		number = releaseNumber(sets[0])
	}
	if number < 1 || number > 1 && !c.cfg.CardReleases {
		return nil, nil, errors.New("unsupported card release")
	}
	raw, err := c.pulseRead(ctx, block, "deck(address,uint256)", addressWord(wallet)+hexWord(int64(number)))
	if err != nil {
		return nil, nil, err
	}
	if len(raw) != 322 {
		return nil, nil, errors.New("invalid deck")
	}
	cards := make([]*cardLoadout, 5)
	ids := make([]string, 5)
	for i := 0; i < 5; i++ {
		token, err := wordInt(raw, i)
		if err != nil {
			return nil, nil, err
		}
		if token == 0 {
			continue
		}
		card, err := c.pulseCard(ctx, block, wallet, token)
		if err != nil {
			return nil, nil, err
		}
		if card.Member != i || card.Burned || card.SetIndex != 0 && card.SetIndex != number {
			return nil, nil, errors.New("invalid deck member")
		}
		cards[i] = card.loadout()
		ids[i] = pulseID(token)
	}
	return cards, ids, nil
}

// Enumerate registered immutable token identities, then filter by confirmed
// ERC-1155 balances. Transfers carry the existing registry state to the new owner.
func (c *shopClient) pulseInventory(ctx context.Context, wallet string) ([]any, map[string][]string, error) {
	block, err := c.pulseBlock(ctx)
	if err != nil {
		return nil, nil, err
	}
	raw, err := c.pulseRead(ctx, block, "count()", "")
	if err != nil {
		return nil, nil, err
	}
	count, err := wordInt(raw, 0)
	if err != nil || count < 0 || count > 100000 {
		return nil, nil, errors.New("invalid card count")
	}
	result := []any{}
	known := map[int64]pulseCard{}
	for offset := int64(0); offset < count; offset += 500 {
		raw, err = c.pulseRead(ctx, block, "tokenIds(uint256,uint256)", hexWord(offset)+hexWord(500))
		if err != nil {
			return nil, nil, err
		}
		n, err := wordInt(raw, 1)
		if err != nil || n < 0 || n > 500 || len(raw) != 2+int(n+2)*64 {
			return nil, nil, errors.New("invalid token page")
		}
		tokens := make([]int64, n)
		words := hexWord(n)
		for i := range tokens {
			tokens[i], err = wordInt(raw, i+2)
			if err != nil {
				return nil, nil, err
			}
			words += hexWord(tokens[i])
		}
		if n == 0 {
			continue
		}
		data := selector("balanceOfBatch(address[],uint256[])") + hexWord(64) + hexWord(96+n*32) + hexWord(n) + strings.Repeat(addressWord(wallet), int(n)) + words
		var balances string
		if err = c.star.p.rpc(ctx, "eth_call", []any{map[string]string{"to": c.cfg.MarketplaceCollection, "data": data}, fmt.Sprintf("0x%x", block)}, &balances); err != nil {
			return nil, nil, err
		}
		if len(balances) != 2+int(n+2)*64 {
			return nil, nil, errors.New("invalid card balances")
		}
		for i, token := range tokens {
			owned, err := wordInt(balances, i+2)
			if err != nil {
				return nil, nil, err
			}
			if owned != 1 {
				continue
			}
			card, err := c.pulseCard(ctx, block, wallet, token)
			if err != nil {
				return nil, nil, err
			}
			if !card.Burned {
				result = append(result, card.view())
				known[token] = card
			}
		}
	}
	decks := map[string][]string{}
	releases := cardReleases[:1]
	if c.cfg.CardReleases {
		releases = cardReleases
	}
	for _, release := range releases {
		raw, err = c.pulseRead(ctx, block, "deck(address,uint256)", addressWord(wallet)+hexWord(int64(release.Number)))
		if err != nil {
			return nil, nil, err
		}
		if len(raw) != 322 {
			return nil, nil, errors.New("invalid deck")
		}
		deck := make([]string, 5)
		for member := 0; member < 5; member++ {
			token, e := wordInt(raw, member)
			if e != nil {
				return nil, nil, e
			}
			if token == 0 {
				continue
			}
			card, ok := known[token]
			number := card.SetIndex
			if number == 0 {
				number = 1
			}
			if !ok || card.Member != member || card.Burned || number != release.Number {
				return nil, nil, errors.New("invalid owned deck member")
			}
			deck[member] = pulseID(token)
		}
		decks[release.SetID] = deck
	}
	return result, decks, nil
}

//go:embed pulse_abi.json
var pulseABIJSON []byte
var pulseABIs = func() map[string]json.RawMessage {
	var methods map[string]json.RawMessage
	if json.Unmarshal(pulseABIJSON, &methods) != nil {
		panic("invalid pulse ABI")
	}
	return methods
}()

func operationABI(job shopJob, method string) json.RawMessage {
	if pulseActive(job) && job.Stage == "execute" {
		return pulseABIs[method]
	}
	return shopABIs[method]
}
