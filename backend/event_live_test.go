package main

// Opt-in end-to-end test for the deployed testnet event, using a disposable
// account and a server-verified input replay. Ordinary test suites skip it.
import (
	"bytes"
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"testing"
	"time"
)

func TestLiveEventRewardDelivery(t *testing.T) {
	base := os.Getenv("EVENT_LIVE_BASE_URL")
	if base == "" {
		t.Skip("set EVENT_LIVE_BASE_URL for testnet verification")
	}
	if time.Now().Before(pulseEventStart) || !time.Now().Before(pulseEventEnd) {
		t.Skip("event is not active")
	}
	raw := make([]byte, 16)
	if _, err := rand.Read(raw); err != nil {
		t.Fatal(err)
	}
	username := "eventqa_" + hex.EncodeToString(raw[:4])
	password := hex.EncodeToString(raw)
	path := filepath.Join("data", "vps-deployment", "event-qa-private.json")
	_ = os.MkdirAll(filepath.Dir(path), 0700)
	saved, _ := json.Marshal(creds(username, password))
	if err := os.WriteFile(path, saved, 0600); err != nil {
		t.Fatal(err)
	}
	client := &http.Client{Timeout: 30 * time.Second}
	token := ""
	call := func(method, path string, body any) (int, map[string]any) {
		var payload io.Reader
		if body != nil {
			b, err := json.Marshal(body)
			if err != nil {
				t.Fatal(err)
			}
			payload = bytes.NewReader(b)
		}
		req, err := http.NewRequest(method, base+path, payload)
		if err != nil {
			t.Fatal(err)
		}
		req.Header.Set("Content-Type", "application/json")
		if token != "" {
			req.Header.Set("Authorization", "Bearer "+token)
		}
		res, err := client.Do(req)
		if err != nil {
			t.Fatal(err)
		}
		defer res.Body.Close()
		var out map[string]any
		if err = json.NewDecoder(res.Body).Decode(&out); err != nil {
			t.Fatalf("invalid response to %s: %v", path, err)
		}
		return res.StatusCode, out
	}
	status, data := call("POST", "/api/v1/auth/register", creds(username, password))
	if status != 201 {
		t.Fatalf("register status %d", status)
	}
	token, _ = data["access_token"].(string)
	if token == "" {
		t.Fatal("missing access token")
	}
	t.Log("Created a dedicated test account; waiting for its managed wallet.")
	ready := false
	for deadline := time.Now().Add(3 * time.Minute); time.Now().Before(deadline); time.Sleep(4 * time.Second) {
		status, data = call("GET", "/api/v1/wallet", nil)
		wallet, _ := data["wallet"].(map[string]any)
		if status == 200 && wallet["status"] == "ready" {
			ready = true
			break
		}
	}
	if !ready {
		t.Fatal("test wallet was not provisioned")
	}
	chart := rewardCharts[pulseSongs[0]+"/Easy"]
	status, data = call("POST", "/api/v1/runs", map[string]any{"song_id": chart.SongID, "difficulty": chart.Difficulty, "revision": chart.Revision, "replay_version": replayVersion})
	if status != 200 {
		t.Fatalf("start returned %d: %v", status, data["error"])
	}
	reward, _ := data["reward"].(map[string]any)
	run, _ := reward["id"].(string)
	if run == "" {
		t.Fatal("missing run ID")
	}
	t.Logf("Started %s; waiting for the actual song duration.", chart.Title)
	time.Sleep(time.Duration(chart.Duration+3) * time.Second)
	status, data = call("POST", "/api/v1/runs/"+run+"/complete", perfectResult(chart, run))
	if status != 200 {
		t.Fatalf("completion returned %d: %v", status, data["error"])
	}
	status, data = call("POST", "/api/v1/events/"+pulseEventID+"/missions/harmony/claim", map[string]any{})
	if status != 200 {
		t.Fatalf("claim returned %d: %v", status, data["error"])
	}
	result, _ := data["reward"].(map[string]any)
	if result["shards"] != float64(1) || result["already_claimed"] == true {
		t.Fatal("wrong reward")
	}
	status, data = call("POST", "/api/v1/events/"+pulseEventID+"/missions/harmony/claim", map[string]any{})
	result, _ = data["reward"].(map[string]any)
	if status != 200 || result["already_claimed"] != true {
		t.Fatal("duplicate claim did not return the existing result")
	}
	t.Log("Claimed one bundle; waiting for the confirmed ERC-1155 delivery.")
	for deadline := time.Now().Add(4 * time.Minute); time.Now().Before(deadline); time.Sleep(5 * time.Second) {
		status, data = call("GET", "/api/v1/inventory", nil)
		if status != 200 {
			continue
		}
		items, _ := data["items"].([]any)
		for _, value := range items {
			item, _ := value.(map[string]any)
			if item["id"] == "prism_shards" {
				quantity, _ := item["quantity"].(float64)
				if quantity == 1 {
					fmt.Println("Verified one confirmed Prism Shards bundle in test inventory; duplicate claim was harmless.")
					return
				}
				if quantity > 1 {
					t.Fatalf("unexpected duplicate item delivery: %.0f", quantity)
				}
			}
		}
	}
	t.Fatal("refinement item did not reach inventory before timeout")
}
