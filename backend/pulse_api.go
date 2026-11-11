package main

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"github.com/gofiber/fiber/v3"
	"strings"
	"time"
)

type pulseRequest struct {
	RequestID   string   `json:"request_id"`
	Kind        string   `json:"kind"`
	CardID      string   `json:"card_id"`
	ItemID      string   `json:"item_id"`
	Donors      []string `json:"donors"`
	SetID       string   `json:"set_id"`
	Member      int      `json:"member_index"`
	Locked      bool     `json:"locked"`
	QuoteHash   string   `json:"quote_hash"`
	Acknowledge bool     `json:"acknowledge_warning"`
}
type pulseQuote struct {
	Hash          string   `json:"hash"`
	Warnings      []string `json:"warnings"`
	CardID        string   `json:"card_id"`
	BeforeLevel   int      `json:"level_before"`
	AfterLevel    int      `json:"level_after"`
	Chance        int      `json:"success_chance_bp"`
	AddedXP       int      `json:"xp_added"`
	BeforeStars   int      `json:"stars_before"`
	AfterStars    int      `json:"stars_after"`
	AfterProgress int      `json:"star_progress_after"`
	Wasted        int      `json:"donors_wasted"`
}
type pulseIntent struct {
	Request                pulseRequest
	Revision               int64
	Roll                   int
	Score, Recovery, Skill int
	Quote                  pulseQuote
}

func (a *api) pulseReady(c fiber.Ctx) error {
	if a.shop == nil || a.config.PulseRouter == "" {
		return failure(c, 503, "cards_unavailable", "Individual cards are not open yet.")
	}
	return nil
}
func pulseQuoteHash(body pulseRequest, cards []pulseCard) string {
	body.RequestID = ""
	body.QuoteHash = ""
	body.Acknowledge = false
	data, _ := json.Marshal(struct {
		Request pulseRequest
		Cards   []pulseCard
	}{body, cards})
	return hashHex(data)
}
func (a *api) pulsePreview(ctx context.Context, p progression, wallet string, body pulseRequest, ignored ...string) (pulseIntent, error) {
	intent := pulseIntent{Request: body}
	q := pulseQuote{CardID: body.CardID, Warnings: []string{}}
	block, err := a.shop.client.pulseBlock(ctx)
	if err != nil {
		return intent, err
	}
	cards := []pulseCard{}
	var target pulseCard
	if body.Kind != "equip" || body.CardID != "" {
		token, ok := pulseToken(body.CardID)
		if !ok {
			return intent, badProgress("Choose an individual card.")
		}
		target, err = a.shop.client.pulseCard(ctx, block, wallet, token)
		if err != nil {
			return intent, err
		}
		owned, err := a.shop.client.pulseOwned(ctx, block, wallet, token)
		if err != nil {
			return intent, err
		}
		if !owned || target.Burned {
			return intent, badProgress("This card is no longer in your wallet.")
		}
		if target.Flags&12 != 0 {
			return intent, badProgress("This card is listed or currently in use.")
		}
		intent.Revision = target.Revision
		cards = append(cards, target)
	}
	inRun := func(id string) bool {
		if p.Active == nil || time.Now().UnixMilli()-p.Active.StartedAt > int64((2*time.Hour).Milliseconds()) {
			return false
		}
		for _, card := range p.Active.DeckIDs {
			if card == id {
				return true
			}
		}
		return p.Active.Card != nil && p.Active.Card.ID == id
	}
	switch body.Kind {
	case "refine":
		material, ok := materialByID(body.ItemID)
		if !ok {
			return intent, badProgress("Choose a refinement item.")
		}
		if target.Level >= 100 {
			return intent, badProgress("This card is already level 100.")
		}
		if inRun(body.CardID) {
			return intent, badProgress("Finish the active song before refining an equipped card.")
		}
		client, _ := a.shop.client.forItem(body.ItemID)
		quantity, err := client.owned(ctx, wallet)
		if err != nil {
			return intent, err
		}
		if quantity < 1 {
			return intent, badProgress("You do not own this refinement item.")
		}
		q.BeforeLevel, q.AfterLevel, q.Chance, q.AddedXP = target.Level, target.Level, cardLevelChance(target.Level), min(material.XP, cardMaxXP-target.XP)
		if target.XP+q.AddedXP >= cardLevelCost(target.Level) {
			q.AfterLevel++
		}
		q.Warnings = append(q.Warnings, fmt.Sprintf("Use 1 %s bundle. A failed level attempt keeps your level and all XP; the bundle is consumed.", material.Name))
	case "star":
		if len(body.Donors) < 1 || len(body.Donors) > 32 {
			return intent, badProgress("Select 1–32 donor cards.")
		}
		if inRun(body.CardID) {
			return intent, badProgress("Finish the active song before upgrading this card.")
		}
		seen := map[string]bool{body.CardID: true}
		for _, id := range body.Donors {
			if seen[id] {
				return intent, badProgress("Each donor must be a different card, separate from the receiver.")
			}
			seen[id] = true
			token, ok := pulseToken(id)
			if !ok {
				return intent, badProgress("Choose individual donor cards.")
			}
			donor, err := a.shop.client.pulseCard(ctx, block, wallet, token)
			if err != nil {
				return intent, err
			}
			owned, err := a.shop.client.pulseOwned(ctx, block, wallet, token)
			if err != nil {
				return intent, err
			}
			if !owned || donor.Burned {
				return intent, badProgress("A donor is no longer in your wallet.")
			}
			if donor.Flags != 0 || inRun(id) {
				return intent, badProgress("Locked, equipped, listed or in-use cards cannot be sacrificed.")
			}
			if !compatibleSacrifice(cardRarity(pulseRarities[target.Rarity]), cardRarity(pulseRarities[donor.Rarity])) {
				return intent, badProgress("This donor's rarity is incompatible with the receiver.")
			}
			cards = append(cards, donor)
			if donor.Level > 1 || donor.XP > 0 || donor.Stars > 1 || donor.Progress > 0 {
				q.Warnings = append(q.Warnings, fmt.Sprintf("%s #%d: level %d, %d XP, %d stars, %d progress will be destroyed. This card counts as ONE donor.", pulseMembers[donor.Member], donor.TokenID, donor.Level, donor.XP, donor.Stars, donor.Progress))
			}
		}
		q.BeforeStars = target.Stars
		q.AfterStars, q.AfterProgress, q.Wasted = pulseStarPreview(target.Stars, target.Progress, len(body.Donors))
		q.Warnings = append([]string{"Sacrifice is permanent. Every selected card is destroyed and contributes exactly ONE donor. No stats, skill, XP, level, stars or progress are inherited."}, q.Warnings...)
		if q.Wasted > 0 {
			q.Warnings = append(q.Warnings, fmt.Sprintf("%d excess donor(s) give no further progress and will still be destroyed.", q.Wasted))
		}
		if target.Skill == 0 {
			q.Warnings = append(q.Warnings, "This card has no skill. Stars will not grant a skill.")
		}
	case "lock":
	case "equip":
		if body.SetID != "pulse" || body.Member < 0 || body.Member > 4 {
			return intent, badProgress("Choose a valid PULSE member slot.")
		}
		if body.CardID != "" && target.Member != body.Member {
			return intent, badProgress("This card belongs in a different member slot.")
		}
		if p.Active != nil && time.Now().UnixMilli()-p.Active.StartedAt < int64((2*time.Hour).Milliseconds()) {
			return intent, badProgress("Finish the active song before editing the deck.")
		}
	default:
		return intent, badProgress("Choose a card action.")
	}
	ids := []string{body.CardID}
	ids = append(ids, body.Donors...)
	ignore := ""
	if len(ignored) > 0 {
		ignore = ignored[0]
	}
	busy, err := a.pulseBusy(ids, "", ignore)
	if err != nil {
		return intent, err
	}
	if len(busy) > 0 {
		return intent, badProgress("A selected card is in use or another action is processing.")
	}
	q.Hash = pulseQuoteHash(body, cards)
	intent.Quote = q
	return intent, nil
}
func (a *api) quotePulseCard(c fiber.Ctx) error {
	if err := a.pulseReady(c); err != nil {
		return err
	}
	var body pulseRequest
	if err := decodeProgressBody(c, &body); err != nil {
		return err
	}
	wallet, err := a.shopWallet(c)
	if err != nil {
		return err
	}
	p, _, err := a.shop.store.ReadProgress(c.Locals("user").(user).ID)
	if err != nil {
		return err
	}
	ctx, cancel := context.WithTimeout(c.Context(), 18*time.Second)
	defer cancel()
	intent, err := a.pulsePreview(ctx, p, wallet.Address, body)
	if err != nil {
		return err
	}
	return c.JSON(fiber.Map{"quote": intent.Quote})
}
func (a *api) actPulseCard(c fiber.Ctx) error {
	if err := a.pulseReady(c); err != nil {
		return err
	}
	var body pulseRequest
	if err := decodeProgressBody(c, &body); err != nil {
		return err
	}
	if !validHex(body.RequestID, 16) {
		return failure(c, 400, "invalid_request", "Use a valid request ID.")
	}
	owner := c.Locals("user").(user).ID
	key := shopKey(a.config, owner, body.RequestID)
	old, err := a.shop.store.shopOperation(key, owner)
	if err != nil {
		return err
	}
	same := func(j *shopJob) bool {
		if j == nil || j.Pulse == nil {
			return false
		}
		x, _ := json.Marshal(j.Pulse.Request)
		y, _ := json.Marshal(body)
		return string(x) == string(y)
	}
	if old != nil {
		if !same(old) {
			return badProgress("This request belongs to a different action.")
		}
		return c.JSON(fiber.Map{"operation": old})
	}
	wallet, err := a.shopWallet(c)
	if err != nil {
		return err
	}
	p, _, err := a.shop.store.ReadProgress(owner)
	if err != nil {
		return err
	}
	ctx, cancel := context.WithTimeout(c.Context(), 18*time.Second)
	defer cancel()
	intent, err := a.pulsePreview(ctx, p, wallet.Address, body)
	if err != nil {
		return err
	}
	if intent.Quote.Hash != body.QuoteHash {
		return badProgress("The card changed. Review a refreshed preview before confirming.")
	}
	if len(intent.Quote.Warnings) > 0 && !body.Acknowledge {
		return badProgress("Acknowledge the sacrifice or refinement warning before confirming.")
	}
	if body.Kind == "refine" {
		intent.Roll, err = cardUpgradeRoll()
		if err != nil {
			return err
		}
	}
	head, err := a.shop.client.star.p.head(ctx)
	if err != nil {
		return err
	}
	j := shopJob{Router: a.config.PulseRouter, Key: key, Owner: owner, RequestID: body.RequestID, Kind: "pulse_" + body.Kind, Wallet: strings.ToLower(wallet.Address), CardID: body.CardID, ItemID: body.ItemID, Quantity: 1, Status: "pending", Stage: "gas", FromBlock: head, Pulse: &intent, LevelBefore: intent.Quote.BeforeLevel, SuccessChance: intent.Quote.Chance}
	return a.mutateProgress(c, func(current *progression, _ time.Time) (any, error) {
		if prior, err := a.shop.store.shopOperation(key, owner); err != nil {
			return nil, err
		} else if prior != nil {
			if !same(prior) {
				return nil, badProgress("Request conflict.")
			}
			return prior, nil
		}
		if current.ShopActive != "" {
			return nil, badProgress("Your previous item action is still processing.")
		}
		// CAS protects against run-start/deck-edit races in this account.
		if (body.Kind == "star" || body.Kind == "refine" || body.Kind == "equip") && current.Active != nil && (p.Active == nil || current.Active.ID != p.Active.ID) && current.Active.ID != "" {
			return nil, badProgress("Finish the active song before changing cards.")
		}
		ids := []string{body.CardID}
		ids = append(ids, body.Donors...)
		busy, err := a.pulseBusy(ids, "", "")
		if err != nil {
			return nil, err
		}
		if len(busy) > 0 {
			return nil, badProgress("A selected card is in use or another action is processing.")
		}
		current.cardLease = &cardLeaseRequest{Keys: pulseLeaseKeys(a.config, ids), Operation: key}
		current.ShopActive = key
		current.shopNew = &j
		current.shopTarget = shopTarget(a.config)
		return j, nil
	})
}
func (a *api) buyPulseCard(c fiber.Ctx, itemID, requestID, total string, quantity int) error {
	if material, ok := materialByID(itemID); ok {
		return a.buyPulseMaterial(c, material, requestID, total, quantity)
	}
	if quantity != 1 || total != "450" {
		return badProgress("Individual cards are generated one at a time for 450 STARL.")
	}
	card, ok := cardByID(itemID)
	if !ok || card.Legacy {
		return badProgress("Choose a PULSE card.")
	}
	owner := c.Locals("user").(user).ID
	key := shopKey(a.config, owner, requestID)
	if old, err := a.shop.store.shopOperation(key, owner); err != nil {
		return err
	} else if old != nil {
		if old.Kind != "pulse_buy" || old.ItemID != itemID {
			return badProgress("Request conflict.")
		}
		return c.JSON(fiber.Map{"operation": old})
	}
	wallet, err := a.shopWallet(c)
	if err != nil {
		return err
	}
	ctx, cancel := context.WithTimeout(c.Context(), 18*time.Second)
	defer cancel()
	if err = a.shop.client.pulsePreflight(ctx); err != nil {
		return failure(c, 503, "cards_unavailable", "Card sales are not open yet.")
	}
	block, err := a.shop.client.pulseBlock(ctx)
	if err != nil {
		return err
	}
	raw, err := a.shop.client.pulseRead(ctx, block, "salesEnabled()", "")
	if err != nil {
		return err
	}
	enabled, err := wordInt(raw, 0)
	if err != nil || enabled != 1 {
		return badProgress("PULSE card sales are not open yet.")
	}
	balance, err := a.shop.client.star.balance(ctx, wallet.Address)
	if err != nil {
		return err
	}
	if balance.Cmp(starlightRaw(450)) < 0 {
		return badProgress("Not enough Starlight in your wallet.")
	}
	rollScore, rollHeal, skill, err := rollCardTraits(5)
	if err != nil {
		return err
	}
	intent := pulseIntent{Request: pulseRequest{Kind: "buy", ItemID: itemID, Member: int(card.TokenID - 6)}, Score: rollScore, Recovery: rollHeal, Skill: skill}
	head, err := a.shop.client.star.p.head(ctx)
	if err != nil {
		return err
	}
	j := shopJob{Router: a.config.PulseRouter, Pulse: &intent, Key: key, Owner: owner, RequestID: requestID, Kind: "pulse_buy", ItemID: itemID, Wallet: strings.ToLower(wallet.Address), Quantity: 1, Status: "pending", Stage: "gas", FromBlock: head}
	return a.mutateProgress(c, func(p *progression, _ time.Time) (any, error) {
		prior, err := a.shop.store.shopOperation(key, owner)
		if err != nil {
			return nil, err
		}
		if prior != nil {
			if prior.Kind != "pulse_buy" || prior.ItemID != itemID {
				return nil, badProgress("Request conflict.")
			}
			return prior, nil
		}
		if p.ShopActive != "" {
			return nil, badProgress("Your previous item action is still processing.")
		}
		p.ShopActive = key
		p.shopNew = &j
		p.shopTarget = shopTarget(a.config)
		return j, nil
	})
}
func pulseActive(j shopJob) bool { return strings.HasPrefix(j.Kind, "pulse_") }

var errPulseState = errors.New("card state unavailable")

func (a *api) buyPulseMaterial(c fiber.Ctx, material cardMaterial, requestID, total string, quantity int) error {
	if quantity < 1 || quantity > 10 || total != fmt.Sprint(material.Price*quantity) {
		return badProgress("The price or quantity changed. Review this item again.")
	}
	owner := c.Locals("user").(user).ID
	key := shopKey(a.config, owner, requestID)
	if old, err := a.shop.store.shopOperation(key, owner); err != nil {
		return err
	} else if old != nil {
		if old.Kind != "pulse_material" || old.ItemID != material.ID || old.Quantity != quantity {
			return badProgress("Request conflict.")
		}
		return c.JSON(fiber.Map{"operation": old})
	}
	wallet, err := a.shopWallet(c)
	if err != nil {
		return err
	}
	ctx, cancel := context.WithTimeout(c.Context(), 18*time.Second)
	defer cancel()
	block, err := a.shop.client.pulseBlock(ctx)
	if err != nil {
		return err
	}
	raw, err := a.shop.client.pulseRead(ctx, block, "salesEnabled()", "")
	if err != nil {
		return err
	}
	on, err := wordInt(raw, 0)
	if err != nil || on != 1 {
		return badProgress("Refinement item sales are not open yet.")
	}
	raw, err = a.shop.client.pulseRead(ctx, block, "materialStock(uint256)", hexWord(material.TokenID))
	if err != nil {
		return err
	}
	stock, err := wordInt(raw, 0)
	if err != nil || stock < int64(quantity) {
		return badProgress("This refinement item is sold out.")
	}
	balance, err := a.shop.client.star.balance(ctx, wallet.Address)
	if err != nil {
		return err
	}
	if balance.Cmp(starlightRaw(int64(material.Price*quantity))) < 0 {
		return badProgress("Not enough Starlight in your wallet.")
	}
	head, err := a.shop.client.star.p.head(ctx)
	if err != nil {
		return err
	}
	j := shopJob{Router: a.config.PulseRouter, Pulse: &pulseIntent{Request: pulseRequest{Kind: "material", ItemID: material.ID}}, Key: key, Owner: owner, RequestID: requestID, Kind: "pulse_material", ItemID: material.ID, Wallet: strings.ToLower(wallet.Address), Quantity: quantity, Status: "pending", Stage: "gas", FromBlock: head}
	return a.mutateProgress(c, func(p *progression, _ time.Time) (any, error) {
		if prior, err := a.shop.store.shopOperation(key, owner); err != nil {
			return nil, err
		} else if prior != nil {
			if prior.Kind != "pulse_material" || prior.ItemID != material.ID || prior.Quantity != quantity {
				return nil, badProgress("Request conflict.")
			}
			return prior, nil
		}
		if p.ShopActive != "" {
			return nil, badProgress("Your previous item action is still processing.")
		}
		p.ShopActive = key
		p.shopNew = &j
		p.shopTarget = shopTarget(a.config)
		return j, nil
	})
}
