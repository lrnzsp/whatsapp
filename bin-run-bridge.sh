#!/usr/bin/env bash
# Author: Fabian Bitter (fabian@bitter.de)
# Launch the WhatsApp bridge with its .env, for the launchd KeepAlive wrapper.
set -euo pipefail
# Resolve the repo from this script's location so it works from any checkout
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$DIR/whatsapp-bridge"
set -a; . "$DIR/.env"; set +a
exec "$DIR/whatsapp-bridge/whatsapp-bridge"
