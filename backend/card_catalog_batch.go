package main

import (
	"context"
	"encoding/hex"
	"errors"
	"fmt"
	"github.com/gofiber/fiber/v3"
	"strings"
)

// Read all release allocation counters at one confirmed block with one RPC.
// Multicall3 is deployed at this address on Elysium; aggregate reverts if any
// subcall fails, so unavailable stock is never presented as an empty balance.
func (c *shopClient) releaseCatalog(ctx context.Context, block int64) ([]any, error) {
	calls := []string{selector("salesEnabled()")}
	for i := 0; i < 45; i++ {
		calls = append(calls, selector("initialLESold(uint256)")+hexWord(int64(i)))
	}
	for _, material := range cardMaterials {
		calls = append(calls, selector("materialStock(uint256)")+hexWord(material.TokenID))
	}
	array := hexWord(int64(len(calls)))
	tail := ""
	offset := len(calls) * 32
	for _, call := range calls {
		raw, e := hex.DecodeString(strings.TrimPrefix(call, "0x"))
		if e != nil {
			return nil, e
		}
		tuple := addressWord(c.cfg.PulseRouter) + hexWord(64) + hexWord(int64(len(raw))) + hex.EncodeToString(raw)
		tuple += strings.Repeat("0", (64-len(tuple)%64)%64)
		array += hexWord(int64(offset))
		tail += tuple
		offset += len(tuple) / 2
	}
	data := selector("aggregate((address,bytes)[])") + hexWord(32) + array + tail
	var response string
	err := c.star.p.rpc(ctx, "eth_call", []any{map[string]string{"to": "0xcA11bde05977b3631167028862bE2a173976CA11", "data": data}, fmt.Sprintf("0x%x", block)}, &response)
	if err != nil {
		return nil, err
	}
	values, err := decodeCatalogAggregate(response, len(calls))
	if err != nil {
		return nil, err
	}
	products := []any{}
	energy, err := catalogProduct(ctx, c, block, values[0])
	if err != nil {
		return nil, err
	}
	products = append(products, energy)
	for index, card := range allMemberCards() {
		client, err := c.forItem(card.ID)
		if err != nil {
			return nil, err
		}
		product := client.itemView()
		sold := values[index+1]
		if sold < 0 || sold > 50 {
			return nil, errors.New("invalid release allocation")
		}
		product["price"], product["currency"], product["price_raw"] = 450, "STARL", starlightRaw(450).String()
		product["initial_allocation"], product["initial_sold"], product["stock"] = 50, sold, 50-sold
		product["artwork_may_be_reissued"], product["admin_issuance_outside_allocation"] = true, true
		product["available"], product["max_quantity"], product["generation"] = values[0] == 1 && sold < 50, 1, "individual_randomized"
		delete(product, "token_id")
		product["drop_rates"] = map[string]any{"rarity": "LE", "score_percent_values": []int{7, 8, 9, 10}, "recovery_rating_values": []int{7, 8, 9, 10}, "each_stat_value_chance_bp": 2500, "skill_chance_bp": 10000, "skill_ids": []int{1, 2, 3, 4, 5, 6}, "skill_weights": []int{1, 1, 1, 1, 1, 1}}
		products = append(products, product)
	}
	for index, material := range cardMaterials {
		client, err := c.forItem(material.ID)
		if err != nil {
			return nil, err
		}
		product := client.itemView()
		stock := values[46+index]
		if stock < 0 {
			return nil, errors.New("invalid material stock")
		}
		product["price"], product["currency"], product["price_raw"] = material.Price, "STARL", starlightRaw(int64(material.Price)).String()
		product["stock"], product["available"], product["max_quantity"] = stock, values[0] == 1 && stock > 0, 10
		products = append(products, product)
	}
	return products, nil
}

func decodeCatalogAggregate(raw string, count int) ([]int64, error) {
	offset, err := wordInt(raw, 1)
	if err != nil || offset < 64 || offset%32 != 0 || offset > int64(len(raw)/2-2) {
		return nil, errors.New("invalid catalog aggregate")
	}
	start := int(offset / 32)
	n, err := wordInt(raw, start)
	if err != nil || n != int64(count) {
		return nil, errors.New("invalid catalog aggregate length")
	}
	values := make([]int64, count)
	for i := range values {
		relative, e := wordInt(raw, start+1+i)
		if e != nil || relative < int64(count*32) || relative%32 != 0 || relative > int64(len(raw)/2) {
			return nil, errors.New("invalid aggregate offset")
		}
		at := start + 1 + int(relative/32)
		length, e := wordInt(raw, at)
		if e != nil || length != 32 {
			return nil, errors.New("invalid catalog value length")
		}
		values[i], e = wordInt(raw, at+1)
		if e != nil {
			return nil, e
		}
	}
	return values, nil
}

func releaseCatalogResponse(c fiber.Ctx, products []any) error {
	available := false
	for _, product := range products {
		if product.(fiber.Map)["available"] == true {
			available = true
		}
	}
	return c.JSON(fiber.Map{"catalog": products, "checkout_enabled": available})
}
