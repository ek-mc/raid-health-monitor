#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STATE_DIR="$(mktemp -d)"
trap 'rm -rf "$STATE_DIR"' EXIT

export STATE_DIR
export MAIL_TO="test@example.com"

# Baseline
"$ROOT_DIR/raid-health-monitor.sh" >/dev/null

# Self-test warning should produce alert JSON in dry-run
out_warn="$($ROOT_DIR/raid-health-monitor.sh --self-test warning --dry-run --json)"
echo "$out_warn" | grep -q '"status":"alert"'
echo "$out_warn" | grep -q '"severity":"warning"'
echo "$out_warn" | grep -q '"changed":true'

# Self-test critical should be critical
out_crit="$($ROOT_DIR/raid-health-monitor.sh --self-test critical --dry-run --json)"
echo "$out_crit" | grep -q '"severity":"critical"'

# Dry-run should not mutate fingerprint file
fp_before="$(cat "$STATE_DIR/last_issue_fingerprint.txt")"
$ROOT_DIR/raid-health-monitor.sh --self-test critical --dry-run >/dev/null
fp_after="$(cat "$STATE_DIR/last_issue_fingerprint.txt")"
[[ "$fp_before" == "$fp_after" ]]

echo "logic: ok"
