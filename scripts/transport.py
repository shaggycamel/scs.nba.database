#!/usr/bin/env python3
"""Move one season's rows between two databases, table by table.

A by-hand runner for scs_hub's Database.transport_from -- the postgres -> Cockroach mirror
without the notebook it used to be. It only moves data. Views are applied separately with
apply_views.py (which also re-grants them), so run that afterwards.

    python scripts/transport.py --source postgres --target cockroach --dry-run
    python scripts/transport.py --source postgres --target cockroach
    python scripts/transport.py --source postgres --target cockroach --season 2024-25

--source and --target are required and name sections of the credentials file, so which
direction to mirror is never assumed. --season defaults to the source context's current
season. --dry-run logs the row count each table would move and writes nothing.
"""

import argparse
import logging

from scs_hub import Database
from scs_hub.context import Context


def main() -> int:
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument('--source', required=True, help='credentials.ini section to read from')
    parser.add_argument('--target', required=True, help='credentials.ini section to write to')
    parser.add_argument(
        '--season',
        default=None,
        help='season to move (default: the current season of the source context)',
    )
    parser.add_argument(
        '--ini',
        default=None,
        help='credentials.ini path (default: SCS_HUB_CREDENTIALS or ~/.config/scs_hub_credentials.ini)',
    )
    parser.add_argument('--dry-run', action='store_true', help='log counts without writing')
    args = parser.parse_args()

    logging.basicConfig(
        level=logging.INFO,
        format='%(asctime)s %(levelname)-7s %(name)s  %(message)s',
        datefmt='%H:%M:%S',
    )

    source = Database(args.source, args.ini)
    target = Database(args.target, args.ini)
    season = args.season or Context(source).cur_season

    logging.getLogger('scs_hub').info(
        'transport: %s -> %s for %s%s',
        args.source,
        args.target,
        season,
        ' (dry run)' if args.dry_run else '',
    )
    moved = target.transport_from(source, season, dry_run=args.dry_run)
    print(
        f'{season}: {len(moved)} table(s), {sum(moved.values())} row(s)'
        + (' (dry run, not written)' if args.dry_run else '')
    )
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
