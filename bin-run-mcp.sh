#!/usr/bin/env bash
# Launch the WhatsApp MCP server (stdio) for MCP clients such as Claude Code /
# Claude Desktop running it natively (no Docker).
#
#   bin-run-mcp.sh            repo layout: loads <repo>/.env, store in <repo>/whatsapp-bridge/store
#   bin-run-mcp.sh <account>  account layout: $WHATSAPP_MCP_HOME/<account>/{.env,store}
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ACCOUNT="${1:-}"
if [ -n "$ACCOUNT" ]; then
  WORK="${WHATSAPP_MCP_HOME:-$HOME/.whatsapp-mcp}/$ACCOUNT"
  ENV_FILE="$WORK/.env"
  export WA_STORE_PATH="$WORK/store"
else
  ENV_FILE="$DIR/.env"
fi
[ -f "$ENV_FILE" ] || { echo "bin-run-mcp: $ENV_FILE not found" >&2; exit 1; }
set -a; . "$ENV_FILE"; set +a
export MCP_TRANSPORT=stdio
# GUI apps start with a minimal PATH: look for uv in the usual places too
UV="$(command -v uv || true)"
for c in "$HOME/.local/bin/uv" "$HOME/.homebrew/bin/uv" /opt/homebrew/bin/uv /usr/local/bin/uv "$HOME/.cargo/bin/uv"; do
  [ -n "$UV" ] && break; [ -x "$c" ] && UV="$c"
done
[ -n "$UV" ] || { echo "uv not found" >&2; exit 1; }
exec "$UV" run --quiet --directory "$DIR/whatsapp-mcp-server" python main.py
