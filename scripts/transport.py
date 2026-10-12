import logging

from scs_hub import Database
from scs_hub.context import Context

# Per-table row counts (and the dry run's "not written" notes) go through scs_hub's logger.
logging.basicConfig(level=logging.INFO, format='%(asctime)s %(levelname)s %(name)s: %(message)s')

# Reads SCS_HUB_CREDENTIALS or ~/.config/scs_hub_credentials.ini by default.
# These name sections of that file, so which direction to mirror is never assumed.

# SOURCE, TARGET = 'postgres', 'cockroach-write'
# source = Database(SOURCE)
# target = Database(TARGET)

# ============================ transport =====================================
# One season, table by table. This only moves data; views are applied separately
# with apply_views.py, which also re-grants them, so run that afterwards.

season = Context(SOURCE).cur_season
# season = '2024-25'                                   # backfill another season

# target.transport_from(source, season, dry_run=True)  # log counts, write nothing
moved = target.transport_from(source, season)
print(f'{season}: {len(moved)} table(s), {sum(moved.values())} row(s)')
