#!/usr/bin/env bash
set -euo pipefail

# ====== CONFIG ======
STATE_DIR="/var/lib/raid-health-monitor"
RAW_SNAPSHOT_FILE="$STATE_DIR/last_snapshot_raw.txt"
NORM_SNAPSHOT_FILE="$STATE_DIR/last_snapshot_normalized.txt"
ALERT_STATE_FILE="$STATE_DIR/alert_state.env"
LOCK_FILE="$STATE_DIR/monitor.lock"
TMP_DIR="$(mktemp -d)"
HOSTNAME_FQDN="$(hostname -f 2>/dev/null || hostname)"

MAIL_TO="you@example.com"
MAIL_FROM="raid-monitor@$HOSTNAME_FQDN"
SUBJECT_PREFIX="[RAID ALERT]"

# Alert dedupe / cooldown controls
WARN_COOLDOWN_SEC=3600
CRIT_COOLDOWN_SEC=900
UNCHANGED_REMINDER_SEC=21600

# Thresholds
MAX_TEMP_WARN=50
MAX_TEMP_CRIT=55
SMART_REALLOC_WARN=10
SMART_PENDING_WARN=1
SMART_UNCORR_WARN=1
SMART_CRC_WARN=20
# ====================

mkdir -p "$STATE_DIR"

have_cmd() { command -v "$1" >/dev/null 2>&1; }

cleanup() { rm -rf "$TMP_DIR"; }
trap cleanup EXIT

exec 9>"$LOCK_FILE"
if ! flock -n 9; then
  echo "Another raid-health-monitor instance is running. Exiting."
  exit 0
fi

RAW_FILE="$TMP_DIR/snapshot_raw.txt"
NORM_FILE="$TMP_DIR/snapshot_normalized.txt"
SUMMARY_FILE="$TMP_DIR/summary.txt"

has_issue=0
critical_count=0
warning_count=0
issue_lines=()
runbook_lines=()

record_issue() {
  local severity="$1"
  local msg="$2"
  issue_lines+=("[$severity] $msg")
  has_issue=1
  if [[ "$severity" == "CRITICAL" ]]; then
    ((critical_count+=1))
  elif [[ "$severity" == "WARNING" ]]; then
    ((warning_count+=1))
  fi
}

add_runbook() {
  local step="$1"
  runbook_lines+=("- $step")
}

score_penalty() {
  local p="$1"
  local current="${health_score:-100}"
  current=$((current - p))
  if (( current < 0 )); then current=0; fi
  health_score="$current"
}

collect_md_arrays() {
  mapfile -t md_arrays < <(awk '/^md[0-9]+/ {print $1}' /proc/mdstat 2>/dev/null || true)
}

check_mdadm_health() {
  if ! have_cmd mdadm; then return; fi
  collect_md_arrays
  if ((${#md_arrays[@]} == 0)); then return; fi

  for md in "${md_arrays[@]}"; do
    local detail
    detail="$(mdadm --detail "/dev/$md" 2>/dev/null || true)"

    local state_line active_disks failed_disks degraded
    state_line="$(awk -F': ' '/State :/ {print $2; exit}' <<<"$detail")"
    active_disks="$(awk -F': ' '/Active Devices :/ {print $2; exit}' <<<"$detail")"
    failed_disks="$(awk -F': ' '/Failed Devices :/ {print $2; exit}' <<<"$detail")"
    degraded="$(awk -F': ' '/Degraded Devices :/ {print $2; exit}' <<<"$detail")"

    failed_disks="${failed_disks:-0}"
    degraded="${degraded:-0}"

    if [[ "$state_line" =~ degraded|recovering|resync|reshape ]]; then
      if [[ "$state_line" =~ degraded ]]; then
        record_issue "CRITICAL" "/dev/$md is DEGRADED (state: $state_line, active: ${active_disks:-?}, failed: $failed_disks, degraded: $degraded)"
        score_penalty 35
        add_runbook "Check mdadm detail for /dev/$md: mdadm --detail /dev/$md"
        add_runbook "Identify failed member(s), replace disk, then add replacement and monitor rebuild"
      else
        record_issue "WARNING" "/dev/$md is in transition state: $state_line"
        score_penalty 10
        add_runbook "Track rebuild progress in /proc/mdstat and avoid heavy IO until complete"
      fi
    fi

    if [[ "$failed_disks" =~ ^[0-9]+$ ]] && (( failed_disks > 0 )); then
      record_issue "CRITICAL" "/dev/$md reports failed devices: $failed_disks"
      score_penalty 30
    fi
    if [[ "$degraded" =~ ^[0-9]+$ ]] && (( degraded > 0 )); then
      record_issue "CRITICAL" "/dev/$md reports degraded devices: $degraded"
      score_penalty 25
    fi
  done
}

check_zfs_health() {
  if ! have_cmd zpool; then return; fi
  local zstatus full
  zstatus="$(zpool status -x 2>/dev/null || true)"
  if grep -qi "all pools are healthy" <<<"$zstatus"; then return; fi

  full="$(zpool status -v 2>/dev/null || true)"
  if grep -qiE "DEGRADED|FAULTED|OFFLINE|UNAVAIL|REMOVED" <<<"$full"; then
    record_issue "CRITICAL" "ZFS reports degraded/faulted pool state"
    score_penalty 35
    add_runbook "Run: zpool status -v and replace/offline failing device(s)"
  else
    record_issue "WARNING" "ZFS pool is not fully healthy"
    score_penalty 10
  fi
}

parse_smart_attr() {
  local attr="$1" text="$2"
  awk -v a="$attr" '$1==a {print $10; found=1} END{ if(!found) print "" }' <<<"$text"
}

check_smart_health() {
  if ! have_cmd smartctl; then return; fi

  mapfile -t disks < <(lsblk -dn -o NAME,TYPE | awk '$2=="disk"{print "/dev/"$1}')
  if ((${#disks[@]} == 0)); then return; fi

  local max_temp=0
  for d in "${disks[@]}"; do
    local health attrs realloc pending uncorr crc temp
    health="$(smartctl -H "$d" 2>/dev/null || true)"
    if ! grep -qiE "PASSED|OK" <<<"$health"; then
      record_issue "CRITICAL" "$d SMART overall status is not PASSED"
      score_penalty 30
      add_runbook "Inspect full SMART report: smartctl -a $d"
    fi

    attrs="$(smartctl -A "$d" 2>/dev/null || true)"
    realloc="$(parse_smart_attr 5 "$attrs")"
    pending="$(parse_smart_attr 197 "$attrs")"
    uncorr="$(parse_smart_attr 198 "$attrs")"
    crc="$(parse_smart_attr 199 "$attrs")"
    temp="$(awk '$1==194 || $1==190 {print $10; found=1} END{if(!found) print ""}' <<<"$attrs")"

    realloc="${realloc:-0}"; pending="${pending:-0}"; uncorr="${uncorr:-0}"; crc="${crc:-0}"; temp="${temp:-0}"

    if [[ "$realloc" =~ ^[0-9]+$ ]] && (( realloc >= SMART_REALLOC_WARN )); then
      record_issue "WARNING" "$d has high Reallocated_Sector_Ct=$realloc"
      score_penalty 8
    fi
    if [[ "$pending" =~ ^[0-9]+$ ]] && (( pending >= SMART_PENDING_WARN )); then
      record_issue "CRITICAL" "$d has Current_Pending_Sector=$pending"
      score_penalty 25
      add_runbook "Backup immediately and schedule drive replacement for $d"
    fi
    if [[ "$uncorr" =~ ^[0-9]+$ ]] && (( uncorr >= SMART_UNCORR_WARN )); then
      record_issue "CRITICAL" "$d has Offline_Uncorrectable=$uncorr"
      score_penalty 25
    fi
    if [[ "$crc" =~ ^[0-9]+$ ]] && (( crc >= SMART_CRC_WARN )); then
      record_issue "WARNING" "$d has UDMA_CRC_Error_Count=$crc (check cable/backplane)"
      score_penalty 5
      add_runbook "Check SATA/SAS cable or backplane path for $d"
    fi

    if [[ "$temp" =~ ^[0-9]+$ ]]; then
      if (( temp > max_temp )); then max_temp="$temp"; fi
      if (( temp >= MAX_TEMP_CRIT )); then
        record_issue "CRITICAL" "$d temperature is ${temp}C"
        score_penalty 15
      elif (( temp >= MAX_TEMP_WARN )); then
        record_issue "WARNING" "$d temperature is ${temp}C"
        score_penalty 7
      fi
    fi
  done

  hottest_temp="$max_temp"
}

determine_status() {
  if (( critical_count > 0 )); then
    health_status="critical"
  elif (( warning_count > 0 )); then
    health_status="warning"
  else
    health_status="healthy"
  fi
}

collect_raw_snapshot() {
  {
    echo "===== RAID HEALTH SNAPSHOT ====="
    echo "Timestamp: $(date -Is)"
    echo "Host: $HOSTNAME_FQDN"
    echo

    echo "===== /proc/mdstat ====="
    [[ -r /proc/mdstat ]] && cat /proc/mdstat || echo "N/A"
    echo

    if have_cmd mdadm; then
      echo "===== mdadm arrays ====="
      collect_md_arrays
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

    echo "===== lsblk ====="
    if have_cmd lsblk; then
      lsblk -o NAME,SIZE,TYPE,MOUNTPOINT,FSTYPE,MODEL,SERIAL,STATE
    else
      echo "lsblk not available"
    fi
    echo

    echo "===== SMART quick status ====="
    if have_cmd smartctl; then
      mapfile -t disks < <(lsblk -dn -o NAME,TYPE | awk '$2=="disk"{print "/dev/"$1}')
      if ((${#disks[@]})); then
        for d in "${disks[@]}"; do
          echo "--- $d ---"
          smartctl -H "$d" 2>/dev/null | awk '/SMART overall-health|SMART Health Status|result/ {print}'
          smartctl -A "$d" 2>/dev/null | awk '$1==5||$1==190||$1==194||$1==197||$1==198||$1==199 {print}'
        done
      else
        echo "No disks found."
      fi
    else
      echo "smartctl not installed"
    fi
  } > "$RAW_FILE"
}

normalize_snapshot() {
  sed -E -e '/^Timestamp:/d' -e '/^Host:/d' -e 's/\[[0-9]+\.[0-9]+\]/[TIME]/g' "$RAW_FILE" > "$NORM_FILE"
}

build_summary() {
  {
    echo "RAID Health Summary"
    echo "Host: $HOSTNAME_FQDN"
    echo "Time: $(date -Is)"
    echo "Status: $health_status"
    echo "Score: ${health_score:-100}/100"
    echo "Warnings: $warning_count"
    echo "Critical: $critical_count"
    echo "Hottest disk temp: ${hottest_temp:-0}C"
    echo

    if ((${#issue_lines[@]})); then
      echo "Issues:"
      printf '%s\n' "${issue_lines[@]}"
      echo
    else
      echo "Issues: none"
      echo
    fi

    if ((${#runbook_lines[@]})); then
      echo "Suggested next steps:"
      printf '%s\n' "${runbook_lines[@]}" | awk '!seen[$0]++'
      echo
    fi
  } > "$SUMMARY_FILE"
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

load_alert_state() {
  last_alert_status="healthy"
  last_alert_hash=""
  last_alert_ts=0
  if [[ -f "$ALERT_STATE_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$ALERT_STATE_FILE"
  fi
  last_alert_status="${last_alert_status:-healthy}"
  last_alert_hash="${last_alert_hash:-}"
  last_alert_ts="${last_alert_ts:-0}"
}

save_alert_state() {
  cat > "$ALERT_STATE_FILE" <<EOF
last_alert_status="$last_alert_status"
last_alert_hash="$last_alert_hash"
last_alert_ts="$last_alert_ts"
EOF
}

should_alert() {
  local now="$1" current_hash="$2"

  if [[ "$health_status" == "healthy" ]]; then
    [[ "$last_alert_status" != "healthy" ]] && return 0
    return 1
  fi

  local cooldown="$WARN_COOLDOWN_SEC"
  [[ "$health_status" == "critical" ]] && cooldown="$CRIT_COOLDOWN_SEC"

  [[ "$last_alert_status" != "$health_status" ]] && return 0
  [[ "$last_alert_hash" != "$current_hash" ]] && return 0
  (( now - last_alert_ts >= UNCHANGED_REMINDER_SEC )) && return 0
  (( now - last_alert_ts >= cooldown )) && return 0

  return 1
}

main() {
  health_score=100
  hottest_temp=0

  collect_raw_snapshot
  normalize_snapshot
  check_mdadm_health
  check_zfs_health
  check_smart_health
  determine_status
  build_summary

  local now current_hash changed
  now="$(date +%s)"
  current_hash="$(sha256sum "$NORM_FILE" | awk '{print $1}')"

  if [[ ! -f "$NORM_SNAPSHOT_FILE" ]]; then
    cp "$RAW_FILE" "$RAW_SNAPSHOT_FILE"
    cp "$NORM_FILE" "$NORM_SNAPSHOT_FILE"
    load_alert_state
    last_alert_status="$health_status"
    last_alert_hash="$current_hash"
    last_alert_ts="$now"
    save_alert_state
    echo "Initial baseline saved to $NORM_SNAPSHOT_FILE"
    exit 0
  fi

  changed=0
  if ! diff -u "$NORM_SNAPSHOT_FILE" "$NORM_FILE" > "$TMP_DIR/diff.txt" 2>&1; then
    changed=1
  fi

  load_alert_state
  if should_alert "$now" "$current_hash"; then
    local subject="$SUBJECT_PREFIX $HOSTNAME_FQDN $health_status (score ${health_score}/100)"
    {
      cat "$SUMMARY_FILE"
      echo
      if (( changed == 1 )); then
        echo "===== NORMALIZED DIFF (last -> current) ====="
        cat "$TMP_DIR/diff.txt"
        echo
      fi
      echo "===== CURRENT SNAPSHOT ====="
      cat "$RAW_FILE"
    } > "$TMP_DIR/mail_body.txt"

    send_mail "$subject" "$TMP_DIR/mail_body.txt" || true

    last_alert_status="$health_status"
    last_alert_hash="$current_hash"
    last_alert_ts="$now"
    save_alert_state
  fi

  cp "$RAW_FILE" "$RAW_SNAPSHOT_FILE"
  cp "$NORM_FILE" "$NORM_SNAPSHOT_FILE"
}

main "$@"
