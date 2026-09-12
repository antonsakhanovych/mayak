# mayak

A portable, Dockerised Minecraft server (Paper) with automatic offsite backups.
Clone it anywhere with Docker, drop in a `.env`, `make up`.

## What's inside

| Service | Image | Job |
|---|---|---|
| `server` | `itzg/minecraft-server` | Paper server. Game port published; RCON stays on the internal network. |
| `backup` | built from `./backup/` | Every `BACKUP_INTERVAL` seconds: pause saves via RCON, `restic` snapshot of `/data` to Cloudflare R2 (and a local repo when enabled), prune, resume saves. |

World and server files live in `./data` (bind mount, gitignored).

## Configuration files

Three files split the config by what varies and what doesn't:

| File | Tracked? | Holds |
|---|---|---|
| `.env` | No (gitignored) | Secrets and per-host values: `RCON_PASSWORD`, restic/R2 credentials, `MC_MEMORY`, `SERVER_PORT`, `DATA_DIR`, `LOCAL_BACKUP_DIR` |
| `mc.env` | Yes | Minecraft version, data packs, and whitelist policy — pinned together so a version bump and a compatible pack bump land in the same reviewable commit |
| `backup.env` | Yes | Backup interval/retention policy — fixed across every deployment |

## Quickstart

```sh
cp .env.example .env
$EDITOR .env             # set RCON_PASSWORD, RESTIC_PASSWORD, RESTIC_REPOSITORY, R2 keys
$EDITOR mc.env           # review WHITELIST/OPS before starting — enforcement is always on
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

Retention after every cycle (`--prune`, values from `backup.env`):
`--keep-hourly 24 --keep-daily 7 --keep-weekly 4`.

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

## Data packs

Set `DATAPACKS` in `mc.env` (git-tracked — see
[Configuration files](#configuration-files)) to a pack's `.zip` URL, e.g.
from Modrinth. The image installs it into `world/datapacks/` on (re)start:

```sh
DATAPACKS=https://cdn.modrinth.com/data/<id>/versions/<version>/pack.zip
```

For more than one, quote the value and put each URL on its own line so the
list stays readable:

```sh
DATAPACKS="https://cdn.modrinth.com/data/<id1>/versions/<v1>/pack1.zip
https://cdn.modrinth.com/data/<id2>/versions/<v2>/pack2.zip"
```

Pick pack versions that target the same `VERSION` this server runs — bump
both in the same commit when upgrading. Apply with `make restart`.

`mc.env` is the source of truth: `REMOVE_OLD_DATAPACKS` (default `true`)
deletes any `.zip` in `world/datapacks/` that isn't in the current
`DATAPACKS` list before reinstalling it, so removing a URL and restarting
actually removes the pack. Set it to `FALSE` if you ever add packs by hand
outside of `DATAPACKS` and want them left alone.

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

1. `git clone` the repo (or `./sync.sh` from a working copy) — this brings
   `mc.env` and `backup.env` with it, since both are git-tracked.
2. Get `.env` onto the target (it holds the restic password and R2 keys — gitignored, never rsynced).
3. Bring the world: `make restore SNAP=latest`, or copy `./data`.
4. `make up`.

Nothing is host-specific. `restart: unless-stopped` handles reboots; there are no
systemd units or host cron jobs to install.

## Whitelist / access control

Always on — `mc.env` ships with `ENABLE_WHITELIST`/`ENFORCE_WHITELIST=TRUE`
and `ONLINE_MODE=TRUE` (required for the whitelist to be trustworthy).
Player and operator usernames live in `mc.env`'s `WHITELIST`/`OPS`, tracked
in git for an audit trail of who was ever added or removed. Edit that file
and `make restart` to change who can join.
