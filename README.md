# mayak

A portable, Dockerised Minecraft server (Paper) with automatic offsite backups.
Clone it anywhere with Docker, drop in the `.env` files, `make up`.

## What's inside

Each container gets its own directory:

| Service | Directory | Image | Job |
|---|---|---|---|
| `server` | `mayak-mc/` | `itzg/minecraft-server` | Paper server. Game port published; RCON stays on the internal network. |
| `backup` | `mayak-backup/` | built from `./mayak-backup/` | Every `BACKUP_INTERVAL` seconds: pause saves via RCON, `restic` snapshot of `/data` to Cloudflare R2, prune, resume saves. |

World and server files live in `./mayak-mc/data` (bind mount, gitignored).
The root `Makefile` stays generic — it orchestrates both services via
`docker compose`, and doesn't know or care what either one runs.

## Configuration files

Five files split the config by what varies and what doesn't:

| File | Tracked? | Holds |
|---|---|---|
| `.env` | No (gitignored) | Needed for `docker-compose.yml`'s own `ports:`/`volumes:` interpolation, or shared by both services: `RCON_PASSWORD`, `SERVER_PORT`, `DATA_DIR` |
| `mayak-mc/mc.env` | Yes | Minecraft version, data packs, and whitelist policy — pinned together so a version bump and a compatible pack bump land in the same reviewable commit |
| `mayak-mc/.env` | No (gitignored) | Server-only values with no shared/interpolation need: `MEMORY` |
| `mayak-backup/backup.env` | Yes | Backup interval/retention policy — fixed across every deployment |
| `mayak-backup/.env` | No (gitignored) | Backup-only values with no interpolation need: `RESTIC_PASSWORD`, `RESTIC_REPOSITORY`, `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_DEFAULT_REGION` |

Root `.env` is a mix of two different reasons, not one: `SERVER_PORT` is
single-service but stuck here anyway because Compose's `${VAR}`
interpolation in `ports:`/`volumes:` lines only reads the shell environment
or the project's root `.env` — `env_file:` (what `mayak-mc/.env`/
`mayak-backup/.env` use) only injects values into a container's runtime
environment *after* the compose file's own YAML has already been resolved,
so it can never feed a `volumes:`/`ports:` line. `RCON_PASSWORD` and
`DATA_DIR` are genuinely shared — both services need the identical value
(backup authenticates against server's RCON; both mount the same world data
path) — so splitting them per-directory would risk drift.

`RESTIC_PASSWORD`/`RESTIC_REPOSITORY` don't have either problem (backup-only,
not used in a `volumes:`/`ports:` line) — they moved to `mayak-backup/.env`.
The tradeoff: root `.env`'s `${VAR:?err}` syntax fails fast with a clear
message if you forget to set a value; `env_file:` has no such guard, so a
blank `RESTIC_PASSWORD` there just surfaces as restic's own (less friendly)
auth error at backup time instead.

## Quickstart

```sh
cp .env.example .env
$EDITOR .env                      # set RCON_PASSWORD
cp mayak-mc/.env.example mayak-mc/.env
cp mayak-backup/.env.example mayak-backup/.env
$EDITOR mayak-backup/.env         # set RESTIC_PASSWORD, RESTIC_REPOSITORY, R2 keys
$EDITOR mayak-mc/mc.env           # review WHITELIST/OPS before starting — enforcement is always on
make up                           # builds the backup image and starts both services
make logs                         # watch it come up
make console                      # RCON prompt once it's healthy
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
| `make restore SNAP=latest` | restore the world data from a snapshot (stop the server first) |
| `make pull` | pull a newer server image |
| `make smoke` | up → wait healthy → backup → list snapshots |
| `make sync [HOST=user@host]` | *(dev machine)* rsync the project to a host |
| `make deploy` | *(target host)* pull + build + (re)start after a sync |

## Backups

Cloud (Cloudflare R2) always runs. Point `RESTIC_REPOSITORY` (in
`mayak-backup/.env`) at `s3:https://<ACCOUNT_ID>.r2.cloudflarestorage.com/<BUCKET>/mayak`
and set `RESTIC_PASSWORD` and the R2 access keys in the same file. The repo
is `restic init`-ed automatically on first run.

Retention after every cycle (`--prune`, values from `mayak-backup/backup.env`):
`--keep-hourly 24 --keep-daily 7 --keep-weekly 4`.

### Restore

```sh
make down
make restore SNAP=latest      # or a snapshot id from `make snapshots`
make up
```

## Data packs

Set `DATAPACKS` in `mayak-mc/mc.env` (git-tracked — see
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

`mayak-mc/mc.env` is the source of truth: `REMOVE_OLD_DATAPACKS` (default
`true`) deletes any `.zip` in `world/datapacks/` that isn't in the current
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

Pure rsync, no remote commands. Every `.env` file (root, `mayak-mc/.env`,
`mayak-backup/.env`) and the world data are never transferred or deleted on
the target.

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
cd ~/repos/mayak
cp .env.example .env && $EDITOR .env
cp mayak-mc/.env.example mayak-mc/.env
cp mayak-backup/.env.example mayak-backup/.env && $EDITOR mayak-backup/.env
make deploy
```

Bring the world with `make restore SNAP=latest` on the target, or by copying
`./mayak-mc/data`.

## Porting to another host

1. `git clone` the repo (or `./sync.sh` from a working copy) — this brings
   `mayak-mc/mc.env` and `mayak-backup/backup.env` with it, since both are
   git-tracked.
2. Get the three `.env` files onto the target (root `.env`, `mayak-mc/.env`,
   `mayak-backup/.env` — gitignored, never rsynced).
3. Bring the world: `make restore SNAP=latest`, or copy `./mayak-mc/data`.
4. `make up`.

Nothing is host-specific. `restart: unless-stopped` handles reboots; there are no
systemd units or host cron jobs to install.

## Whitelist / access control

Always on — `mayak-mc/mc.env` ships with `ENABLE_WHITELIST`/
`ENFORCE_WHITELIST=TRUE` and `ONLINE_MODE=TRUE` (required for the whitelist
to be trustworthy). Player and operator usernames live in `mc.env`'s
`WHITELIST`/`OPS`, tracked in git for an audit trail of who was ever added
or removed. Edit that file and `make restart` to change who can join.
