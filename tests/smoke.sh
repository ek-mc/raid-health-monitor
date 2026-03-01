#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STATE_DIR="$(mktemp -d)"
trap 'rm -rf "$STATE_DIR"' EXIT

export STATE_DIR
export MAIL_TO="test@example.com"

bash -n "$ROOT_DIR/raid-health-monitor.sh"

# Baseline run
"$ROOT_DIR/raid-health-monitor.sh" >/dev/null

[[ -f "$STATE_DIR/last_state.txt" ]]
[[ -f "$STATE_DIR/last_raw_snapshot.txt" ]]
[[ -f "$STATE_DIR/runs.jsonl" ]]

# Follow-up run should also pass and append log
before_lines=$(wc -l < "$STATE_DIR/runs.jsonl")
"$ROOT_DIR/raid-health-monitor.sh" >/dev/null
after_lines=$(wc -l < "$STATE_DIR/runs.jsonl")

if [[ "$after_lines" -le "$before_lines" ]]; then
  echo "runs.jsonl did not grow"
  exit 1
fi

echo "smoke: ok"
