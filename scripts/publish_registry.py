"""Publish the Jetson league registry back to Cockroach.

Runs on the NUC after the weekly fty jobs. Cockroach remains the customer-facing
authority; this copies the two registry tables the entry app reads. Customer
tables and ``util.draft_player_log`` are never published.

Usage:
    uv run python scripts/publish_registry.py --dry-run
    uv run python scripts/publish_registry.py
"""

import argparse

import sqlalchemy
from psycopg2.extras import execute_values
from scs_hub import Database

TABLES = ('league', 'league_competitor')


def insert_rows(conn, table: str, df) -> None:
    cols = ', '.join(f'"{c}"' for c in df.columns)
    statement = f'INSERT INTO fty."{table}" ({cols}) VALUES %s'
    cursor = conn.connection.cursor()
    try:
        execute_values(cursor, statement, df.rows(), page_size=1000)
    finally:
        cursor.close()


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source-section', default='jetson-write')
    parser.add_argument('--target-section', default='cockroach-write')
    parser.add_argument('--source-db', help='override the source database name')
    parser.add_argument('--target-db', help='override the target database name')
    parser.add_argument('--dry-run', action='store_true', help='read both sides but write nothing')
    args = parser.parse_args()

    source = Database(args.source_section)
    target = Database(args.target_section)
    if args.source_db:
        source.engine = sqlalchemy.create_engine(source.engine.url.set(database=args.source_db))
    if args.target_db:
        target.engine = sqlalchemy.create_engine(target.engine.url.set(database=args.target_db))

    frames = {}
    for table in TABLES:
        df = source.read(f'SELECT * FROM fty."{table}"')
        if df.is_empty():
            raise SystemExit(f'refusing to publish: {table} is empty on the Jetson')
        frames[table] = df
        print(f'source fty.{table}: {df.height:,} rows')

    if args.dry_run:
        for table in TABLES:
            current = target.read(f'SELECT count(*) FROM fty."{table}"').item()
            print(f'target fty.{table}: {current:,} rows (dry run)')
        return

    with target.engine.begin() as conn:
        conn.execute(sqlalchemy.text('DELETE FROM fty.league_competitor'))
        conn.execute(sqlalchemy.text('DELETE FROM fty.league'))
        insert_rows(conn, 'league', frames['league'])
        insert_rows(conn, 'league_competitor', frames['league_competitor'])

    for table in TABLES:
        print(f'published fty.{table}: {frames[table].height:,} rows')


if __name__ == '__main__':
    main()
