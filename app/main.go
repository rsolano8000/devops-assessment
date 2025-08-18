package main

import (
	"fmt"
	"log"
	"net/http"
	"os"
)

func handler(w http.ResponseWriter, r *http.Request) {
	env := os.Getenv("ENV")
	if env == "" { env = "local" }
	version := os.Getenv("VERSION")
	if version == "" { version = "0.0.0" }
	msg := os.Getenv("APP_MESSAGE")
	if msg == "" { msg = "Hello World" }
	fmt.Fprintf(w, "Hello from %s (version %s): %s\n", env, version, msg)
}

func healthz(w http.ResponseWriter, r *http.Request) {
	w.WriteHeader(http.StatusOK)
	w.Write([]byte("ok"))
}

func main() {
	http.HandleFunc("/", handler)
	http.HandleFunc("/healthz", healthz)
	port := os.Getenv("PORT")
	if port == "" { port = "8080" }
	log.Printf("Starting server on :%s...", port)
	if err := http.ListenAndServe(":"+port, nil); err != nil {
		log.Fatal(err)
	}
}
