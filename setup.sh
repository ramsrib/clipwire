#!/usr/bin/env bash
# clipwire installer. Generic + idempotent; bakes in no personal paths.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN="$REPO_DIR/clipwire"
LABEL="com.ramsrib.clipwire"
PLIST_SRC="$REPO_DIR/install/${LABEL}.plist"
PLIST_DST="$HOME/Library/LaunchAgents/${LABEL}.plist"
LOGDIR="$HOME/.config/clipwire"

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
  push)           push "$@" ;;
  uninstall)      uninstall ;;
  *)
    cat <<'EOF'
clipwire setup
usage:
  ./setup.sh build                  build the binary
  ./setup.sh install-daemon         build + install & start the launchd daemon (laptop)
  ./setup.sh push <host>            cross-build and copy the binary to <host>:~/.local/bin
  ./setup.sh uninstall              stop & remove the daemon
EOF
    ;;
esac
