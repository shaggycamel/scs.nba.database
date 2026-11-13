#!/usr/bin/env bash
# Nightly compressed dump of the Jetson analytics database.
#
# Runs on the Jetson. pg_dump comes from the Postgres container, so no host
# PostgreSQL client is needed. Override BACKUP_DIR when /srv is not writable.
set -euo pipefail

BACKUP_DIR="${BACKUP_DIR:-/srv/backups}"
CONTAINER="${CONTAINER:-scs-nba-pg}"
DB_NAME="${DB_NAME:-nba}"
DB_USER="${DB_USER:-scs}"
KEEP_DUMPS="${KEEP_DUMPS:-7}"

STAMP="$(date -u +%F)"
DUMP="$BACKUP_DIR/nba-$STAMP.dump"
TMP="$BACKUP_DIR/.nba-$STAMP.dump.tmp"

log() { printf '%s %s\n' "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" "$*"; }

umask 077
mkdir -p "$BACKUP_DIR"
chmod 700 "$BACKUP_DIR"

exec 9>"$BACKUP_DIR/.dump.lock"
if ! flock -n 9; then
    log "another dump is already running; exiting"
    exit 0
fi

trap 'rm -f "$TMP"' EXIT

log "dumping $DB_NAME from $CONTAINER to $DUMP"
docker exec "$CONTAINER" pg_dump -U "$DB_USER" -Fc -Z6 "$DB_NAME" > "$TMP"

if [ ! -s "$TMP" ]; then
    log "dump is empty; refusing to keep it"
    exit 1
fi

mv "$TMP" "$DUMP"
chmod 600 "$DUMP"
sha256sum "$DUMP" > "$DUMP.sha256"
chmod 600 "$DUMP.sha256"
log "wrote $DUMP ($(du -h "$DUMP" | cut -f1))"

# Keep the newest KEEP_DUMPS dumps. A same-day re-run overwrites in place, so
# the count does not grow.
shopt -s nullglob
files=("$BACKUP_DIR"/nba-*.dump)
if ((${#files[@]} > KEEP_DUMPS)); then
    mapfile -t old < <(ls -1t "${files[@]}")
    for f in "${old[@]:KEEP_DUMPS}"; do
        log "pruning $f"
        rm -f "$f" "$f.sha256"
    done
fi
