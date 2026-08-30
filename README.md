# mayak

A portable, Dockerised Minecraft server (Paper) with automatic offsite backups.
Clone it anywhere with Docker, drop in a `.env`, `make up`.

## What's inside

| Service | Image | Job |
|---|---|---|
| `server` | `itzg/minecraft-server` | Paper server. Game port published; RCON stays on the internal network. |
| `backup` | built from `./backup/` | Every `BACKUP_INTERVAL` seconds: pause saves via RCON, `restic` snapshot of `/data` to Cloudflare R2 (and a local repo when enabled), prune, resume saves. |

World and server files live in `./data` (bind mount, gitignored).

## Quickstart

```sh
cp .env.example .env
$EDITOR .env            # set RCON_PASSWORD, RESTIC_PASSWORD, RESTIC_REPOSITORY, R2 keys
make up                 # builds the backup image and starts both services
make logs               # watch it come up
make console            # RCON prompt once it's healthy
```

Connect on `localhost` (or the host's LAN IP), port `SERVER_PORT` (default 25565).

## Commands

| Command | Effect |
|---|---|
| `make up` / `make down` | start / stop everything |
| `make restart` | restart just the server |
| `make logs` | follow server logs |
| `make console` | interactive RCON console |
| `make cmd C="whitelist list"` | run one RCON command |
| `make backup` | run a backup cycle immediately |
| `make snapshots` | list cloud snapshots |
| `make restore SNAP=latest` | restore `./data` from a snapshot (stop the server first) |
| `make pull` | pull a newer server image |
| `make smoke` | up → wait healthy → backup → list snapshots |
| `make sync [HOST=user@host]` | *(dev machine)* rsync the project to a host |
| `make deploy` | *(target host)* pull + build + (re)start after a sync |

## Backups

Cloud (Cloudflare R2) always runs. Point `RESTIC_REPOSITORY` at
`s3:https://<ACCOUNT_ID>.r2.cloudflarestorage.com/<BUCKET>/mayak` and set the R2
access keys as `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY`. The repo is
`restic init`-ed automatically on first run.

Retention after every cycle:
`--keep-hourly 24 --keep-daily 7 --keep-weekly 4 --prune`.

### Local secondary copy (optional, per host)

Set `LOCAL_BACKUP_DIR` to a real mountpoint (e.g. an external HDD) and create a
marker file on it:

```sh
touch /mnt/your-hdd/.mayak-enabled
```

When the marker is present the sidecar also keeps a `restic` repo at
`<LOCAL_BACKUP_DIR>/restic`. When the drive is unplugged (marker gone) it logs
one line and skips — the cloud backup is unaffected. Left at the default
(`./.local-backup`, no marker), local backups just don't happen.

### Restore

```sh
make down
make restore SNAP=latest      # or a snapshot id from `make snapshots`
make up
```

## Sync and deploy

Two steps, run in two places. Sync moves files only; deploy runs on the target.

**1. Sync** — on the dev machine:

```sh
./sync.sh                       # -> $MAYAK_HOST or asakh@raspberrypi, ~/repos/mayak
./sync.sh user@box /srv/mayak   # explicit target and path
./sync.sh -n                    # dry run
make sync                       # via make (make sync HOST=user@box to override)
```

Pure rsync, no remote commands. `.env`, `data/`, and `.local-backup/` are never
transferred or deleted on the target.

**2. Deploy** — on the target (e.g. ssh'd into the Pi):

```sh
cd ~/repos/mayak
make deploy                     # docker compose pull server + up -d --build
```

First time on a fresh host:

```sh
ssh asakh@raspberrypi 'mkdir -p ~/repos/mayak'
./sync.sh                                                    # from the dev machine
ssh asakh@raspberrypi
cd ~/repos/mayak && cp .env.example .env && $EDITOR .env
make deploy
```

Bring the world with `make restore SNAP=latest` on the target, or by copying `./data`.

## Porting to another host

1. `git clone` the repo (or `./sync.sh` from a working copy).
2. Get `.env` onto the target (it holds the restic password and R2 keys — gitignored, never rsynced).
3. Bring the world: `make restore SNAP=latest`, or copy `./data`.
4. `make up`.

Nothing is host-specific. `restart: unless-stopped` handles reboots; there are no
systemd units or host cron jobs to install.

## Not done yet

- **Whitelist / access control.** `.env.example` has `ENABLE_WHITELIST`,
  `ENFORCE_WHITELIST`, `WHITELIST`, `OPS` stubbed with `ONLINE_MODE=TRUE`. Wire
  them up when you're ready to lock the server to specific players.
