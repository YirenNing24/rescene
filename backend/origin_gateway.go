package main

import (
	"crypto/subtle"
	"log"
	"net"
	"net/http"
	"net/http/httputil"
	"net/url"
	"os"
	"strings"
	"time"
)

// The existing named tunnel routes only /rescene/ to this listener. A dedicated
// Worker injects its origin credential; unrelated services keep their routes.
func originHandler(target *url.URL, secret string) http.Handler {
	proxy := httputil.NewSingleHostReverseProxy(target)
	proxy.ErrorHandler = func(w http.ResponseWriter, _ *http.Request, _ error) {
		http.Error(w, "Service temporarily unavailable", 503)
	}
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if len(secret) < 32 || subtle.ConstantTimeCompare([]byte(r.Header.Get("X-Remine-Edge")), []byte(secret)) != 1 {
			http.NotFound(w, r)
			return
		}
		if !strings.HasPrefix(r.URL.Path, "/rescene/") {
			http.NotFound(w, r)
			return
		}
		r.URL.Path = strings.TrimPrefix(r.URL.Path, "/rescene")
		r.URL.RawPath = ""
		r.RequestURI = ""
		r.Header.Del("X-Forwarded-For")
		r.Header.Del("Forwarded")
		if r.URL.Path == "/download" && (r.Method == "GET" || r.Method == "HEAD") && os.Getenv("APK_RELEASE_PATH") != "" {
			// A sideloaded game contains the music library; allow slow downloads to
			// finish independently of the short gameplay request timeout.
			_ = http.NewResponseController(w).SetWriteDeadline(time.Now().Add(10 * time.Minute))
			w.Header().Set("Content-Type", "application/vnd.android.package-archive")
			w.Header().Set("Content-Disposition", `attachment; filename="RESCENE-Rhythm.apk"`)
			http.ServeFile(w, r, os.Getenv("APK_RELEASE_PATH"))
			return
		}
		r.Body = http.MaxBytesReader(w, r.Body, profileUploadLimit)
		proxy.ServeHTTP(w, r)
	})
}
func startOriginGateway(c config) *http.Server {
	if c.OriginAddr == "" {
		return nil
	}
	_, port, e := net.SplitHostPort(c.Addr)
	if e != nil {
		log.Fatal("Invalid API listener")
	}
	target, _ := url.Parse("http://127.0.0.1:" + port)
	server := &http.Server{Addr: c.OriginAddr, Handler: originHandler(target, c.EdgeSecret), ReadHeaderTimeout: 10 * time.Second, ReadTimeout: 30 * time.Second, WriteTimeout: 35 * time.Second, IdleTimeout: 60 * time.Second, MaxHeaderBytes: 32768}
	go func() {
		if e := server.ListenAndServe(); e != nil && e != http.ErrServerClosed {
			log.Fatal("Origin listener failed")
		}
	}()
	return server
}
