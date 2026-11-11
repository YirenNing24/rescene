package main

import (
	"time"

	"github.com/gofiber/fiber/v3"
)

type loginReward struct {
	Day       int `json:"day"`
	XP        int `json:"xp"`
	Starlight int `json:"starlight"`
}

var loginRewards = [...]loginReward{
	{1, 50, 30}, {2, 60, 40}, {3, 75, 50}, {4, 90, 60},
	{5, 100, 75}, {6, 125, 100}, {7, 200, 200},
}

type loginReceipt struct {
	loginReward
	Date           string   `json:"date"`
	LevelBefore    int      `json:"level_before"`
	LevelAfter     int      `json:"level_after"`
	Unlocks        []string `json:"unlocks"`
	AlreadyClaimed bool     `json:"already_claimed"`
}

type loginProgress struct {
	// Completed persists across missed days; Day 7 starts a new cycle tomorrow.
	Completed int          `json:"completed"`
	Last      loginReceipt `json:"last"`
}

func loginView(p loginProgress, now time.Time) fiber.Map {
	today := now.UTC().Format("2006-01-02")
	claimed := p.Last.Date >= today
	completed := p.Completed
	if completed == 7 && !claimed {
		completed = 0
	}
	return fiber.Map{"date": today, "completed": completed, "next_day": min(completed+1, 7), "claimed_today": claimed, "rewards": loginRewards[:]}
}

// Both the server date and expected calendar day bind retries to one reward.
// mutateProgress commits the claim and balances in the same FalkorDB CAS write.
func applyLoginClaim(p *progression, now time.Time, date string, day int) (loginReceipt, error) {
	today := now.UTC().Format("2006-01-02")
	if date != today {
		return loginReceipt{}, badProgress("Daily gifts have reset. Refresh your calendar.")
	}
	if p.Login.Last.Date == today && p.Login.Last.Day == day {
		result := p.Login.Last
		result.AlreadyClaimed = true
		return result, nil
	}
	view := loginView(p.Login, now)
	if view["claimed_today"].(bool) {
		return loginReceipt{}, badProgress("Today's daily gift has already been claimed.")
	}
	if day < 1 || day > 7 || day != view["next_day"].(int) {
		return loginReceipt{}, badProgress("Refresh your calendar before claiming this gift.")
	}
	before, _, _ := levelFor(p.XP)
	prior := cosmetics(*p)
	reward := loginRewards[day-1]
	p.XP += int64(reward.XP)
	p.Starlight += int64(reward.Starlight)
	after, _, _ := levelFor(p.XP)
	unlocks := []string{}
	for i, item := range cosmetics(*p) {
		if item.Unlocked && !prior[i].Unlocked {
			unlocks = append(unlocks, item.Name)
		}
	}
	result := loginReceipt{loginReward: reward, Date: today, LevelBefore: before, LevelAfter: after, Unlocks: unlocks}
	p.Login = loginProgress{Completed: day, Last: result}
	return result, nil
}

func (a *api) claimDailyLogin(c fiber.Ctx) error {
	var body struct {
		Date string `json:"date"`
		Day  int    `json:"day"`
	}
	if err := decodeProgressBody(c, &body); err != nil {
		return err
	}
	return a.mutateProgress(c, func(p *progression, now time.Time) (any, error) {
		return applyLoginClaim(p, now, body.Date, body.Day)
	})
}
