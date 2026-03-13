#!/usr/bin/env bash
set -euo pipefail

HOSTNAME_FQDN="$(hostname -f 2>/dev/null || hostname)"

# Capture explicit environment overrides so config files don't clobber them.
CAP_STATE_DIR="${STATE_DIR-}"
CAP_STATE_FILE="${STATE_FILE-}"
CAP_RAW_FILE="${RAW_FILE-}"
CAP_LOG_FILE="${LOG_FILE-}"
CAP_ALERT_BODY_FILE="${ALERT_BODY_FILE-}"
CAP_ISSUE_FILE="${ISSUE_FILE-}"
CAP_ISSUE_FINGERPRINT_FILE="${ISSUE_FINGERPRINT_FILE-}"
CAP_MAIL_TO="${MAIL_TO-}"
CAP_MAIL_FROM="${MAIL_FROM-}"
CAP_SUBJECT_PREFIX="${SUBJECT_PREFIX-}"
CAP_NOTIFY_CHANNELS="${NOTIFY_CHANNELS-}"
CAP_TELEGRAM_WEBHOOK_URL="${TELEGRAM_WEBHOOK_URL-}"
CAP_TELEGRAM_BOT_TOKEN="${TELEGRAM_BOT_TOKEN-}"
CAP_TELEGRAM_CHAT_ID="${TELEGRAM_CHAT_ID-}"
CAP_SLACK_WEBHOOK_URL="${SLACK_WEBHOOK_URL-}"
CAP_DISCORD_WEBHOOK_URL="${DISCORD_WEBHOOK_URL-}"
CAP_SMARTCTL_EXTRA_ARGS="${SMARTCTL_EXTRA_ARGS-}"
CAP_SEND_RECOVERY_NOTIFICATIONS="${SEND_RECOVERY_NOTIFICATIONS-}"
CAP_CONFIG_FILE="${CONFIG_FILE-}"
CAP_CONFIG_DIR="${CONFIG_DIR-}"

CONFIG_DIR="${CONFIG_DIR:-.}"
CONFIG_FILE="${CONFIG_FILE:-/etc/raid-health-monitor.conf}"
LOCAL_CONFIG_FILE="${LOCAL_CONFIG_FILE:-$CONFIG_DIR/raid-health-monitor.conf}"

load_config() {
  local cfg="$1"
  [[ -f "$cfg" ]] || return 0
  # shellcheck disable=SC1090
  source "$cfg"
}

load_config "$CONFIG_FILE"
load_config "$LOCAL_CONFIG_FILE"

# Re-apply explicit env overrides.
[[ -n "$CAP_STATE_DIR" ]] && STATE_DIR="$CAP_STATE_DIR"
[[ -n "$CAP_STATE_FILE" ]] && STATE_FILE="$CAP_STATE_FILE"
[[ -n "$CAP_RAW_FILE" ]] && RAW_FILE="$CAP_RAW_FILE"
[[ -n "$CAP_LOG_FILE" ]] && LOG_FILE="$CAP_LOG_FILE"
[[ -n "$CAP_ALERT_BODY_FILE" ]] && ALERT_BODY_FILE="$CAP_ALERT_BODY_FILE"
[[ -n "$CAP_ISSUE_FILE" ]] && ISSUE_FILE="$CAP_ISSUE_FILE"
[[ -n "$CAP_ISSUE_FINGERPRINT_FILE" ]] && ISSUE_FINGERPRINT_FILE="$CAP_ISSUE_FINGERPRINT_FILE"
[[ -n "$CAP_MAIL_TO" ]] && MAIL_TO="$CAP_MAIL_TO"
[[ -n "$CAP_MAIL_FROM" ]] && MAIL_FROM="$CAP_MAIL_FROM"
[[ -n "$CAP_SUBJECT_PREFIX" ]] && SUBJECT_PREFIX="$CAP_SUBJECT_PREFIX"
[[ -n "$CAP_NOTIFY_CHANNELS" ]] && NOTIFY_CHANNELS="$CAP_NOTIFY_CHANNELS"
[[ -n "$CAP_TELEGRAM_WEBHOOK_URL" ]] && TELEGRAM_WEBHOOK_URL="$CAP_TELEGRAM_WEBHOOK_URL"
[[ -n "$CAP_TELEGRAM_BOT_TOKEN" ]] && TELEGRAM_BOT_TOKEN="$CAP_TELEGRAM_BOT_TOKEN"
[[ -n "$CAP_TELEGRAM_CHAT_ID" ]] && TELEGRAM_CHAT_ID="$CAP_TELEGRAM_CHAT_ID"
[[ -n "$CAP_SLACK_WEBHOOK_URL" ]] && SLACK_WEBHOOK_URL="$CAP_SLACK_WEBHOOK_URL"
[[ -n "$CAP_DISCORD_WEBHOOK_URL" ]] && DISCORD_WEBHOOK_URL="$CAP_DISCORD_WEBHOOK_URL"
[[ -n "$CAP_SMARTCTL_EXTRA_ARGS" ]] && SMARTCTL_EXTRA_ARGS="$CAP_SMARTCTL_EXTRA_ARGS"
[[ -n "$CAP_SEND_RECOVERY_NOTIFICATIONS" ]] && SEND_RECOVERY_NOTIFICATIONS="$CAP_SEND_RECOVERY_NOTIFICATIONS"
[[ -n "$CAP_CONFIG_FILE" ]] && CONFIG_FILE="$CAP_CONFIG_FILE"
[[ -n "$CAP_CONFIG_DIR" ]] && CONFIG_DIR="$CAP_CONFIG_DIR"

STATE_DIR="${STATE_DIR:-/var/lib/raid-health-monitor}"
STATE_FILE="${STATE_FILE:-$STATE_DIR/last_state.txt}"
RAW_FILE="${RAW_FILE:-$STATE_DIR/last_raw_snapshot.txt}"
LOG_FILE="${LOG_FILE:-$STATE_DIR/runs.jsonl}"
ALERT_BODY_FILE="${ALERT_BODY_FILE:-$STATE_DIR/last_alert_body.txt}"
ISSUE_FILE="${ISSUE_FILE:-$STATE_DIR/last_issues.txt}"
ISSUE_FINGERPRINT_FILE="${ISSUE_FINGERPRINT_FILE:-$STATE_DIR/last_issue_fingerprint.txt}"
MAIL_TO="${MAIL_TO:-you@example.com}"
MAIL_FROM="${MAIL_FROM:-raid-monitor@$HOSTNAME_FQDN}"
SUBJECT_PREFIX="${SUBJECT_PREFIX:-[RAID ALERT]}"
NOTIFY_CHANNELS="${NOTIFY_CHANNELS:-mail}"
SMARTCTL_EXTRA_ARGS="${SMARTCTL_EXTRA_ARGS:-}"
SEND_RECOVERY_NOTIFICATIONS="${SEND_RECOVERY_NOTIFICATIONS:-false}"
JSON_OUTPUT=false
DRY_RUN=false
SELF_TEST_MODE=""

usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Options:
  --config <path>           Load config file (in addition to defaults)
  --json                    Print machine-readable JSON summary to stdout
  --dry-run                 Do not write baseline/state files or send notifications
  --self-test <warning|critical>
                            Simulate warning/critical issues for pipeline testing
  -h, --help                Show this help
EOF
}

EXTRA_CONFIG_FILE=""
while (($#)); do
  case "$1" in
    --config)
      EXTRA_CONFIG_FILE="${2:-}"
      shift 2
      ;;
    --json)
      JSON_OUTPUT=true
      shift
      ;;
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    --self-test)
      SELF_TEST_MODE="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ -n "$EXTRA_CONFIG_FILE" ]]; then
  load_config "$EXTRA_CONFIG_FILE"
fi

mkdir -p "$STATE_DIR"

TMP_DIR="$(mktemp -d)"
RAW_TMP="$TMP_DIR/raw_snapshot.txt"
STATE_TMP="$TMP_DIR/normalized_state.txt"
ISSUES_TMP="$TMP_DIR/issues.txt"
DIFF_TMP="$TMP_DIR/state.diff"

cleanup() { rm -rf "$TMP_DIR"; }
trap cleanup EXIT

have_cmd() { command -v "$1" >/dev/null 2>&1; }

json_escape() {
  sed 's/\\/\\\\/g; s/"/\\"/g'
}

now_iso() {
  date '+%Y-%m-%dT%H:%M:%S%z' | sed 's/\([0-9][0-9]\)$/:\1/'
}

hash_text_file() {
  local f="$1"
  if have_cmd sha256sum; then
    sha256sum "$f" | awk '{print $1}'
  elif have_cmd shasum; then
    shasum -a 256 "$f" | awk '{print $1}'
  else
    cksum "$f" | awk '{print $1}'
  fi
}

log_run() {
  local status="$1" changed="$2" reason="$3" duration_ms="$4" severity="$5" issue_count="$6" fingerprint="$7"
  local ts
  ts="$(now_iso)"
  printf '{"ts":"%s","host":"%s","status":"%s","severity":"%s","issue_count":%s,"fingerprint":"%s","changed":%s,"duration_ms":%s,"reason":"%s"}\n' \
    "$ts" "$HOSTNAME_FQDN" "$status" "$severity" "$issue_count" "$fingerprint" "$changed" "$duration_ms" "$(printf '%s' "$reason" | json_escape)" \
    >> "$LOG_FILE"
}

send_mail() {
  local subject="$1" body_file="$2"

  if have_cmd mail; then
    mail -s "$subject" -r "$MAIL_FROM" "$MAIL_TO" < "$body_file"
    return
  fi

  if have_cmd sendmail; then
    {
      echo "From: $MAIL_FROM"
      echo "To: $MAIL_TO"
      echo "Subject: $subject"
      echo
      cat "$body_file"
    } | sendmail -t
    return
  fi

  echo "No mail command available (mail/sendmail)." >&2
  return 1
}

post_webhook_json() {
  local url="$1" payload="$2"
  have_cmd curl || return 1
  curl -fsS -X POST -H 'Content-Type: application/json' --data "$payload" "$url" >/dev/null
}

send_telegram() {
  local message="$1"
  if [[ -n "${TELEGRAM_WEBHOOK_URL:-}" ]]; then
    local payload
    payload="{\"text\":\"$(printf '%s' "$message" | json_escape)\"}"
    post_webhook_json "$TELEGRAM_WEBHOOK_URL" "$payload"
    return
  fi

  if [[ -n "${TELEGRAM_BOT_TOKEN:-}" && -n "${TELEGRAM_CHAT_ID:-}" ]] && have_cmd curl; then
    curl -fsS -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
      -d "chat_id=${TELEGRAM_CHAT_ID}" \
      --data-urlencode "text=${message}" >/dev/null
    return
  fi

  return 1
}

send_slack() {
  local message="$1"
  [[ -n "${SLACK_WEBHOOK_URL:-}" ]] || return 1
  post_webhook_json "$SLACK_WEBHOOK_URL" "{\"text\":\"$(printf '%s' "$message" | json_escape)\"}"
}

send_discord() {
  local message="$1"
  [[ -n "${DISCORD_WEBHOOK_URL:-}" ]] || return 1
  post_webhook_json "$DISCORD_WEBHOOK_URL" "{\"content\":\"$(printf '%s' "$message" | json_escape)\"}"
}

send_notifications() {
  local subject="$1" body_file="$2"
  local message
  message="${subject}
$(cat "$body_file")"

  IFS=',' read -r -a channels <<< "$NOTIFY_CHANNELS"
  local ch
  for ch in "${channels[@]}"; do
    ch="$(printf '%s' "$ch" | tr -d '[:space:]')"
    [[ -n "$ch" ]] || continue
    case "$ch" in
      mail) send_mail "$subject" "$body_file" || true ;;
      telegram) send_telegram "$message" || true ;;
      slack) send_slack "$message" || true ;;
      discord) send_discord "$message" || true ;;
      *) echo "Unknown notification channel: $ch" >&2 ;;
    esac
  done
}

discover_smart_targets() {
  declare -A seen=()

  if have_cmd lsblk; then
    while IFS= read -r d; do
      [[ -n "$d" ]] || continue
      if [[ -z "${seen[$d]:-}" ]]; then
        echo "$d|auto"
        seen[$d]=1
      fi
    done < <(lsblk -dnpo NAME,TYPE | awk '$2=="disk"{print $1}')
  fi

  if have_cmd smartctl; then
    while IFS= read -r line; do
      local dev dtype
      dev="$(awk '{print $1}' <<< "$line")"
      dtype="$(sed -n 's/.* -d \([^ ]*\).*/\1/p' <<< "$line")"
      [[ -n "$dev" ]] || continue
      [[ -n "$dtype" ]] || dtype="auto"
      local key="$dev|$dtype"
      if [[ -z "${seen[$key]:-}" ]]; then
        echo "$key"
        seen[$key]=1
      fi
    done < <(smartctl --scan-open 2>/dev/null || true)
  fi
}

smart_health_line() {
  local dev="$1" dtype="$2"
  local out
  if [[ "$dtype" == "auto" ]]; then
    out="$(smartctl -H $SMARTCTL_EXTRA_ARGS "$dev" 2>/dev/null || true)"
  else
    out="$(smartctl -H -d "$dtype" $SMARTCTL_EXTRA_ARGS "$dev" 2>/dev/null || true)"
  fi
  if [[ -z "$out" ]]; then
    echo "smart:${dev}[${dtype}]:status=unavailable"
    return
  fi
  awk -v d="$dev" -v t="$dtype" '/SMART overall-health|SMART Health Status|result|PASSED|FAILED|OK|critical warning/ {print "smart:" d "[" t "]:" $0}' <<< "$out" | head -n 1
}

collect_raw_snapshot() {
  {
    echo "===== RAID HEALTH SNAPSHOT ====="
    echo "Timestamp: $(now_iso)"
    echo "Host: $HOSTNAME_FQDN"
    echo

    echo "===== /proc/mdstat ====="
    if [[ -r /proc/mdstat ]]; then
      cat /proc/mdstat
    else
      echo "N/A"
    fi
    echo

    if have_cmd mdadm; then
      echo "===== mdadm arrays ====="
      mapfile -t md_arrays < <(awk '/^md[0-9]+/ {print $1}' /proc/mdstat 2>/dev/null || true)
      if ((${#md_arrays[@]})); then
        for md in "${md_arrays[@]}"; do
          echo "--- /dev/$md ---"
          mdadm --detail "/dev/$md" || true
          echo
        done
      else
        echo "No md arrays found."
      fi
      echo
    fi

    if have_cmd zpool; then
      echo "===== ZFS pools ====="
      zpool status -v || true
      echo
    fi

    echo "===== lsblk (devices) ====="
    if have_cmd lsblk; then
      lsblk -o NAME,SIZE,TYPE,TRAN,MOUNTPOINT,FSTYPE,MODEL,SERIAL,STATE
    else
      echo "lsblk not available"
    fi
    echo

    echo "===== SMART quick status ====="
    if have_cmd smartctl; then
      mapfile -t targets < <(discover_smart_targets)
      if ((${#targets[@]})); then
        for t in "${targets[@]}"; do
          local dev dtype
          dev="${t%%|*}"
          dtype="${t#*|}"
          echo "--- $dev ($dtype) ---"
          if [[ "$dtype" == "auto" ]]; then
            smartctl -H $SMARTCTL_EXTRA_ARGS "$dev" || true
          else
            smartctl -H -d "$dtype" $SMARTCTL_EXTRA_ARGS "$dev" || true
          fi
          echo
        done
      else
        echo "No SMART targets found."
      fi
    else
      echo "smartctl not installed"
    fi
  } > "$RAW_TMP"
}

build_normalized_state() {
  {
    echo "host=$HOSTNAME_FQDN"

    if [[ -r /proc/mdstat ]]; then
      awk '
        /^md[0-9]+/ {arr=$1; line=$0; getline detail;
          gsub(/^[ \t]+|[ \t]+$/, "", detail);
          print "mdstat:" arr ":" line " | " detail
        }
      ' /proc/mdstat
    fi

    if have_cmd mdadm; then
      mapfile -t md_arrays < <(awk '/^md[0-9]+/ {print $1}' /proc/mdstat 2>/dev/null || true)
      for md in "${md_arrays[@]:-}"; do
        [[ -n "$md" ]] || continue
        mdadm --detail "/dev/$md" 2>/dev/null |
          awk -v a="$md" '
            /State *:/ {print "mdadm:" a ":state=" $0}
            /Active Devices *:/ {print "mdadm:" a ":active=" $0}
            /Working Devices *:/ {print "mdadm:" a ":working=" $0}
            /Failed Devices *:/ {print "mdadm:" a ":failed=" $0}
            /Spare Devices *:/ {print "mdadm:" a ":spare=" $0}
            /Events *:/ {print "mdadm:" a ":events=" $0}
          '
      done
    fi

    if have_cmd zpool; then
      zpool status -v 2>/dev/null |
        awk '
          /^  pool: / {pool=$2; print "zpool:" pool ":pool=" $0}
          /^ state: / {print "zpool:" pool ":state=" $0}
          /DEGRADED|FAULTED|UNAVAIL|OFFLINE|REMOVED|errors:/ {print "zpool:" pool ":signal=" $0}
        '
    fi

    if have_cmd smartctl; then
      mapfile -t targets < <(discover_smart_targets)
      for t in "${targets[@]:-}"; do
        [[ -n "$t" ]] || continue
        local dev dtype line
        dev="${t%%|*}"
        dtype="${t#*|}"
        line="$(smart_health_line "$dev" "$dtype")"
        [[ -n "$line" ]] && echo "$line"
      done
    fi
  } | sed 's/[[:space:]]\+/ /g' | sed 's/ *$//' | sort -u > "$STATE_TMP"
}

build_issues() {
  : > "$ISSUES_TMP"

  awk '
    /mdstat:.*\[[U_]+\]/ && /_/ {print "critical|md|array degraded|" $0}
    /mdadm:.*failed=.*[1-9]/ {print "critical|mdadm|failed devices|" $0}
    /zpool:.*state=.*DEGRADED|zpool:.*state=.*FAULTED|zpool:.*state=.*UNAVAIL/ {print "critical|zfs|pool degraded|" $0}
    /zpool:.*signal=.*errors: [1-9]/ {print "warning|zfs|pool errors|" $0}
    /smart:.*FAILED|smart:.*critical warning[^0]*[1-9]/ {print "critical|smart|smart failed|" $0}
    /smart:.*status=unavailable/ {print "warning|smart|smart unavailable|" $0}
  ' "$STATE_TMP" | sed 's/[[:space:]]\+/ /g' | sort -u >> "$ISSUES_TMP"

  case "$SELF_TEST_MODE" in
    warning)
      echo "warning|self-test|simulated warning issue|self-test-warning" >> "$ISSUES_TMP"
      ;;
    critical)
      echo "critical|self-test|simulated critical issue|self-test-critical" >> "$ISSUES_TMP"
      ;;
    "") ;;
    *)
      echo "Invalid --self-test mode: $SELF_TEST_MODE" >&2
      exit 2
      ;;
  esac

  sort -u -o "$ISSUES_TMP" "$ISSUES_TMP"
}

validate_state() {
  if [[ ! -s "$STATE_TMP" ]]; then
    echo "normalized state is empty"
    return 1
  fi

  if ! grep -Eq '^(mdstat:|mdadm:|zpool:|smart:|host=)' "$STATE_TMP"; then
    echo "normalized state missing expected keys"
    return 1
  fi

  return 0
}

json_summary() {
  local status="$1" severity="$2" changed="$3" reason="$4" issue_count="$5" fingerprint="$6"
  local issues_json="" first=true line escaped
  while IFS= read -r line; do
    escaped="$(printf '%s' "$line" | json_escape)"
    if $first; then
      issues_json="\"$escaped\""
      first=false
    else
      issues_json="$issues_json,\"$escaped\""
    fi
  done < "$ISSUES_TMP"

  printf '{"ts":"%s","host":"%s","status":"%s","severity":"%s","changed":%s,"reason":"%s","issue_count":%s,"fingerprint":"%s","issues":[%s]}\n' \
    "$(now_iso)" "$HOSTNAME_FQDN" "$status" "$severity" "$changed" "$(printf '%s' "$reason" | json_escape)" "$issue_count" "$fingerprint" "$issues_json"
}

main() {
  local start_ns end_ns duration_ms
  start_ns="$(date +%s%N 2>/dev/null || date +%s000000000)"

  collect_raw_snapshot
  build_normalized_state

  if ! validate_state; then
    cp "$RAW_TMP" "$RAW_FILE"
    cp "$STATE_TMP" "$STATE_FILE.invalid" 2>/dev/null || true
    end_ns="$(date +%s%N 2>/dev/null || date +%s000000000)"
    duration_ms=$(( (end_ns - start_ns) / 1000000 ))
    log_run "error" false "validation_failed" "$duration_ms" "critical" 0 ""
    $JSON_OUTPUT && json_summary "error" "critical" false "validation_failed" 0 ""
    exit 1
  fi

  build_issues

  local issue_count severity status
  issue_count="$(wc -l < "$ISSUES_TMP" | tr -d ' ')"
  if [[ "$issue_count" -eq 0 ]]; then
    severity="ok"
    status="ok"
    printf 'ok\n' > "$ISSUES_TMP"
  elif grep -q '^critical|' "$ISSUES_TMP"; then
    severity="critical"
    status="alert"
  else
    severity="warning"
    status="alert"
  fi

  local fingerprint changed reason prev_fingerprint
  fingerprint="$(hash_text_file "$ISSUES_TMP")"
  prev_fingerprint=""
  [[ -f "$ISSUE_FINGERPRINT_FILE" ]] && prev_fingerprint="$(cat "$ISSUE_FINGERPRINT_FILE")"

  changed=false
  reason="no_change"

  if [[ ! -f "$STATE_FILE" ]]; then
    reason="baseline_created"
    changed=false
    if ! $DRY_RUN; then
      cp "$STATE_TMP" "$STATE_FILE"
      cp "$RAW_TMP" "$RAW_FILE"
      cp "$ISSUES_TMP" "$ISSUE_FILE"
      printf '%s\n' "$fingerprint" > "$ISSUE_FINGERPRINT_FILE"
    fi
    end_ns="$(date +%s%N 2>/dev/null || date +%s000000000)"
    duration_ms=$(( (end_ns - start_ns) / 1000000 ))
    log_run "$status" "$changed" "$reason" "$duration_ms" "$severity" "$issue_count" "$fingerprint"
    $JSON_OUTPUT && json_summary "$status" "$severity" "$changed" "$reason" "$issue_count" "$fingerprint"
    echo "Initial normalized RAID state saved to $STATE_FILE"
    exit 0
  fi

  if [[ "$fingerprint" != "$prev_fingerprint" ]]; then
    changed=true
    reason="issue_fingerprint_changed"

    diff -u "$STATE_FILE" "$STATE_TMP" > "$DIFF_TMP" 2>&1 || true
    {
      echo "RAID/disk health issue set changed on $HOSTNAME_FQDN"
      echo "Time: $(now_iso)"
      echo "Severity: $severity"
      echo "Issue fingerprint: $fingerprint"
      echo
      echo "===== ISSUES ====="
      cat "$ISSUES_TMP"
      echo
      echo "===== NORMALIZED DIFF ====="
      cat "$DIFF_TMP"
      echo
      echo "===== NEW NORMALIZED STATE ====="
      cat "$STATE_TMP"
      echo
      echo "===== NEW RAW SNAPSHOT ====="
      cat "$RAW_TMP"
    } > "$ALERT_BODY_FILE"

    if ! $DRY_RUN; then
      if [[ "$status" == "alert" || "$SEND_RECOVERY_NOTIFICATIONS" == "true" ]]; then
        send_notifications "$SUBJECT_PREFIX $HOSTNAME_FQDN $severity" "$ALERT_BODY_FILE"
      fi
      cp "$STATE_TMP" "$STATE_FILE"
      cp "$RAW_TMP" "$RAW_FILE"
      cp "$ISSUES_TMP" "$ISSUE_FILE"
      printf '%s\n' "$fingerprint" > "$ISSUE_FINGERPRINT_FILE"
    fi
  else
    if ! $DRY_RUN; then
      cp "$RAW_TMP" "$RAW_FILE"
    fi
  fi

  end_ns="$(date +%s%N 2>/dev/null || date +%s000000000)"
  duration_ms=$(( (end_ns - start_ns) / 1000000 ))
  log_run "$status" "$changed" "$reason" "$duration_ms" "$severity" "$issue_count" "$fingerprint"
  $JSON_OUTPUT && json_summary "$status" "$severity" "$changed" "$reason" "$issue_count" "$fingerprint"
  exit 0
}

main "$@"
