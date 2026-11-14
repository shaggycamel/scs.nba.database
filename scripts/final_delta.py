"""Refresh a seeded Postgres database from Cockroach before cutover.

Usage:
    uv run python scripts/final_delta.py --target-db nba_rehearsal
    uv run python scripts/final_delta.py --target-section jetson-write

The target must be a clone of ``nba_seed``, the seed itself, or the Jetson.
Small and rewritten tables are replaced outright; append-only tables are topped
up. ``util.player_identity_review`` is never touched.
"""

import argparse

import sqlalchemy
from psycopg2.extras import execute_values
from scs_hub import Database


def insert_rows(conn, schema: str, table: str, df) -> None:
    cols = ', '.join(f'"{c}"' for c in df.columns)
    statement = f'INSERT INTO {schema}."{table}" ({cols}) VALUES %s'
    cursor = conn.connection.cursor()
    try:
        execute_values(cursor, statement, df.rows(), page_size=1000)
    finally:
        cursor.close()


def replace_full(src: Database, tgt: Database, schema: str, table: str, transform=None):
    df = src.read(f'SELECT * FROM {schema}."{table}"')
    if transform is not None:
        df = transform(df)
    with tgt.engine.begin() as conn:
        conn.execute(sqlalchemy.text(f'DELETE FROM {schema}."{table}"'))
        insert_rows(conn, schema, table, df)
    print(f'{schema}.{table}: {df.height:,} rows')


def replace_full_sql(src, tgt, schema, table, query):
    df = src.read(query)
    with tgt.engine.begin() as conn:
        conn.execute(sqlalchemy.text(f'DELETE FROM {schema}."{table}"'))
        insert_rows(conn, schema, table, df)
    print(f'{schema}.{table}: {df.height:,} rows')


def append_rows(tgt: Database, schema: str, table: str, df) -> None:
    if df.is_empty():
        print(f'{schema}.{table}: no new rows')
        return
    with tgt.engine.begin() as conn:
        insert_rows(conn, schema, table, df)
    print(f'{schema}.{table}: +{df.height:,} rows')


def append_missing_games(src, tgt, table, game_ids):
    if not game_ids:
        print(f'nba.{table}: no missing games')
        return
    ids = ','.join(str(int(g)) for g in game_ids)
    df = src.read(f'SELECT * FROM nba."{table}" WHERE game_id IN ({ids})')
    append_rows(tgt, 'nba', table, df)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--target-section', default='postgres')
    parser.add_argument('--target-db', help='override the target database name')
    args = parser.parse_args()

    if args.target_section == 'postgres' and not args.target_db:
        raise SystemExit(
            'refusing to target the local nba database; pass --target-db or a '
            'non-postgres --target-section'
        )

    src = Database('cockroach-write')
    base = Database(args.target_section)
    tgt = Database(args.target_section)
    if args.target_db:
        tgt.engine = sqlalchemy.create_engine(base.engine.url.set(database=args.target_db))

    # Rewritten nba tables. team_box_score comes first so the missing-game
    # checks below see the current game universe.
    replace_full(src, tgt, 'nba', 'league_game_schedule')
    replace_full(src, tgt, 'nba', 'team_box_score')
    replace_full(src, tgt, 'nba', 'team_roster')
    replace_full(src, tgt, 'nba', 'injuries')

    missing_box = tgt.read("""
        SELECT DISTINCT b.game_id
        FROM nba.team_box_score b
        WHERE NOT EXISTS (
            SELECT 1 FROM nba.player_box_score p WHERE p.game_id = b.game_id
        )
        ORDER BY 1
    """)['game_id'].to_list()
    append_missing_games(src, tgt, 'player_box_score', missing_box)

    max_pbp_date = tgt.read("""
        SELECT max(g.game_date)
        FROM nba.play_by_play p
        JOIN nba.league_game_schedule g ON g.game_id = p.game_id
    """).item()
    cutoff = max_pbp_date.isoformat() if max_pbp_date else '2026-11-01'
    missing_pbp = tgt.read(f"""
        SELECT DISTINCT b.game_id
        FROM nba.team_box_score b
        JOIN nba.league_game_schedule g ON g.game_id = b.game_id
        WHERE g.game_date >= DATE '{cutoff}' - 2
          AND g.team_winner IS NOT NULL
          AND NOT EXISTS (
              SELECT 1 FROM nba.play_by_play p WHERE p.game_id = b.game_id
          )
        ORDER BY 1
    """)['game_id'].to_list()
    append_missing_games(src, tgt, 'play_by_play', missing_pbp)

    # statyx: replace the season snapshots, append the per-game tables.
    replace_full(src, tgt, 'statyx', 'schedule', transform=lambda df: df.unique())
    replace_full(src, tgt, 'statyx', 'team_roster')

    for table, date_column in (
        ('game_stats', 'game_date'),
        ('advanced_stats', 'game_date'),
        ('potential_assists', 'game_date'),
        ('standings', 'date'),
    ):
        cutoff_value = tgt.read(f'SELECT max({date_column}) FROM statyx."{table}"').item()
        if cutoff_value is None:
            replace_full(src, tgt, 'statyx', table)
            continue
        df = src.read(
            f'SELECT * FROM statyx."{table}" WHERE {date_column} > '
            f"DATE '{cutoff_value.isoformat()}'"
        )
        append_rows(tgt, 'statyx', table, df)

    # fty: small/rewritten tables are cheap enough to replace outright.
    with tgt.engine.begin() as conn:
        conn.execute(sqlalchemy.text('DELETE FROM fty.platform_category'))
        conn.execute(sqlalchemy.text('DELETE FROM fty.category_label'))
    replace_full(src, tgt, 'fty', 'category_label')
    replace_full(src, tgt, 'fty', 'platform_category')

    for table in (
        'league',
        'league_competitor',
        'league_byes',
        'league_categories',
        'league_matchup',
        'league_matchup_dates',
        'matchup_box_score',
        'matchup_result',
        'free_agents',
        'scoring_format',
        'customer',
        'customer_league',
    ):
        replace_full(src, tgt, 'fty', table)

    replace_full_sql(
        src,
        tgt,
        'fty',
        'customer_platform',
        'SELECT customer_id, platform, credentials::text AS credentials FROM fty.customer_platform',
    )

    roster_cut = tgt.read('SELECT max(assigned_date) FROM fty.competitor_roster').item()
    df = src.read(
        f"SELECT * FROM fty.competitor_roster WHERE assigned_date >= DATE '{roster_cut.isoformat()}'"
    )
    with tgt.engine.begin() as conn:
        conn.execute(
            sqlalchemy.text(
                f"DELETE FROM fty.competitor_roster WHERE assigned_date >= DATE '{roster_cut.isoformat()}'"
            )
        )
        insert_rows(conn, 'fty', 'competitor_roster', df)
    print(f'fty.competitor_roster: {df.height:,} rows from {roster_cut}')

    activity_cut = tgt.read('SELECT max(timestamp) FROM fty.recent_activity').item()
    df = src.read(
        f"SELECT * FROM fty.recent_activity WHERE timestamp >= TIMESTAMPTZ '{activity_cut.isoformat()}'"
    )
    with tgt.engine.begin() as conn:
        conn.execute(
            sqlalchemy.text(
                f"DELETE FROM fty.recent_activity WHERE timestamp >= TIMESTAMPTZ '{activity_cut.isoformat()}'"
            )
        )
        insert_rows(conn, 'fty', 'recent_activity', df)
    print(f'fty.recent_activity: {df.height:,} rows from {activity_cut}')

    # util: replace the registries, preserve the review history.
    replace_full(src, tgt, 'util', 'update_schedule')
    replace_full(src, tgt, 'util', 'table_column_order')
    replace_full(src, tgt, 'util', 'deps_saved_ddl')
    replace_full(src, tgt, 'util', 'draft_player_log')
    replace_full_sql(
        src,
        tgt,
        'util',
        'sql_grant',
        'SELECT grantee, schema, table_name, relation_type, privilege FROM util.sql_grant',
    )

    with tgt.engine.begin() as conn:
        conn.execute(sqlalchemy.text('DELETE FROM util.player_source_id'))
        conn.execute(sqlalchemy.text('DELETE FROM util.player'))
    replace_full(src, tgt, 'util', 'player')
    replace_full(src, tgt, 'util', 'player_source_id')

    log_cut = tgt.read('SELECT max(task_time) FROM util.update_log').item()
    df = src.read(
        f"SELECT * FROM util.update_log WHERE task_time > TIMESTAMPTZ '{log_cut.isoformat()}'"
    )
    append_rows(tgt, 'util', 'update_log', df)

    # mod: every model table is small enough to replace.
    for table in (
        'injury_daily_forecast_base',
        'player_archetype_base',
        'player_archetype_current_base',
        'player_archetype_model_base',
        'player_archetype_profile_base',
        'team_hierarchy_base',
    ):
        replace_full(src, tgt, 'mod', table)

    print('final delta complete')


if __name__ == '__main__':
    main()
