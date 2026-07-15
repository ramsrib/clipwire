package main

import (
	"fmt"
	"os"
)

const version = "0.1.0"

const usage = `clipwire — paste clipboard images into a program on a remote host over SSH.

Usage:
  clipwire serve [--socket PATH]
        Run the clipboard daemon (on the laptop). Reads the clipboard as PNG
        and serves it over a unix socket.
        --socket  socket to listen on
                  (default: $CLIPWIRE_SOCKET, else $HOME/.clipwire.sock)

  clipwire pull [--socket PATH] [--dir DIR]
        Fetch the clipboard image over the SSH reverse-tunnel (on the remote),
        save it to a unique PNG, and print the absolute path on stdout.
        --socket  socket to connect to
                  (default: $CLIPWIRE_SOCKET, else /tmp/clipwire.sock)
        --dir     directory for the saved PNG (default: system temp dir)

  clipwire --version
  clipwire --help
`

func main() {
	args := os.Args[1:]
	if len(args) == 0 {
		fmt.Print(usage)
		return
	}
	switch args[0] {
	case "serve":
		if err := runServe(args[1:]); err != nil {
			fmt.Fprintln(os.Stderr, "clipwire serve:", err)
			os.Exit(1)
		}
	case "pull":
		runPull(args[1:]) // manages its own exit codes
	case "--version", "-v", "version":
		fmt.Println("clipwire", version)
	case "--help", "-h", "help":
		fmt.Print(usage)
	default:
		fmt.Fprintln(os.Stderr, "clipwire: unknown command:", args[0])
		fmt.Fprint(os.Stderr, usage)
		os.Exit(2)
	}
}
