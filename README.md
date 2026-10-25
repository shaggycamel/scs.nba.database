# scs.nba.database

Scheduled table updates for the NBA / fantasy database.

`__main__.py` reads `util.update_schedule`, calls each row's `associated_function` on a
[scs-hub](https://github.com/shaggycamel/scs.scs_hub) `SportsHub`, writes one row per
scheduled function to `util.update_log` (`task` is the row's `associated_function`),
emails any failures, and exits non-zero if anything failed.
Each `util.update_log` row records the run's `cadence` — the argument that selected it,
or `all` for a bare run — and `row_count`: the rows the task wrote (`0` for a successful
no-op). For `util.sync_player_identity` it is the number of new players minted instead.
Failed tasks, `process start`/`process end`, and dashboard rows keep `row_count` NULL.

```
python __main__.py                 # every table where pause IS FALSE
python __main__.py daily,intraday  # only rows whose cadence is one of these
python __main__.py daily intraday  # same; space- or comma-separated
```

Each row's `cadence` names the run it belongs to: `./cron.sh daily` picks up every
unpaused row with `cadence = 'daily'`, and a bare `./cron.sh` ignores cadence entirely.
Rows run once each, in a single `ORDER BY schema_sequence, function_sequence, table_name`
(`NULLS LAST` on the two sequence keys), with no per-cadence grouping. `schema_sequence`
keeps the dependency order nba → statyx → fty → util; `function_sequence` orders the
functions within a schema.

It runs as a Docker container, once per cron job, on a single always-on host (the NUC).

## Configuration

Everything lives in one system-wide file, `~/.config/scs_hub_credentials.ini` — the same
file scs-hub reads for its DB and platform credentials. Set `SCS_HUB_CREDENTIALS` to
point at a different path instead; both `__main__.py` and scs-hub honour it. Create the
file `chmod 600` and never commit it (it lives outside the repo).

It holds the DB/platform sections scs-hub expects (`[cockroach-write]`/`[postgres]`,
`[statyx]`, `[espn_api]`, `[yahoo_api]`) plus this repo's `[runtime]` and `[smtp]` sections.

A direct `python __main__.py` reads the same file, so no `cd` or working-directory setup is
needed.

| Section    | Key        | Env override    | Purpose                                     |
| ---------- | ---------- | --------------- | ------------------------------------------- |
| `[runtime]`| `db_con`   | `DB_CON`        | which DB section to write to                |
| `[smtp]`   | `user`     | `SMTP_USER`     | Gmail address failure alerts are sent from  |
| `[smtp]`   | `password` | `SMTP_PASSWORD` | Gmail app password                          |
| `[smtp]`   | `to`       | `ALERT_TO`      | recipient; defaults to `user`               |

Environment variables win when set, so `os.environ['DB_CON'] = 'postgres'` still works in
an interactive console. Without `[smtp] user` + `password` the failure email is skipped
and the run simply exits 1.

The local `~/.config` file should point at `[runtime] db_con = postgres` so a stray local
run cannot write to cockroach.

## Deploying to the NUC

The image is built on the NUC itself — native amd64, no registry, and no credentials ever
leave the box.

```bash
# 1. one-off: the system-wide config file
mkdir -p ~/.config
$EDITOR ~/.config/scs_hub_credentials.ini   # real creds, db_con = cockroach-write
chmod 600 ~/.config/scs_hub_credentials.ini

# 2. build (repeat after every git pull)
cd ~/shaggy_camel_sports/nba/database && git pull
docker build -t scs.nba.database:latest .

# 3. run
./cron.sh                         # all unpaused tables
./cron.sh daily,intraday,weekly   # only those cadences
```

`cron.sh` bind-mounts the config read-only at `/root/.config/scs_hub_credentials.ini`,
so nothing secret is in the image. The run writes through the `[cockroach-write]` section
(`cron.sh` sets `DB_CON=cockroach-write` unless the environment already sets it). It keeps
the container after the run (no `--rm`) so `docker logs update_tables` works until the next
run, and it propagates the exit status.

Crontab — cron has no `PATH` (which is why `cron.sh` sets one). The NUC runs Ubuntu's
Debian/Vixie cron, which ignores `CRON_TZ` (that is a cronie feature), and its system
timezone is `Etc/UTC`, so every hour below is UTC. They are the UTC equivalents of the
original NZ wall-clock times, fixed in UTC so runs stay aligned to the US game schedule
rather than shifting with NZ DST:

```cron
# weekly, Monday 12:00 UTC (Tuesday 01:00 NZDT)
0 12 * * 1      /home/oli/shaggy_camel_sports/nba/database/cron.sh weekly   >> /home/oli/shaggy_camel_sports/nba/database/cron.log 2>&1

# daily, 13:00 UTC (02:00 NZDT)
0 13 * * *      /home/oli/shaggy_camel_sports/nba/database/cron.sh daily    >> /home/oli/shaggy_camel_sports/nba/database/cron.log 2>&1

# intraday, every 3h: 01,04,07,10,16,19,22 UTC (05,08,11,14,17,20,23 NZDT)
0 1,4,7,10,16,19,22 * * * /home/oli/shaggy_camel_sports/nba/database/cron.sh intraday >> /home/oli/shaggy_camel_sports/nba/database/cron.log 2>&1

# league dash: daily 16:30 UTC (05:30 NZDT);
# intraday 01:30,03:30,17:30,19:30,21:30,23:30 UTC
30 16 * * *     PROVISION=1 /home/oli/shaggy_camel_sports/nba/fty/league_dash/deploy/cron.sh daily    >> /home/oli/shaggy_camel_sports/nba/fty/league_dash/cron.log 2>&1
30 1,3,17,19,21,23 * * * PROVISION=1 SKIP_BASE=1 /home/oli/shaggy_camel_sports/nba/fty/league_dash/deploy/cron.sh intraday >> /home/oli/shaggy_camel_sports/nba/fty/league_dash/cron.log 2>&1
```

No environment setup needed — `cron.sh` reads `~/.config/scs_hub_credentials.ini` (or
`SCS_HUB_CREDENTIALS`). The redirect captures the wrapper's output; the container's own
logs are also available via `docker logs update_tables` until the next run. These entries
are live on the NUC.

Run frequency is otherwise driven from the database: `util.update_schedule.cadence`
selects which run picks up a row, and `util.update_schedule.pause` excludes it from
every run (including a bare `./cron.sh`). The `cadence`, `schema_sequence` and
`function_sequence` columns are mirrored in `sql/tables/util.update_schedule.sql`, which
rebuilds the table so its column order (… `cadence`, `schema_sequence`, `function_sequence`,
`pause`) is reproduced — no dialect here can place a column at a position.

That same argument is written to `util.update_log.cadence` on every row a run inserts
(`all` for a bare `./cron.sh`). Each row also carries `source` — the repo that wrote it,
derived from the checkout's git remote (`scs.nba.database` here, `scs.nba.fty.league_dash`
from the dashboard) — and `job_kickoff`, the run's start time, identical on every row of
one run so a run can be grouped. Both are set in `cron.sh` (env-overridable) and passed
into the container. The columns are established by rebuilding the table —
`sql/tables/util.update_log.sql`, run against postgres only (a rebuild is required because
no dialect here can place a column at a position). Cockroach is then overwritten from
postgres, which recreates the table in the same column order.

`row_count` was added later with `ALTER TABLE util.update_log ADD COLUMN row_count BIGINT`
on both databases, so it sits last and rows written before then keep NULL. A rebuild
reproduces that visible order. It counts rows written, not net change: delete-and-rewrite
tasks report their insert volume, deletes are not counted, and tasks that write nothing
log `0`. `util.sync_player_identity` is the exception — it reports gross new
`util.player` rows minted, because its raw engine writes do not pass through `db.write`.

## Notes on the image

- Multi-stage. The build stage needs `build-essential` + `libpq-dev` because scs-hub
  pins `psycopg2`, which publishes no Linux wheels and compiles from source.
- Runtime needs `libpq5` (psycopg2), `tzdata` (`ZoneInfo('Pacific/Auckland')`) and
  `default-jre-headless` — `nbainjuries` starts a JVM via jpype at *import* time and
  `scs_hub.nba` imports it at module top, so Java is needed on every run, not just
  injury runs.
- `uv` is pinned to the version that generated `uv.lock`, and `uv sync --locked` fails the
  build if the lock drifts from `pyproject.toml`. Bump the two together.
- The container runs as root on purpose: a non-root uid could not read the `chmod 600`
  host config through the read-only bind mount, and `/root/.config` is where scs-hub
  resolves it by default.

## Development

```bash
uv sync
uvx ruff check __main__.py
```

`scripts/manual_update.py` is a REPL scratchpad for running individual `hub.*` calls by
hand — not part of the scheduled run, and not in the image. `scripts/apply_views.py` applies
the `sql/views` files and re-grants them, and
`scripts/transport.py` mirrors one season between the two databases named at its top —
neither is in the image.
`sql/` holds view, function and table DDL for reference (hand-applied; the database is the
system of record).

## Deferred work

The fty roster/division change still needs the NUC image rebuilt and the weekly
`fty.get_league` / `fty.get_league_competitor` schedule rows added. See
[FTY_ROSTER_DIVISIONS_FOLLOWUP.md](FTY_ROSTER_DIVISIONS_FOLLOWUP.md).
