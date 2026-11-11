package main

import (
	"context"
	"encoding/json"
	"errors"
	"regexp"
	"time"

	"github.com/gofiber/fiber/v3"
	"github.com/redis/go-redis/v9"
)

var streamCursor = regexp.MustCompile(`^[0-9]{1,20}-[0-9]{1,20}$`)

type socialEvent struct {
	ID   string `json:"id"`
	Kind string `json:"kind"`
	Peer string `json:"peer_id"`
	At   int64  `json:"at"`
}

func (s *graphStore) eventKey(owner string) string {
	return "rescene:" + s.graph.Id + ":social:" + owner
}
func (a *api) notifyPlayer(owner, kind, peer string) {
	s, ok := a.store.(*graphStore)
	if !ok {
		return
	}
	ctx, cancel := context.WithTimeout(context.Background(), time.Second)
	defer cancel()
	key := s.eventKey(owner)
	_ = s.db.Conn.XAdd(ctx, &redis.XAddArgs{Stream: key, MaxLen: 200, Approx: true, Values: map[string]any{"kind": kind, "peer": peer, "at": time.Now().UnixMilli()}}).Err()
	_ = s.db.Conn.Expire(ctx, key, 48*time.Hour).Err()
}

// Bounded authenticated long polling. Stream cursors survive reconnects and Redis
// works across API processes. Message bodies are fetched through private chat APIs.
func (a *api) socialEvents(c fiber.Ctx) error {
	s, ok := a.store.(*graphStore)
	if !ok {
		return fiber.ErrServiceUnavailable
	}
	owner := c.Locals("user").(user).ID
	cursor := c.Query("cursor")
	ctx, cancel := context.WithTimeout(context.Background(), 9*time.Second)
	defer cancel()
	key := s.eventKey(owner)
	if cursor == "" {
		rows, e := s.db.Conn.XRevRangeN(ctx, key, "+", "-", 1).Result()
		if e != nil {
			return e
		}
		cursor = "0-0"
		if len(rows) > 0 {
			cursor = rows[0].ID
		}
		return c.JSON(fiber.Map{"cursor": cursor, "events": []socialEvent{}})
	}
	if !streamCursor.MatchString(cursor) {
		return fiber.ErrBadRequest
	}
	// Permit one concurrent foreground connection per device. Each request
	// owns a unique lease; a crash cannot permanently occupy a slot.
	device := c.Query("device", "main")
	if device != "main" && !validHex(device, 16) {
		return fiber.ErrBadRequest
	}
	leaseKey := key + ":poll:" + device
	lease, err := s.db.Conn.SetNX(ctx, leaseKey, true, 10*time.Second).Result()
	if err != nil {
		return err
	}
	if !lease {
		return failure(c, 429, "poll_active", "Another event request is active.")
	}
	defer s.db.Conn.Del(context.Background(), leaseKey)
	rows, err := s.db.Conn.XRead(ctx, &redis.XReadArgs{Streams: []string{key, cursor}, Count: 50, Block: 8 * time.Second}).Result()
	if err != nil && !errors.Is(err, redis.Nil) {
		return err
	}
	out := []socialEvent{}
	for _, stream := range rows {
		for _, v := range stream.Messages {
			raw, _ := json.Marshal(v.Values)
			var fields struct {
				Kind string      `json:"kind"`
				Peer string      `json:"peer"`
				At   json.Number `json:"at"`
			}
			_ = json.Unmarshal(raw, &fields)
			at, _ := fields.At.Int64()
			if at == 0 {
				if text, ok := v.Values["at"].(string); ok {
					n := json.Number(text)
					at, _ = n.Int64()
				}
			}
			out = append(out, socialEvent{v.ID, fields.Kind, fields.Peer, at})
			cursor = v.ID
		}
	}
	return c.JSON(fiber.Map{"cursor": cursor, "events": out})
}
func (a *api) socialTyping(c fiber.Ctx) error {
	s, ok := a.store.(socialStore)
	if !ok {
		return fiber.ErrServiceUnavailable
	}
	owner := c.Locals("user").(user).ID
	peer := c.Params("id")
	if !validHex(peer, 16) || owner == peer {
		return fiber.ErrBadRequest
	}
	peers, e := s.SocialPlayers(owner, "peer", "", "", peer, false, 1)
	if e != nil {
		return e
	}
	if len(peers) == 0 || !peers[0].CanChat {
		return fiber.ErrForbidden
	}
	a.notifyPlayer(peer, "typing", owner)
	return c.JSON(fiber.Map{"ok": true})
}
