#!/usr/bin/env bash
# One-shot native macOS installer (no Docker) for whatsapp-mcp-extended.
#
#   scripts/install-macos.sh [account ...]     install + pair (default account: "default")
#   scripts/install-macos.sh --pair <account>  (re)pair one account
#
# Each account is one WhatsApp number, with its own bridge (launchd service,
# own port and store) under ~/.whatsapp-mcp/<account>/ and its own MCP server
# registered in Claude Code as "whatsapp-<account>".
#
# Can be run from a clone or straight from GitHub:
#   curl -fsSL https://raw.githubusercontent.com/lrnzsp/whatsapp/local/scripts/install-macos.sh | bash -s -- personale business
set -euo pipefail

REPO_URL="${REPO_URL:-https://github.com/lrnzsp/whatsapp.git}"
REPO_BRANCH="${REPO_BRANCH:-local}"
INSTALL_DIR="${INSTALL_DIR:-$HOME/whatsapp-mcp}"
WA_HOME="${WHATSAPP_MCP_HOME:-$HOME/.whatsapp-mcp}"
BASE_PORT="${BASE_PORT:-8180}"
LABEL_PREFIX="com.whatsapp-mcp"

say()  { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
ok()   { printf '   \033[32m✓\033[0m %s\n' "$*"; }
warn() { printf '   \033[33m!\033[0m %s\n' "$*"; }
die()  { printf '\n\033[31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }
ask()  { local v; printf '%s' "$1" >/dev/tty; read -r v </dev/tty; printf '%s' "$v"; }

[ "$(uname -s)" = Darwin ] || die "this installer is for macOS"

# ── prerequisites ─────────────────────────────────────────────────────────────
say "Checking prerequisites"
if ! xcode-select -p >/dev/null 2>&1; then
  xcode-select --install >/dev/null 2>&1 || true
  die "Xcode Command Line Tools are being installed: accept the dialog, then run this script again."
fi
ok "Xcode Command Line Tools"
if ! command -v uv >/dev/null 2>&1 && [ ! -x "$HOME/.local/bin/uv" ]; then
  say "Installing uv (Python package manager, from astral.sh)"
  curl -LsSf https://astral.sh/uv/install.sh | sh >/dev/null
fi
export PATH="$HOME/.local/bin:$PATH"
ok "uv $(uv --version | awk '{print $2}')"
CLAUDE_BIN="$(command -v claude || true)"
[ -n "$CLAUDE_BIN" ] || warn "claude CLI not found: MCP servers will not be registered (install Claude Code, then re-run)"

# ── repository ────────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd || true)"
if [ -n "$SCRIPT_DIR" ] && [ -f "$SCRIPT_DIR/../bin-run-bridge.sh" ]; then
  REPO="$(cd "$SCRIPT_DIR/.." && pwd)"
  ok "Using repository at $REPO"
else
  REPO="$INSTALL_DIR"
  if [ -d "$REPO/.git" ]; then
    say "Updating $REPO"; git -C "$REPO" pull -q --ff-only
  else
    say "Cloning $REPO_URL ($REPO_BRANCH) into $REPO"
    git clone -q --branch "$REPO_BRANCH" "$REPO_URL" "$REPO"
  fi
fi

# ── build bridge + python deps ────────────────────────────────────────────────
say "Building the bridge (first time downloads the Go toolchain, ~1 min)"
NO_RESTART=1 "$REPO/scripts/build-native-macos.sh" >/dev/null
ok "bridge built"
say "Installing the MCP server dependencies"
(cd "$REPO/whatsapp-mcp-server" && uv sync --quiet)
ok "python environment ready"

# ── helpers ───────────────────────────────────────────────────────────────────
account_port() { grep -E '^API_PORT=' "$WA_HOME/$1/.env" | cut -d= -f2; }
account_key()  { grep -E '^API_KEY=' "$WA_HOME/$1/.env" | cut -d= -f2; }

health() { curl -s -m 3 "http://127.0.0.1:$1/api/health" || true; }
tcp_busy() { (exec 3<>"/dev/tcp/127.0.0.1/$1") 2>/dev/null; }
port_busy() {  # reserved by an installed account / the repo-layout .env, or actually listening
  local f; for f in "$WA_HOME"/*/.env "$REPO/.env"; do
    [ -f "$f" ] && grep -qx "API_PORT=$1" "$f" && return 0
  done
  tcp_busy "$1"
}

wait_bridge() {  # $1 port, $2 launchd label
  local i pid; for i in $(seq 1 30); do
    pid="$(launchctl print "gui/$(id -u)/$2" 2>/dev/null | awk -F'= ' '/^[[:space:]]*pid = /{print $2}')"
    [ -n "$pid" ] && health "$1" | grep -q '"connected"' && return 0; sleep 2
  done; return 1
}

setup_account() {  # $1 name, $2 port
  local name="$1" port="$2" dir="$WA_HOME/$1"
  say "Account '$name' (port $port)"
  mkdir -p "$dir/store" && chmod 700 "$dir" "$dir/store"
  if [ ! -f "$dir/.env" ]; then
    cat > "$dir/.env" <<ENV
# WhatsApp MCP account '$name' — generated $(date +%F)
API_KEY=$(openssl rand -hex 32)
API_PORT=$port
API_BIND_HOST=127.0.0.1
BRIDGE_HOST=127.0.0.1:$port
TZ=$(readlink /etc/localtime | sed 's|.*/zoneinfo/||')
WHATSAPP_MCP_TOOLSETS=all
# Outgoing safety gate (empty = no restriction). Exact match; *@g.us = all groups.
WHATSAPP_ALLOWLIST_JIDS=
# Folders the bridge may send files from, besides /tmp (':'-separated)
MEDIA_ALLOWED_DIRS=$HOME/Documents:$HOME/Desktop:$HOME/Downloads
ENV
    chmod 600 "$dir/.env"; ok "created $dir/.env"
  else
    ok "keeping existing $dir/.env"
  fi

  local label="$LABEL_PREFIX.$name" plist="$HOME/Library/LaunchAgents/$LABEL_PREFIX.$name.plist"
  mkdir -p "$HOME/Library/LaunchAgents" "$HOME/Library/Logs"
  cat > "$plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>$label</string>
  <key>ProgramArguments</key><array>
    <string>/bin/bash</string><string>$REPO/bin-run-bridge.sh</string><string>$name</string>
  </array>
  <key>EnvironmentVariables</key><dict><key>WHATSAPP_MCP_HOME</key><string>$WA_HOME</string></dict>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>ThrottleInterval</key><integer>30</integer>
  <key>ProcessType</key><string>Background</string>
  <key>StandardOutPath</key><string>$HOME/Library/Logs/whatsapp-bridge-$name.log</string>
  <key>StandardErrorPath</key><string>$HOME/Library/Logs/whatsapp-bridge-$name.log</string>
</dict></plist>
PLIST
  # Re-install cleanly: unload a previous copy of the job and wait until launchd has let
  # go of the label and the old process has released the port (bootout is asynchronous)
  launchctl bootout "gui/$(id -u)/$label" >/dev/null 2>&1 || true
  local i; for i in $(seq 1 30); do
    launchctl print "gui/$(id -u)/$label" >/dev/null 2>&1 || tcp_busy "$port" || break; sleep 1
  done
  launchctl bootstrap "gui/$(id -u)" "$plist"
  wait_bridge "$port" "$label" || die "bridge '$name' did not start; see $HOME/Library/Logs/whatsapp-bridge-$name.log"
  ok "bridge running as login service $label"

  if [ -n "$CLAUDE_BIN" ]; then
    "$CLAUDE_BIN" mcp remove --scope user "whatsapp-$name" >/dev/null 2>&1 || true
    "$CLAUDE_BIN" mcp add --scope user "whatsapp-$name" -e "WHATSAPP_MCP_HOME=$WA_HOME" -- /bin/bash "$REPO/bin-run-mcp.sh" "$name" >/dev/null
    ok "registered MCP server 'whatsapp-$name' in Claude Code"
  fi
}

pair_account() {  # $1 name
  local name="$1" port key phone resp code i st
  port="$(account_port "$name")"; key="$(account_key "$name")"
  if health "$port" | grep -q '"needs_pairing":false'; then
    ok "'$name' is already paired"; return 0
  fi
  say "Pairing '$name' with WhatsApp"
  phone="$(ask "   Phone number for '$name' (with country code, e.g. +39 347 1234567): ")"
  phone="$(printf '%s' "$phone" | tr -cd '0-9')"
  [ -n "$phone" ] || { warn "no number given, skipping (re-run with --pair $name)"; return 0; }
  resp="$(curl -s -m 20 -X POST -H "X-API-Key: $key" -H 'Content-Type: application/json' \
          -d "{\"phone_number\":\"$phone\"}" "http://127.0.0.1:$port/api/pair")"
  code="$(printf '%s' "$resp" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("code",""))' 2>/dev/null || true)"
  [ -n "$code" ] || { warn "pairing request failed: $resp"; return 0; }
  printf '\n   On the phone: WhatsApp > Settings > Linked Devices > Link a Device > "Link with phone number instead"\n'
  printf '   Enter this code:  \033[1m%s\033[0m   (valid ~2.5 minutes)\n\n' "$code"
  for i in $(seq 1 90); do
    st="$(health "$port")"
    if printf '%s' "$st" | grep -q '"connected":true' && printf '%s' "$st" | grep -q '"needs_pairing":false'; then
      ok "'$name' paired and connected. History sync runs in the background for a few minutes."; return 0
    fi
    sleep 2
  done
  warn "still waiting for '$name'; check later with: curl http://127.0.0.1:$port/api/health"
}

# ── main ──────────────────────────────────────────────────────────────────────
if [ "${1:-}" = "--pair" ]; then
  [ -n "${2:-}" ] || die "usage: $0 --pair <account>"
  [ -f "$WA_HOME/$2/.env" ] || die "account '$2' not installed"
  pair_account "$2"; exit 0
fi

ACCOUNTS=("$@"); [ ${#ACCOUNTS[@]} -gt 0 ] || ACCOUNTS=(default)
for a in "${ACCOUNTS[@]}"; do
  printf '%s' "$a" | grep -Eq '^[a-z0-9][a-z0-9_-]*$' || die "account name '$a' must be lowercase letters, digits, - or _"
done

port=$BASE_PORT
for a in "${ACCOUNTS[@]}"; do
  if [ -f "$WA_HOME/$a/.env" ]; then port="$(account_port "$a")"; fi
  while ! [ -f "$WA_HOME/$a/.env" ] && port_busy "$port"; do port=$((port+1)); done
  setup_account "$a" "$port"
  port=$((port+1))
done
if [ -z "${SKIP_PAIR:-}" ]; then for a in "${ACCOUNTS[@]}"; do pair_account "$a"; done; fi

# Bridges that were already installed keep running the old binary until restarted
for svc in $(launchctl list 2>/dev/null | awk '$3 ~ /^com\.(whatsapp-mcp|lrnz\.whatsapp-bridge)/ {print $3}'); do
  case " ${ACCOUNTS[*]/#/$LABEL_PREFIX.} " in *" $svc "*) continue;; esac
  launchctl kickstart -k "gui/$(id -u)/$svc" 2>/dev/null && ok "restarted $svc with the new build"
done

say "Done"
cat <<TXT
   Accounts: ${ACCOUNTS[*]}   (config + data in $WA_HOME/<account>/)
   In Claude Code the tools appear in NEW sessions as: $(printf 'whatsapp-%s ' "${ACCOUNTS[@]}")
   Re-pair:      $REPO/scripts/install-macos.sh --pair <account>
   Update:       cd "$REPO" && git pull && scripts/build-native-macos.sh
   Claude Desktop: add to claude_desktop_config.json, for each account:
     "whatsapp-<account>": {"command": "/bin/bash", "args": ["$REPO/bin-run-mcp.sh", "<account>"]}
TXT
