# clipwire

Paste clipboard **images** into a terminal program running on a **remote** machine
over SSH — the thing that normally doesn't work, because a program can only read
the clipboard of the machine it runs on.

Built for pasting screenshots into CLI coding agents (Claude Code, etc.) running
in a remote tmux/SSH session, but it's generic: it hands the remote side a PNG
file and prints its path.

## The problem, in one rule

> **A program can only read the clipboard of the machine it is running on.**

Your screenshot is on your **laptop's** clipboard. Your terminal program runs on
the **remote** host. When it tries to paste, it reads the *remote's* clipboard —
which never has your screenshot. SSH doesn't forward image clipboard data, and
tmux strips binary clipboard content entirely.

## How it works — two pieces, one per machine

The work splits across two machines, so clipwire is one binary run in two modes:

```
   LAPTOP (has the image)                       REMOTE (runs your CLI program)
   ┌────────────────────────┐                   ┌────────────────────────────┐
   │  📋 clipboard: shot     │                   │  your terminal program      │
   │                         │    SSH tunnel     │                             │
   │  clipwire serve  ◀──────┼──(reverse socket)─┼──  clipwire pull            │
   │  (launchd daemon,       │                   │   (on demand)               │
   │   reads clipboard,      │   1. "send image" │                             │
   │   returns PNG) ─────────┼──── 2. PNG bytes ─┼─▶ saves /tmp/clip-XXXX.png  │
   │                         │                   │   prints the path ──────────┼─▶ paste
   └────────────────────────┘                   └────────────────────────────┘
```

- **`clipwire serve`** runs on the **laptop** as a background daemon. It listens on
  a unix socket and, when asked, reads the clipboard as PNG and returns the bytes.
  It must already be running because the request originates from the remote — the
  remote can only connect to something already listening.
- **`clipwire pull`** runs on the **remote**, on demand. It reaches back through an
  SSH reverse-tunnel to the daemon, saves the PNG to a unique temp file, and prints
  the path. You (or a tmux binding) then hand that path to your program — which can
  read a file even though it can't reach your laptop's clipboard.

The SSH **reverse tunnel** is the pipe between them: `RemoteForward` maps a socket
on the remote back to the daemon's socket on the laptop. It's established when you
connect, so nothing on the laptop needs to be internet-reachable.

## Install

### Homebrew (recommended)

**Laptop** (macOS — runs the daemon):

```bash
brew install ramsrib/tap/clipwire
brew services start clipwire       # run the clipboard daemon under launchd
```

**Remote — macOS** (where your terminal program runs — only needs `pull`):

```bash
brew install ramsrib/tap/clipwire
```

**Remote — Linux** (`pull` only — the daemon is macOS-only, so a Linux box is always
the remote, never the clipboard source):

```bash
go install github.com/ramsrib/clipwire@latest
```

`go install` drops the binary in `$(go env GOPATH)/bin` (usually `~/go/bin`), which is
frequently **not** on your `PATH` — so `clipwire` won't be found until you add it. In
your shell rc (`~/.profile` for login bash, and/or `~/.zshrc`):

```bash
export PATH="$HOME/go/bin:$PATH"
```

Upgrade later by re-running `go install github.com/ramsrib/clipwire@latest`.
(Prefer Homebrew? `brew install ramsrib/tap/clipwire` also works on Linux once
[Homebrew on Linux](https://docs.brew.sh/Homebrew-on-Linux) is installed.)

### SSH prerequisites (configure once per host, by hand)

clipwire needs two SSH settings that you add yourself, in the corresponding files —
one on each end. clipwire does **not** edit your SSH config for you.

**Client** — add the reverse forward for the host you SSH into, in `~/.ssh/config`:

```
Host <host>
  RemoteForward /tmp/clipwire.sock ~/.clipwire.sock
```

**Server (required)** — on that remote host, let sshd reclaim the socket. Add
`StreamLocalBindUnlink yes` to its `sshd_config` as a one-time drop-in (run by hand — needs sudo):

```bash
echo "StreamLocalBindUnlink yes" | sudo tee /etc/ssh/sshd_config.d/clipwire.conf
```

New connections pick it up (on macOS no reload is needed).

This server-side line is **not optional**: the reverse-forward socket is created by
the *remote's* sshd, and many systems (macOS included) leave it orphaned on
disconnect — without it, the next connection's forward fails to bind with
`remote port forwarding failed`. Note that `StreamLocalBindUnlink` in the *client*
`~/.ssh/config` does **not** help here — client-side it only governs `-L` local
forwards.

### From source

```bash
git clone https://github.com/ramsrib/clipwire && cd clipwire
./setup.sh install-daemon          # build + start the launchd daemon (laptop)
./setup.sh push <host>             # copy the binary to a remote
```
(The server-side `sshd_config` step is manual — see "Server (required)" above.)

Reconnect your SSH session so the tunnel is established, then paste away.
(Optionally add the `prefix + P` tmux binding from `install/clipwire.tmux` on the remote.)

## Usage

```bash
clipwire serve                 # laptop daemon (usually run by launchd, not by hand)
clipwire pull                  # remote: save clipboard image, print the file path
clipwire pull | pbcopy         # e.g. capture the path however you like
```

tmux binding (remote `~/.tmux.conf`) — `prefix + P` types the path into the pane:

```tmux
bind-key P run-shell 'p=$(clipwire pull 2>/dev/null) && tmux send-keys -t "#{pane_id}" " $p "'
```

## Security notes

- The tunnel uses a **unix-domain socket** (not a TCP port), so the clipboard isn't
  exposed on any network interface. On a shared remote host, file permissions on the
  forwarded socket gate access — anyone who can read it can pull your clipboard.
- The daemon serves whatever image is on the clipboard *at request time*. It holds
  nothing and logs no image data.

## Limitations

- The daemon's clipboard reader is macOS-only today (`serve` runs on the laptop,
  which is assumed to be a Mac). `pull` runs anywhere Go runs.
- tmux blocks binary clipboard data, which is *why* this exists — clipwire never puts
  the image on a clipboard; it moves a file and passes a path.

## License

MIT — see [LICENSE](./LICENSE).
