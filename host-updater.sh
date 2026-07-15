#!/usr/bin/env bash
# Daily auto-update for SAMM docker installs.
#
# Recommended cron entry:
#   0 4 * * * /opt/samm-docker/host-updater.sh >> /var/log/samm-update.log 2>&1
#
# What it does:
#   1. Read the currently-installed version from docker-compose.yml (header)
#   2. Query github.com/mhdhaidarah/samm-docker for the latest release tag
#   3. If newer: download the new docker-compose.yml, carry your existing
#      POSTGRES_PASSWORD / WA_BRIDGE_TOKEN into it (they live in the compose —
#      no .env), back up the old file, then `docker compose pull` + `up -d`
#   4. Otherwise: log "up to date" and exit 0
#
# Failures don't change running state — if any step before `up -d` fails the
# previous compose file is left in place and the stack keeps running.

set -euo pipefail

INSTALL_DIR=/opt/samm-docker
REPO=mhdhaidarah/samm-docker
COMPOSE_FILE="$INSTALL_DIR/docker-compose.yml"
PW_PLACEHOLDER="change-me-strong-random-string"
TOKEN_PLACEHOLDER="change-me-random-token"

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

# ---- carry credentials from the running compose (or a legacy .env) ----------
PG_PW=$(awk '/^ *POSTGRES_PASSWORD:/{print $2; exit}' "$COMPOSE_FILE" || true)
WA_TOKEN=$(awk '/^ *WA_BRIDGE_TOKEN:/{print $2; exit}' "$COMPOSE_FILE" || true)
if [ -f "$INSTALL_DIR/.env" ]; then   # legacy layout (pre-3.9.2)
    { [ -z "$PG_PW" ] || [ "$PG_PW" = "$PW_PLACEHOLDER" ]; } \
      && PG_PW=$(awk -F= '/^POSTGRES_PASSWORD=/{print $2; exit}' "$INSTALL_DIR/.env" || true)
    { [ -z "$WA_TOKEN" ] || [ "$WA_TOKEN" = "$TOKEN_PLACEHOLDER" ]; } \
      && WA_TOKEN=$(awk -F= '/^WA_BRIDGE_TOKEN=/{print $2; exit}' "$INSTALL_DIR/.env" || true)
fi
[ -n "$PG_PW" ] && [ "$PG_PW" != "$PW_PLACEHOLDER" ] \
  || { echo "cannot determine current POSTGRES_PASSWORD — refusing to update"; exit 1; }
if [ -z "$WA_TOKEN" ] || [ "$WA_TOKEN" = "$TOKEN_PLACEHOLDER" ]; then
    WA_TOKEN=$(python3 -c "import secrets; print(secrets.token_urlsafe(32))" 2>/dev/null \
             || openssl rand -base64 32 | tr -d '=+/' | head -c 43)
fi

cp "$COMPOSE_FILE" "${COMPOSE_FILE}.bak.$(date +%Y%m%d-%H%M%S)"

TMP=$(mktemp)
trap 'rm -f "$TMP"' EXIT
curl -fsSL "https://github.com/${REPO}/releases/download/${LATEST_TAG}/docker-compose.yml" -o "$TMP"
sed -i \
    -e "s|${PW_PLACEHOLDER}|${PG_PW}|g" \
    -e "s|${TOKEN_PLACEHOLDER}|${WA_TOKEN}|g" \
    "$TMP"
grep -q "$PW_PLACEHOLDER" "$TMP" && { echo "password carry-over failed"; exit 1; }
mv "$TMP" "$COMPOSE_FILE"
chmod 600 "$COMPOSE_FILE"

docker compose pull
docker compose up -d

echo "[$(date -Iseconds)] updated to $LATEST"
