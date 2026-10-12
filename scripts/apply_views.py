from pathlib import Path

from scs_hub import Database

# Reads SCS_HUB_CREDENTIALS or ~/.config/scs_hub_credentials.ini by default.
db = Database('cockroach-read')

# Every sql/views/<schema>/*.sql file, applied in one pass. CREATE OR REPLACE, so
# re-running is safe. Globbed from __file__ so it works from any cwd; the schema
# order is the paths' sort order (fty, nba, util).
VIEWS_DIR = Path(__file__).resolve().parent.parent / 'sql' / 'views'
for path in sorted(VIEWS_DIR.glob('*/*.sql')):
    db.execute(path.read_text())
    print(path.name)

# Recreating a view drops its grants; re-grant SELECT to the read-only role.
db.regrant_read()
