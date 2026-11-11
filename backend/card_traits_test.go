package main

import "testing"

func TestRarityRollsUsePublishedStatRanges(t *testing.T) {
	expected := [6]rarityPolicy{{1, 2, 0}, {2, 3, 1000}, {3, 5, 2500}, {5, 7, 5000}, {7, 10, 8000}, {7, 10, 10000}}
	if rarityPolicies != expected {
		t.Fatal("rarity policies diverged from published ranges/chances")
	}
	for rarity, policy := range expected {
		for range 128 {
			score, recovery, skill, err := rollCardTraits(rarity)
			if err != nil || score < policy.Min*100 || score > policy.Max*100 || score%100 != 0 || recovery < policy.Min || recovery > policy.Max || skill < 0 || skill > 6 {
				t.Fatalf("invalid traits for rarity %d: score %d recovery %d skill %d: %v", rarity, score, recovery, skill, err)
			}
			if policy.SkillChance == 0 && skill != 0 || policy.SkillChance == 10000 && skill == 0 {
				t.Fatal("Common must have no skill; LE must have a skill")
			}
		}
	}
	for _, rarity := range []int{-1, 6, 100} {
		if _, _, _, err := rollCardTraits(rarity); err == nil {
			t.Fatal("invalid rarity accepted")
		}
	}
}
