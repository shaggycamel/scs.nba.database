#!/usr/bin/env bash
# Pull the newest Jetson dump to the NUC, encrypt it, and push it to MEGA.
#
# Runs on the NUC. Set DRY_RUN=1 to stop after the local encrypted copy is
# made, before any rclone call. The unencrypted dump is kept locally for fast
# restores; MEGA only ever receives the .age file.
set -euo pipefail
export PATH="$HOME/.local/bin:$PATH"

JETSON_HOST="${JETSON_HOST:-jetson}"
REMOTE_DIR="${REMOTE_DIR:-/srv/backups}"
LOCAL_DIR="${LOCAL_DIR:-/srv/nba-backups}"
DAILY_DIR="$LOCAL_DIR/daily"
WEEKLY_DIR="$LOCAL_DIR/weekly"
KEEP_DAILY="${KEEP_DAILY:-14}"
KEEP_WEEKLY="${KEEP_WEEKLY:-8}"
AGE_PUBKEY="${AGE_PUBKEY:-$HOME/.config/scs_backup_age.pub}"
RCLONE_REMOTE="${RCLONE_REMOTE:-mega:nba-backups}"
DRY_RUN="${DRY_RUN:-0}"

log() { printf '%s %s\n' "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" "$*"; }

umask 077
mkdir -p "$DAILY_DIR" "$WEEKLY_DIR"
chmod 700 "$LOCAL_DIR" "$DAILY_DIR" "$WEEKLY_DIR"

exec 9>"$LOCAL_DIR/.backup.lock"
if ! flock -n 9; then
    log "another backup is already running; exiting"
    exit 0
fi

LATEST="$(ssh "$JETSON_HOST" "ls -1t '$REMOTE_DIR'/nba-*.dump 2>/dev/null | head -1")"
if [ -z "$LATEST" ]; then
    log "no dump found on $JETSON_HOST:$REMOTE_DIR"
    exit 1
fi

FILE="$(basename "$LATEST")"
DEST="$DAILY_DIR/$FILE"
log "newest Jetson dump: $FILE"

rsync -a --partial "$JETSON_HOST:$LATEST" "$DEST"

REMOTE_SUM="$(ssh "$JETSON_HOST" "sha256sum '$LATEST'" | awk '{print $1}')"
LOCAL_SUM="$(sha256sum "$DEST" | awk '{print $1}')"
if [ -z "$REMOTE_SUM" ] || [ "$REMOTE_SUM" != "$LOCAL_SUM" ]; then
    log "checksum mismatch for $FILE"
    exit 1
fi
chmod 600 "$DEST"

if [ "$(date -u +%u)" -eq 7 ]; then
    cp -p "$DEST" "$WEEKLY_DIR/$FILE"
    chmod 600 "$WEEKLY_DIR/$FILE"
    log "refreshed weekly copy $FILE"
fi

# Prune by mtime, newest first, never touching the newest file.
prune_daily() {
    local files sorted f
    shopt -s nullglob
    files=("$DAILY_DIR"/nba-*.dump)
    ((${#files[@]} > KEEP_DAILY)) || return 0
    mapfile -t sorted < <(ls -1t "${files[@]}")
    for f in "${sorted[@]:KEEP_DAILY}"; do
        log "pruning daily $f"
        rm -f "$f" "$f.sha256" "$f.age"
    done
}

prune_weekly() {
    local files sorted f
    shopt -s nullglob
    files=("$WEEKLY_DIR"/nba-*.dump)
    ((${#files[@]} > KEEP_WEEKLY)) || return 0
    mapfile -t sorted < <(ls -1t "${files[@]}")
    for f in "${sorted[@]:KEEP_WEEKLY}"; do
        log "pruning weekly $f"
        rm -f "$f"
    done
}

prune_daily
prune_weekly

ENC="$DEST.age"
if [ ! -f "$ENC" ] || [ "$DEST" -nt "$ENC" ]; then
    if [ ! -f "$AGE_PUBKEY" ]; then
        log "missing age public key: $AGE_PUBKEY"
        exit 1
    fi
    rm -f "$ENC.tmp"
    age -r "$(cat "$AGE_PUBKEY")" -o "$ENC.tmp" "$DEST"
    mv "$ENC.tmp" "$ENC"
    chmod 600 "$ENC"
    log "encrypted $FILE"
fi

if [ "$DRY_RUN" = "1" ]; then
    log "DRY_RUN=1: skipping rclone upload"
    exit 0
fi

rclone copyto "$ENC" "$RCLONE_REMOTE/daily/$FILE.age"
log "uploaded daily/$FILE.age"

if [ "$(date -u +%d)" = "01" ]; then
    MONTHLY="nba-$(date -u +%Y-%m).dump.age"
    rclone copyto "$ENC" "$RCLONE_REMOTE/monthly/$MONTHLY"
    log "uploaded monthly/$MONTHLY"
fi

rclone delete "$RCLONE_REMOTE/daily" --include "nba-*.dump.age" --min-age 30d
if rclone lsf "$RCLONE_REMOTE/monthly" >/dev/null 2>&1; then
    rclone delete "$RCLONE_REMOTE/monthly" --include "nba-*.dump.age" --min-age 365d
fi
log "backup complete"
