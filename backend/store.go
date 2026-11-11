package main

import (
	"context"
	"errors"
	"fmt"
	"strings"
	"sync"
	"time"

	falkordb "github.com/FalkorDB/falkordb-go/v2"
)

var errDuplicate = errors.New("username already taken")
var errNotFound = errors.New("account not found")

type user struct {
	TermsVersion    string      `json:"-"`
	PrivacyVersion  string      `json:"-"`
	LegalAcceptedAt string      `json:"-"`
	ID              string      `json:"id"`
	Username        string      `json:"username"`
	CreatedAt       string      `json:"created_at"`
	PasswordHash    string      `json:"-"`
	PasswordVersion int64       `json:"-"`
	Wallet          *walletInfo `json:"wallet,omitempty"`
}

type userStore interface {
	Create(user, string) (user, error)
	ByUsername(string) (user, error)
	ByID(string) (user, error)
	Ping() error
}

type graphStore struct {
	db    *falkordb.FalkorDB
	graph *falkordb.Graph
	// The official client's result decoder maintains a graph schema cache.
	// Protect that cache; uniqueness itself comes from the atomic database MERGE.
	mu sync.Mutex
}

func openStore(url, name string) (*graphStore, error) {
	db, err := falkordb.FromURL(url)
	if err != nil {
		return nil, errors.New("invalid FALKORDB_URL")
	}
	s := &graphStore{db: db, graph: db.SelectGraph(name)}
	if err = s.Ping(); err != nil {
		db.Conn.Close()
		return nil, fmt.Errorf("connect to FalkorDB: %w", err)
	}
	// Creates the graph and exact-match index on first startup. Repeated startup is safe.
	_, err = s.query("CREATE INDEX FOR (u:User) ON (u.username_key)", nil)
	if err != nil && !strings.Contains(strings.ToLower(err.Error()), "already indexed") && !strings.Contains(strings.ToLower(err.Error()), "already exists") {
		db.Conn.Close()
		return nil, fmt.Errorf("initialize account index: %w", err)
	}
	_, err = s.query("CREATE INDEX FOR (u:User) ON (u.id)", nil)
	if err != nil && !strings.Contains(strings.ToLower(err.Error()), "already indexed") && !strings.Contains(strings.ToLower(err.Error()), "already exists") {
		db.Conn.Close()
		return nil, fmt.Errorf("initialize account ID index: %w", err)
	}
	_, err = s.query("CREATE INDEX FOR (p:Progression) ON (p.owner)", nil)
	if err != nil && !strings.Contains(strings.ToLower(err.Error()), "already indexed") && !strings.Contains(strings.ToLower(err.Error()), "already exists") {
		db.Conn.Close()
		return nil, fmt.Errorf("initialize progression index: %w", err)
	}
	_, err = s.query("CREATE INDEX FOR (w:Wallet) ON (w.key)", nil)
	if err != nil && !strings.Contains(strings.ToLower(err.Error()), "already indexed") && !strings.Contains(strings.ToLower(err.Error()), "already exists") {
		db.Conn.Close()
		return nil, fmt.Errorf("initialize wallet index: %w", err)
	}
	for _, property := range []string{"key", "target", "owner"} {
		_, err = s.query("CREATE INDEX FOR (j:ShopOperation) ON (j."+property+")", nil)
		if err != nil && !strings.Contains(strings.ToLower(err.Error()), "already indexed") && !strings.Contains(strings.ToLower(err.Error()), "already exists") {
			db.Conn.Close()
			return nil, fmt.Errorf("initialize shop index: %w", err)
		}
		_, err = s.query("CREATE INDEX FOR (j:StarlightPayout) ON (j."+property+")", nil)
		if err != nil && !strings.Contains(strings.ToLower(err.Error()), "already indexed") && !strings.Contains(strings.ToLower(err.Error()), "already exists") {
			db.Conn.Close()
			return nil, fmt.Errorf("initialize Starlight payout index: %w", err)
		}
		_, err = s.query("CREATE INDEX FOR (j:LeaderboardPublication) ON (j."+property+")", nil)
		if err != nil && !strings.Contains(strings.ToLower(err.Error()), "already indexed") && !strings.Contains(strings.ToLower(err.Error()), "already exists") {
			db.Conn.Close()
			return nil, fmt.Errorf("initialize publication index: %w", err)
		}
	}
	for _, property := range []string{"key", "chart_key", "owner"} {
		_, err = s.query("CREATE INDEX FOR (b:PersonalBest) ON (b."+property+")", nil)
		if err != nil && !strings.Contains(strings.ToLower(err.Error()), "already indexed") && !strings.Contains(strings.ToLower(err.Error()), "already exists") {
			db.Conn.Close()
			return nil, fmt.Errorf("initialize score index: %w", err)
		}
	}
	for _, property := range []string{"token_hash", "previous_hash"} {
		_, err = s.query("CREATE INDEX FOR (s:LoginSession) ON (s."+property+")", nil)
		if err != nil && !strings.Contains(strings.ToLower(err.Error()), "already indexed") && !strings.Contains(strings.ToLower(err.Error()), "already exists") {
			db.Conn.Close()
			return nil, fmt.Errorf("initialize login session index: %w", err)
		}
	}
	for _, label := range []string{"Presence", "Conversation", "DirectMessage"} {
		_, err = s.query("CREATE INDEX FOR (n:"+label+") ON (n.key)", nil)
		if err != nil && !strings.Contains(strings.ToLower(err.Error()), "already indexed") && !strings.Contains(strings.ToLower(err.Error()), "already exists") {
			db.Conn.Close()
			return nil, fmt.Errorf("initialize social index: %w", err)
		}
	}
	return s, nil
}

func (s *graphStore) Close() error { return s.db.Conn.Close() }
func (s *graphStore) Ping() error {
	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()
	return s.db.Conn.Ping(ctx).Err()
}
func (s *graphStore) query(q string, params map[string]interface{}) (*falkordb.QueryResult, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.graph.Query(q, params, falkordb.NewQueryOptions().SetTimeout(2000))
}

const userFields = " RETURN u.id, u.username, u.created_at, u.password_hash, coalesce(u.password_version,0), coalesce(u.terms_version,''), coalesce(u.privacy_version,''), coalesce(u.legal_accepted_at,'')"

func decodeUser(result *falkordb.QueryResult, err error) (user, error) {
	if err != nil {
		return user{}, err
	}
	if !result.Next() {
		return user{}, errNotFound
	}
	r := result.Record()
	idValue, _ := r.GetByIndex(0)
	nameValue, _ := r.GetByIndex(1)
	dateValue, _ := r.GetByIndex(2)
	hashValue, _ := r.GetByIndex(3)
	versionValue, _ := r.GetByIndex(4)
	id, okID := idValue.(string)
	username, okName := nameValue.(string)
	created, okDate := dateValue.(string)
	hash, okHash := hashValue.(string)
	if !okID || !okName || !okDate || !okHash {
		return user{}, errors.New("invalid account data")
	}
	termsValue, _ := r.GetByIndex(5)
	privacyValue, _ := r.GetByIndex(6)
	acceptedValue, _ := r.GetByIndex(7)
	terms, _ := termsValue.(string)
	privacy, _ := privacyValue.(string)
	accepted, _ := acceptedValue.(string)
	version, _ := versionValue.(int64)
	return user{ID: id, Username: username, CreatedAt: created, PasswordHash: hash, PasswordVersion: version, TermsVersion: terms, PrivacyVersion: privacy, LegalAcceptedAt: accepted}, nil
}

func (s *graphStore) Create(u user, canonical string) (user, error) {
	// A single write query is atomic even when different API processes register
	// the same username concurrently. ON CREATE never changes an existing hash.
	stored, err := decodeUser(s.query(`MERGE (u:User {username_key: $key})
ON CREATE SET u.id = $id, u.username = $username, u.created_at = $created, u.password_hash = $hash, u.terms_version = $terms, u.privacy_version = $privacy, u.legal_accepted_at = $accepted`+userFields,
		map[string]interface{}{"key": canonical, "id": u.ID, "username": u.Username, "created": u.CreatedAt, "hash": u.PasswordHash, "terms": u.TermsVersion, "privacy": u.PrivacyVersion, "accepted": u.LegalAcceptedAt}))
	if err != nil {
		return user{}, err
	}
	if stored.ID != u.ID {
		return user{}, errDuplicate
	}
	return stored, nil
}
func (s *graphStore) ByUsername(key string) (user, error) {
	return decodeUser(s.query("MATCH (u:User {username_key: $key})"+userFields, map[string]interface{}{"key": key}))
}
func (s *graphStore) ByID(id string) (user, error) {
	return decodeUser(s.query("MATCH (u:User {id: $id})"+userFields, map[string]interface{}{"id": id}))
}
