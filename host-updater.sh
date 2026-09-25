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

# awk must read to the END. `{print $4; exit}` closed the pipe while curl was
# still streaming the rest of the JSON: curl died with 23 "Failed writing body",
# pipefail made that the pipeline's status, and set -e ended the update. It is a
# race on how the body arrives in chunks -- 1 run in 6 on a slow 22.04 lab VM,
# never on a fast link -- so it hits exactly the installs least able to notice.
LATEST_TAG=$(curl -fsSL "https://api.github.com/repos/${REPO}/releases/latest" \
             | awk -F'"' '/"tag_name":/ && !t {t=$4} END {print t}')
[ -n "${LATEST_TAG:-}" ] || { echo "could not resolve latest release"; exit 1; }
LATEST="${LATEST_TAG#v}"

if [ "$CURRENT" = "$LATEST" ]; then
    echo "[$(date -Iseconds)] up to date: $CURRENT"
    exit 0
fi

echo "[$(date -Iseconds)] updating $CURRENT -> $LATEST"

# Run the NEW release's updater, not this one. The self-refresh at the bottom
# only helped the update AFTER this one, so every fix to the apply sequence
# below reached customers a release late. Fetch it first; if it differs, hand
# over to it once (the env guard stops a loop). Any failure: carry on here.
if [ -z "${SAMM_UPDATER_HANDOFF:-}" ]; then
    NEW_SELF=$(mktemp)
    if curl -fsSL "https://github.com/${REPO}/releases/download/${LATEST_TAG}/host-updater.sh" -o "$NEW_SELF" \
       && head -1 "$NEW_SELF" | grep -q '^#!/usr/bin/env bash' && bash -n "$NEW_SELF" \
       && ! cmp -s "$NEW_SELF" "$INSTALL_DIR/host-updater.sh"; then
        chmod 0755 "$NEW_SELF" && mv "$NEW_SELF" "$INSTALL_DIR/host-updater.sh"
        echo "[$(date -Iseconds)] handing over to the $LATEST updater"
        SAMM_UPDATER_HANDOFF=1 exec "$INSTALL_DIR/host-updater.sh"
    fi
    rm -f "$NEW_SELF"
fi

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

# Apply in stages so RADIUS keeps answering. A plain `up -d` stopped every
# container at once and FreeRADIUS then waited for samm-api to become healthy,
# migrations included -- logins failed for that whole window. Instead, as the
# bare-OS updater does:
#   1. stop the background daemons (they must not run on a half-migrated schema);
#   2. recreate samm-api alone -- it runs the migrations -- while the OLD
#      FreeRADIUS container keeps authenticating;
#   3. once samm-api is healthy, bring everything else up on the new images.
# A step that fails falls through to the plain `up -d`, which is what ran before.
staged_up() {
    docker compose stop samm-worker samm-radius samm-notification samm-telegram || return 1
    docker compose up -d --no-deps samm-api || return 1
    local waited=0 h=""
    while [ "$waited" -lt 900 ]; do
        h=$(docker inspect -f '{{.State.Health.Status}}' "$(docker compose ps -q samm-api)" 2>/dev/null || true)
        [ "$h" = healthy ] && return 0
        sleep 5; waited=$((waited + 5))
    done
    echo "samm-api not healthy after 15 min (last: ${h:-unknown})"; return 1
}
staged_up || echo "[$(date -Iseconds)] staged apply incomplete; starting everything"
docker compose up -d

# Refresh this script too. Nothing else ever replaces it, so without this a fix
# to the updater would only reach installs that re-run install.sh. Best effort,
# and last: the stack is already updated. mv gives the new file a new inode, so
# the copy bash is still reading from is untouched.
NEW_SELF=$(mktemp)
if curl -fsSL "https://github.com/${REPO}/releases/download/${LATEST_TAG}/host-updater.sh" -o "$NEW_SELF" \
   && head -1 "$NEW_SELF" | grep -q '^#!/usr/bin/env bash' && bash -n "$NEW_SELF"; then
    chmod 0755 "$NEW_SELF" && mv "$NEW_SELF" "$INSTALL_DIR/host-updater.sh"
else
    rm -f "$NEW_SELF"
fi

echo "[$(date -Iseconds)] updated to $LATEST"
