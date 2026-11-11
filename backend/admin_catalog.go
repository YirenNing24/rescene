package main

import (
	"context"
	"github.com/gofiber/fiber/v3"
	"sync"
	"time"
)

func (s *adminSystem) catalog(c fiber.Ctx) error {
	if s.api.shop == nil {
		return c.JSON(fiber.Map{"rows": []any{}, "source": "Commerce is disabled in server configuration."})
	}
	ctx, cancel := context.WithTimeout(c.Context(), 12*time.Second)
	defer cancel()
	ids := s.api.shop.client.itemIDs()
	rows := make([]fiber.Map, len(ids))
	var wg sync.WaitGroup
	for i, id := range ids {
		wg.Add(1)
		go func(i int, id string) {
			defer wg.Done()
			client, e := s.api.shop.client.forItem(id)
			if e != nil {
				rows[i] = fiber.Map{"id": id, "status": "unavailable"}
				return
			}
			row := client.itemView()
			row["currency"] = "STARL"
			row["price"] = client.price()
			row["router"] = client.cfg.ShopRouter
			row["listing_id"] = client.cfg.ShopListingID
			listing, e := client.listing(ctx)
			if e != nil {
				row["status"] = "needs_review"
				row["error"] = e.Error()
				row["stock"] = nil
			} else {
				row["stock"] = listing.Stock
				row["status"] = "ready"
				row["starts_at"] = listing.Start * 1000
				row["ends_at"] = listing.End * 1000
				if listing.End <= time.Now().Unix() {
					row["status"] = "expired"
				}
			}
			if e = client.preflight(ctx); e != nil {
				row["status"] = "needs_review"
				row["router_error"] = e.Error()
			}
			rows[i] = row
		}(i, id)
	}
	wg.Wait()
	return c.JSON(fiber.Map{"rows": rows, "source": "Live chain stock and router checks. needs_review blocks safe checkout; catalog metadata cannot override immutable contracts.", "fresh_at": time.Now().UTC()})
}

func (s *adminSystem) rules(c fiber.Ctx) error {
	p := progression{}
	p.normalize(time.Now())
	levels := []fiber.Map{}
	var xp int64
	for level := 1; level <= 100; level++ {
		_, _, cost := levelFor(xp)
		levels = append(levels, fiber.Map{"level": level, "xp_floor": xp, "next_level_cost": cost})
		xp += cost
	}
	return c.JSON(fiber.Map{"energy": fiber.Map{"cap": energyCap, "run_cost": energyRunCost, "regeneration_minutes": energyInterval.Minutes(), "drink_refill": 5}, "missions": missions(p), "calendar": loginRewards[:], "levels": levels, "source": "Authoritative compiled game rules. Changing these values requires a compatible API and game release."})
}
