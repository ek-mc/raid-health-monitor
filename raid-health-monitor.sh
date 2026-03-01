#!/usr/bin/env bash
set -euo pipefail

# ====== CONFIG ======
STATE_DIR="${STATE_DIR:-/var/lib/raid-health-monitor}"
STATE_FILE="${STATE_FILE:-$STATE_DIR/last_state.txt}"
RAW_FILE="${RAW_FILE:-$STATE_DIR/last_raw_snapshot.txt}"
LOG_FILE="${LOG_FILE:-$STATE_DIR/runs.jsonl}"
ALERT_BODY_FILE="${ALERT_BODY_FILE:-$STATE_DIR/last_alert_body.txt}"
HOSTNAME_FQDN="$(hostname -f 2>/dev/null || hostname)"
MAIL_TO="${MAIL_TO:-you@example.com}"
MAIL_FROM="${MAIL_FROM:-raid-monitor@$HOSTNAME_FQDN}"
SUBJECT_PREFIX="${SUBJECT_PREFIX:-[RAID ALERT]}"
# ====================

mkdir -p "$STATE_DIR"

TMP_DIR="$(mktemp -d)"
RAW_TMP="$TMP_DIR/raw_snapshot.txt"
STATE_TMP="$TMP_DIR/normalized_state.txt"
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

log_run() {
  local status="$1" changed="$2" reason="$3" duration_ms="$4"
  local ts
  ts="$(now_iso)"
  printf '{"ts":"%s","host":"%s","status":"%s","changed":%s,"duration_ms":%s,"reason":"%s"}\n' \
    "$ts" "$HOSTNAME_FQDN" "$status" "$changed" "$duration_ms" "$(printf '%s' "$reason" | json_escape)" \
    >> "$LOG_FILE"
}

send_mail() {
  local subject="$1"
  local body_file="$2"

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
        done
      else
        echo "No disks found."
      fi
    else
      echo "smartctl not installed"
    fi
  } > "$RAW_TMP"
}

build_normalized_state() {
  {
    echo "host=$HOSTNAME_FQDN"

    # mdstat degraded/recovery indicators only
    if [[ -r /proc/mdstat ]]; then
      awk '
        /^md[0-9]+/ {arr=$1; line=$0; getline detail;
          gsub(/^[ \t]+|[ \t]+$/, "", detail);
          print "mdstat:" arr ":" line " | " detail
        }
      ' /proc/mdstat
    fi

    # mdadm normalized health lines
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

    # zpool important status only
    if have_cmd zpool; then
      zpool status -v 2>/dev/null |
        awk '
          /^  pool: / {pool=$2; print "zpool:" pool ":pool=" $0}
          /^ state: / {print "zpool:" pool ":state=" $0}
          /DEGRADED|FAULTED|UNAVAIL|OFFLINE|REMOVED|errors:/ {print "zpool:" pool ":signal=" $0}
        '
    fi

    # SMART health only
    if have_cmd smartctl && have_cmd lsblk; then
      mapfile -t disks < <(lsblk -dn -o NAME,TYPE | awk '$2=="disk"{print "/dev/"$1}')
      for d in "${disks[@]:-}"; do
        [[ -n "$d" ]] || continue
        smartctl -H "$d" 2>/dev/null |
          awk -v d="$d" '/SMART overall-health|SMART Health Status|result/ {print "smart:" d ":" $0}'
      done
    fi
  } | sed 's/[[:space:]]\+/ /g' | sed 's/ *$//' | sort -u > "$STATE_TMP"
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
    log_run "error" false "validation_failed" "$duration_ms"
    exit 1
  fi

  if [[ ! -f "$STATE_FILE" ]]; then
    cp "$STATE_TMP" "$STATE_FILE"
    cp "$RAW_TMP" "$RAW_FILE"
    end_ns="$(date +%s%N 2>/dev/null || date +%s000000000)"
    duration_ms=$(( (end_ns - start_ns) / 1000000 ))
    log_run "ok" false "baseline_created" "$duration_ms"
    echo "Initial normalized RAID state saved to $STATE_FILE"
    exit 0
  fi

  if ! diff -u "$STATE_FILE" "$STATE_TMP" > "$DIFF_TMP" 2>&1; then
    {
      echo "RAID/disk health state changed on $HOSTNAME_FQDN"
      echo "Time: $(now_iso)"
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

    send_mail "$SUBJECT_PREFIX $HOSTNAME_FQDN state changed" "$ALERT_BODY_FILE" || true

    cp "$STATE_TMP" "$STATE_FILE"
    cp "$RAW_TMP" "$RAW_FILE"

    end_ns="$(date +%s%N 2>/dev/null || date +%s000000000)"
    duration_ms=$(( (end_ns - start_ns) / 1000000 ))
    log_run "ok" true "state_changed" "$duration_ms"
    exit 0
  fi

  cp "$RAW_TMP" "$RAW_FILE"
  end_ns="$(date +%s%N 2>/dev/null || date +%s000000000)"
  duration_ms=$(( (end_ns - start_ns) / 1000000 ))
  log_run "ok" false "no_change" "$duration_ms"
  exit 0
}

main "$@"
