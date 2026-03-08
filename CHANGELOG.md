# Changelog

## [Unreleased]

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