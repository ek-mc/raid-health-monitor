# RAID Health Monitor

Simple Bash monitor for RAID / disk health state changes.

It snapshots storage health, builds a **normalized health state**, compares with last known good state, and sends email only when the normalized state changes.

## What it checks

- `/proc/mdstat` (array status/recovery signals)
- `mdadm --detail` health fields (if mdadm exists)
- `zpool status -v` critical state signals (if ZFS exists)
- `smartctl -H` quick SMART status (if smartctl exists)

## Key improvements (v2)

- ✅ Normalized diff (avoids false alerts from timestamp-only changes)
- ✅ Validation layer before compare/send
- ✅ JSONL observability log per run (`runs.jsonl`)
- ✅ Raw snapshot + normalized state persisted for debugging

## Script

- `raid-health-monitor.sh`

## Configure

You can override via environment variables (recommended):

- `MAIL_TO` (required for useful alerts)
- `MAIL_FROM`
- `SUBJECT_PREFIX`
- `STATE_DIR` (default: `/var/lib/raid-health-monitor`)

Example:

```bash
MAIL_TO="you@example.com" /usr/local/bin/raid-health-monitor.sh
```

## Install

```bash
sudo cp raid-health-monitor.sh /usr/local/bin/raid-health-monitor.sh
sudo chmod +x /usr/local/bin/raid-health-monitor.sh
```

## First run

```bash
sudo MAIL_TO="you@example.com" /usr/local/bin/raid-health-monitor.sh
```

First run creates baseline:

- `last_state.txt` (normalized state baseline)
- `last_raw_snapshot.txt` (raw diagnostic snapshot)

No email is sent on first run.

## Cron (every 10 min)

```bash
sudo crontab -e
```

```cron
*/10 * * * * MAIL_TO="you@example.com" /usr/local/bin/raid-health-monitor.sh
```

## Validation + observability files

Under `STATE_DIR`:

- `last_state.txt` → normalized baseline used for diff
- `last_raw_snapshot.txt` → last raw snapshot
- `last_alert_body.txt` → most recent email body
- `runs.jsonl` → one JSON line per run (status, duration, reason)

## Mail requirements

Need one of:

- `mail` command (`mailx`), or
- `sendmail`

## Quick test

1. Run once (baseline)
2. Simulate state change (lab/test machine)
3. Run again
4. Confirm alert email + `runs.jsonl` changed=`true`

## Security notes

- Script runs local commands only.
- Does not send data externally except alert email via local mail/sendmail.
- Keep `STATE_DIR` permissions restricted (`root:root`, mode `700/750`).
