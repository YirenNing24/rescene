package main

import (
	"io"
	"net/http"
	"net/http/httptest"
	"net/url"
	"os"
	"strings"
	"testing"
)

func TestOriginRequiresCredentialAndStripsOnlyGamePrefix(t *testing.T) {
	upstream := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		_, _ = w.Write([]byte(r.URL.RequestURI() + "|" + r.Header.Get("X-Remine-Client-IP")))
	}))
	defer upstream.Close()
	target, _ := url.Parse(upstream.URL)
	secret := strings.Repeat("s", 64)
	handler := originHandler(target, secret)
	for _, tc := range []struct {
		path, key string
		status    int
		body      string
	}{{"/rescene/healthz", "", 404, ""}, {"/healthz", secret, 404, ""}, {"/rescene/api/v1/challenges?cursor=1", secret, 200, "/api/v1/challenges?cursor=1|203.0.113.1"}} {
		req := httptest.NewRequest("GET", tc.path, nil)
		req.Header.Set("X-Remine-Edge", tc.key)
		req.Header.Set("X-Remine-Client-IP", "203.0.113.1")
		out := httptest.NewRecorder()
		handler.ServeHTTP(out, req)
		if out.Code != tc.status {
			t.Fatal(out.Code, tc.status)
		}
		b, _ := io.ReadAll(out.Result().Body)
		if tc.body != "" && string(b) != tc.body {
			t.Fatal(string(b))
		}
	}
}

func TestOriginAPKSupportsRanges(t *testing.T) {
	file := t.TempDir() + "/game.apk"
	if e := os.WriteFile(file, []byte("test-game-package"), 0600); e != nil {
		t.Fatal(e)
	}
	t.Setenv("APK_RELEASE_PATH", file)
	target, _ := url.Parse("http://127.0.0.1:1")
	secret := strings.Repeat("s", 64)
	handler := originHandler(target, secret)
	req := httptest.NewRequest("GET", "/rescene/download", nil)
	req.Header.Set("X-Remine-Edge", secret)
	req.Header.Set("Range", "bytes=0-3")
	out := httptest.NewRecorder()
	handler.ServeHTTP(out, req)
	if out.Code != 206 || out.Body.String() != "test" {
		t.Fatal(out.Code, out.Body.String())
	}
}
