# Backups

Nightly Jetson dump, NUC copy, encrypted MEGA upload, and a monthly restore
drill. Design and retention targets are in
[`docs/JETSON_MIGRATION.md`](../../docs/JETSON_MIGRATION.md#backups).

## Packages and directories

NUC:

```bash
sudo apt-get install -y age
sudo install -d -m 700 -o oli -g oli /srv/nba-backups /srv/nba-backups/daily /srv/nba-backups/weekly

# Ubuntu's rclone package omits the MEGA backend; use the official binary.
mkdir -p ~/.local/bin
curl -L https://downloads.rclone.org/rclone-current-linux-amd64.zip -o /tmp/rclone.zip
unzip -o /tmp/rclone.zip -d /tmp/rclone
install -m 755 /tmp/rclone/rclone-*-linux-amd64/rclone ~/.local/bin/rclone
rm -f /tmp/rclone.zip
```

Jetson (no host PostgreSQL client or age/rclone needed):

```bash
sudo install -d -m 700 -o oli -g oli /srv/backups
```

Both checkouts must be on the branch carrying these scripts:

```bash
cd ~/shaggy_camel_sports/nba/database
git fetch origin jetson-postgres-migration
git checkout jetson-postgres-migration
git pull --ff-only
```

## Keys and remote

Generate the age key on the NUC. Copy the private key into the password
manager; losing it loses every encrypted backup.

```bash
mkdir -p ~/.config
age-keygen -o ~/.config/scs_backup_age.key
chmod 600 ~/.config/scs_backup_age.key
age-keygen -y ~/.config/scs_backup_age.key > ~/.config/scs_backup_age.pub
```

Configure the MEGA remote once:

```bash
rclone config
# remote name: mega, storage: mega
```

The scripts expect `mega:nba-backups/daily/` and
`mega:nba-backups/monthly/`.

## Manual test

On the Jetson:

```bash
~/shaggy_camel_sports/nba/database/deploy/backups/jetson_dump.sh
```

On the NUC:

```bash
DRY_RUN=1 ~/shaggy_camel_sports/nba/database/deploy/backups/nuc_backup.sh
~/shaggy_camel_sports/nba/database/deploy/backups/check_backups.py --no-email
```

Then run one real upload and verify it appears:

```bash
rclone lsf mega:nba-backups/daily/
```

## Cron

UTC on both hosts. The times are 03:15, 03:45 and 04:15 NZDT.

Jetson:

```cron
15 14 * * * /home/oli/shaggy_camel_sports/nba/database/deploy/backups/jetson_dump.sh >> /home/oli/shaggy_camel_sports/nba/database/backup.log 2>&1
```

NUC:

```cron
45 14 * * * /home/oli/shaggy_camel_sports/nba/database/deploy/backups/nuc_backup.sh >> /home/oli/shaggy_camel_sports/nba/database/backup.log 2>&1
15 15 * * * /home/oli/shaggy_camel_sports/nba/database/deploy/backups/check_backups.py >> /home/oli/shaggy_camel_sports/nba/database/backup.log 2>&1
30 15 1 * * /home/oli/shaggy_camel_sports/nba/database/deploy/backups/restore_drill.sh >> /home/oli/shaggy_camel_sports/nba/database/backup.log 2>&1
```

Retention: Jetson 7 daily; NUC 14 daily + 8 weekly; MEGA 30 daily + 12 monthly.
