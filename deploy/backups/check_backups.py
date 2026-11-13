#!/usr/bin/env python3
"""Alert when the newest Jetson or MEGA backup is stale.

Runs on the NUC after nuc_backup.sh. Reads [smtp] from the shared credentials
file and exits non-zero when either copy is older than MAX_AGE_HOURS.
"""

import argparse
import configparser
import json
import os
import shutil
import smtplib
import subprocess
import sys
from datetime import datetime, timezone
from email.message import EmailMessage
from pathlib import Path

MAX_AGE_HOURS = int(os.environ.get('MAX_AGE_HOURS', '36'))
LOCAL_DIR = Path(os.environ.get('LOCAL_DIR', '/srv/nba-backups/daily'))
RCLONE_REMOTE = os.environ.get('RCLONE_REMOTE', 'mega:nba-backups')
RCLONE = Path.home() / '.local' / 'bin' / 'rclone'
INI_PATH = Path(
    os.environ.get('SCS_HUB_CREDENTIALS', Path.home() / '.config' / 'scs_hub_credentials.ini')
)

parser = configparser.ConfigParser()
parser.read(INI_PATH)


def setting(env_name: str, section: str, key: str) -> str | None:
    """Environment wins, then the credentials file, like __main__.py."""
    return os.environ.get(env_name) or parser.get(section, key, fallback=None)


def format_time(value: datetime | None) -> str:
    if value is None:
        return 'missing'
    return value.astimezone(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')


def age_hours(value: datetime | None) -> float:
    if value is None:
        return float('inf')
    return (datetime.now(timezone.utc) - value).total_seconds() / 3600


def newest_local() -> datetime | None:
    if not LOCAL_DIR.is_dir():
        return None
    files = list(LOCAL_DIR.glob('nba-*.dump'))
    if not files:
        return None
    newest = max(files, key=lambda path: path.stat().st_mtime)
    return datetime.fromtimestamp(newest.stat().st_mtime, tz=timezone.utc)


def newest_remote() -> datetime | None:
    rclone = str(RCLONE) if RCLONE.is_file() else shutil.which('rclone')
    if rclone is None:
        raise RuntimeError('rclone is not installed')
    result = subprocess.run(
        [rclone, 'lsjson', f'{RCLONE_REMOTE}/daily', '--files-only'],
        capture_output=True,
        text=True,
        check=False,
    )
    if result.returncode != 0:
        detail = result.stderr.strip() or 'rclone lsjson failed'
        raise RuntimeError(detail)
    objects = json.loads(result.stdout or '[]')
    times = [
        datetime.fromisoformat(obj['ModTime'].replace('Z', '+00:00'))
        for obj in objects
        if obj.get('ModTime')
    ]
    return max(times) if times else None


def send_alert(issues: list[str]) -> None:
    user = setting('SMTP_USER', 'smtp', 'user')
    password = setting('SMTP_PASSWORD', 'smtp', 'password')
    if not user or not password:
        print('no SMTP user/password configured; alert not sent', file=sys.stderr)
        return
    recipient = setting('ALERT_TO', 'smtp', 'to') or user
    message = EmailMessage()
    message['Subject'] = 'NBA backup check failed'
    message['From'] = user
    message['To'] = recipient
    message.set_content('\n'.join(issues))
    with smtplib.SMTP('smtp.gmail.com', 587) as server:
        server.starttls()
        server.login(user, password)
        server.send_message(message)


def main() -> int:
    argument_parser = argparse.ArgumentParser(description=__doc__)
    argument_parser.add_argument(
        '--no-email', action='store_true', help='print the result but do not send mail'
    )
    args = argument_parser.parse_args()

    issues = []
    try:
        local = newest_local()
    except OSError as exc:
        local = None
        issues.append(f'local backup directory error: {exc}')
    try:
        remote = newest_remote()
    except (RuntimeError, json.JSONDecodeError) as exc:
        remote = None
        issues.append(f'MEGA check failed: {exc}')

    local_age = age_hours(local)
    remote_age = age_hours(remote)
    print(f'newest local dump: {format_time(local)} ({local_age:.1f}h old)')
    print(f'newest MEGA dump:  {format_time(remote)} ({remote_age:.1f}h old)')

    if local_age > MAX_AGE_HOURS:
        issues.append(f'newest local dump is {local_age:.1f}h old')
    if remote_age > MAX_AGE_HOURS:
        issues.append(f'newest MEGA dump is {remote_age:.1f}h old')

    if not issues:
        return 0

    for issue in issues:
        print(f'FAIL: {issue}', file=sys.stderr)
    if not args.no_email:
        try:
            send_alert(issues)
        except Exception as exc:  # noqa: BLE001 - alert path must report, not mask
            print(f'could not send alert: {exc}', file=sys.stderr)
    return 1


if __name__ == '__main__':
    sys.exit(main())
