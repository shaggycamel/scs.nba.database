#!/usr/bin/env bash
# Start or replace the Jetson Postgres container.
#
# Usage: ./run.sh
#
# The container is defined in compose.yaml. POSTGRES_PASSWORD comes from .env
# in this directory. Data lives in /srv/scs-nba-pg and survives replacement.
set -euo pipefail

cd "$(dirname "$0")"
docker compose up -d
docker compose ps
