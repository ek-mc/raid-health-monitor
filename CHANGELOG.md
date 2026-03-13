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
- Systemd deployment examples:
  - `systemd/raid-health-monitor.service`
  - `systemd/raid-health-monitor.timer`
- Config template: `examples/raid-health-monitor.conf.example`.
- Logic test suite (`tests/logic.sh`) for JSON/self-test/dry-run/fingerprint behavior.

### Changed
- SMART target discovery now combines `lsblk` disks with `smartctl --scan-open` targets (improves NVMe/controller-backed coverage).
- Alert dedupe now uses stable issue fingerprint hashing to reduce alert churn from non-semantic snapshot differences.
- README expanded with new CLI flags, notification channels, and systemd usage.

### Fixed
- Reduced repeated notifications when underlying issue set has not changed.
- Improved reliability of health-state transitions by comparing normalized issue sets.

## [0.2.0] - 2026-03-09

### Added
- Health scoring model (0–100)
- Severity classification (`healthy`, `warning`, `critical`)
- Runbook-style remediation hints in alert emails
- SMART attribute checks for key risk signals (5, 190/194, 197, 198, 199)
- Alert dedupe state (`alert_state.env`) and lock-file guard (`monitor.lock`)

### Changed
- Snapshot comparison now uses normalized state to reduce noisy alerts
- Alert flow now supports cooldown windows + periodic unhealthy reminders
- README updated with v0.2.0 configuration and behavior

### Fixed
- Avoided duplicate alerts from timestamp-only changes
- Reduced repeated noise during unchanged unhealthy states

## [0.1.0] - 2026-03-05

### Added
- Initial public release
- RAID state snapshots + diff-based email alerting
- mdadm, zpool, lsblk, and SMART quick-status collection

## [0.0.1] - 2026-03-04

### Added
- Documented GitHub Actions workflows in README
- GitHub Actions CI workflow (`bash -n` + smoke test)
- `SECURITY.md` policy
- Baseline `.gitignore` for secrets/local artifacts

## [0.0.0] - 2026-03-04

### Added
- Added MIT `LICENSE` file