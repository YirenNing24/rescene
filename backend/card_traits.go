package main

import "errors"

type rarityPolicy struct{ Min, Max, SkillChance int }

var rarityPolicies = [6]rarityPolicy{{1, 2, 0}, {2, 3, 1000}, {3, 5, 2500}, {5, 7, 5000}, {7, 10, 8000}, {7, 10, 10000}}

func rollCardTraits(rarity int) (score, recovery, skill int, err error) {
	if rarity < 0 || rarity >= len(rarityPolicies) {
		return 0, 0, 0, errors.New("invalid rarity")
	}
	policy := rarityPolicies[rarity]
	score, err = secureRange(policy.Min, policy.Max)
	if err != nil {
		return
	}
	score *= 100
	recovery, err = secureRange(policy.Min, policy.Max)
	if err != nil {
		return
	}
	var chance int
	chance, err = secureRange(0, 9999)
	if err != nil {
		return
	}
	if chance < policy.SkillChance {
		skill, err = secureRange(1, 6)
	}
	return
}
