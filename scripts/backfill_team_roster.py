"""Rebuild nba.team_roster as clean, evidence-based player-team stints.

The box score is authoritative for who played and for which team; the existing
roster, transaction log and how-acquired text only add movement dates. Rows are
kept for players who did not appear in the box score that season (injured or
bench), but they do not invent dates for them.

The injury report supplies one extra piece of evidence: a player traded while
injured may never play for the new team, so the box score has no new-team run.
If the report shows the player on that team, that is a real stint and is added
with the report's date range.

Null dates are deliberate:

* entry_date IS NULL -> already on the roster at the start of the season.
* exit_date IS NULL  -> still on the roster at the end of the season (or open).

Nothing is filled with season boundaries; the views coalesce those. A backfill
is idempotent: it builds a candidate, validates it, and only replaces the live
table with --apply.

Usage:
    uv run python scripts/backfill_team_roster.py --db-con postgres
    uv run python scripts/backfill_team_roster.py --db-con postgres --apply
    uv run python scripts/backfill_team_roster.py --db-con cockroach-write --apply
"""

from __future__ import annotations

import argparse
from datetime import UTC, datetime, timedelta

import polars as pl
from scs_hub import Database
from sqlalchemy import text

COLUMNS = [
    "season",
    "team_id",
    "team_slug",
    "player_id",
    "player",
    "position",
    "num",
    "how_acquired",
    "salary",
    "entry_date",
    "exit_date",
]
TEAM_ALIASES = {"blazers": "POR", "bobcats": "CHA"}
NEAR_SEASON_EDGE_DAYS = 3
DATE_IN_TEXT = r"(\d{1,2}/\d{1,2}/\d{2})"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--db-con", default="postgres", help="credentials section")
    parser.add_argument(
        "--apply",
        action="store_true",
        help="replace nba.team_roster after the candidate validates",
    )
    return parser.parse_args()


def team_lookup(db: Database) -> dict[str, str]:
    teams = db.read("SELECT team_slug, team_long, team_name FROM nba.teams")
    lookup: dict[str, str] = {}
    for row in teams.iter_rows(named=True):
        for value in (row["team_slug"], row["team_long"], row["team_name"]):
            if value:
                lookup[value.lower()] = row["team_slug"]
    lookup.update(TEAM_ALIASES)
    return lookup


def season_bounds(db: Database) -> pl.DataFrame:
    return db.read("""
        SELECT season, begin_date, end_date
        FROM nba.key_dates
        WHERE season_type = 'Regular Season'
    """)


def box_runs(db: Database) -> pl.DataFrame:
    """One row per consecutive run of games with the same team.

    The run detection is done in SQL: Cockroach's 594k box-score rows are much
    cheaper to scan there than to transfer into Python.
    """
    return db.read("""
        WITH box AS (
            SELECT lgs.season, lgs.game_date, lgs.game_id, lgs.team AS team_slug,
                   t.team_id, pbs.player_id, pbs.player_name
            FROM nba.player_box_score pbs
            JOIN nba.teams t ON pbs.team_id = t.team_id
            JOIN nba.league_game_schedule lgs
              ON pbs.game_id = lgs.game_id AND t.team_slug = lgs.team
            WHERE lgs.season_type = 'Regular Season' AND pbs.min > 0
        ),
        marked AS (
            SELECT *,
                   CASE
                       WHEN team_slug = LAG(team_slug) OVER (
                           PARTITION BY player_id, season
                           ORDER BY game_date, game_id
                       ) THEN 0
                       ELSE 1
                   END AS new_run
            FROM box
        ),
        runs AS (
            SELECT *,
                   SUM(new_run) OVER (
                       PARTITION BY player_id, season
                       ORDER BY game_date, game_id
                       ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
                   ) AS run_id
            FROM marked
        )
        SELECT season, player_id, team_slug, team_id, run_id,
               COUNT(*) AS box_games,
               MIN(game_date) AS first_game,
               MAX(game_date) AS last_game,
               MAX(player_name) AS box_name
        FROM runs
        GROUP BY season, player_id, team_slug, team_id, run_id
    """)


def injury_report_stints(db: Database) -> pl.DataFrame:
    """Player-team stints evidenced by the injury report.

    A player traded while injured may never appear in the new team's box
    score. The report is the only evidence of the new-team stint.
    """
    return db.read("""
        SELECT season, team_slug, MAX(team_id) AS team_id,
               nba_id AS player_id,
               MAX(player_name) AS player,
               MIN(game_date) AS first_report,
               MAX(game_date) AS last_report
        FROM nba.injuries_vw
        WHERE nba_id IS NOT NULL
          AND season IS NOT NULL
          AND season >= '2021-22'
        GROUP BY season, team_slug, nba_id
        -- One-day rows are usually a scraper/team-assignment error, and a
        -- one-day "trade" would create a false stint. Real injured-traded
        -- stints last more than a few days.
        HAVING MAX(game_date) - MIN(game_date) >= 3
    """)


def roster_attributes(db: Database) -> pl.DataFrame:
    roster = db.read("SELECT * FROM nba.team_roster").with_columns(
        pl.col("player_id").cast(pl.Int64, strict=False)
    )
    roster = roster.filter(pl.col("player_id").is_not_null())
    return roster.group_by("season", "team_slug", "team_id", "player_id").agg(
        pl.col("player").drop_nulls().last().alias("player"),
        pl.col("position").drop_nulls().last().alias("position"),
        pl.col("num").drop_nulls().last().alias("num"),
        pl.col("how_acquired").drop_nulls().last().alias("how_acquired"),
        pl.col("salary").drop_nulls().last().alias("salary"),
        pl.col("entry_date").drop_nulls().min().alias("entry_date"),
        pl.col("exit_date").drop_nulls().max().alias("exit_date"),
    )


def no_box_rows(db: Database, runs: pl.DataFrame) -> pl.DataFrame:
    """Existing roster rows for player-seasons with no box-score appearance."""
    roster = db.read("SELECT * FROM nba.team_roster").with_columns(
        pl.col("player_id").cast(pl.Int64, strict=False)
    )
    roster = roster.filter(pl.col("player_id").is_not_null())
    box_players = runs.select("season", "player_id").unique()
    no_box = roster.join(box_players, on=["season", "player_id"], how="anti")
    return no_box.group_by("season", "team_slug", "team_id", "player_id").agg(
        pl.col("player").drop_nulls().last().alias("player"),
        pl.col("position").drop_nulls().last().alias("position"),
        pl.col("num").drop_nulls().last().alias("num"),
        pl.col("how_acquired").drop_nulls().last().alias("how_acquired"),
        pl.col("salary").drop_nulls().last().alias("salary"),
        pl.when(pl.col("entry_date").is_null().any())
        .then(None)
        .otherwise(pl.col("entry_date").min())
        .alias("entry_date"),
        pl.when(pl.col("exit_date").is_null().any())
        .then(None)
        .otherwise(pl.col("exit_date").max())
        .alias("exit_date"),
    ).with_columns(
        pl.lit(None).cast(pl.UInt32).alias("box_games"),
        pl.lit(None).cast(pl.Date).alias("first_game"),
        pl.lit(None).cast(pl.Date).alias("last_game"),
    )


def normalise(cand: pl.DataFrame, bounds: pl.DataFrame) -> pl.DataFrame:
    cand = cand.join(bounds, on="season", how="left")
    cand = cand.with_columns(
        pl.col("how_acquired")
        .str.extract(DATE_IN_TEXT, 1)
        .str.strptime(pl.Date, "%m/%d/%y", strict=False)
        .alias("acquired_date")
    )
    cand = cand.with_columns(
        pl.when(
            pl.col("entry_date").is_not_null()
            & (
                (pl.col("entry_date") <= pl.col("begin_date") + pl.duration(days=NEAR_SEASON_EDGE_DAYS))
                | (pl.col("entry_date") > pl.col("end_date"))
            )
        )
        .then(None)
        .otherwise(pl.col("entry_date"))
        .alias("entry_date"),
        pl.when(
            pl.col("exit_date").is_not_null()
            & (
                (pl.col("exit_date") >= pl.col("end_date") - pl.duration(days=NEAR_SEASON_EDGE_DAYS))
                | (pl.col("exit_date") < pl.col("begin_date"))
            )
        )
        .then(None)
        .otherwise(pl.col("exit_date"))
        .alias("exit_date"),
    )
    return cand.with_columns(
        pl.when(
            pl.col("acquired_date").is_not_null()
            & (pl.col("acquired_date") > pl.col("begin_date") + pl.duration(days=NEAR_SEASON_EDGE_DAYS))
            & (pl.col("acquired_date") < pl.col("end_date"))
        )
        .then(pl.col("acquired_date"))
        .otherwise(pl.col("entry_date"))
        .alias("entry_date")
    )


def transaction_dates(db: Database, bounds: pl.DataFrame, teams: dict[str, str]) -> dict:
    tx = db.read("""
        SELECT tl.date, tl.team, tl.acc_req, nm.nba_id AS player_id
        FROM nba.transaction_log tl
        LEFT JOIN util.player_id_map_vw nm
          ON lower(trim(tl.player)) IN (
              lower(trim(nm.nba_name)), lower(trim(nm.conformed_name))
          )
        WHERE tl.transaction_type = 'Movement'
    """).filter(pl.col("player_id").is_not_null())
    tx = tx.with_columns(
        pl.col("team")
        .map_elements(
            lambda value: teams.get(str(value).lower()) if value else None,
            return_dtype=pl.String,
        )
        .alias("team_slug")
    )
    tx = (
        tx.join(bounds, how="cross")
        .filter((pl.col("date") >= pl.col("begin_date")) & (pl.col("date") <= pl.col("end_date")))
        .select("season", "date", "team_slug", "player_id", "acc_req")
    )
    grouped: dict[tuple[str, int], list[dict]] = {}
    for row in tx.iter_rows(named=True):
        grouped.setdefault((row["season"], row["player_id"]), []).append(row)
    return grouped


def apply_transactions(cand: pl.DataFrame, transactions: dict) -> pl.DataFrame:
    rows = cand.to_dicts()
    changed_entry = changed_exit = 0
    for row in rows:
        if row["first_game"] is None:
            continue
        txs = transactions.get((row["season"], row["player_id"]), [])
        if not txs:
            continue
        team = row["team_slug"]
        first, last = row["first_game"], row["last_game"]
        begin, end = row["begin_date"], row["end_date"]
        arrivals = [
            tx
            for tx in txs
            if tx["acc_req"] == "Acquired"
            and tx["date"] <= first
            and (tx["team_slug"] is None or tx["team_slug"] == team)
        ]
        if arrivals:
            acquired = max(tx["date"] for tx in arrivals)
            if acquired > begin + timedelta(days=NEAR_SEASON_EDGE_DAYS) and acquired != row["entry_date"]:
                row["entry_date"] = acquired
                changed_entry += 1
        departures = [
            tx
            for tx in txs
            if tx["acc_req"] == "Relinquished"
            and tx["date"] >= last
            and tx["date"] < end - timedelta(days=NEAR_SEASON_EDGE_DAYS)
            and (tx["team_slug"] is None or tx["team_slug"] == team)
        ]
        if departures:
            departed = min(tx["date"] for tx in departures)
            if departed != row["exit_date"]:
                row["exit_date"] = departed
                changed_exit += 1
    print(f"transaction dates: {changed_entry} entries, {changed_exit} exits")
    return pl.DataFrame(rows, infer_schema_length=None)


def reconcile(cand: pl.DataFrame) -> pl.DataFrame:
    groups: dict[tuple[str, int], list[dict]] = {}
    for row in cand.to_dicts():
        groups.setdefault((row["season"], row["player_id"]), []).append(row)

    out: list[dict] = []
    for group in groups.values():
        group.sort(
            key=lambda row: (
                row["entry_date"] or row["begin_date"],
                row["exit_date"] or row["end_date"],
                row["team_slug"],
            )
        )
        merged: list[dict] = []
        for row in group:
            row["_start"] = row["entry_date"] or row["begin_date"]
            row["_end"] = row["exit_date"] or row["end_date"]
            if merged:
                previous = merged[-1]
                if row["_start"] < previous["_end"]:
                    if row["team_slug"] == previous["team_slug"]:
                        previous["_start"] = min(previous["_start"], row["_start"])
                        previous["_end"] = max(previous["_end"], row["_end"])
                        for column in ("player", "position", "num", "how_acquired", "salary"):
                            if not previous.get(column) and row.get(column):
                                previous[column] = row[column]
                        if row.get("box_games") is not None:
                            previous["box_games"] = (previous.get("box_games") or 0) + row["box_games"]
                        previous["first_game"] = min(
                            [value for value in (previous.get("first_game"), row.get("first_game")) if value],
                            default=None,
                        )
                        previous["last_game"] = max(
                            [value for value in (previous.get("last_game"), row.get("last_game")) if value],
                            default=None,
                        )
                        continue
                    boundary = max(row["_start"], previous["_start"] + timedelta(days=1))
                    previous["_end"] = min(previous["_end"], boundary)
                    row["_start"] = boundary
                    if row["_end"] < row["_start"]:
                        row["_end"] = row["_start"]
            merged.append(row)
        if merged[0]["entry_date"] is not None and merged[0]["entry_date"] <= merged[0][
            "begin_date"
        ] + timedelta(days=NEAR_SEASON_EDGE_DAYS):
            merged[0]["entry_date"] = None
        for row in merged:
            row["entry_date"] = None if row["_start"] <= row["begin_date"] else row["_start"]
            row["exit_date"] = None if row["_end"] >= row["end_date"] else row["_end"]
            out.append(row)
    return pl.DataFrame(out, infer_schema_length=None)


def build_candidate(db: Database) -> pl.DataFrame:
    bounds = season_bounds(db)
    teams = team_lookup(db)
    runs = box_runs(db)
    attrs = roster_attributes(db)
    no_box = no_box_rows(db, runs)

    cand = runs.join(attrs, on=["season", "team_slug", "team_id", "player_id"], how="left")
    cand = cand.with_columns(
        pl.coalesce("player", "box_name").alias("player"),
        pl.lit(None).cast(pl.UInt32).alias("source_rows"),
    )
    cand = pl.concat([cand, no_box], how="diagonal_relaxed")

    # Add stints evidenced only by the injury report. This is the traded-while-
    # injured case: the player never appears in the new team's box score.
    report = injury_report_stints(db)
    seen = cand.select("season", "team_slug", "player_id").unique()
    report = report.join(seen, on=["season", "team_slug", "player_id"], how="anti")
    report = report.with_columns(
        pl.col("first_report").alias("entry_date"),
        (pl.col("last_report") + pl.duration(days=1)).alias("exit_date"),
        pl.lit(0).cast(pl.UInt32).alias("box_games"),
        pl.col("first_report").alias("first_game"),
        pl.col("last_report").alias("last_game"),
        pl.lit(None).cast(pl.UInt32).alias("source_rows"),
    )
    cand = pl.concat([cand, report], how="diagonal_relaxed")
    cand = normalise(cand, bounds)

    # A team change closes the old run and opens the new one at the next first game.
    cand = cand.sort("season", "player_id", "first_game", "team_slug")
    cand = cand.with_columns(
        pl.col("first_game").shift(-1).over("season", "player_id").alias("next_first")
    )
    cand = cand.with_columns(
        pl.when(
            pl.col("next_first").is_not_null()
            & (pl.col("exit_date").is_null() | (pl.col("exit_date") > pl.col("next_first")))
        )
        .then(pl.col("next_first"))
        .otherwise(pl.col("exit_date"))
        .alias("exit_date")
    )
    cand = cand.with_columns(
        pl.col("next_first").shift(1).over("season", "player_id").alias("prev_boundary")
    )
    cand = cand.with_columns(
        pl.when(
            pl.col("prev_boundary").is_not_null()
            & (pl.col("entry_date").is_null() | (pl.col("entry_date") < pl.col("prev_boundary")))
        )
        .then(pl.col("prev_boundary"))
        .otherwise(pl.col("entry_date"))
        .alias("entry_date")
    )

    cand = apply_transactions(cand, transaction_dates(db, bounds, teams))
    rows = cand.to_dicts()
    for row in rows:
        if row["box_games"] is None:
            continue
        if row["entry_date"] is not None and row["entry_date"] > row["first_game"]:
            row["entry_date"] = row["first_game"]
        if row["exit_date"] is not None and row["exit_date"] <= row["last_game"]:
            row["exit_date"] = row["last_game"] + timedelta(days=1)
        if row["entry_date"] is not None and row["entry_date"] <= row["begin_date"] + timedelta(
            days=NEAR_SEASON_EDGE_DAYS
        ):
            row["entry_date"] = None
        if row["exit_date"] is not None and row["exit_date"] >= row["end_date"] - timedelta(
            days=NEAR_SEASON_EDGE_DAYS
        ):
            row["exit_date"] = None
    cand = reconcile(pl.DataFrame(rows, infer_schema_length=None))
    # A one-day report-only stint can be truncated to entry == exit by the
    # overlap pass. Treat the exit as exclusive.
    cand = cand.with_columns(
        pl.when(
            pl.col("entry_date").is_not_null()
            & pl.col("exit_date").is_not_null()
            & (pl.col("exit_date") <= pl.col("entry_date"))
        )
        .then(pl.col("entry_date") + pl.duration(days=1))
        .otherwise(pl.col("exit_date"))
        .alias("exit_date")
    )
    return cand.select(COLUMNS)


def validate(db: Database, cand: pl.DataFrame) -> None:
    runs = box_runs(db)
    box_keys = runs.select("season", "team_slug", "team_id", "player_id").unique()
    cand_keys = cand.select("season", "team_slug", "team_id", "player_id").unique()
    missing = box_keys.join(cand_keys, on=["season", "team_slug", "team_id", "player_id"], how="anti")
    if missing.height:
        raise SystemExit(f"candidate misses {missing.height} box-score stints")

    report_keys = injury_report_stints(db).select("season", "team_slug", "player_id").unique()
    missing_report = report_keys.join(
        cand.select("season", "team_slug", "player_id").unique(),
        on=["season", "team_slug", "player_id"],
        how="anti",
    )
    if missing_report.height:
        raise SystemExit(f"candidate misses {missing_report.height} injury-report stints")

    bounds = season_bounds(db)
    with_bounds = cand.join(bounds, on="season", how="left")
    invalid = with_bounds.filter(
        pl.col("entry_date").is_not_null()
        & pl.col("exit_date").is_not_null()
        & (pl.col("exit_date") <= pl.col("entry_date"))
    )
    if invalid.height:
        raise SystemExit(f"candidate has {invalid.height} invalid date windows")

    check = with_bounds.with_columns(
        pl.coalesce("entry_date", "begin_date").alias("start"),
        pl.coalesce("exit_date", "end_date").alias("end"),
    ).sort("season", "player_id", "start")
    check = check.with_columns(pl.col("end").shift(1).over("season", "player_id").alias("prev_end"))
    overlaps = check.filter(pl.col("prev_end").is_not_null() & (pl.col("start") < pl.col("prev_end")))
    if overlaps.height:
        raise SystemExit(f"candidate has {overlaps.height} overlapping stints")

    first = check.group_by("season", "player_id").first()
    bad_first = first.filter(
        pl.col("entry_date").is_not_null()
        & (pl.col("entry_date") <= pl.col("begin_date") + pl.duration(days=NEAR_SEASON_EDGE_DAYS))
    )
    if bad_first.height:
        raise SystemExit(f"candidate has {bad_first.height} first rows with a season-start entry date")

    print(
        f"validated: {cand.height:,} stints, {missing.height} missing box stints, "
        f"{missing_report.height} missing report stints, "
        f"{invalid.height} invalid windows, {overlaps.height} overlaps"
    )


def apply_candidate(db: Database, cand: pl.DataFrame, table: str) -> None:
    db.write(cand, table, schema="scratch", if_exists="replace")
    with db.engine.begin() as conn:
        before = conn.execute(text("SELECT count(*) FROM nba.team_roster")).scalar_one()
        expected = conn.execute(text(f"SELECT count(*) FROM scratch.{table}")).scalar_one()
        conn.execute(text("DELETE FROM nba.team_roster"))
        conn.execute(
            text(f"""
                INSERT INTO nba.team_roster ({", ".join(COLUMNS)})
                SELECT {", ".join(COLUMNS)} FROM scratch.{table}
            """)
        )
        after = conn.execute(text("SELECT count(*) FROM nba.team_roster")).scalar_one()
        if after != expected:
            raise SystemExit(f"row count mismatch after publish: {after} != {expected}")
    print(f"replaced nba.team_roster: {before:,} -> {after:,} rows")


def main() -> None:
    args = parse_args()
    db = Database(args.db_con)
    db.execute("CREATE SCHEMA IF NOT EXISTS scratch")
    stamp = datetime.now(UTC).strftime("%Y%m%dT%H%M%SZ").lower()
    cand = build_candidate(db)
    validate(db, cand)
    table = f"team_roster_candidate_{stamp}"
    if args.apply:
        db.execute(
            f"CREATE TABLE IF NOT EXISTS scratch.team_roster_backup_{stamp} AS "
            "SELECT * FROM nba.team_roster"
        )
        apply_candidate(db, cand, table)
    else:
        db.write(cand, table, schema="scratch", if_exists="replace")
        print(f"dry run: wrote scratch.{table}; rerun with --apply to replace nba.team_roster")


if __name__ == "__main__":
    main()
