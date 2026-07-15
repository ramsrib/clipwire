package main

import (
	"bytes"
	"context"
	"flag"
	"fmt"
	"io"
	"net"
	"net/http"
	"os"
	"path/filepath"
	"time"
)

func defaultPullSocket() string {
	if s := os.Getenv("CLIPWIRE_SOCKET"); s != "" {
		return s
	}
	return "/tmp/clipwire.sock"
}

var pngMagic = []byte{0x89, 'P', 'N', 'G', 0x0D, 0x0A, 0x1A, 0x0A}

func runPull(args []string) {
	fs := flag.NewFlagSet("pull", flag.ContinueOnError)
	socket := fs.String("socket", defaultPullSocket(), "unix socket to connect to")
	dir := fs.String("dir", os.TempDir(), "directory for the saved PNG")
	if err := fs.Parse(args); err != nil {
		os.Exit(2)
	}

	pruneOldClips(*dir)

	client := &http.Client{
		Transport: &http.Transport{
			DialContext: func(ctx context.Context, _, _ string) (net.Conn, error) {
				var d net.Dialer
				return d.DialContext(ctx, "unix", *socket)
			},
		},
		Timeout: 15 * time.Second,
	}

	resp, err := client.Get("http://unix/")
	if err != nil {
		fmt.Fprintf(os.Stderr, "clipwire: cannot reach the clipwire daemon at %s — is the SSH reverse tunnel up (RemoteForward) and the daemon running on the laptop?\n", *socket)
		os.Exit(4)
	}
	defer resp.Body.Close()

	switch resp.StatusCode {
	case http.StatusNoContent:
		fmt.Fprintln(os.Stderr, "clipwire: no image on clipboard")
		os.Exit(3)
	case http.StatusOK:
		// fall through
	default:
		fmt.Fprintf(os.Stderr, "clipwire: daemon returned %s\n", resp.Status)
		os.Exit(5)
	}

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		fmt.Fprintln(os.Stderr, "clipwire: reading response:", err)
		os.Exit(5)
	}
	if len(body) < len(pngMagic) || !bytes.Equal(body[:len(pngMagic)], pngMagic) {
		fmt.Fprintln(os.Stderr, "clipwire: response was not a PNG")
		os.Exit(5)
	}

	f, err := os.CreateTemp(*dir, "clip-*.png")
	if err != nil {
		fmt.Fprintln(os.Stderr, "clipwire: creating temp file:", err)
		os.Exit(5)
	}
	if _, err := f.Write(body); err != nil {
		_ = f.Close()
		fmt.Fprintln(os.Stderr, "clipwire: writing image:", err)
		os.Exit(5)
	}
	_ = f.Close()
	_ = os.Chmod(f.Name(), 0o600)
	fmt.Println(f.Name())
}

// pruneOldClips removes clip-*.png files older than 24h (best-effort).
func pruneOldClips(dir string) {
	matches, err := filepath.Glob(filepath.Join(dir, "clip-*.png"))
	if err != nil {
		return
	}
	cutoff := time.Now().Add(-24 * time.Hour)
	for _, m := range matches {
		if info, err := os.Stat(m); err == nil && info.ModTime().Before(cutoff) {
			_ = os.Remove(m)
		}
	}
}
