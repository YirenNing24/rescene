package main

import (
	"encoding/json"
	"errors"
	"os"
	"testing"
	"time"
)

func TestPolicyVersionMatchesPublishedDocuments(t *testing.T) {
	raw, err := os.ReadFile("../assets/legal/policies.json")
	if err != nil {
		t.Fatal(err)
	}
	var policy struct {
		Version        string `json:"version"`
		Contact        string `json:"contact"`
		Terms, Privacy struct {
			Title    string
			Sections []struct{ Title, Body string }
		}
	}
	if err = json.Unmarshal(raw, &policy); err != nil {
		t.Fatal(err)
	}
	if policy.Version != legalPolicyVersion || policy.Contact != "winterape25@gmail.com" || len(policy.Terms.Sections) == 0 || len(policy.Privacy.Sections) == 0 {
		t.Fatal("published policies and server agreement contract differ")
	}
}

func TestRegistrationRequiresAndPersistsPolicyAgreement(t *testing.T) {
	store := testStore(t)
	for _, kind := range []string{"missing", "declined", "old_terms", "old_privacy"} {
		body := creds("policy_player", "password123")
		switch kind {
		case "missing":
			delete(body, "accept_policies")
		case "declined":
			body["accept_policies"] = false
		case "old_terms":
			body["terms_version"] = "old"
		case "old_privacy":
			body["privacy_version"] = "old"
		}
		app := testApp(t, store)
		status, result, _ := request(t, app, "POST", "/api/v1/auth/register", body, "")
		requireStatus(t, status, 400)
		if result["error"].(map[string]any)["code"] != "policy_agreement_required" {
			t.Fatalf("wrong rejection: %v", result)
		}
		if _, err := store.ByUsername("policy_player"); !errors.Is(err, errNotFound) {
			t.Fatal("rejected registration created an account")
		}
	}
	app := testApp(t, store)
	status, result, _ := request(t, app, "POST", "/api/v1/auth/register", creds("policy_player", "password123"), "")
	requireStatus(t, status, 201)
	account, err := store.ByUsername("policy_player")
	if err != nil {
		t.Fatal(err)
	}
	if account.TermsVersion != legalPolicyVersion || account.PrivacyVersion != legalPolicyVersion {
		t.Fatal("accepted versions were not saved")
	}
	accepted, err := time.Parse(time.RFC3339, account.LegalAcceptedAt)
	if err != nil || time.Since(accepted) > time.Minute {
		t.Fatal("missing server-generated agreement time")
	}
	if _, ok := result["user"].(map[string]any)["legal_accepted_at"]; ok {
		t.Fatal("internal agreement record leaked into public user")
	}
	status, _, _ = request(t, app, "POST", "/api/v1/auth/login", map[string]string{"username": "policy_player", "password": "password123"}, "")
	requireStatus(t, status, 200)
	status, _, _ = request(t, testApp(t, store), "POST", "/api/v1/auth/register", creds("policy_player", "password123"), "")
	requireStatus(t, status, 409)
	saved, err := store.ByID(account.ID)
	if err != nil || saved.LegalAcceptedAt != account.LegalAcceptedAt {
		t.Fatal("duplicate registration changed the original agreement")
	}
}
