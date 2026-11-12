package main

import (
	_ "embed"
	"encoding/json"
	"fmt"
	"strings"
)

// Numeric release identities and artwork slugs are shared with the contract and clients.
type cardRelease struct {
	Number int    `json:"number"`
	SetID  string `json:"set_id"`
	Name   string `json:"name"`
	Slug   string `json:"slug"`
}

//go:embed card_releases.json
var cardReleasesJSON []byte
var cardReleases = func() []cardRelease {
	var result []cardRelease
	if json.Unmarshal(cardReleasesJSON, &result) != nil || len(result) != 9 {
		panic("invalid card releases")
	}
	for i, r := range result {
		if r.Number != i+1 {
			panic("invalid card release numbering")
		}
	}
	return result
}()

func releaseNumber(setID string) int {
	for _, r := range cardReleases {
		if r.SetID == setID {
			return r.Number
		}
	}
	return 0
}
func releaseByNumber(number int) cardRelease {
	if number < 1 || number > len(cardReleases) {
		return cardRelease{}
	}
	return cardReleases[number-1]
}
func releaseTemplate(number, member int) string {
	if number == 1 {
		return fmt.Sprintf("scene_%02d", member+1)
	}
	return fmt.Sprintf("le_%s_%02d", strings.ReplaceAll(releaseByNumber(number).Slug, "-", "_"), member+1)
}
func allMemberCards() []memberCard {
	result := append([]memberCard{}, memberCards...)
	for _, release := range cardReleases[1:] {
		for member, base := range memberCards {
			result = append(result, memberCard{releaseTemplate(release.Number, member), base.Member, base.Accent, int64(6 + (release.Number-1)*5 + member), false})
		}
	}
	return result
}
func (c *shopClient) cardsForSale() []memberCard {
	if c.cfg.CardReleases {
		return allMemberCards()
	}
	return memberCards
}
func cardReleaseFor(card memberCard) cardRelease { return releaseByNumber(int((card.TokenID-6)/5) + 1) }
