package main

import (
	"context"
	"errors"
	"fmt"
	"github.com/gofiber/fiber/v3"
	"strings"
	"time"
)

type memberCard struct {
	ID, Member, Accent string
	TokenID            int64
	Legacy             bool
}

var memberCards = []memberCard{
	{"scene_01", "Woni", "c7bbff", 6, false},
	{"scene_02", "Liv", "e0b3cf", 7, false},
	{"scene_03", "Minami", "a9cbea", 8, false},
	{"scene_04", "May", "c8b2e6", 9, false},
	{"scene_05", "Zena", "b1d6d4", 10, false},
}

func cardByID(id string) (memberCard, bool) {
	for _, card := range memberCards {
		if card.ID == id {
			return card, true
		}
		if "legacy_"+card.ID == id {
			card.ID = id
			card.TokenID -= 5
			card.Legacy = true
			return card, true
		}
	}
	return memberCard{}, false
}
func normalizedItemID(id string) string {
	if id == "" {
		return "energy_drink"
	}
	return id
}
func (c *shopClient) isCard() bool { _, ok := cardByID(c.itemID); return ok }
func (c *shopClient) price() int {
	if material, ok := materialByID(c.itemID); ok {
		return material.Price
	}
	if c.isCard() {
		return 450
	}
	return drinkPrice
}
func (c *shopClient) firstID(id int64) int64 {
	if card, ok := cardByID(c.itemID); ok && card.Legacy {
		return 1
	}
	if c.isCard() || c.isMaterial() {
		return 6
	}
	return id
}
func (c *shopClient) forItem(id string) (*shopClient, error) {
	if normalizedItemID(id) == "energy_drink" {
		return c, nil
	}
	card, cardOK := cardByID(id)
	material, matOK := materialByID(id)
	if (!cardOK && !matOK) || !c.cfg.CardsEnabled {
		return nil, errors.New("card_unavailable")
	}
	clone := *c
	clone.itemID = id
	clone.cfg.ShopRouter = c.cfg.CardsRouter
	tid := material.TokenID
	if cardOK {
		tid = card.TokenID
		if card.Legacy {
			if c.cfg.LegacyCardsRouter == "" {
				return nil, errors.New("legacy_card_unavailable")
			}
			clone.cfg.ShopRouter = c.cfg.LegacyCardsRouter
		}
	}
	clone.cfg.ShopTokenID, clone.cfg.ShopListingID = tid, tid
	return &clone, nil
}
func (c *shopClient) itemIDs() []string {
	ids := []string{"energy_drink"}
	if c.cfg.CardsEnabled {
		if c.cfg.PulseRouter == "" && strings.EqualFold(c.cfg.CardsRouter, c.cfg.LegacyCardsRouter) {
			for _, card := range memberCards {
				ids = append(ids, "legacy_"+card.ID)
			}
			return ids
		}
		for _, card := range memberCards {
			ids = append(ids, card.ID)
		}
		for _, material := range cardMaterials {
			ids = append(ids, material.ID)
		}
	}
	return ids
}
func (c *shopClient) inventoryIDs() []string {
	ids := c.itemIDs()
	if c.cfg.PulseRouter != "" {
		ids = []string{"energy_drink"}
		for _, material := range cardMaterials {
			ids = append(ids, material.ID)
		}
	}
	if c.cfg.CardsEnabled && c.cfg.LegacyCardsRouter != "" {
		for _, card := range memberCards {
			found := false
			for _, id := range ids {
				if id == "legacy_"+card.ID {
					found = true
				}
			}
			if !found {
				ids = append(ids, "legacy_"+card.ID)
			}
		}
	}
	return ids
}
func (c *shopClient) isMaterial() bool { _, ok := materialByID(c.itemID); return ok }
func (c *shopClient) legacy() bool     { card, ok := cardByID(c.itemID); return ok && card.Legacy }
func (c *shopClient) itemView() fiber.Map {
	if material, ok := materialByID(c.itemID); ok {
		return fiber.Map{"id": material.ID, "name": material.Name, "category": "upgrades", "training_xp": material.XP, "token_id": fmt.Sprint(material.TokenID)}
	}
	if card, ok := cardByID(c.itemID); ok {
		series, rarity := "PULSE", "LE"
		if card.Legacy {
			series, rarity = "First Scene", "SR"
		}
		return fiber.Map{"id": card.ID, "name": card.Member + " · " + series, "member": card.Member, "category": "cards", "rarity": rarity, "series": series, "legacy": card.Legacy, "token_id": fmt.Sprint(card.TokenID)}
	}
	return fiber.Map{"id": "energy_drink", "name": "Energy Drink", "category": "energy", "energy": 5, "token_id": fmt.Sprint(c.cfg.ShopTokenID)}
}

// Equipment is a persisted cosmetic choice. Ownership is checked against a
// confirmed chain block at equip time and every Inventory refresh.
func (a *api) equipMemberCard(c fiber.Ctx) error {
	if a.shop == nil || !a.config.CardsEnabled {
		return failure(c, 503, "cards_disabled", "Cards are not available yet.")
	}
	var body struct {
		ItemID string `json:"item_id"`
	}
	if err := decodeProgressBody(c, &body); err != nil {
		return err
	}
	if body.ItemID != "" {
		client, err := a.shop.client.forItem(body.ItemID)
		if err != nil || !client.isCard() {
			return failure(c, 400, "invalid_card", "Choose a member card.")
		}
		wallet, err := a.shopWallet(c)
		if err != nil {
			return failure(c, 409, "wallet_pending", "Your wallet is getting ready.")
		}
		ctx, cancel := context.WithTimeout(c.Context(), 6*time.Second)
		defer cancel()
		owned, err := client.owned(ctx, wallet.Address)
		if err != nil {
			return failure(c, 503, "inventory_unavailable", "Your collection is updating. Please try again.")
		}
		if owned < 1 {
			return failure(c, 409, "card_not_owned", "Collect this card before equipping it.")
		}
	}
	return a.mutateProgress(c, func(p *progression, _ time.Time) (any, error) {
		p.EquippedCard = body.ItemID
		return fiber.Map{"equipped_card": body.ItemID}, nil
	})
}

// A stale preference must never advertise a card moved out of the wallet.
func (a *api) verifiedMemberCard(ctx context.Context, owner, id string) string {
	ctx, cancel := context.WithTimeout(ctx, 6*time.Second)
	defer cancel()
	if a.shop == nil || !a.config.CardsEnabled || id == "" {
		return ""
	}
	client, err := a.shop.client.forItem(id)
	if err != nil || !client.isCard() {
		return ""
	}
	wallet, err := a.shop.store.ReadWallet(owner, a.config.EngineProjectID, a.config.EngineURL)
	if err != nil || wallet.Status != "ready" {
		return ""
	}
	owned, err := client.owned(ctx, wallet.Address)
	if err != nil || owned < 1 {
		return ""
	}
	return id
}
