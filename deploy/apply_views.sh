#!/bin/bash
# Apply the production views from this checkout.
#
# Views are DDL, not job output: run this after a pull that changes
# sql/views/**, not on every model run. With no arguments it applies every
# schema in dependency order; pass --schema mod for the model views.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

export PATH="$HOME/.local/bin:/usr/local/bin:/usr/bin:/bin"
exec uv run --frozen python scripts/apply_views.py "$@"
