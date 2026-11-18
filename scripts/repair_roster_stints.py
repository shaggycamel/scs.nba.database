"""Reopen player stints closed by a partial CommonTeamRoster fetch.

A team that fails CommonTeamRoster during ``nba.get_team_roster`` is absent from
that run's frame. Older versions of the function still diffed it against every
open stint, so all of that team's players looked like departures and their
stints were closed on the run date.

This repairs the stored table from the current NBA roster: for each affected
team, every player the API still lists has their latest closed stint reopened.
Players the API no longer lists are left alone, and no dates are changed for
players with a newer open stint. The default is a dry run.

Usage:
    uv run python scripts/repair_roster_stints.py --db-con jetson-write
    uv run python scripts/repair_roster_stints.py --db-con jetson-write --apply
"""

from __future__ import annotations

import argparse

import polars as pl
from nba_api.stats.endpoints import commonteamroster
from scs_hub.context import Context
from scs_hub.db import Database
from sqlalchemy import text


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--db-con", default="postgres", help="credentials section")
    parser.add_argument(
        "--teams",
        default="ATL,BOS,CLE,NOP",
        help="comma-separated team slugs to repair",
    )
    parser.add_argument(
        "--apply",
        action="store_true",
        help="write the repair; without it the script only reports",
    )
    return parser.parse_args()


def current_roster_ids(ctx: Context, team_id: int) -> list[int]:
    raw = commonteamroster.CommonTeamRoster(
        season=ctx.cur_season_year, team_id=team_id
    ).get_data_frames()[0]
    if raw is None or len(raw) == 0:
        raise RuntimeError(f"CommonTeamRoster returned no rows for team {team_id}")
    return (
        pl.from_pandas(raw)
        .get_column("PLAYER_ID")
        .cast(pl.Int64)
        .unique()
        .to_list()
    )


def repair_team(
    db: Database, ctx: Context, team_slug: str, team_id: int, apply: bool
) -> None:
    api_ids = current_roster_ids(ctx, team_id)
    id_list = ", ".join(str(player_id) for player_id in api_ids)

    stored = db.read(
        f"SELECT player_id::BIGINT AS player_id, entry_date, exit_date "
        f"FROM nba.team_roster "
        f"WHERE season = '{ctx.cur_season}' AND team_id = {team_id} "
        f"AND player_id::BIGINT IN ({id_list})"
    )
    stored_ids = set(stored.get_column("player_id").cast(pl.Int64).to_list())

    missing = sorted(set(api_ids) - stored_ids)
    closed = stored.filter(pl.col("exit_date").is_not_null())
    print(
        f"{team_slug}: api={len(api_ids)} stored={len(stored_ids)} "
        f"reopen={closed.height} missing_from_table={missing}"
    )
    if closed.height:
        print(
            "  "
            + ", ".join(
                f"{row['player_id']} ({row['exit_date']})"
                for row in closed.iter_rows(named=True)
            )
        )

    if not apply or closed.is_empty():
        return

    # Reopen only the latest stint per player. A player with a newer open stint
    # already has the right state, and an older closed stint is history.
    with db.engine.begin() as conn:
        result = conn.execute(
            text(
                f"""
                UPDATE nba.team_roster tr
                SET exit_date = NULL
                WHERE tr.season = '{ctx.cur_season}'
                  AND tr.team_id = {team_id}
                  AND tr.player_id::BIGINT IN ({id_list})
                  AND tr.exit_date IS NOT NULL
                  AND tr.entry_date IS NOT DISTINCT FROM (
                      SELECT max(tr2.entry_date)
                      FROM nba.team_roster tr2
                      WHERE tr2.season = tr.season
                        AND tr2.team_id = tr.team_id
                        AND tr2.player_id = tr.player_id
                  )
                """
            )
        )
    print(f"  reopened {result.rowcount} row(s)")


def main() -> None:
    args = parse_args()
    db = Database(args.db_con)
    ctx = Context(db)

    teams = (
        ctx.nba_teams.filter(pl.col("abbreviation").is_in(args.teams.split(",")))
        .select("id", "abbreviation")
        .sort("abbreviation")
    )
    found = set(teams.get_column("abbreviation").to_list())
    not_found = sorted(set(args.teams.split(",")) - found)
    if not_found:
        raise RuntimeError(f"unknown team slug(s): {not_found}")

    for row in teams.iter_rows(named=True):
        repair_team(db, ctx, row["abbreviation"], int(row["id"]), args.apply)

    if args.apply:
        check = db.read(
            f"SELECT team_slug, count(*) AS rows, "
            f"count(*) FILTER (WHERE exit_date IS NULL) AS open_stints "
            f"FROM nba.team_roster WHERE season = '{ctx.cur_season}' "
            f"GROUP BY team_slug ORDER BY open_stints, team_slug"
        )
        print("\nOpen stints by team:")
        print(check.filter(pl.col("open_stints") == 0))
        print(check.filter(pl.col("team_slug").is_in(args.teams.split(","))))


if __name__ == "__main__":
    main()
