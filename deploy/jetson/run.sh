#!/usr/bin/env bash
# Start (or replace) the Jetson Postgres container.
#
# Usage: ./run.sh
#
# Reads POSTGRES_PASSWORD from .env in this directory. The data directory is
# /srv/scs-nba-pg and survives replacing the container. Docker creates it on
# first run and the image chowns it to the postgres user.
#
# Published on loopback, the LAN address and Tailscale only. The LAN address is
# what the NUC uses; Tailscale is what the Mac uses, because macOS refuses
# LAN connections from most binaries.
set -euo pipefail

cd "$(dirname "$0")"
set -a
. ./.env
set +a

docker rm -f scs-nba-pg >/dev/null 2>&1 || true

docker run -d \
  --name scs-nba-pg \
  --restart unless-stopped \
  --shm-size 1g \
  -p 127.0.0.1:5432:5432 \
  -p 192.168.68.109:5432:5432 \
  -p 100.76.153.9:5432:5432 \
  -e POSTGRES_DB=nba \
  -e POSTGRES_USER=scs \
  -e POSTGRES_PASSWORD \
  -e TZ=UTC \
  -e PGTZ=UTC \
  -v /srv/scs-nba-pg:/var/lib/postgresql/data \
  --health-cmd "pg_isready -U scs -d nba" \
  --health-interval 10s \
  --health-timeout 5s \
  --health-retries 5 \
  postgres:17 \
  postgres \
    -c shared_buffers=4GB \
    -c effective_cache_size=12GB \
    -c work_mem=64MB \
    -c maintenance_work_mem=1GB \
    -c max_connections=50 \
    -c max_wal_size=4GB \
    -c timezone=UTC \
    -c log_timezone=UTC \
    -c autovacuum_vacuum_scale_factor=0.05 \
    -c autovacuum_analyze_scale_factor=0.02

echo "scs-nba-pg started; data in /srv/scs-nba-pg"
