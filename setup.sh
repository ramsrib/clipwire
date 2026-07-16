#!/usr/bin/env bash
# clipwire installer. Generic + idempotent; bakes in no personal paths.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN="$REPO_DIR/clipwire"
LABEL="com.ramsrib.clipwire"
PLIST_SRC="$REPO_DIR/install/${LABEL}.plist"
PLIST_DST="$HOME/Library/LaunchAgents/${LABEL}.plist"
LOGDIR="$HOME/.config/clipwire"
LOCAL_SOCK="$HOME/.clipwire.sock"
REMOTE_SOCK="/tmp/clipwire.sock"

build() {
  ( cd "$REPO_DIR" && go build -o clipwire . )
  echo "built $BIN"
}

install_daemon() {
  build
  mkdir -p "$LOGDIR" "$HOME/Library/LaunchAgents"
  sed -e "s|__BIN__|$BIN|g" -e "s|__LOGDIR__|$LOGDIR|g" "$PLIST_SRC" > "$PLIST_DST"
  local domain="gui/$(id -u)"
  launchctl bootout "$domain/$LABEL" 2>/dev/null || true
  launchctl bootstrap "$domain" "$PLIST_DST" 2>/dev/null || launchctl load "$PLIST_DST"
  launchctl kickstart -k "$domain/$LABEL" 2>/dev/null || true
  echo "daemon installed and started ($LABEL); logs in $LOGDIR"
}

# host_block_exists <host> <config> — is there a `Host` line listing <host>?
host_block_exists() {
  awk -v host="$1" '
    $1=="Host"{for(i=2;i<=NF;i++) if($i==host){found=1}}
    END{exit found?0:1}' "$2"
}

install_tunnel() {
  local host="${1:-}"
  [ -n "$host" ] || { echo "usage: setup.sh install-tunnel <host>" >&2; exit 1; }
  local cfg="$HOME/.ssh/config"
  local fwd="RemoteForward $REMOTE_SOCK $LOCAL_SOCK"
  touch "$cfg"

  if grep -qE "^[[:space:]]*RemoteForward[[:space:]]+$REMOTE_SOCK([[:space:]]|\$)" "$cfg"; then
    echo "tunnel already present in $cfg (RemoteForward $REMOTE_SOCK) — no change"
  elif host_block_exists "$host" "$cfg"; then
    local tmp; tmp="$(mktemp)"
    awk -v host="$host" -v l1="  $fwd" '
      {print}
      $1=="Host"{for(i=2;i<=NF;i++) if($i==host){print l1}}' "$cfg" > "$tmp"
    # Preserve a symlinked config (e.g. dotfiles) — overwrite content, not the link.
    cat "$tmp" > "$cfg"
    rm -f "$tmp"
    echo "added RemoteForward under existing 'Host $host' in $cfg"
  else
    printf '\nHost %s\n  %s\n' "$host" "$fwd" >> "$cfg"
    echo "appended new 'Host $host' block with RemoteForward to $cfg"
  fi

  echo "NOTE: the remote also needs 'StreamLocalBindUnlink yes' in its sshd_config"
  echo "      (one-time, run by hand with sudo) — see the README 'Server (required)' step."
}

push() {
  local host="${1:-}"
  [ -n "$host" ] || { echo "usage: setup.sh push <host>" >&2; exit 1; }
  local info; info="$(ssh "$host" 'echo "$(uname -s) $(uname -m)"')"
  local os="${info%% *}" arch="${info##* }" goos goarch
  case "$os" in
    Darwin) goos=darwin ;;
    Linux)  goos=linux ;;
    *) echo "unsupported remote OS: $os" >&2; exit 1 ;;
  esac
  case "$arch" in
    arm64|aarch64) goarch=arm64 ;;
    x86_64|amd64)  goarch=amd64 ;;
    *) echo "unsupported remote arch: $arch" >&2; exit 1 ;;
  esac
  mkdir -p "$REPO_DIR/dist"
  local out="$REPO_DIR/dist/clipwire-$goos-$goarch"
  ( cd "$REPO_DIR" && GOOS="$goos" GOARCH="$goarch" go build -o "$out" . )
  ssh "$host" 'mkdir -p ~/.local/bin'
  scp "$out" "$host:.local/bin/clipwire"
  ssh "$host" 'chmod +x ~/.local/bin/clipwire'
  echo "pushed clipwire to $host:~/.local/bin/clipwire ($goos/$goarch)"
}

uninstall() {
  local domain="gui/$(id -u)"
  launchctl bootout "$domain/$LABEL" 2>/dev/null || true
  rm -f "$PLIST_DST"
  echo "uninstalled daemon; removed $PLIST_DST"
}

cmd="${1:-}"
shift || true
case "$cmd" in
  build)          build ;;
  install-daemon) install_daemon ;;
  install-tunnel) install_tunnel "$@" ;;
  push)           push "$@" ;;
  uninstall)      uninstall ;;
  *)
    cat <<'EOF'
clipwire setup
usage:
  ./setup.sh build                  build the binary
  ./setup.sh install-daemon         build + install & start the launchd daemon (laptop)
  ./setup.sh install-tunnel <host>  add the RemoteForward line to ~/.ssh/config for <host>
  ./setup.sh push <host>            cross-build and copy the binary to <host>:~/.local/bin
  ./setup.sh uninstall              stop & remove the daemon
EOF
    ;;
esac
