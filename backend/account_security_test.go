package main

import (
	"fmt"
	"strings"
	"sync"
	"testing"
)

func TestAccountSecurityRevokesSessionsAndConsumesRecoveryOnce(t *testing.T) {
	s := testStore(t)
	app := testApp(t, s)
	status, initial, _ := request(t, app, "POST", "/api/v1/auth/register", creds("recoverplayer", "password123"), "")
	requireStatus(t, status, 201)
	access := initial["access_token"].(string)
	refresh := initial["refresh_token"].(string)
	status, _, _ = request(t, app, "POST", "/api/v1/account/recovery-codes", map[string]string{"password": "incorrect"}, access)
	requireStatus(t, status, 403)
	status, codes, _ := request(t, app, "POST", "/api/v1/account/recovery-codes", map[string]string{"password": "password123"}, access)
	requireStatus(t, status, 200)
	list := codes["recovery_codes"].([]any)
	if len(list) != 8 {
		t.Fatal("expected eight codes")
	}
	code := list[0].(string)
	owner := initial["user"].(map[string]any)["id"].(string)
	rows, err := s.query(`MATCH(u:User {id:$id}) RETURN u.recovery_hashes`, map[string]interface{}{"id": owner})
	if err != nil || !rows.Next() {
		t.Fatal(err)
	}
	v, _ := rows.Record().GetByIndex(0)
	if strings.Contains(fmt.Sprint(v), code) || strings.Contains(fmt.Sprint(v), strings.ReplaceAll(code, "-", "")) {
		t.Fatal("bad digest")
	}
	status, _, _ = request(t, app, "POST", "/api/v1/account/password", map[string]string{"current_password": "password123", "new_password": "password456"}, access)
	requireStatus(t, status, 200)
	status, _, _ = request(t, app, "GET", "/api/v1/auth/me", nil, access)
	requireStatus(t, status, 401)
	status, _, _ = request(t, app, "POST", "/api/v1/auth/refresh", refreshBody(refresh, 77), "")
	requireStatus(t, status, 401)
	status, _, _ = request(t, app, "POST", "/api/v1/auth/login", creds("recoverplayer", "password123"), "")
	requireStatus(t, status, 401)
	status, logged, _ := request(t, app, "POST", "/api/v1/auth/login", creds("recoverplayer", "password456"), "")
	requireStatus(t, status, 200)
	status, _, _ = request(t, app, "POST", "/api/v1/auth/recover", map[string]string{"username": "recoverplayer", "recovery_code": code, "new_password": "password789"}, "")
	requireStatus(t, status, 200)
	status, _, _ = request(t, app, "GET", "/api/v1/auth/me", nil, logged["access_token"].(string))
	requireStatus(t, status, 401)
	status, _, _ = request(t, app, "POST", "/api/v1/auth/recover", map[string]string{"username": "recoverplayer", "recovery_code": code, "new_password": "password000"}, "")
	requireStatus(t, status, 401)
	n, err := s.RecoveryCount(owner)
	if err != nil || n != 7 {
		t.Fatal(n, err)
	}
	// Two database clients cannot spend the same recovery secret twice.
	var wg sync.WaitGroup
	success := make(chan bool, 2)
	for range 2 {
		wg.Go(func() {
			ok, e := s.RecoverPassword("recoverplayer", recoveryDigest(list[1].(string)), "new_hash")
			if e != nil {
				t.Error(e)
			}
			success <- ok
		})
	}
	wg.Wait()
	close(success)
	count := 0
	for ok := range success {
		if ok {
			count++
		}
	}
	if count != 1 {
		t.Fatal("recovery replay", count)
	}
}
