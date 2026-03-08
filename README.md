# RAID Health Monitor

Status: Active | Last release: v0.2.0 | Last update: 2026-03-09 | Live: https://github.com/ek-mc/raid-health-monitor

Bash RAID monitor with **health scoring**, **severity-based alerts**, and **alert dedupe/cooldown**.

It checks mdadm/ZFS/SMART, creates a normalized snapshot, and sends email only when meaningful health state changes (or periodic reminders while unhealthy).

## What it checks

- `/proc/mdstat`
- `mdadm --detail` (if mdadm exists)
- `zpool status -v` (if ZFS exists)
- `lsblk` device overview
- `smartctl -H` and key SMART attributes (5, 190/194, 197, 198, 199)

## New in v0.2.0

- Health score (0–100)
- Severity classification: `healthy | warning | critical`
- Issue list + runbook hints in alert emails
- Timestamp-insensitive snapshot comparison (less noise)
- Alert dedupe with cooldown windows
- Periodic reminder while unhealthy
- Lock file to prevent overlapping runs

## Script

- `raid-health-monitor.sh`

## Configure

Edit variables at top of script:

- `MAIL_TO="you@example.com"` (required)
- `MAIL_FROM`, `SUBJECT_PREFIX`
- Thresholds:
  - `MAX_TEMP_WARN`, `MAX_TEMP_CRIT`
  - `SMART_REALLOC_WARN`, `SMART_PENDING_WARN`, `SMART_UNCORR_WARN`, `SMART_CRC_WARN`
- Alert behavior:
  - `WARN_COOLDOWN_SEC`, `CRIT_COOLDOWN_SEC`, `UNCHANGED_REMINDER_SEC`

## Install

```bash
sudo cp raid-health-monitor.sh /usr/local/bin/raid-health-monitor.sh
sudo chmod +x /usr/local/bin/raid-health-monitor.sh
```

## First run

```bash
sudo /usr/local/bin/raid-health-monitor.sh
```

Creates baseline in:

- `/var/lib/raid-health-monitor/last_snapshot_raw.txt`
- `/var/lib/raid-health-monitor/last_snapshot_normalized.txt`
- `/var/lib/raid-health-monitor/alert_state.env`

No noisy alert spam on baseline creation.

## Cron (every 10 min)

```bash
sudo crontab -e
```

Add:

```cron
*/10 * * * * /usr/local/bin/raid-health-monitor.sh
```

## Mail requirements

Need at least one of:

- `mail` command (`mailx`), or
- `sendmail`

## Notes

- Alerts are sent on meaningful changes, not timestamp-only differences.
- Recovery (`warning/critical -> healthy`) triggers a recovery email.
- While unhealthy, reminders are rate-limited by cooldown/reminder settings.

## Quick test

1. Run once to create baseline
2. Temporarily force a known issue (lab environment only)
3. Run again and confirm alert email includes:
   - severity + score
   - issue list
   - suggested next steps
