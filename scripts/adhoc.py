from scs_hub import SportsHub

# con_from = SportsHub("postgres")
# con_to = SportsHub("cockroach-write")

seasons = [
    f"{year}-{str(year + 1)[2:]}"
    for year in range(2020, 2027)
]

for season in seasons:
    query = f"""
        SELECT pbp.*
        FROM nba.play_by_play AS pbp
        INNER JOIN (
            SELECT DISTINCT game_id
            FROM nba.play_by_play_vw
            WHERE season = '{season}'
        ) AS season_games
            ON season_games.game_id = pbp.game_id
    """
    df = con_from.db.read(query)

    if df.is_empty():
        print(f"{season}: no rows")
        continue

    con_to.db.write(df, "play_by_play", "nba")
    print(f"{season}: appended {df.height:,} rows")