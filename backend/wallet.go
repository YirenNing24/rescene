package main

import (
	"bytes"
	"context"
	"crypto/rand"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"io"
	"log"
	"net/http"
	"regexp"
	"strings"
	"sync"
	"time"

	"github.com/gofiber/fiber/v3"
)

const walletAuthProvider = "rescene_password_v1"
const walletLease = 2 * time.Minute

var walletAddressPattern = regexp.MustCompile(`^0x[0-9a-fA-F]{40}$`)

// Only public wallet information crosses the game's API boundary.
type walletInfo struct {
	ID        string `json:"id,omitempty"`
	Address   string `json:"address,omitempty"`
	Status    string `json:"status"`
	Custody   string `json:"custody"`
	CreatedAt string `json:"created_at,omitempty"`
}
type engineWallet struct {
	ID            string `json:"id"`
	AppID         string `json:"appId"`
	UserID        string `json:"userId"`
	Address       string `json:"address"`
	AuthProvider  string `json:"authProvider"`
	WalletCustody string `json:"walletCustody"`
	WalletType    string `json:"walletType"`
	Status        string `json:"status"`
	CreatedAt     string `json:"createdAt"`
}
type walletProblem string

func (e walletProblem) Error() string { return string(e) }

type walletEngine struct {
	baseURL, apiKey, projectID string
	client                     *http.Client
}

func newWalletEngine(cfg config) *walletEngine {
	return &walletEngine{baseURL: cfg.EngineURL, apiKey: cfg.EngineAPIKey, projectID: cfg.EngineProjectID, client: &http.Client{
		Timeout: 25 * time.Second,
		// Never forward the Engine credential to a redirect destination.
		CheckRedirect: func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse },
	}}
}
func (e *walletEngine) ensure(ctx context.Context, userID string) (walletInfo, error) {
	// Engine looks up (project, authProvider, userID) before creating a managed wallet.
	// Repeating this identity also recovers a successful response lost in transit.
	payload, _ := json.Marshal(map[string]string{"userID": userID, "authProvider": walletAuthProvider, "metadata": `{"application":"rescene-rhythm"}`})
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, e.baseURL+"/v1/user-wallets/managed", bytes.NewReader(payload))
	if err != nil {
		return walletInfo{}, walletProblem("engine_request_invalid")
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Accept", "application/json")
	req.Header.Set("User-Agent", "Mozilla/5.0 (compatible; RESCENE-Rhythm-Backend/0.1)")
	req.Header.Set("X-GMR-Engine-Key", e.apiKey)
	res, err := e.client.Do(req)
	if err != nil {
		return walletInfo{}, walletProblem("engine_unavailable")
	}
	defer res.Body.Close()
	if res.StatusCode == 401 || res.StatusCode == 403 {
		return walletInfo{}, walletProblem("engine_authorization_failed")
	}
	if res.StatusCode != 200 && res.StatusCode != 201 {
		return walletInfo{}, walletProblem("engine_unavailable")
	}
	var body struct {
		Wallet engineWallet `json:"wallet"`
	}
	data, err := io.ReadAll(io.LimitReader(res.Body, 65537))
	if err != nil || len(data) > 65536 {
		return walletInfo{}, walletProblem("engine_response_invalid")
	}
	if json.Unmarshal(data, &body) != nil {
		return walletInfo{}, walletProblem("engine_response_invalid")
	}
	w := body.Wallet
	if w.ID == "" || len(w.ID) > 128 || !walletAddressPattern.MatchString(w.Address) || w.Address == "0x0000000000000000000000000000000000000000" || w.AppID != e.projectID || w.UserID != userID || w.AuthProvider != walletAuthProvider || w.WalletCustody != "managed" || w.WalletType != "managed_user" || w.Status != "active" {
		return walletInfo{}, walletProblem("engine_response_invalid")
	}
	return walletInfo{ID: w.ID, Address: strings.ToLower(w.Address), Status: "ready", Custody: "managed", CreatedAt: w.CreatedAt}, nil
}

type walletStore interface {
	ReadWallet(string, string, string) (walletInfo, error)
	ClaimWallet(string, string, string, string, time.Time) (bool, error)
	SaveWallet(string, string, string, string, walletInfo) (bool, error)
	RetryWallet(string, string, string, string, string, time.Time) error
	MissingWalletUsers(string, string, time.Time) ([]string, error)
}

func walletKey(userID, projectID, origin string) string {
	sum := sha256.Sum256([]byte(origin + "/" + projectID + "/" + userID))
	return hex.EncodeToString(sum[:])
}
func (s *graphStore) ReadWallet(id, project, origin string) (walletInfo, error) {
	key := walletKey(id, project, origin)
	r, err := s.query(`MATCH (u:User {id:$owner}) MERGE (w:Wallet {key:$key})
ON CREATE SET w.owner=$owner,w.project_id=$project,w.engine_url=$origin,w.status='pending',w.lease_until=0,w.next_attempt_at=0,w.attempts=0,w.id='',w.address='',w.created_at=''
MERGE (u)-[:HAS_WALLET]->(w) RETURN w.id,w.address,w.status,w.created_at`, map[string]interface{}{"owner": id, "key": key, "project": project, "origin": origin})
	if err != nil {
		return walletInfo{}, err
	}
	if !r.Next() {
		return walletInfo{}, errNotFound
	}
	row := r.Record()
	values := make([]string, 4)
	for i := range values {
		v, _ := row.GetByIndex(i)
		values[i], _ = v.(string)
	}
	status := values[2]
	if status == "provisioning" {
		status = "pending"
	}
	return walletInfo{ID: values[0], Address: values[1], Status: status, Custody: "managed", CreatedAt: values[3]}, nil
}
func (s *graphStore) ClaimWallet(id, project, origin, lease string, now time.Time) (bool, error) {
	r, err := s.query(`MATCH (w:Wallet {key:$key}) WHERE w.status<>'ready' AND w.lease_until<=$now AND w.next_attempt_at<=$now
SET w.status='provisioning',w.lease_token=$lease,w.lease_until=$until,w.attempts=w.attempts+1 RETURN w.key`, map[string]interface{}{"key": walletKey(id, project, origin), "lease": lease, "now": now.UnixMilli(), "until": now.Add(walletLease).UnixMilli()})
	if err != nil {
		return false, err
	}
	return r.Next(), nil
}
func (s *graphStore) SaveWallet(id, project, origin, lease string, w walletInfo) (bool, error) {
	r, err := s.query(`MATCH (w:Wallet {key:$key}) WHERE w.lease_token=$lease AND w.status<>'ready'
SET w.status='ready',w.id=$id,w.address=$address,w.created_at=$created,w.lease_until=0,w.next_attempt_at=0,w.error_code='' RETURN w.key`, map[string]interface{}{"key": walletKey(id, project, origin), "lease": lease, "id": w.ID, "address": w.Address, "created": w.CreatedAt})
	if err != nil {
		return false, err
	}
	return r.Next(), nil
}
func (s *graphStore) RetryWallet(id, project, origin, lease, code string, now time.Time) error {
	// Keep the lease after ambiguous failures: the upstream may still be finishing
	// a timed-out request. The next attempt uses the same Engine user identity.
	_, err := s.query(`MATCH (w:Wallet {key:$key}) WHERE w.lease_token=$lease AND w.status<>'ready'
SET w.status='retrying',w.error_code=$code,w.next_attempt_at=$retry RETURN w.key`, map[string]interface{}{"key": walletKey(id, project, origin), "lease": lease, "code": code, "retry": now.Add(5 * time.Minute).UnixMilli()})
	return err
}
func (s *graphStore) MissingWalletUsers(project, origin string, now time.Time) ([]string, error) {
	r, err := s.query(`MATCH (u:User) OPTIONAL MATCH (u)-[:HAS_WALLET]->(w:Wallet {project_id:$project,engine_url:$origin})
WITH u,w WHERE w IS NULL OR (w.status<>'ready' AND w.lease_until<=$now AND w.next_attempt_at<=$now) RETURN u.id LIMIT 100`, map[string]interface{}{"project": project, "origin": origin, "now": now.UnixMilli()})
	if err != nil {
		return nil, err
	}
	ids := []string{}
	for r.Next() {
		v, _ := r.Record().GetByIndex(0)
		if id, ok := v.(string); ok {
			ids = append(ids, id)
		}
	}
	return ids, nil
}

type walletService struct {
	store  walletStore
	engine *walletEngine
	ctx    context.Context
	cancel context.CancelFunc
	wg     sync.WaitGroup
	jobs   chan string
	mu     sync.Mutex
	queued map[string]bool
}

func startWalletService(store userStore, cfg config) (*walletService, error) {
	if cfg.EngineAPIKey == "" {
		return nil, nil
	}
	ws, ok := store.(walletStore)
	if !ok {
		return nil, errors.New("wallet storage unavailable")
	}
	ctx, cancel := context.WithCancel(context.Background())
	s := &walletService{store: ws, engine: newWalletEngine(cfg), ctx: ctx, cancel: cancel, jobs: make(chan string, 128), queued: map[string]bool{}}
	s.wg.Add(1)
	go s.run()
	return s, nil
}
func (s *walletService) close() error {
	if s != nil {
		s.cancel()
		s.wg.Wait()
	}
	return nil
}
func (s *walletService) queue(id string) {
	if s == nil {
		return
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.queued[id] {
		return
	}
	select {
	case s.jobs <- id:
		s.queued[id] = true
	default:
	}
}
func (s *walletService) public(id string) (walletInfo, error) {
	if s == nil {
		return walletInfo{Status: "not_configured", Custody: "managed"}, nil
	}
	w, err := s.store.ReadWallet(id, s.engine.projectID, s.engine.baseURL)
	if err == nil && w.Status != "ready" {
		s.queue(id)
	}
	return w, err
}
func (s *walletService) backfill() {
	ids, err := s.store.MissingWalletUsers(s.engine.projectID, s.engine.baseURL, time.Now())
	if err != nil {
		log.Print("wallet backfill: storage unavailable")
		return
	}
	for _, id := range ids {
		s.queue(id)
	}
}
func (s *walletService) run() {
	defer s.wg.Done()
	tick := time.NewTicker(30 * time.Second)
	defer tick.Stop()
	s.backfill()
	for {
		if s.ctx.Err() != nil {
			return
		}
		select {
		case <-s.ctx.Done():
			return
		case <-tick.C:
			s.backfill()
		case id := <-s.jobs:
			s.provision(id)
			s.mu.Lock()
			delete(s.queued, id)
			s.mu.Unlock()
		}
	}
}
func (s *walletService) provision(id string) {
	w, err := s.store.ReadWallet(id, s.engine.projectID, s.engine.baseURL)
	if err != nil || w.Status == "ready" {
		return
	}
	key := make([]byte, 16)
	if _, err = rand.Read(key); err != nil {
		return
	}
	lease := hex.EncodeToString(key)
	claimed, err := s.store.ClaimWallet(id, s.engine.projectID, s.engine.baseURL, lease, time.Now())
	if err != nil || !claimed {
		return
	}
	w, err = s.engine.ensure(s.ctx, id)
	if err != nil {
		// Never log upstream bodies, request headers, API keys or vault details.
		code := "engine_unavailable"
		var problem walletProblem
		if errors.As(err, &problem) {
			code = string(problem)
		}
		_ = s.store.RetryWallet(id, s.engine.projectID, s.engine.baseURL, lease, code, time.Now())
		log.Printf("wallet provisioning deferred: %s", code)
		return
	}
	saved, err := s.store.SaveWallet(id, s.engine.projectID, s.engine.baseURL, lease, w)
	if err != nil || !saved {
		log.Print("wallet link pending recovery; storage write not confirmed")
	}
}
func (a *api) walletUser(u user) user {
	w, err := a.wallets.public(u.ID)
	if err != nil {
		w = walletInfo{Status: "retrying", Custody: "managed"}
	}
	u.Wallet = &w
	return u
}
func (a *api) walletStatus(c fiber.Ctx) error {
	u := c.Locals("user").(user)
	w, err := a.wallets.public(u.ID)
	if err != nil {
		return failure(c, 503, "wallet_unavailable", "Your wallet is temporarily unavailable. Please try again.")
	}
	return c.JSON(fiber.Map{"wallet": w})
}
