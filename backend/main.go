package main

import (
	"context"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"golang.org/x/crypto/bcrypt"
)

func main() {
	if len(os.Args) > 1 && os.Args[1] == "--healthcheck" {
		req, _ := http.NewRequest("GET", "http://127.0.0.1:8080/healthz", nil)
		req.Header.Set("X-Remine-Edge", os.Getenv("ORIGIN_EDGE_SECRET"))
		client := &http.Client{Timeout: 3 * time.Second}
		res, e := client.Do(req)
		if e != nil {
			os.Exit(1)
		}
		_ = res.Body.Close()
		if res.StatusCode != 200 {
			os.Exit(1)
		}
		return
	}
	cfg, err := loadConfig()
	if err != nil {
		log.Fatal(err)
	}
	store, err := openStore(cfg.DatabaseURL, cfg.Graph)
	if err != nil {
		log.Fatal(err)
	}
	defer store.Close()
	app, err := newApp(store, cfg, bcrypt.DefaultCost+2)
	if err != nil {
		log.Fatal(err)
	}
	origin := startOriginGateway(cfg)
	stop := make(chan os.Signal, 1)
	signal.Notify(stop, os.Interrupt, syscall.SIGTERM)
	go func() {
		<-stop
		if origin != nil {
			ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
			_ = origin.Shutdown(ctx)
			cancel()
		}
		_ = app.ShutdownWithTimeout(5 * time.Second)
	}()
	log.Printf("RESCÉNE API listening on %s", cfg.Addr)
	if err = app.Listen(cfg.Addr); err != nil {
		log.Print(err)
	}
}
