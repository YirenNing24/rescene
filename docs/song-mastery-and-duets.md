# Song mastery, score targets, and weekly duets

Each song has six account-owned milestones: clear Easy, Normal, Hard, and
Ultra Hard; clear at 90% accuracy; and full combo a difficulty. A verified
clear is required, including on paused (unranked) runs. Each milestone's XP and
STARL reward can be claimed once. The full-combo milestone also grants one
Prism Shards ×10 refinement bundle through the existing confirmed ERC-1155
reward queue. Completing all six goals on a song unlocks the Song Specialist
title. Current verified historical personal-best records are imported once;
prior attempts not represented by those records cannot be reconstructed.

A run ticket may contain a score target: the nearest higher current-chart best
from a mutual, unblocked friend, or the player's own verified best. The target
is pinned at run start and is informational; no score or judgment rules change.
The result screen displays the personal-best gap, change from the last local
attempt, and any team score bonus. Friend challenges opened from results carry
the song and difficulty into the existing invitation flow.

Weekly duets begin by inviting a mutual friend. Acceptance locks one pair for
that UTC week. Verified, unpaused clears from both friends contribute to goals;
up to five clears per player count for the clear goal. Each participant claims
each completed reward independently. The week starts Monday at 00:00 UTC and
rewards remain claimable for 48 hours after the week ends. Starts in the week
count if completed within the normal two-hour run expiry. Incomplete pending
invitations can be declined or cancelled.

The weekly spotlight rotates among PULSE, GLOW UP, lip bomb and SCENEDROME. Each
week contains two server-defined missions; the featured song rotates daily and
the week has a 48-hour reward-claim window. It runs alongside the existing
PULSE launch event, whose rules and rewards are unchanged.

Authenticated endpoints: `GET /api/v1/mastery/{song_id}`;
`POST /api/v1/mastery/{song_id}/{milestone_id}/claim` with `{}`;
`GET /api/v1/coop`; `POST /api/v1/coop/invite` with `player_id`;
`POST /api/v1/coop/{id}/action` with `accept`, `decline`, or `cancel`;
and `POST /api/v1/coop/{id}/claim` with `goal`. Reward mutations use the
progression CAS and durable reward queues; repeat claims do not pay twice.
