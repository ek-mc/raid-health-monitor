# Changelog

## [Unreleased]

## [0.3.0] - 2026-03-14

### Added
- Layered external config loading:
  - `/etc/raid-health-monitor.conf`
  - local `./raid-health-monitor.conf`
  - optional `--config <path>`
- Multi-channel notifications via `NOTIFY_CHANNELS`:
  - `mail`, `telegram`, `slack`, `discord`
- Telegram delivery via either webhook URL or Bot API token/chat ID.
- JSON output mode (`--json`) for machine-readable summary payloads.
- Self-test and dry-run modes (`--self-test warning|critical`, `--dry-run`).
- Issue-set persistence (`last_issues.txt`) and fingerprint state (`last_issue_fingerprint.txt`).
- Systemd deployment examples:
  - `systemd/raid-health-monitor.service`
  - `systemd/raid-health-monitor.timer`
- Config template: `examples/raid-health-monitor.conf.example`.
- Expanded shell test suite (`tests/logic.sh`).

### Changed
- SMART target discovery now combines `lsblk` disks with `smartctl --scan-open` targets (improves NVMe/controller-backed coverage).
- Alert dedupe now uses stable issue fingerprint hashing to reduce alert churn from non-semantic snapshot differences.
- README expanded with new CLI flags, notification channels, and systemd usage.

### Fixed
- Reduced repeated notifications when underlying issue set has not changed.
- Improved reliability of health-state transitions by comparing normalized issue sets.

## [0.2.0] - 2026-03-01

### Added
- Normalized health-state comparison (`last_state.txt`) instead of full raw diff.
- Validation step before compare/send.
- JSONL run observability log (`runs.jsonl`).
- Persisted raw snapshot (`last_raw_snapshot.txt`).
- Persisted latest alert body (`last_alert_body.txt`).
- `CONTRIBUTING.md` and basic smoke tests.

### Changed
- Email alert now includes normalized diff + raw snapshot.
- Config now supports env overrides for all key paths and mail fields.

### Fixed
- Eliminated false-positive alerts caused by timestamp-only snapshot changes.

## [0.1.0] - 2026-03-05

### Added
- Initial public release.
- RAID state snapshots + diff-based email alerting.
- mdadm, zpool, lsblk, and SMART quick-status collection.

## [0.0.1] - 2026-03-04

### Added
- Documented GitHub Actions workflows in README.
- GitHub Actions CI workflow (`bash -n` + smoke test).
- `SECURITY.md` policy.
- Baseline `.gitignore` for secrets/local artifacts.

## [0.0.0] - 2026-03-04

### Added
- Added MIT `LICENSE` file.
