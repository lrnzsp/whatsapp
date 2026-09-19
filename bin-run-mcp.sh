#!/usr/bin/env bash
# Launch the WhatsApp MCP server (stdio) with the repo's .env, for MCP clients
# such as Claude Code / Claude Desktop running it natively (no Docker).
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
set -a; . "$DIR/.env"; set +a
export MCP_TRANSPORT=stdio
# GUI apps start with a minimal PATH: look for uv in the usual places too
UV="$(command -v uv || true)"
for c in "$HOME/.local/bin/uv" "$HOME/.homebrew/bin/uv" /opt/homebrew/bin/uv /usr/local/bin/uv "$HOME/.cargo/bin/uv"; do
  [ -n "$UV" ] && break; [ -x "$c" ] && UV="$c"
done
[ -n "$UV" ] || { echo "uv not found" >&2; exit 1; }
exec "$UV" run --quiet --directory "$DIR/whatsapp-mcp-server" python main.py
