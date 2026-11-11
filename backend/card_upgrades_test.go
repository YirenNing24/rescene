package main

import (
	"encoding/json"
	"testing"
)

func TestCardLevelOddsAndHundredLevelBoundary(t *testing.T) {
	prior := 10001
	for level := 1; level < cardMaxLevel; level++ {
		chance := cardLevelChance(level)
		if chance > prior || chance < 2000 || chance > 10000 {
			t.Fatalf("invalid odds at level %d: %d", level, chance)
		}
		prior = chance
		cost := cardLevelCost(level)
		for _, roll := range []int{0, chance - 1, chance, 9999} {
			if roll >= 10000 {
				continue
			}
			result, err := resolveCardUpgrade(level, cost, 100, roll)
			if err != nil || !result.Attempted || result.Succeeded != (roll < chance) {
				t.Fatalf("incorrect result for level %d, roll %d: %+v %v", level, roll, result, err)
			}
			if result.Succeeded {
				if result.After != level+1 || result.XP != 100 {
					t.Fatal("success did not advance exactly one level and spend XP")
				}
			} else if result.After != level || result.XP != cost+100 {
				t.Fatal("failure changed level or lost XP")
			}
		}
	}
	for _, level := range []int{-1, 0, 100, 101} {
		if cardLevelChance(level) != 0 || cardLevelCost(level) != 0 {
			t.Fatal("invalid or maximum level has an upgrade")
		}
		if _, err := resolveCardUpgrade(level, 1000, 100, 0); err == nil {
			t.Fatal("invalid or max level accepted")
		}
	}
	if cardMaxLevel != 100 || cardLevelChance(9) != 10000 || cardLevelChance(10) != 9000 || cardLevelChance(90) != 2000 {
		t.Fatal("target-level odds boundaries changed")
	}
}

func TestCardXPAloneDoesNotSetLevel(t *testing.T) {
	p := pulseCard{Level: 1, XP: 500000}
	if p.loadout().Level != 1 {
		t.Fatal("XP silently bypassed upgrade rolls")
	}
	result, err := resolveCardUpgrade(99, 0, 100, 9999)
	if err != nil || result.Attempted || result.After != 99 || result.XP != 100 {
		t.Fatal("insufficient XP attempted a level")
	}
	result, err = resolveCardUpgrade(99, cardMaxXP, 450, 0)
	if err != nil || result.After != 100 || result.XP != cardMaxXP-cardLevelCost(99) {
		t.Fatal("max-level final success or XP cap incorrect")
	}
}

func TestUpgradeRollIsDurableAndPrivate(t *testing.T) {
	j := shopJob{Kind: "enhance", UpgradeRoll: 8672, LevelBefore: 87, SuccessChance: 2500}
	stored, err := decodeShopJob(encodeShopJob(j))
	if err != nil || stored.UpgradeRoll != j.UpgradeRoll || stored.LevelBefore != j.LevelBefore {
		t.Fatal("worker restart lost the original roll")
	}
	public, err := json.Marshal(j)
	if err != nil {
		t.Fatal(err)
	}
	var view map[string]any
	if err = json.Unmarshal(public, &view); err != nil {
		t.Fatal(err)
	}
	if len(view) == 0 || view["UpgradeRoll"] != nil || view["upgrade_roll"] != nil {
		t.Fatal("private roll leaked to client")
	}
	for range 100 {
		roll, err := cardUpgradeRoll()
		if err != nil || roll < 0 || roll >= 10000 {
			t.Fatal("invalid secure roll")
		}
	}
}

func TestSacrificeCompatibilityAndGuaranteedStars(t *testing.T) {
	rarities := []cardRarity{cardCommon, cardUncommon, cardRare, cardEpic, cardLegendary, cardLE}
	for _, target := range rarities {
		for _, donor := range rarities {
			compatible := target == donor || target == cardLE && donor == cardLegendary || target == cardLegendary && donor == cardLE
			if compatibleSacrifice(target, donor) != compatible {
				t.Fatal("rarity compatibility incorrect", target, donor)
			}
			if compatible {
				for stars := 1; stars < 5; stars++ {
					after, progress, wasted := pulseStarPreview(stars, 0, stars*2)
					if after != stars+1 || progress != 0 || wasted != 0 {
						t.Fatal("star costs must be 2,4,6,8 with guaranteed progression")
					}
				}
			}
		}
	}
	if compatibleSacrifice("", "") || compatibleSacrifice("Fake", "Fake") {
		t.Fatal("unknown rarity accepted")
	}
}
