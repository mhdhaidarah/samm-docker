<div align="center">

<img src="s-box-logo.svg" width="96" alt="SAMM logo" />

# SAMM — Docker

### SecuryTik Active MikroTik Manager — Docker Compose distribution

**ISP management platform for MikroTik PPPoE & Hotspot, packaged as Docker Compose**

[![Release](https://img.shields.io/github/v/release/mhdhaidarah/samm-docker?style=flat-square&color=3b82f6&label=latest%20release)](https://github.com/mhdhaidarah/samm-docker/releases/latest)
[![Docker Image](https://img.shields.io/badge/Docker%20Hub-mhdhaidarah%2Fsamm-2496ED?logo=docker&logoColor=white&style=flat-square)](https://hub.docker.com/r/mhdhaidarah/samm)
[![Compose](https://img.shields.io/badge/Docker_Compose-v2-2496ED?logo=docker&logoColor=white&style=flat-square)](https://docs.docker.com/compose/)
[![PostgreSQL](https://img.shields.io/badge/PostgreSQL-16-4169E1?logo=postgresql&logoColor=white&style=flat-square)](https://postgresql.org)
[![FreeRADIUS](https://img.shields.io/badge/FreeRADIUS-3-CC0000?style=flat-square&logoColor=white)](https://freeradius.org)
[![A SecuryTik product](https://img.shields.io/badge/a-SecuryTik%20product-22d3ee?style=flat-square)](https://securytik.com)

[**samm.securytik.com**](https://samm.securytik.com) &nbsp;·&nbsp; [Documentation](https://samm.securytik.com/docs) &nbsp;·&nbsp; [Bare-OS install](https://github.com/mhdhaidarah/samm) &nbsp;·&nbsp; [Report a Bug](mailto:samm@securytik.com?subject=SAMM%20Docker%20Bug%20Report)

</div>

---

## Overview

SAMM is an ISP management platform built on FreeRADIUS and PostgreSQL. It handles subscriber authentication, real-time usage enforcement, and billing for MikroTik PPPoE and Hotspot deployments — with a polished web portal for administrators and customers.

This repository is the **Docker Compose distribution** of SAMM. Source stays closed: the published image `mhdhaidarah/samm` is built from Cython-compiled binaries — no `.py` source for the compiled modules. The bare-OS install lives at **[mhdhaidarah/samm →](https://github.com/mhdhaidarah/samm)**.

```
MikroTik(s) ──Auth/Acct──► freeradius (container, :1812/:1813)
                ▲                       │
                │                       ▼
                └─ CoA / Disconnect ◄── samm-radius · samm-worker · samm-api · samm-notification · samm-telegram
                                        │
                                        ▼
                                    postgres (container)
```

Every release publishes:

- 🐳 **Docker image** `mhdhaidarah/samm:<ver>` to [Docker Hub](https://hub.docker.com/r/mhdhaidarah/samm), pinned to a sha256 digest
- 📦 **Compose bundle** (`docker-compose.yml`, `install.sh`, `host-updater.sh`, `.env.example`, `README.md`) to this repo's [Releases](https://github.com/mhdhaidarah/samm-docker/releases)

CI in the private source repo fires both on every `v*` tag push, so the bare-OS tarball and this Docker bundle stay version-locked.

---

## Two ways to install

| | One-line install | Manual Compose |
|---|---|---|
| When | Hosts where `curl … \| sudo bash` is allowed | Restricted environments — locked-down boxes, behind allowlists, or "I want to read the file first" |
| Command | `curl -fsSL … install.sh \| sudo bash` | `git clone` + edit `.env` + `docker compose up -d` |
| Pinning | Pinned to the matching image digest (per release) | Tracks `mhdhaidarah/samm:latest` by default |
| Pace | Drops everything into `/opt/samm-docker/` and starts containers | You control every step |

Both end with SAMM running on the host's LAN IP, RADIUS on UDP 1812/1813, and the admin/customer portal at `http://<host>:8000/`.

---

## Quick install (Ubuntu / Debian)

```bash
curl -fsSL https://github.com/mhdhaidarah/samm-docker/releases/latest/download/install.sh \
    | sudo bash
```

The installer detects Docker, installs it if missing, drops a `docker-compose.yml` + `.env` into `/opt/samm-docker/`, and brings the stack up. Safe to re-run for upgrades — `.env` is preserved.

After ~30 seconds:

- **Admin portal**     `http://<host>:8000/admin`
- **Customer portal**  `http://<host>:8000/`
- **RADIUS auth**      UDP 1812 on the host's LAN IP
- **RADIUS accounting** UDP 1813 on the host's LAN IP

Default credentials: `admin` / `samm` — **change on first login**.

---

## Manual Compose install (no curl-pipe)

For hosts that can't (or shouldn't) run `curl | bash` directly — e.g. machines behind strict egress policies, or any operator who'd rather audit every step.

```bash
git clone https://github.com/mhdhaidarah/samm-docker.git
cd samm-docker
cp .env.example .env
$EDITOR .env                    # set POSTGRES_PASSWORD and SAMM_PUBLIC_HOST
docker compose up -d
```

The repo-root `docker-compose.yaml` references `mhdhaidarah/samm:latest`, so a plain `docker compose pull && docker compose up -d` always brings you to the current version.

If you want a **version-pinned** compose file (recommended for production — pinned by sha256 digest, immutable), grab the per-release one from the matching GitHub Release:

```bash
curl -fLO https://github.com/mhdhaidarah/samm-docker/releases/latest/download/docker-compose.yml
```

That digest-pinned version is what `install.sh` deploys.

---

## Windows (Docker Desktop) — evaluation only

You can run SAMM on Windows via Docker Desktop + WSL2. **Not recommended for production** because:

- Windows **sleep / hibernate / lid-close stops the containers** — there's no equivalent of a Linux server that just stays up
- Auto-restart on host boot only fires when WSL boots (not when Windows boots)
- Daily auto-update cron only runs while WSL is alive
- No 24/7 reliability guarantee for RADIUS auth and accounting

Use it for evaluation / demo, then deploy production on a Linux VM (Hyper-V, Proxmox, ESXi) or a small physical box (NUC running Ubuntu Server).

**Evaluation steps:**

1. Install [Docker Desktop](https://www.docker.com/products/docker-desktop) and let it set up the WSL2 backend.

2. Open **PowerShell** (no admin needed) and grab the compose bundle:
   ```powershell
   mkdir C:\samm-docker
   cd C:\samm-docker
   curl.exe -fLO https://github.com/mhdhaidarah/samm-docker/releases/latest/download/docker-compose.yml
   curl.exe -fLO https://github.com/mhdhaidarah/samm-docker/releases/latest/download/env.example
   copy env.example .env
   notepad .env
   ```
   *(Use `curl.exe` explicitly — PowerShell's `curl` alias is `Invoke-WebRequest` with different flags.)*

3. In Notepad, edit `.env`:
   - `POSTGRES_PASSWORD=` — any strong random string (≥16 chars)
   - `SAMM_PUBLIC_HOST=` — your Windows LAN IPv4 (run `ipconfig` to find it)

   Save and close.

4. Pull and start:
   ```powershell
   docker compose pull
   docker compose up -d
   ```

5. **Watch it boot in Docker Desktop** → Containers tab → the `samm` group shows 7 services (postgres, samm-api, samm-radius, samm-worker, samm-notification, samm-telegram, freeradius). All turn green within ~30 s.

6. Open `http://localhost:8000/admin` — login `admin` / `samm` (change immediately).

7. **If testing RADIUS from a real MikroTik**: Windows Defender Firewall may prompt the first time MikroTik sends UDP 1812 — accept it. Or pre-allow:
   ```powershell
   New-NetFirewallRule -DisplayName "SAMM RADIUS" -Direction Inbound -Protocol UDP -LocalPort 1812,1813 -Action Allow
   ```
   Point MikroTik at `<windows-ip>:1812/1813`.

**Day-to-day:**

- Right-click the `samm` stack in Docker Desktop → Stop / Start / Logs
- Or from PowerShell: `cd C:\samm-docker; docker compose down` and `docker compose up -d`

**Tear down completely:**
```powershell
cd C:\samm-docker
docker compose down -v   # -v wipes postgres + Fernet key
Remove-Item -Recurse C:\samm-docker
```

---

## What it ships

| Container | Image | Role |
|---|---|---|
| `postgres` | `postgres:16-alpine` | Subscriber + billing + accounting DB |
| `samm-api` | `mhdhaidarah/samm` | FastAPI admin + customer portal (port 8000) |
| `samm-radius` | `mhdhaidarah/samm` | Time-driven AAA: expiration / quota / daily reset + CoA dispatch |
| `samm-worker` | `mhdhaidarah/samm` | MikroTik API inventory + ICMP ping sweep |
| `samm-notification` | `mhdhaidarah/samm` | Email + Telegram notification outbox drain |
| `samm-telegram` | `mhdhaidarah/samm` | Long-polling Telegram self-service bot |
| `freeradius` | `freeradius/freeradius-server:3` | FreeRADIUS with SAMM-rendered config |

All five SAMM containers run the same `mhdhaidarah/samm:<ver>` image — different `command:` per role. The release's `docker-compose.yml` pins the image by `sha256` digest, so even if Docker Hub were compromised a stale digest can't substitute a different image.

### Features (same as bare-OS)

- **AAA core** — FreeRADIUS 3 + PostgreSQL, PAP/CHAP, PPPoE + Hotspot, hybrid CoA (CoA-Update → fallback Disconnect), dynamic NAS registration
- **Plans & limits** — 4 independent limits per plan (`expiration`, `quota`, `uptime`, `daily`), speed-window scheduling, non-resettable billing counters
- **Financial accounting** — double-entry engine, invoices, expenses, resellers, depreciation
- **Admin portal** — customer + plan management, live MikroTik inventory, voucher card generation, role-based permissions
- **Customer portal** — self-service usage / invoices / tickets
- **Telegram self-service bot** — interactive verify, profile, plan, ticket flows
- **6 languages** (English / Arabic RTL / Turkish / French / Spanish / German), **11 themes**, all switchable per user

---

## Network requirements

- Host needs **UDP 1812 + 1813** free. **Don't run docker SAMM alongside a bare-OS SAMM** on the same host — they'd fight for those ports. If switching from bare-OS, run `apt purge freeradius postgresql` first (back up first if you have data).
- The `freeradius` container exposes UDP 1812 + 1813 via standard compose port mapping. **No host networking needed** — the kernel forwards inbound UDP to the container transparently.
- MikroTik NAS points to **the host's LAN IP** on 1812/1813. The shared secret is set in the SAMM admin portal under *System → RADIUS*.
- Outbound to MikroTik routers (API on `:8728`, CoA on `:3799`, ICMP for monitoring) works over the standard Docker bridge with NAT — no special routing.

---

## Configuration

`.env` (created by `install.sh` from `.env.example`):

```bash
POSTGRES_PASSWORD=<auto-generated 32-byte urlsafe>
SAMM_PUBLIC_HOST=<auto-detected LAN IP>
SAMM_API_PORT=8000
TZ=UTC
```

Persisted state lives in two Docker volumes:

- `samm_pgdata` — Postgres data files
- `samm_etcsamm` — Fernet key (`secret.key`) + the auto-rendered `samm.yaml`

The Fernet key encrypts MikroTik API passwords stored in the DB. **Back up both volumes together** — losing `samm_etcsamm` means losing the ability to decrypt those passwords.

```bash
sudo docker run --rm \
    -v samm_pgdata:/src/pgdata:ro \
    -v samm_etcsamm:/src/etcsamm:ro \
    -v "$(pwd):/out" \
    alpine tar czf "/out/samm-backup-$(date +%F).tar.gz" -C /src .
```

---

## Boot startup

`install.sh` installs `samm-docker.service` (systemd, enabled). The stack comes back up after a host reboot — even if you ran `docker compose down` before shutdown. Belt-and-suspenders alongside compose's `restart: unless-stopped`: the restart policy survives Docker daemon restarts, the systemd unit covers explicit-down + reboot.

```bash
systemctl status samm-docker            # see boot-unit status
sudo systemctl disable samm-docker      # opt out of boot-start
sudo systemctl enable samm-docker       # opt back in
```

---

## Upgrading

### Automatic (cron — set up for you)

`install.sh` configures auto-update — nothing to do:

- `/opt/samm-docker/host-updater.sh` — the upgrade script
- `/etc/cron.d/samm-docker` — runs `host-updater.sh` **daily at 04:00**
- `/var/log/samm-update.log` — captures stdout + stderr each run

Each run: queries the latest release tag, downloads the matching digest-pinned `docker-compose.yml`, then `docker compose pull && docker compose up -d`. No-op when nothing's new.

Disable: `sudo rm /etc/cron.d/samm-docker`. Change schedule by editing that file.

### Manual

Re-run the installer:

```bash
sudo curl -fsSL https://github.com/mhdhaidarah/samm-docker/releases/latest/download/install.sh \
    | sudo bash
```

This refreshes the compose file + pulls the new image. **`.env` is preserved.**

Or with the manual Compose path:

```bash
cd /path/to/your/samm-docker
git pull
docker compose pull
docker compose up -d
```

---

## Service management

```bash
cd /opt/samm-docker         # (or your install dir)

docker compose ps           # status of all containers
docker compose logs -f      # follow logs from all services
docker compose logs -f samm-api samm-radius   # follow specific services
docker compose restart samm-api               # restart one service
docker compose down         # stop the stack (keep volumes)
docker compose down -v      # stop + WIPE volumes (postgres + fernet key)
```

---

## Licensing

Each install is licensed per device:

| Tier | AAA users | Hotspot cards | NAS / routers |
|---|---|---|---|
| **Free** | 100 | 500 | 2 |
| **Pro** | 2,000 | 5,000 | 5 |
| **Pro Max** | unlimited | unlimited | unlimited |

Activate and manage licensing from **System → License** in the admin portal. Same license server as the bare-OS install — `https://license-samm.securytik.com`.

See [samm.securytik.com](https://samm.securytik.com) for pricing.

---

## v1 limitations

These work in the bare-OS install but **not yet** in the Docker variant:

- **Staged license lockdown** — the in-process license check still throttles the data plane and the reactivation wall in the admin portal still shows, but the enforcer doesn't stop containers under soft/hard lockdown in v1.
- **Built-in WireGuard / Cloudflare Tunnel admin pages** — use the [bare-OS install](https://github.com/mhdhaidarah/samm) if you need these. The Docker variant assumes you manage VPN/tunnel on the host directly.
- **Dynamic FreeRADIUS config reload** — changes via the admin UI need `docker compose restart freeradius` to take effect.

---

## Uninstall

```bash
cd /opt/samm-docker
docker compose down -v      # WIPES postgres + the Fernet key — back up first
sudo rm -rf /opt/samm-docker
```

---

## Documentation & support

- 📖 **Full guide:** [samm.securytik.com/docs](https://samm.securytik.com/docs) — install, plans, subscribers, limits, and the complete operator manual
- 🖥️ **Bare-OS install instead:** [github.com/mhdhaidarah/samm](https://github.com/mhdhaidarah/samm)
- 🐛 **Report a bug:** [samm@securytik.com](mailto:samm@securytik.com?subject=SAMM%20Docker%20Bug%20Report)
- 💡 **Request a feature:** [samm@securytik.com](mailto:samm@securytik.com?subject=SAMM%20Docker%20Feature%20Request)

---

<div align="center">

Built by [**SecuryTik**](https://securytik.com) &nbsp;·&nbsp; SAMM is a SecuryTik product

</div>
