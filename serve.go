package main

import (
	"errors"
	"flag"
	"fmt"
	"net"
	"net/http"
	"os"
	"os/signal"
	"path/filepath"
	"syscall"
)

func defaultServeSocket() string {
	if s := os.Getenv("CLIPWIRE_SOCKET"); s != "" {
		return s
	}
	home, _ := os.UserHomeDir()
	return filepath.Join(home, ".clipwire.sock")
}

func runServe(args []string) error {
	fs := flag.NewFlagSet("serve", flag.ContinueOnError)
	socket := fs.String("socket", defaultServeSocket(), "unix socket to listen on")
	if err := fs.Parse(args); err != nil {
		return err
	}

	// Clear a stale socket left by a previous run.
	if err := os.Remove(*socket); err != nil && !os.IsNotExist(err) {
		return fmt.Errorf("removing stale socket: %w", err)
	}

	ln, err := net.Listen("unix", *socket)
	if err != nil {
		return fmt.Errorf("listen %s: %w", *socket, err)
	}
	if err := os.Chmod(*socket, 0o600); err != nil {
		return fmt.Errorf("chmod socket: %w", err)
	}

	cleanup := func() {
		_ = ln.Close()
		_ = os.Remove(*socket)
	}

	sigc := make(chan os.Signal, 1)
	signal.Notify(sigc, syscall.SIGINT, syscall.SIGTERM)
	go func() {
		<-sigc
		fmt.Fprintln(os.Stderr, "clipwire serve: shutting down")
		cleanup()
		os.Exit(0)
	}()

	mux := http.NewServeMux()
	mux.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodGet {
			http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
			return
		}
		png, err := readClipboardPNG()
		if errors.Is(err, errNoImage) {
			w.WriteHeader(http.StatusNoContent)
			fmt.Fprintln(os.Stderr, "clipwire serve: 204 no image")
			return
		}
		if err != nil {
			http.Error(w, "clipboard read failed", http.StatusInternalServerError)
			fmt.Fprintln(os.Stderr, "clipwire serve: error:", err)
			return
		}
		w.Header().Set("Content-Type", "image/png")
		w.WriteHeader(http.StatusOK)
		n, _ := w.Write(png)
		fmt.Fprintf(os.Stderr, "clipwire serve: served %d bytes\n", n)
	})

	fmt.Fprintf(os.Stderr, "clipwire serve: listening on %s\n", *socket)
	srv := &http.Server{Handler: mux}
	err = srv.Serve(ln)
	cleanup()
	return err
}
