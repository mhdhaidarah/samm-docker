#!/usr/bin/env bash
# Daily auto-update for SAMM docker installs.
#
# Recommended cron entry:
#   0 4 * * * /opt/samm-docker/host-updater.sh >> /var/log/samm-update.log 2>&1
#
# What it does:
#   1. Read the currently-installed version from docker-compose.yml (header)
#   2. Query github.com/mhdhaidarah/samm-docker for the latest release tag
#   3. If newer: download the new docker-compose.yml (which pins the new
#      image digest), back up the old one, then `docker compose pull` +
#      `docker compose up -d`
#   4. Otherwise: log "up to date" and exit 0
#
# Failures don't change running state — if any step before `up -d` fails the
# previous compose file is left in place and the stack keeps running.

set -euo pipefail

INSTALL_DIR=/opt/samm-docker
REPO=mhdhaidarah/samm-docker
COMPOSE_FILE="$INSTALL_DIR/docker-compose.yml"

cd "$INSTALL_DIR"

[ -f "$COMPOSE_FILE" ] || { echo "no docker-compose.yml at $COMPOSE_FILE"; exit 1; }

CURRENT=$(awk -F': ' '/^# version: /{print $2; exit}' "$COMPOSE_FILE" || true)
CURRENT="${CURRENT:-unknown}"

LATEST_TAG=$(curl -fsSL "https://api.github.com/repos/${REPO}/releases/latest" \
             | awk -F'"' '/"tag_name":/{print $4; exit}')
[ -n "${LATEST_TAG:-}" ] || { echo "could not resolve latest release"; exit 1; }
LATEST="${LATEST_TAG#v}"

if [ "$CURRENT" = "$LATEST" ]; then
    echo "[$(date -Iseconds)] up to date: $CURRENT"
    exit 0
fi

echo "[$(date -Iseconds)] updating $CURRENT -> $LATEST"

cp "$COMPOSE_FILE" "${COMPOSE_FILE}.bak.$(date +%Y%m%d-%H%M%S)"

TMP=$(mktemp)
trap 'rm -f "$TMP"' EXIT
curl -fsSL "https://github.com/${REPO}/releases/download/${LATEST_TAG}/docker-compose.yml" -o "$TMP"
mv "$TMP" "$COMPOSE_FILE"

# The WhatsApp bridge is a digest-pinned image in the new compose — `docker
# compose pull` below fetches the matching version, nothing else to refresh.

# Ensure the WhatsApp bridge token exists — .env files from before the bridge
# existed lack it, and the wa-bridge service requires it once the profile is on.
if [ -f "$INSTALL_DIR/.env" ] && ! grep -q '^WA_BRIDGE_TOKEN=' "$INSTALL_DIR/.env"; then
    WA_TOKEN=$(python3 -c "import secrets; print(secrets.token_urlsafe(32))" 2>/dev/null \
             || openssl rand -base64 32 | tr -d '=+/' | head -c 43)
    printf 'WA_BRIDGE_TOKEN=%s\n' "$WA_TOKEN" >> "$INSTALL_DIR/.env"
fi

docker compose pull
docker compose up -d

echo "[$(date -Iseconds)] updated to $LATEST"
