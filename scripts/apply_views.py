"""Apply the production view files under sql/views/<schema>/<name>_vw.sql.

Usage:
    uv run python scripts/apply_views.py
    uv run python scripts/apply_views.py --schema mod
    uv run python scripts/apply_views.py --db-con postgres
"""

import argparse
from pathlib import Path

from scs_hub import Database

# Dependency order, not alphabetical: mod views read the shared schemas.
SCHEMA_ORDER = ('nba', 'statyx', 'fty', 'util', 'mod')

# Only production views are applied. Retired SQL has been deleted; the suffix
# check keeps any future non-view SQL out of this pass.
VIEWS_DIR = Path(__file__).resolve().parent.parent / 'sql' / 'views'


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        '--schema',
        action='append',
        choices=SCHEMA_ORDER,
        help='apply only this schema; repeat for more (default: all)',
    )
    parser.add_argument(
        '--db-con',
        default='cockroach-write',
        help="credentials.ini section (use 'postgres' locally)",
    )
    return parser.parse_args()


def has_base_tables(db: Database, schema: str) -> bool:
    """Whether this connection carries the schema's tables (not just its views)."""
    return (
        db.read(
            'SELECT count(*) FROM information_schema.tables '
            f"WHERE table_schema = '{schema}' AND table_type = 'BASE TABLE'"
        ).item()
        > 0
    )


def has_role(db: Database, role: str = 'kobe_public') -> bool:
    """Whether the read-only role exists on this connection."""
    return (
        db.read(f"SELECT count(*) FROM pg_roles WHERE rolname = '{role}'").item() > 0
    )


def main() -> None:
    args = parse_args()
    schemas = args.schema or SCHEMA_ORDER
    db = Database(args.db_con)

    applied = 0
    for schema in schemas:
        if not has_base_tables(db, schema):
            print(f'{schema}: no base tables on this connection; skipped')
            continue
        for path in sorted((VIEWS_DIR / schema).glob('*_vw.sql')):
            db.execute(path.read_text())
            print(f'{schema}/{path.name}')
            applied += 1

    if not applied:
        print('no view files matched; nothing to apply')
        return

    # Replacing a view drops its grants. Local dev databases may not carry the
    # production read-only role.
    if has_role(db):
        db.regrant_read()
        print(f'applied {applied} view(s) and regranted read access')
    else:
        print(f'applied {applied} view(s); kobe_public absent, grants skipped')


if __name__ == '__main__':
    main()
