#!/usr/bin/env bash
# Build the bridge as a native macOS binary (no Docker) and restart the launchd
# service if one is installed. Uses `go` from PATH, otherwise fetches the official
# toolchain (checksum-verified) into a cache dir. Needs the Xcode Command Line Tools.
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/whatsapp-bridge-build"
LABEL="${BRIDGE_LAUNCHD_LABEL:-com.lrnz.whatsapp-bridge}"

if ! command -v go >/dev/null 2>&1; then
  if [ ! -x "$CACHE/go/bin/go" ]; then
    mkdir -p "$CACHE"
    arch=$([ "$(uname -m)" = arm64 ] && echo arm64 || echo amd64)
    read -r fn sha < <(curl -fsSL 'https://go.dev/dl/?mode=json' | python3 -c "
import json,sys
for r in json.load(sys.stdin):
    for f in r['files']:
        if r['stable'] and f['os']=='darwin' and f['arch']=='$arch' and f['kind']=='archive':
            print(f['filename'], f['sha256']); sys.exit()")
    echo "Downloading $fn ..."
    curl -fsSL -o "$CACHE/$fn" "https://go.dev/dl/$fn"
    [ "$(shasum -a 256 "$CACHE/$fn" | cut -d' ' -f1)" = "$sha" ] || { echo "checksum mismatch" >&2; exit 1; }
    tar -xzf "$CACHE/$fn" -C "$CACHE" && rm -f "$CACHE/$fn"
  fi
  export PATH="$CACHE/go/bin:$PATH"
fi

# The standalone Command Line Tools compile cgo (go-sqlite3) without the full Xcode license
[ -d /Library/Developer/CommandLineTools ] && export DEVELOPER_DIR=/Library/Developer/CommandLineTools
cd "$DIR/whatsapp-bridge"
CGO_ENABLED=1 go build -o whatsapp-bridge.new .
mv -f whatsapp-bridge.new whatsapp-bridge
echo "Built $(pwd)/whatsapp-bridge"

if launchctl print "gui/$(id -u)/$LABEL" >/dev/null 2>&1; then
  launchctl kickstart -k "gui/$(id -u)/$LABEL" && echo "Restarted $LABEL"
fi
