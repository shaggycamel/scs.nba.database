# NUC Smoke Test Plan

## Goal

On the NUC, verify the Docker image builds, its runtime dependencies load without database
access, and each scheduled cadence runs successfully against `cockroach-write`. Check both
job success and the expected data refresh. Do not enable automatic cron entries as part of
this test.

## Current state

- PostgreSQL and `cockroach-write` now have matching `util.update_schedule` rows: 20 each,
  no differences.
- The missing Cockroach row was added: `nba.play_by_play` → `nba.get_play_by_play`, daily,
  unpaused.
- The active schedule contains:
  - **Daily: 13 jobs** — NBA schedule, play-by-play, player/team box scores and roster;
    Statyx schedule, standings, game/advanced stats, potential assists and roster;
    fantasy matchup box score; player-identity sync.
  - **Intraday: 4 jobs** — NBA injuries; fantasy competitor rosters, free agents and
    recent activity.
  - **Weekly: 3 jobs** — fantasy league byes, matchups and matchup results.
- The NUC crontab currently has the weekly Tuesday 01:00, daily 02:00, and two
  intraday-window entries commented out. No automatic NBA cadence runs are currently
  scheduled there.
- The image has not yet been built or run on the NUC. Dev is for inspection; do not try to
  run the image there.

## Important behavior

- `cron.sh` defaults to `DB_CON=cockroach-write`; explicitly set it for each test run so an
  inherited environment variable cannot redirect the target.
- Cadence runs perform real updates and write to `util.update_log`. There is no dry-run
  mode.
- `cron.sh` removes the existing container named `update_tables` before each run. Capture
  that run's output and inspect `docker logs update_tables` **before starting the next
  cadence**, or the previous container's logs will be lost.
- A successful exit verifies the configured jobs ran; it does not by itself prove every
  desired season, date range or data field is present. Validate data freshness/coverage
  for the intended dataset as well.
- Leave the NUC cron entries commented out until the smoke tests pass and automatic
  scheduling is explicitly approved.

## Test steps

### 1. Preflight on the NUC

From `~/shaggy_camel_sports/nba/database`:

- Check the current checkout/commit and `git status`; preserve unrelated changes.
- Confirm Docker is available and the credentials file exists and is readable by the cron
  user. Do not print or copy credentials.
- Confirm the credentials configuration includes `[cockroach-write]`.
- Confirm no other update run is in progress and no `update_tables` container is running;
  the wrapper removes that named container before launching.
- Read the active `cockroach-write` schedule and confirm the expected 13/4/3 jobs are
  present and unpaused. Stop if it differs from the reconciled schedule.

### 2. Build the image on the NUC

Update deps and the lock file before building. Build natively on the NUC, as documented:

```bash
docker build -t scs.nba.database:latest .
```

If the build fails, record the failing step and stop before running any cadence. Do not
push the image or modify cron configuration.

### 3. Run a database-free container smoke check

Override the image entrypoint; do not mount credentials or instantiate `SportsHub`:

```bash
docker run --rm --entrypoint python scs.nba.database:latest -c 'import py_compile; py_compile.compile("/app/__main__.py", doraise=True); import polars, psycopg2, jpype, scs_hub.nba; from zoneinfo import ZoneInfo; ZoneInfo("Pacific/Auckland"); print("runtime smoke OK")'
```

This checks Python syntax, application/runtime imports, the Java-dependent NBA import path
and Auckland timezone data. It must not connect to a database. If it fails, stop and report
the error; do not start a cadence run.

### 4. Run each cadence manually, one at a time

Run from the repository directory. Capture each command's output and exit status, then
inspect `docker logs update_tables` before proceeding to the next cadence:

```bash
set -o pipefail
DB_CON=cockroach-write ./cron.sh weekly 2>&1 | tee /tmp/nba-weekly-smoke.log
DB_CON=cockroach-write ./cron.sh daily 2>&1 | tee /tmp/nba-daily-smoke.log
DB_CON=cockroach-write ./cron.sh intraday 2>&1 | tee /tmp/nba-intraday-smoke.log
```

These are real database updates. Do not use bare `./cron.sh`; that selects every unpaused
schedule row, regardless of cadence. If a cadence fails, stop and investigate before
running subsequent cadences.

### 5. Verify each run

For each cadence:

- Confirm the wrapper exit status is `0`.
- Inspect the container output/logs for errors.
- Read `util.update_log` on `cockroach-write`, scoped to that run's `job_kickoff` and
  cadence. Expect `process start`, one successful task entry per selected schedule row,
  and `process end`; the `connect_leagues` setup has no task row of its own.
- Check expected data was refreshed for the intended season/date range, not just that job
  calls returned successfully.
- Record failures and error details without including credentials or secrets in the
  handoff.

Expected scheduled-task counts are **13 daily, 4 intraday, 3 weekly**, plus process
start/end log events for each run.

## After testing

Report build result, smoke-check result, each cadence's exit status, failed tasks (if any),
and data freshness checks. Keep automatic cron entries disabled pending review. Do not
stage or commit changes unless separately requested.

## Preserve existing work

At handoff, the working tree also contained changes in `scripts/apply_views.py`,
`scripts/manual_update.py`, `sql/views/nba/schedule_vw.sql`, `uv.lock`,
`scripts/adhoc.py`, and `sql/views/nba/play_by_play_vw.sql`, in addition to the README
update. Do not overwrite or stage those unrelated changes.
