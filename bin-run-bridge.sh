#!/usr/bin/env bash
# Author: Fabian Bitter (fabian@bitter.de)
# Launch the WhatsApp bridge with its .env, for the launchd KeepAlive wrapper.
#
#   bin-run-bridge.sh            repo layout: <repo>/.env, store in <repo>/whatsapp-bridge/store
#   bin-run-bridge.sh <account>  account layout: $WHATSAPP_MCP_HOME/<account>/{.env,store}
#                                (default home: ~/.whatsapp-mcp), one bridge per WhatsApp number
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ACCOUNT="${1:-}"
if [ -n "$ACCOUNT" ]; then
  WORK="${WHATSAPP_MCP_HOME:-$HOME/.whatsapp-mcp}/$ACCOUNT"
  ENV_FILE="$WORK/.env"
else
  WORK="$DIR/whatsapp-bridge"
  ENV_FILE="$DIR/.env"
fi
[ -f "$ENV_FILE" ] || { echo "bin-run-bridge: $ENV_FILE not found" >&2; exit 1; }
cd "$WORK"
set -a; . "$ENV_FILE"; set +a
exec "$DIR/whatsapp-bridge/whatsapp-bridge"
