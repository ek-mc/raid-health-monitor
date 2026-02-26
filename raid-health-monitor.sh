#!/usr/bin/env bash
set -euo pipefail

# ====== CONFIG ======
STATE_DIR="/var/lib/raid-health-monitor"
STATE_FILE="$STATE_DIR/last_state.txt"
TMP_FILE="$(mktemp)"
HOSTNAME_FQDN="$(hostname -f 2>/dev/null || hostname)"
MAIL_TO="you@example.com"
MAIL_FROM="raid-monitor@$HOSTNAME_FQDN"
SUBJECT_PREFIX="[RAID ALERT]"
# ====================

mkdir -p "$STATE_DIR"

have_cmd() { command -v "$1" >/dev/null 2>&1; }

collect_state() {
  {
    echo "===== RAID HEALTH SNAPSHOT ====="
    echo "Timestamp: $(date -Is)"
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
  } > "$TMP_FILE"
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

main() {
  collect_state

  if [[ ! -f "$STATE_FILE" ]]; then
    cp "$TMP_FILE" "$STATE_FILE"
    echo "Initial RAID state saved to $STATE_FILE"
    rm -f "$TMP_FILE"
    exit 0
  fi

  if ! diff -u "$STATE_FILE" "$TMP_FILE" >/tmp/raid_state_diff.$$ 2>&1; then
    {
      echo "RAID/disk health state changed on $HOSTNAME_FQDN"
      echo "Time: $(date -Is)"
      echo
      echo "===== DIFF ====="
      cat /tmp/raid_state_diff.$$
      echo
      echo "===== NEW SNAPSHOT ====="
      cat "$TMP_FILE"
    } > /tmp/raid_alert_body.$$

    send_mail "$SUBJECT_PREFIX $HOSTNAME_FQDN state changed" /tmp/raid_alert_body.$$ || true

    cp "$TMP_FILE" "$STATE_FILE"
    rm -f /tmp/raid_state_diff.$$ /tmp/raid_alert_body.$$ "$TMP_FILE"
    exit 0
  else
    rm -f /tmp/raid_state_diff.$$ "$TMP_FILE"
    exit 0
  fi
}

main "$@"
