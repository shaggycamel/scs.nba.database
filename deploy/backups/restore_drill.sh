#!/usr/bin/env bash
# Restore the newest NUC backup into a throwaway PostgreSQL 17 container and
# check that the core tables came back. The container is removed on exit.
set -euo pipefail

LOCAL_DIR="${LOCAL_DIR:-/srv/nba-backups/daily}"
DUMP="${1:-$(ls -1t "$LOCAL_DIR"/nba-*.dump 2>/dev/null | head -1)}"
NAME="scs-nba-restore-test-$$"

log() { printf '%s %s\n' "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" "$*"; }

if [ -z "$DUMP" ] || [ ! -f "$DUMP" ]; then
    log "no dump found in $LOCAL_DIR"
    exit 1
fi

cleanup() {
    docker rm -f "$NAME" >/dev/null 2>&1 || true
}
trap cleanup EXIT

log "starting $NAME for $DUMP"
docker run -d --name "$NAME" \
    -e POSTGRES_HOST_AUTH_METHOD=trust \
    -e POSTGRES_DB=nba_restore_test \
    postgres:17 >/dev/null

# pg_isready can succeed against the entrypoint's temporary server before
# POSTGRES_DB exists, so wait for the database itself.
ready=0
for _ in $(seq 1 120); do
    if docker exec "$NAME" psql -U postgres -d nba_restore_test -tAc 'select 1' >/dev/null 2>&1; then
        ready=1
        break
    fi
    sleep 1
done
if [ "$ready" -ne 1 ]; then
    log "restore container did not become ready"
    exit 1
fi

log "restoring"
docker exec -i "$NAME" pg_restore -U postgres -d nba_restore_test \
    --no-owner --no-privileges --exit-on-error < "$DUMP"

check_count() {
    local label="$1"
    local query="$2"
    local value
    value="$(docker exec "$NAME" psql -U postgres -d nba_restore_test -tAc "$query" | tr -d '[:space:]')"
    if [ -z "$value" ] || [ "$value" -le 0 ]; then
        log "check failed: $label returned '$value'"
        exit 1
    fi
    log "check ok: $label = $value"
}

check_count "nba.player_box_score" "select count(*) from nba.player_box_score"
check_count "nba.play_by_play" "select count(*) from nba.play_by_play"
check_count "util.update_log" "select count(*) from util.update_log"
check_count "statyx.schedule" "select count(*) from statyx.schedule"
check_count "mod.team_hierarchy_base" "select count(*) from mod.team_hierarchy_base"

log "restore drill passed"
