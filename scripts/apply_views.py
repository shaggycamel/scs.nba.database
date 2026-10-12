#!/usr/bin/env python3
"""Apply every sql/views/<schema>/*.sql file to a Postgres or Cockroach database.

Nothing in this repo ever applied these files; this is that step. The database is the
system of record for the views and sql/views is a hand-applied mirror, so this makes the
mirror authoritative again.

Reads and writes go through scs_hub's Database, the same connection layer every job uses, so
there is no psql to install and no DSN to keep in sync. The section to connect with is --con,
else DB_CON, else [runtime] db_con in the credentials file -- the same file and order
__main__.py resolves.

Each file is applied with CREATE OR REPLACE, retrying until no new failures appear so a view
may safely reference another view whose file is applied later in the same run. Nothing is
dropped by default: DROP ... CASCADE would silently take views that live in the database but
have no file here (util.active_player_vw and util.unmatched_player_source_vw both hang off
util.player_directory_vw). When a view's column list has genuinely changed, CREATE OR
REPLACE cannot express it -- use --force-drop, which drops that one view without CASCADE so a
real dependency fails loudly instead of being destroyed.

    DB_CON=cockroach python scripts/apply_views.py --dry-run
    DB_CON=cockroach python scripts/apply_views.py
    DB_CON=postgres  python scripts/apply_views.py --schema fty

Cockroach has no implicit grants for a read-only role, so --grant re-applies SELECT to that
role with Database.regrant_read, which sweeps every table and view in the schemas just
touched and is idempotent.

The closing count check compares live view counts against the file count per schema, so a
view that exists in the database without a file is visible rather than assumed harmless.
"""

from __future__ import annotations

import argparse
import configparser
import os
import re
import sys
from collections import Counter
from pathlib import Path

from scs_hub import Database
from scs_hub.config import credentials_path

VIEWS_DIR = Path(__file__).resolve().parent.parent / 'sql' / 'views'
NAME_RE = re.compile(r'create\s+(?:or\s+replace\s+)?view\s+([a-z_]\w*\.[a-z_]\w*)', re.I)
MAX_PASSES = 5


def view_files(schema: str | None) -> list[Path]:
    pattern = f'{schema}/*.sql' if schema else '*/*.sql'
    return sorted(VIEWS_DIR.glob(pattern))


def view_name(sql: str) -> str:
    match = NAME_RE.search(sql)
    if match is None:
        raise ValueError('no CREATE VIEW statement found')
    return match.group(1)


def resolve_con(explicit: str | None, ini_path: str) -> str | None:
    """--con > DB_CON > [runtime] db_con, the same order __main__.py resolves."""
    if explicit:
        return explicit
    env = os.environ.get('DB_CON')
    if env:
        return env
    parser = configparser.ConfigParser()
    parser.read(ini_path)
    return parser.get('runtime', 'db_con', fallback=None)


def live_counts(db: Database, schemas: list[str]) -> Counter[str]:
    quoted = ','.join(f"'{s}'" for s in schemas)
    df = db.read(
        f'SELECT schemaname, count(*) AS n FROM pg_views WHERE schemaname IN ({quoted}) GROUP BY 1'
    )
    return Counter({schema: int(n) for schema, n in zip(df['schemaname'], df['n'])})


def main() -> int:
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument(
        '--con',
        default=None,
        help='credentials.ini section to connect with (default: DB_CON, else [runtime] db_con)',
    )
    parser.add_argument(
        '--ini',
        default=None,
        help='credentials.ini path (default: SCS_HUB_CREDENTIALS or ~/.config/scs_hub_credentials.ini)',
    )
    parser.add_argument('--schema', default=None, help='only this sql/views/<schema>/ folder')
    parser.add_argument(
        '--force-drop',
        action='store_true',
        help='drop each view (no CASCADE) before creating it; needed only when a column '
        'list changed, and it fails loudly rather than taking dependent views with it',
    )
    parser.add_argument(
        '--grant',
        default=None,
        help='after applying, GRANT SELECT on the touched schemas to this role',
    )
    parser.add_argument('--dry-run', action='store_true')
    args = parser.parse_args()

    ini_path = credentials_path(args.ini)
    con = resolve_con(args.con, ini_path)
    if not con:
        print(
            f'no connection: pass --con, set DB_CON, or add [runtime] db_con to {ini_path}',
            file=sys.stderr,
        )
        return 2

    jobs: list[tuple[Path, str, str]] = []
    for path in view_files(args.schema):
        sql = path.read_text()
        try:
            jobs.append((path, view_name(sql), sql))
        except ValueError as exc:
            print(f'{path}: {exc}', file=sys.stderr)
            return 2

    if not jobs:
        print(f'no view files under {VIEWS_DIR}', file=sys.stderr)
        return 2

    print(f'{len(jobs)} view files under {VIEWS_DIR}')
    if args.dry_run:
        for path, name, _ in jobs:
            print(f'  {name:40s} {path.relative_to(VIEWS_DIR.parent.parent)}')
        return 0

    db = Database(con, ini_path)
    print(f'connected to {con} ({db.engine.name})')

    expected = Counter(name.split('.')[0] for _, name, _ in jobs)
    pending: list[tuple[Path, str, str]] = list(jobs)
    last_errors: dict[Path, str] = {}
    done = False
    for attempt in range(1, MAX_PASSES + 1):
        failed: list[tuple[Path, str, str]] = []
        last_errors = {}
        for path, name, sql in pending:
            try:
                if args.force_drop:
                    db.execute(f'DROP VIEW IF EXISTS {name}')
                db.execute(sql)
            except Exception as exc:  # report and retry rather than abort the sweep
                failed.append((path, name, sql))
                last_errors[path] = str(exc)
        print(f'pass {attempt}: {len(pending) - len(failed)} ok, {len(failed)} failed')
        if not failed:
            done = True
            break
        if len(failed) == len(pending):
            break  # no progress: the same files would fail forever
        pending = failed

    if not done:
        for path, _, _ in pending:
            print(f'FAILED {path}: {last_errors.get(path, "")}', file=sys.stderr)
        return 1

    counts = live_counts(db, sorted(expected))
    bad = False
    for schema in sorted(expected):
        got, want = counts.get(schema, 0), expected[schema]
        if got < want:
            note, bad = 'MISMATCH', True  # a file did not apply
        elif got > want:
            note = f'EXTRA {got - want} in the db with no file here'
        else:
            note = 'ok'
        print(f'{schema}: {got} views live, {want} files [{note}]')

    if args.grant:
        granted = db.regrant_read(args.grant, tuple(sorted(expected)))
        print(
            f'granted SELECT to {args.grant} on: {", ".join(granted) if granted else "no schemas"}'
        )

    return 1 if bad else 0


if __name__ == '__main__':
    raise SystemExit(main())
