# RAID Health Monitor

Bash monitor for RAID / disk health with **issue-level dedupe**.

It collects storage state, normalizes it, derives a stable issue set, hashes that set, and only alerts when the issue fingerprint changes (instead of noisy snapshot diffs).

## Highlights

- External config support:
  - `/etc/raid-health-monitor.conf`
  - optional local override `./raid-health-monitor.conf`
  - optional `--config /path/to/file`
- Better SMART target discovery:
  - native block disks from `lsblk`
  - controller-backed targets via `smartctl --scan-open` (e.g. `-d megaraid,N`)
- Alert dedupe via stable issue fingerprint hash
- Multi-channel notifications (config-driven):
  - mail (existing)
  - Telegram webhook/bot API
  - Slack webhook
  - Discord webhook
- `--json` mode for machine-readable output
- `--self-test warning|critical` and `--dry-run` for testing pipelines
- Systemd unit/timer examples included

## What it checks

- `/proc/mdstat`
- `mdadm --detail` (if available)
- `zpool status -v` (if available)
- `smartctl -H` quick checks across discovered targets

## Install

```bash
sudo cp raid-health-monitor.sh /usr/local/bin/raid-health-monitor.sh
sudo chmod +x /usr/local/bin/raid-health-monitor.sh
```

## Basic usage

```bash
sudo MAIL_TO="you@example.com" /usr/local/bin/raid-health-monitor.sh
```

First run creates baseline/state files and does not alert.

## CLI options

```text
--config <path>            Load extra config file
--json                     Print JSON summary to stdout
--dry-run                  No state writes, no notifications
--self-test warning        Simulate warning condition
--self-test critical       Simulate critical condition
```

## Configuration

Create `/etc/raid-health-monitor.conf`:

```bash
# Notification channels (comma-separated): mail,telegram,slack,discord
NOTIFY_CHANNELS="mail,telegram"

MAIL_TO="ops@example.com"
MAIL_FROM="raid-monitor@example.com"
SUBJECT_PREFIX="[RAID ALERT]"

# Telegram option A: generic webhook URL
# TELEGRAM_WEBHOOK_URL="https://example.com/telegram-webhook"

# Telegram option B: native bot API
# TELEGRAM_BOT_TOKEN="123456:ABCDEF"
# TELEGRAM_CHAT_ID="-1001234567890"

# Slack/Discord webhooks
# SLACK_WEBHOOK_URL="https://hooks.slack.com/services/..."
# DISCORD_WEBHOOK_URL="https://discord.com/api/webhooks/..."

# State paths
STATE_DIR="/var/lib/raid-health-monitor"

# Optional smartctl extras
# SMARTCTL_EXTRA_ARGS="-n standby"

# Send notifications also on recovery fingerprint changes
SEND_RECOVERY_NOTIFICATIONS="false"
```

Optional local override in current working directory:

```bash
./raid-health-monitor.conf
```

## JSON output example

```bash
./raid-health-monitor.sh --json
```

Example output:

```json
{"ts":"2026-03-14T00:00:00+02:00","host":"node1","status":"ok","severity":"ok","changed":false,"reason":"no_change","issue_count":0,"fingerprint":"...","issues":["ok"]}
```

## Self-test examples

```bash
# simulate warning issue set
./raid-health-monitor.sh --self-test warning --json --dry-run

# simulate critical issue set
./raid-health-monitor.sh --self-test critical --json --dry-run
```

## State/observability files

Under `STATE_DIR`:

- `last_state.txt` → normalized baseline state
- `last_raw_snapshot.txt` → latest raw diagnostic snapshot
- `last_issues.txt` → latest normalized issue set
- `last_issue_fingerprint.txt` → latest issue fingerprint hash
- `last_alert_body.txt` → latest composed alert body
- `runs.jsonl` → structured run log

## Systemd (recommended)

Example files:

- `systemd/raid-health-monitor.service`
- `systemd/raid-health-monitor.timer`
- `examples/raid-health-monitor.conf.example`

Install quickly:

```bash
sudo cp systemd/raid-health-monitor.service /etc/systemd/system/
sudo cp systemd/raid-health-monitor.timer /etc/systemd/system/
sudo cp examples/raid-health-monitor.conf.example /etc/raid-health-monitor.conf
sudo systemctl daemon-reload
sudo systemctl enable --now raid-health-monitor.timer
```

## Tests

```bash
tests/smoke.sh
tests/logic.sh
```

## Security notes

- Runs local commands only.
- External traffic only for configured notification channels.
- Keep `STATE_DIR` restricted (`root:root`, `700/750`).
