# SAMM — Docker distribution

The official Docker image for **SAMM** (SecuryTik Active MikroTik Manager) — a
FreeRADIUS + PostgreSQL + FastAPI AAA stack for MikroTik ISPs: PPPoE / Hotspot /
DHCP-IPoE access, IPv6 dual-stack, plans & limits, double-entry billing with
online payments (Stripe / Binance / PayPal) + QuickBooks/Xero export, REST API +
webhooks, admin & customer portals, Email/Telegram/SMS/WhatsApp notifications,
and an HA replication runbook.

> **▶ Start here → [github.com/mhdhaidarah/samm-docker](https://github.com/mhdhaidarah/samm-docker)**
> Don't pull these images by hand — use the **compose bundle** from the
> **samm-docker** releases. It pins the exact multi-arch digests (app,
> freeradius, wa-bridge) and wires the whole stack together, including the
> optional WhatsApp QR bridge. One-line install below, MikroTik RouterOS
> container instructions in the [docs](https://samm.securytik.com/docs).

## Which file do I use? (start here)

**One question: are you pasting YAML into your MikroTik router's *Container* menu?**

| Where you run SAMM | Use | Why |
|---|---|---|
| **On a computer** — any Linux server / VM / desktop, x86 **or** ARM, including MikroTik **CHR** | the **installer** (`curl … install.sh \| bash`) or **`docker-compose.yml`** | Docker auto-detects your CPU — nothing to choose |
| **Inside a MikroTik router** (RouterOS → Container) | **`docker-compose.mikrotik.yml`** | RouterOS can't pick a CPU architecture; this file is pinned to arm64 (every container-capable MikroTik board is arm64) so it won't fail with `Exec format error` |

That's the whole decision — you never pick "amd64 vs arm64" yourself.

## Quick install (Ubuntu / Debian)

```bash
curl -fsSL https://github.com/mhdhaidarah/samm-docker/releases/latest/download/install.sh \
    | sudo bash
```

The installer detects Docker, installs it if missing, drops a
`docker-compose.yml` + `.env` into `/opt/samm-docker/`, and brings the stack up.

After ~30 seconds:

- **Admin portal**   `http://<host>:8000/admin`
- **Customer portal** `http://<host>:8000/`
- **RADIUS auth**     UDP 1812 on the host's LAN IP
- **RADIUS accounting** UDP 1813 on the host's LAN IP

Default credentials: **`admin` / `admin`** — **change on first login**.

## Windows (Docker Desktop) — evaluation only

You can run SAMM on Windows via Docker Desktop + WSL2. **Not recommended for production** because:

- Windows sleep / hibernate / lid-close stops the containers
- Boot-restart only fires when WSL boots (not on Windows boot)
- Daily auto-update cron only runs while WSL is alive
- No 24/7 reliability for RADIUS auth and accounting

Use it for evaluation, then deploy production on a Linux VM or small physical box.

**Evaluation steps from PowerShell** (no WSL terminal needed; Docker Desktop's WSL backend handles it):

```powershell
mkdir C:\samm-docker
cd C:\samm-docker
curl.exe -fLO https://github.com/mhdhaidarah/samm-docker/releases/latest/download/docker-compose.yml
curl.exe -fLO https://github.com/mhdhaidarah/samm-docker/releases/latest/download/env.example
copy env.example .env
notepad .env   # set POSTGRES_PASSWORD and SAMM_PUBLIC_HOST (your Windows LAN IP)
docker compose pull
docker compose up -d
```

Watch it boot in Docker Desktop → Containers → the `samm` stack expands into 8 services. Open `http://localhost:8000/admin` (login **`admin` / `admin`**).

If MikroTik will hit this Windows host, allow UDP 1812/1813 through Windows Firewall:
```powershell
New-NetFirewallRule -DisplayName "SAMM RADIUS" -Direction Inbound -Protocol UDP -LocalPort 1812,1813 -Action Allow
```

Tear down: `docker compose down -v` (the `-v` wipes the postgres + Fernet key volumes).

## MikroTik (RouterOS 7 container feature)

**Running SAMM directly on a MikroTik router? Use the dedicated
[`docker-compose.mikrotik.yml`](https://github.com/mhdhaidarah/samm-docker/releases/latest/download/docker-compose.mikrotik.yml) — NOT the normal `docker-compose.yml`.**

Why: unlike Docker, **RouterOS Container cannot choose a CPU architecture** from
a multi-arch image — it always pulls amd64. On a MikroTik router (which is
arm64) that makes every container die with
`exited with status 255: execvp … Exec format error`. The `docker-compose.mikrotik.yml`
file pins every image to its **arm64** build, which is what every
container-capable MikroTik board is (RB5009, hAP ax², CCR2004/2116/2216, L009 …),
so RouterOS pulls the right one.

Steps — in WebFig/WinBox:

1. **Container → Apps → New → YAML**, paste
   **`docker-compose.mikrotik.yml`** (from the latest release), point it at an
   ext4-formatted USB/microSD, submit.
2. RouterOS pulls each arm64 image and wires the services up.

> **x86 RouterOS or CHR?** Those are just PCs/VMs — **don't** use the mikrotik
> file. Install Docker and run the normal one-line installer above; Docker
> auto-detects your CPU. (Or use the standard `docker-compose.yml`.)

Full walkthrough (prep, disk formatting, RADIUS wiring) lives at
<https://samm.securytik.com/docs#doc-install> under *Option D*.

> **Note for maintainers.** MikroTik's compose parser drops the `command:`
> field on YAML import. Every SAMM **app** service therefore carries BOTH
> `command: ["<role>"]` and `environment: SAMM_ROLE: <role>` for the same
> role; `entrypoint.sh` reads `${SAMM_ROLE:-${1:-api}}` so either source
> works. Keep both fields in lockstep when adding app services. (`wa-bridge`
> needs neither — its role is baked into the image's CMD, which is exactly
> what makes it RouterOS-proof.)

## What it ships

| Container | Role |
| --- | --- |
| `postgres` | Postgres 16 on the private compose bridge |
| `samm-api` | FastAPI admin + customer portal (exposes :8000) |
| `samm-radius` | Time-driven AAA + CoA sender |
| `samm-worker` | MikroTik inventory + ICMP ping sweep (`NET_RAW`) |
| `samm-notification` | Email/Telegram/SMS/WhatsApp notification outbox drain |
| `samm-telegram` | Long-polling Telegram bot |
| `freeradius` | Stock `freeradius/freeradius-server:3`, SAMM config mounted |
| `wa-bridge` | WhatsApp QR bridge (idles until the QR provider is used) — self-contained multi-arch image |

The app + freeradius + wa-bridge images are all `mhdhaidarah/samm` (tags
`<ver>`, `freeradius-<ver>`, `wa-bridge-<ver>`), each pinned to a sha256 digest
in the compose file and built multi-arch (amd64 + arm64). App source stays
closed: it's built from Cython-compiled binaries — no `.py` source.

## WhatsApp QR bridge (optional)

WhatsApp has two providers under **Notifications → Channels → WhatsApp**:

- **Meta WhatsApp Cloud API** *(official, recommended)* — token + Phone-Number-ID,
  nothing extra to run; works out of the box.
- **Unofficial QR link** *(at your own risk)* — a small Baileys sidecar that
  **already runs as part of the stack** (the `wa-bridge` service — nothing to
  enable). Just open the WhatsApp channel, pick **Unofficial QR link**, and scan
  the QR. It idles (no linked number, no traffic) until you do.

  The bridge is a **self-contained image** (`mhdhaidarah/samm:wa-bridge-<ver>`,
  multi-arch) with code + deps baked in — so it starts instantly and runs on
  normal Docker **and on MikroTik's RouterOS container feature** alike (no
  bind-mount, no `command:`). The linked session persists in the `wabridge_auth`
  volume; `WA_BRIDGE_TOKEN` is auto-generated in `.env`. Don't want it running?
  `docker compose stop wa-bridge`.

## Boot startup

`install.sh` installs `samm-docker.service` (systemd, enabled). The stack
comes back up after a host reboot even if you had run `docker compose down`
before shutdown. Belt-and-suspenders alongside compose's
`restart: unless-stopped`: the restart policy survives Docker daemon
restarts; the systemd unit covers explicit-down + reboot.

Disable: `sudo systemctl disable samm-docker.service`.

## Network

- Host needs UDP 1812 + 1813 free. **Coexisting with a bare-OS SAMM install
  is not supported** — if you previously ran `install.sh` from
  `mhdhaidarah/samm` on this host, `apt purge freeradius postgresql` before
  installing the docker variant.
- The `freeradius` container exposes 1812 + 1813 via standard compose port
  mapping (no host networking).
- MikroTik NAS points to **the host's LAN IP** on 1812/1813. The shared
  secret is set in the SAMM admin portal under *System → RADIUS*.

## Upgrading

`install.sh` sets up auto-update for you:

- `/opt/samm-docker/host-updater.sh` — the upgrade script
- `/etc/cron.d/samm-docker` — runs `host-updater.sh` **daily at 04:00**
- `/var/log/samm-update.log` — captures stdout + stderr each run

Each run: query the latest release tag, download the matching digest-pinned
`docker-compose.yml`, `docker compose pull && docker compose up -d`. No-op when
nothing's new.

Disable auto-update: `sudo rm /etc/cron.d/samm-docker`. Change the schedule
by editing that file.

Manual upgrade:

```bash
sudo curl -fsSL https://github.com/mhdhaidarah/samm-docker/releases/latest/download/install.sh \
    | sudo bash
```

Re-running `install.sh` preserves `.env`; it only refreshes `docker-compose.yml`
and pulls the new image.

## Backup

Three volumes carry state worth keeping:

- `samm_pgdata` — Postgres data
- `samm_etcsamm` — Fernet key (`secret.key`) and the rendered `samm.yaml`
- `samm_wabridge_auth` — the WhatsApp QR bridge's linked session (losing it
  just means re-scanning the QR — include it if you use the QR provider)

**Losing `samm_etcsamm` means losing the Fernet key**, which means you can no
longer decrypt MikroTik API passwords stored in the DB. Back them up
together:

```bash
sudo docker run --rm \
    -v samm_pgdata:/src/pgdata:ro \
    -v samm_etcsamm:/src/etcsamm:ro \
    -v samm_wabridge_auth:/src/wabridge_auth:ro \
    -v "$(pwd):/out" \
    alpine tar czf "/out/samm-backup-$(date +%F).tar.gz" -C /src .
```

## Docker-variant limitations

These work in the bare-OS install but **not** in the Docker variant:

- **Staged license lockdown** (soft/hard stops on samm-worker etc.) — the
  in-process license check still throttles the data plane and the
  reactivation wall in the admin portal still shows, but the lockdown
  enforcer doesn't stop containers.
- **Dynamic FreeRADIUS config reload** — changes via the admin UI require
  `docker compose restart freeradius` to take effect.

The **WireGuard** and **Cloudflare Tunnel** admin pages are
automatically hidden in the docker variant. They manage host-level systemd
services that aren't reachable from inside the container; the admin sidebar
hides them and the routes redirect with a "configure on the host" notice.
Use the bare-OS install if you need built-in VPN / tunnel management.

## Multi-arch + MikroTik containers

The published images are **multi-arch** — `linux/amd64` and `linux/arm64` ship
under the same tag. On a normal Docker host (**including Apple-silicon Macs, x86,
and arm servers**) `docker pull` and Compose pick the right variant
automatically — one `docker-compose.yml`, nothing to choose.

**MikroTik RouterOS Container is the exception:** it does **not** negotiate
architecture and always pulls amd64, so it needs the arm64-pinned
**`docker-compose.mikrotik.yml`** (see the MikroTik section above). Use that file
for on-the-router installs; use the normal `docker-compose.yml` everywhere else.

- **Apple-silicon Docker Desktop** (M1/M2/M3 Macs) — runs native via the normal
  compose, no Rosetta.
- **MikroTik containers** (RouterOS 7.4+) on arm64 hardware — RB5009, hAP ax²,
  CCR2004/2116/2216, and similar — via `docker-compose.mikrotik.yml`. Both compose
  files are plain YAML 1.2 (no merge keys) so RouterOS's parser reads them cleanly.

armv7 devices and the smaller mipsbe/smips MikroTik boards are not supported —
the Python/FastAPI/Postgres/freeradius stack needs more headroom than those
SKUs provide. The bare-OS install on a small Linux box remains the
recommended production path for larger deployments; MikroTik-on-container suits small/branch sites.

## Uninstall

```bash
cd /opt/samm-docker
docker compose down -v   # -v wipes the postgres volume AND the Fernet key
sudo rm -rf /opt/samm-docker
```

## Support

- Issues: https://github.com/mhdhaidarah/samm/issues
- Docs:   https://samm.securytik.com/docs

Built by [SecuryTik](https://securytik.com).
