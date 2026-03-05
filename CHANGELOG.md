# Changelog

## [Unreleased]

## [0.0.0] - 2026-03-04

### Added
- Added MIT `LICENSE` file.


## [0.0.1] - 2026-03-04

### Added
- Documented GitHub Actions workflows in README.
- GitHub Actions CI workflow (`bash -n` + smoke test)
- `SECURITY.md` policy
- Baseline `.gitignore` for secrets/local artifacts

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