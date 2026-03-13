# Changelog

## [Unreleased]

### Added
- External config loading (`/etc/raid-health-monitor.conf` + optional `./raid-health-monitor.conf` + `--config`)
- Multi-channel notifications (mail, Telegram, Slack, Discord) via `NOTIFY_CHANNELS`
- JSON output mode (`--json`) for machine-readable summaries
- Self-test and dry-run modes (`--self-test warning|critical`, `--dry-run`)
- Issue-set persistence (`last_issues.txt`) and fingerprint state (`last_issue_fingerprint.txt`)
- Systemd examples:
  - `systemd/raid-health-monitor.service`
  - `systemd/raid-health-monitor.timer`
  - `examples/raid-health-monitor.conf.example`
- Expanded shell tests (`tests/logic.sh`)

### Changed
- SMART discovery now combines `lsblk` disks and `smartctl --scan-open` targets for better controller-backed coverage
- Alert dedupe now keys on stable normalized issue fingerprint hash instead of raw state diff churn
- Run logs now include severity, issue_count, and fingerprint

### Fixed
- Reduced noisy repeat alerts for unchanged issue conditions

## [0.2.0] - 2026-03-01

### Added
- Normalized health-state comparison (`last_state.txt`) instead of full raw diff
- Validation step before compare/send
- JSONL run observability log (`runs.jsonl`)
- Persisted raw snapshot (`last_raw_snapshot.txt`)
- Persisted latest alert body (`last_alert_body.txt`)
- `CONTRIBUTING.md` and basic smoke tests

### Changed
- Email alert now includes normalized diff + raw snapshot
- Config now supports env overrides for all key paths and mail fields

### Fixed
- Eliminated false-positive alerts caused by timestamp-only snapshot changes
