# Changelog

## [Unreleased]

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
