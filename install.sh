#!/usr/bin/env bash
# SAMM Docker installer — one-shot bootstrap.
# Generated for SAMM v3.6.10.
#
#   curl -fsSL https://github.com/mhdhaidarah/samm-docker/releases/download/v3.6.10/install.sh | sudo bash
#
# What this does:
#   1. Verify root + supported OS (Ubuntu/Debian)
#   2. Install Docker engine + compose plugin if missing
#   3. Create /opt/samm-docker/
#   4. Download docker-compose.yml + .env.example for SAMM v3.6.10
#   5. Generate a secure POSTGRES_PASSWORD into .env (preserves an existing .env)
#   6. docker compose pull && docker compose up -d
#   7. Print admin URL + first-login info
#
# Safe to re-run — upgrades the compose file + image; never overwrites .env.
set -euo pipefail

VERSION="3.6.10"
INSTALL_DIR=/opt/samm-docker
REPO=mhdhaidarah/samm-docker
RELEASE_URL="https://github.com/${REPO}/releases/download/v${VERSION}"

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
    c_reset=$'\033[0m'; c_bold=$'\033[1m'
    c_grn=$'\033[32m'; c_ylw=$'\033[33m'; c_red=$'\033[31m'
else
    c_reset=''; c_bold=''; c_grn=''; c_ylw=''; c_red=''
fi
say()  { printf '%s==>%s %s\n' "$c_bold$c_grn" "$c_reset" "$1"; }
warn() { printf '%s!! %s %s\n' "$c_bold$c_ylw" "$c_reset" "$1" >&2; }
die()  { printf '%sxx %s %s\n' "$c_bold$c_red" "$c_reset" "$1" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || die "must run as root — use: curl ... | sudo bash"
[ -r /etc/os-release ] || die "cannot read /etc/os-release"
# shellcheck disable=SC1091
. /etc/os-release
case "${ID:-}" in
    ubuntu|debian) ;;
    *) die "unsupported OS: ${PRETTY_NAME:-unknown}. v1 supports Ubuntu/Debian only." ;;
esac

# ---------- Docker engine + compose plugin ----------
if ! command -v docker >/dev/null 2>&1; then
    say "installing docker engine"
    apt-get update -qq
    apt-get install -y -qq docker.io docker-compose-v2 2>/dev/null \
      || apt-get install -y -qq docker.io docker-compose-plugin
fi
if ! docker compose version >/dev/null 2>&1; then
    say "installing docker compose plugin"
    apt-get install -y -qq docker-compose-v2 2>/dev/null \
      || apt-get install -y -qq docker-compose-plugin
fi
systemctl enable --now docker >/dev/null 2>&1 || true

# ---------- Install dir ----------
mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR"

# ---------- Compose + env ----------
say "downloading docker-compose for SAMM v${VERSION}"
curl -fsSL "${RELEASE_URL}/docker-compose.yml" -o docker-compose.yml.new
mv docker-compose.yml.new docker-compose.yml

say "downloading host-updater.sh (use it in cron for auto-upgrades)"
curl -fsSL "${RELEASE_URL}/host-updater.sh" -o host-updater.sh
chmod +x host-updater.sh

# The WhatsApp QR bridge is a self-contained image (mhdhaidarah/samm:wa-bridge-*)
# pulled by the compose stack — nothing to download here.

if [ ! -f .env ]; then
    say "generating .env (first install)"
    curl -fsSL "${RELEASE_URL}/env.example" -o .env.tmp

    PG_PW=$(python3 -c "import secrets; print(secrets.token_urlsafe(32))" 2>/dev/null \
          || openssl rand -base64 32 | tr -d '=+/' | head -c 43)
    WA_TOKEN=$(python3 -c "import secrets; print(secrets.token_urlsafe(32))" 2>/dev/null \
          || openssl rand -base64 32 | tr -d '=+/' | head -c 43)
    LAN_IP=$(ip -4 -o route get 1 2>/dev/null \
             | awk '{for(i=1;i<=NF;i++)if($i=="src"){print $(i+1); exit}}' || true)
    LAN_IP="${LAN_IP:-127.0.0.1}"

    sed -i \
        -e "s|__GENERATED_POSTGRES_PASSWORD__|${PG_PW}|" \
        -e "s|__GENERATED_WA_BRIDGE_TOKEN__|${WA_TOKEN}|" \
        -e "s|__DETECTED_HOST__|${LAN_IP}|" \
        .env.tmp
    mv .env.tmp .env
    chmod 600 .env
else
    warn ".env already exists — leaving it alone. Edit then 'docker compose up -d' to apply changes."
    LAN_IP=$(awk -F= '/^SAMM_PUBLIC_HOST=/{print $2}' .env || true)
    LAN_IP="${LAN_IP:-127.0.0.1}"
fi

# ---------- systemd unit (boot startup) ----------
# Belt-and-suspenders alongside compose's `restart: unless-stopped`. The
# restart policy survives Docker daemon restarts; this systemd unit also
# brings the stack back up even after a `docker compose down`.
say "installing samm-docker.service (boot startup)"
cat > /etc/systemd/system/samm-docker.service <<EOF
[Unit]
Description=SAMM Docker Compose stack
Requires=docker.service
After=docker.service network-online.target
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=true
WorkingDirectory=${INSTALL_DIR}
ExecStart=/usr/bin/docker compose up -d
ExecStop=/usr/bin/docker compose down

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload

# ---------- cron entry (daily auto-update) ----------
# host-updater.sh checks the latest release tag, downloads the matching
# digest-pinned compose, and pulls the new image. No-op when up to date.
# Remove /etc/cron.d/samm-docker to disable auto-updates.
say "installing /etc/cron.d/samm-docker (daily auto-update at 04:00)"
cat > /etc/cron.d/samm-docker <<EOF
# SAMM Docker auto-update — runs daily at 04:00 local time.
# Edit the schedule below or remove this file to disable.
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
0 4 * * * root ${INSTALL_DIR}/host-updater.sh >> /var/log/samm-update.log 2>&1
EOF
chmod 0644 /etc/cron.d/samm-docker

# ---------- Pull + bring stack up via systemd ----------
say "pulling SAMM image (this can take a few minutes on first install)"
docker compose pull --quiet

say "starting SAMM services (enabled on boot via samm-docker.service)"
systemctl enable --now samm-docker.service

# ---------- Post-install info ----------
API_PORT=$(awk -F= '/^SAMM_API_PORT=/{print $2}' .env)
API_PORT="${API_PORT:-8000}"

echo
printf '%s==============================================================%s\n' "$c_bold" "$c_reset"
say "SAMM v${VERSION} is starting up — give it ~30s before opening the portal"
echo
printf '  Admin portal:    %shttp://%s:%s/admin%s\n'    "$c_bold" "$LAN_IP" "$API_PORT" "$c_reset"
printf '  Customer portal: %shttp://%s:%s/%s\n'         "$c_bold" "$LAN_IP" "$API_PORT" "$c_reset"
echo
echo  "Default credentials:  admin / admin  (change immediately after first login)"
echo
echo  "Point your MikroTik NAS at this host's LAN IP for RADIUS:"
printf '  Auth: %s:1812/udp     Acct: %s:1813/udp\n' "$LAN_IP" "$LAN_IP"
echo  "  Shared secret is set in the SAMM admin portal under System -> RADIUS."
echo
echo  "Follow logs:  cd $INSTALL_DIR && docker compose logs -f"
echo  "Stop:         cd $INSTALL_DIR && docker compose down"
echo
echo  "Auto-restart on reboot:  systemd unit samm-docker.service (enabled)"
echo  "Auto-update:             /etc/cron.d/samm-docker → daily 04:00 → host-updater.sh"
echo  "  Disable with: sudo systemctl disable samm-docker.service"
echo  "                sudo rm /etc/cron.d/samm-docker"
printf '%s==============================================================%s\n' "$c_bold" "$c_reset"
