package main

import (
	"time"

	"github.com/gofiber/fiber/v3"
)

const energyCap = 100
const energyInterval = 30 * time.Minute
const energyRunCost = 1

type energyProgress struct {
	Current int   `json:"current"`
	NextAt  int64 `json:"next_at"` // Server Unix milliseconds; zero while full.
}

func (p *progression) spendEnergy(now time.Time) error {
	p.recoverEnergy(now)
	if p.Energy.Current < energyRunCost {
		return progressError{409, "Not enough energy. Recover 1 energy every 30 minutes. Please wait for your next energy."}
	}
	if p.Energy.Current == energyCap {
		p.Energy.NextAt = now.UnixMilli() + energyInterval.Milliseconds()
	}
	p.Energy.Current -= energyRunCost
	return nil
}

func (p *progression) recoverEnergy(now time.Time) {
	// One-time capacity expansion refill, persisted with normal progression CAS.
	if p.EnergyCapacity < energyCap {
		p.Energy = &energyProgress{Current: energyCap}
		p.EnergyCapacity = energyCap
	}
	if p.Energy == nil {
		p.Energy = &energyProgress{Current: energyCap}
	}
	e := p.Energy
	e.Current = max(0, min(energyCap, e.Current))
	if e.Current == energyCap {
		e.NextAt = 0
		return
	}
	interval := energyInterval.Milliseconds()
	if e.NextAt <= 0 {
		e.NextAt = now.UnixMilli() + interval
		return
	}
	if now.UnixMilli() < e.NextAt {
		return
	}
	gained := 1 + (now.UnixMilli()-e.NextAt)/interval
	if gained >= int64(energyCap-e.Current) {
		e.Current = energyCap
		e.NextAt = 0
		return
	}
	e.Current += int(gained)
	e.NextAt += gained * interval
}

func energyView(p progression, now time.Time) fiber.Map {
	view := fiber.Map{"current": p.Energy.Current, "max": energyCap, "run_cost": energyRunCost, "recovery_seconds": int(energyInterval.Seconds()), "next_recovery_at": nil, "next_recovery_in_seconds": 0, "full_at": nil}
	if p.Energy.NextAt > 0 {
		view["next_recovery_at"] = time.UnixMilli(p.Energy.NextAt).UTC().Format(time.RFC3339Nano)
		view["next_recovery_in_seconds"] = max(int64(0), (p.Energy.NextAt-now.UnixMilli()+999)/1000)
		view["full_at"] = time.UnixMilli(p.Energy.NextAt + int64(energyCap-p.Energy.Current-1)*energyInterval.Milliseconds()).UTC().Format(time.RFC3339Nano)
	}
	return view
}
