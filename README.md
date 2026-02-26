# RAID Health Monitor

Simple Bash monitor for RAID / disk health state changes.

It snapshots current storage health, compares with last snapshot, and sends email **only when state changes**.

## What it checks

- `/proc/mdstat`
- `mdadm --detail` (if mdadm exists)
- `zpool status -v` (if ZFS exists)
- `lsblk` device overview
- `smartctl -H` quick SMART health (if smartctl exists)

## Script

- `raid-health-monitor.sh`

## Configure

Edit these variables at the top of the script:

- `MAIL_TO="you@example.com"`  ← change this
- optionally `MAIL_FROM`, `SUBJECT_PREFIX`, `STATE_DIR`

## Install (recommended)

```bash
sudo cp raid-health-monitor.sh /usr/local/bin/raid-health-monitor.sh
sudo chmod +x /usr/local/bin/raid-health-monitor.sh
```

## First run

```bash
sudo /usr/local/bin/raid-health-monitor.sh
```

First run creates baseline state at:

- `/var/lib/raid-health-monitor/last_state.txt`

No email is sent on first run.

## Cron (every 10 min)

```bash
sudo crontab -e
```

Add:

```cron
*/10 * * * * /usr/local/bin/raid-health-monitor.sh
```

## Mail requirements

You need at least one of:

- `mail` command (`mailx`), or
- `sendmail`

## Notes

- The RAID monitor alerts on **any snapshot difference**, so timestamp/content changes can trigger email.
- If you want a quieter version (ignore timestamp-only changes), adapt the snapshot comparison section.

## Quick test for alert

1. Run once (baseline)
2. Temporarily edit script output content (or unplug a non-critical disk on test machine)
3. Run again and confirm alert email arrives
