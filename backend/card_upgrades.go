package main

import (
	"crypto/rand"
	"errors"
	"math/big"
)

// Probabilities are basis points. A roll is sampled once when the durable
// operation is created, never by the client or again in the delivery worker.
func cardUpgradeRoll() (int, error) {
	roll, err := rand.Int(rand.Reader, big.NewInt(10000))
	if err != nil {
		return 0, err
	}
	return int(roll.Int64()), nil
}

func cardLevelChance(level int) int {
	if level < 1 || level >= cardMaxLevel {
		return 0
	}
	// Chance is based on the target level, with a 20% floor at 91–100.
	target := level + 1
	return [...]int{10000, 9000, 8000, 7000, 6000, 5000, 4000, 3000, 2500, 2000}[(target-1)/10]
}

func cardLevelCost(level int) int {
	if level < 1 || level >= cardMaxLevel {
		return 0
	}
	return 20 + (level-1)*5
}

type cardUpgradeResult struct {
	Before, After int
	XP, AppliedXP int
	Chance        int
	Attempted     bool
	Succeeded     bool
}

// Each consumed bundle grants its advertised XP and can attempt ONE level.
// If the attempt fails, all XP is retained, including that bundle's XP.
// Only success spends the level's XP cost. Neither outcome rerolls traits.
func resolveCardUpgrade(level, xp, materialXP, roll int) (cardUpgradeResult, error) {
	if level < 1 || level >= cardMaxLevel || xp < 0 || xp > cardMaxXP || materialXP <= 0 || roll < 0 || roll >= 10000 {
		return cardUpgradeResult{}, errors.New("invalid card upgrade")
	}
	afterXP := min(cardMaxXP, xp+materialXP)
	result := cardUpgradeResult{Before: level, After: level, XP: afterXP, AppliedXP: afterXP - xp, Chance: cardLevelChance(level)}
	if afterXP < cardLevelCost(level) {
		return result, nil
	}
	result.Attempted = true
	if roll < result.Chance {
		result.Succeeded = true
		result.After++
		result.XP -= cardLevelCost(level)
	}
	return result, nil
}

type cardRarity string

const (
	cardCommon    cardRarity = "Common"
	cardUncommon  cardRarity = "Uncommon"
	cardRare      cardRarity = "Rare"
	cardEpic      cardRarity = "Epic"
	cardLegendary cardRarity = "Legendary"
	cardLE        cardRarity = "LE"
	cardMaxStars             = 5
)

func compatibleSacrifice(target, donor cardRarity) bool {
	switch target {
	case cardLE, cardLegendary:
		return donor == cardLE || donor == cardLegendary
	case cardCommon, cardUncommon, cardRare, cardEpic:
		return target == donor
	default:
		return false
	}
}
