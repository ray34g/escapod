#!/usr/bin/env bash
set -euo pipefail

if [[ -n "${NOTIFY_SOCKET:-}" ]]; then
    systemd-notify --ready || true
fi

TIMESTAMP="${TIMESTAMP:-$(date '+%Y%m%d%H%M%S')}"
SCHEDULE_DATETIME=$(date '+%Y-%m-%d %H:%M:%S')
CONFIG_DIR="${CONFIG_DIR:-/etc/escapod}"
LOG_DIR="${LOG_DIR:-/var/log/escapod}"
LOG_FILE="$LOG_DIR/info_${TIMESTAMP}.log"
PREV="$LOG_DIR/info_prev.log"
BACKUP_DIR="${BACKUP_DIR:-/var/log/escapod/backups}"
REBOOT_FLAG="$LOG_DIR/reboot-requested.log"
AWS_CLI="${AWS_CLI_PATH:-/usr/bin/aws}"

# --- Phase: scheduled / pre-reboot / post-reboot
PHASE="${1:-pre-reboot}"

# --- Environment Variables ---
if [[ -f "$CONFIG_DIR/escapod.env" ]]; then
  set -a
  source "$CONFIG_DIR/escapod.env"
  set +a
fi

# --- Parse shutdown schedule if phase is scheduled ---
parse_scheduled_info() {
  SCHEDULE_INFO_FILE="/run/systemd/shutdown/scheduled"
  SCHEDULE_DATETIME=$(date '+%Y-%m-%d %H:%M:%S')
  WALLMESSAGE="(none)"

  if [[ -f "$SCHEDULE_INFO_FILE" ]]; then
    WALLMESSAGE=$(grep "^WALL_MESSAGE=" "$SCHEDULE_INFO_FILE" | cut -d'=' -f2- | tr -d '"')
    # decode \xe3 → UTF-8
    WALLMESSAGE=$(printf '%b' "$WALLMESSAGE")
    WALLMESSAGE=${WALLMESSAGE:-"(none)"}
  fi
}

case "$PHASE" in
  scheduled)
    parse_scheduled_info
    SUBJECT_MESSAGE="[$(hostname)] Reboot has been scheduled at $SCHEDULE_DATETIME"
    ;;
  pre-reboot)
    SUBJECT_MESSAGE="[$(hostname)] Reboot is starting now"
    mkdir -p /var/lib/escapod
    touch "$REBOOT_FLAG"
    ;;
  post-reboot)
    SUBJECT_MESSAGE="[$(hostname)] Reboot has completed successfully"
    if [[ ! -f "$REBOOT_FLAG" ]]; then
      echo "No reboot flag found. Skipping post-reboot actions."
      exit 0
    fi
    ;;
  *)
    SUBJECT_MESSAGE="[$(hostname)] Escapod report ($PHASE)"
    ;;
esac

# --- Log ---
create_log() {
  mkdir -p "$LOG_DIR"

  # --- Rotation ---
  [[ -f "$LOG_FILE" ]] && mv -f "$LOG_FILE" "$PREV" || true

  log() {
    printf "\n[%s]\n" "$1" >>"$LOG_FILE"
    shift
    "$@" >>"$LOG_FILE" 2>&1 || true
  }

  AWS_CLI="${AWS_CLI_PATH:-/usr/bin/aws}"

  # --- Header ---
  {
    echo "===== ESCAPOD PHASE: ${PHASE^^} | TIMESTAMP: $TIMESTAMP ====="
    echo "Host   : $(hostname)"
    echo "Kernel : $(uname -r)"
    echo "Scheduled time : $SCHEDULE_DATETIME"
  } >"$LOG_FILE"

  log uptime          uptime
  log timedatectl     timedatectl
  log who             who
  log disk            df -hT
  log memory          free -h
  log "top-5 cpu"     bash -c "ps -eo pid,comm,%cpu --sort=-%cpu | head -n6"
  log "top-5 mem"     bash -c "ps -eo pid,comm,%mem --sort=-%mem | head -n6"
  log "ip addr"       ip -brief addr
  log listening       ss -tunlp
  log lscpu           lscpu
  log lsblk           lsblk -o NAME,SIZE,TYPE,MOUNTPOINT
  log dmesg-tail      dmesg -T | tail -n100
  #--- Kubernetes / CRI-O / docker-compose ---
  command -v kubectl &>/dev/null  && log "k8s pods"  kubectl get pods -A --no-headers
  command -v crictl  &>/dev/null  && log "cri-o ctr" crictl ps
  command -v docker-compose &>/dev/null && log "compose ps" docker-compose ps --all
}

# --- Backup ---
create_backup() {
  [[ "${BACKUP_ENABLED:-true}" != "true" ]] && return
  [[ -z "${BACKUP_PATHS:-}" ]] && return

  IFS=' ' read -ra paths <<< "$BACKUP_PATHS"
  for path in "${paths[@]}"; do
    [[ -e "$path" ]] || { echo "skip $path" >>"$LOG_FILE"; continue; }
    name="$(basename "$path").tgz"
    tmpfile="$(mktemp "/var/tmp/${name}.XXXX")"
    tar -czf "$tmpfile" --absolute-names --preserve-permissions "$path"
    chmod 644 "$tmpfile"
    # --- S3 Upload ---
    if [[ "${UPLOAD_TO_S3:-false}" == "true" ]]; then
      "$AWS_CLI" s3 cp "$(realpath "$tmpfile")" \
      "s3://${S3_BUCKET}/${S3_PREFIX}/$(hostname)_${TIMESTAMP}/${name}" \
      --region "$AWS_REGION" || true
    fi

    if [[ "${KEEP_LOCAL_BACKUP:-true}" == "true" ]]; then
      mkdir -p "$BACKUP_DIR"
      mv "$tmpfile" "$BACKUP_DIR/${TIMESTAMP}_${name}"
    else
      rm -f "$tmpfile"
    fi
  done
}

# --- SES Email (aws-cli) ---
send_mail() {
  [[ "${MAIL_ENABLED:-true}" != "true" ]] && return
  
  local subject=$SUBJECT_MESSAGE
  local bodyfile="/var/tmp/mail_body_${TIMESTAMP}.txt"
  local emailfile="/var/tmp/mail_raw_${TIMESTAMP}.txt"
  local encodedfile="/var/tmp/mail_raw_${TIMESTAMP}.b64"
  local jsonfile="/var/tmp/mail_raw_${TIMESTAMP}.json"
  local attachfile="$LOG_FILE"
  local boundary="===BOUNDARY_${TIMESTAMP}==="

  # BODY
  cat >"$bodyfile" <<EOF
[$(hostname)] | Phase: ${PHASE^^}
📝 WALLMESSAGE: ${WALLMESSAGE}

📍 Host: $(hostname)
🖥️ Kernel: $(uname -r)
📦 Snapshot ID: ${TIMESTAMP}

The following diagnostic and configuration information has been collected:
 - System status (uptime, load, users)
 - Network status and interfaces
 - Resource usage (CPU, memory, disk)
 - Running processes and services
 - System settings (sysctl, mount info)
 - Kubernetes / CRI-O / Docker Compose (if applicable)
 - Backup: ${BACKUP_ENABLED:-true} | S3 Upload: ${UPLOAD_TO_S3:-false}
 - Mail notification: ${MAIL_ENABLED:-true}

$( [[ "${UPLOAD_TO_S3:-}" == "true" ]] && echo "S3: s3://${S3_BUCKET}/${S3_PREFIX}/$(hostname)_${TIMESTAMP}/" )
$( [[ "${KEEP_LOCAL_BACKUP:-}" == "true" ]] && echo "Local backup: ${BACKUP_DIR}" )

(This message was automatically generated by Escapod.)
EOF

  chmod 644 "$bodyfile"

  # MIME
  {
    printf 'From:"%s" <%s>\n' "$FROM_NAME" "$FROM_ADDR"
    printf 'To:%s\n' "$TO_ADDRS"
    printf 'Subject:%s\n' "$subject"
    printf 'MIME-Version: 1.0\n'
    printf 'Content-Type: multipart/mixed; boundary="%s"\n' "$boundary"
    printf '\n--%s\n' "$boundary"
    printf 'Content-Type: text/plain; charset=UTF-8\n\n'
    cat "$bodyfile"
    printf '\n--%s\n' "$boundary"
    printf 'Content-Type: text/plain; name="%s"\n' "$(basename "$attachfile")"
    printf 'Content-Disposition: attachment; filename="%s"\n' "$(basename "$attachfile")"
    printf 'Content-Transfer-Encoding: base64\n\n'
    base64 "$attachfile"
    printf '\n--%s--\n' "$boundary"
  } > "$emailfile"

  base64 -w 0 "$emailfile" > "$encodedfile"
  cat > "$jsonfile" <<EOF
{
  "RawMessage": {
    "Data": "$(cat "$encodedfile")"
  }
}
EOF

  "$AWS_CLI" ses send-raw-email \
  --cli-input-json "file://$(realpath "$jsonfile")" \
  --region "$AWS_REGION" || true

  rm -f "$bodyfile" "$emailfile" "$encodedfile" "$jsonfile"
}

# --- Notify ---
notify_terminal_sessions() {
  local msg="
[$(hostname)] will reboot soon.
Phase: ${PHASE^^}
Backup and logs collected.
"
  if [[ -n "${NOTIFY_SOCKET:-}" ]]; then
    systemd-notify --reboot-message="$msg" || true
  fi
}

  # --- Run ---
case "$PHASE" in
  scheduled)
    create_log & lp=$!
    create_backup & bp=$!
    send_mail & mp=$!
    wait $lp $bp $mp
    notify_terminal_sessions
    ;;
  pre-reboot)
    create_log & lp=$!
    create_backup & bp=$!
    send_mail & mp=$!
    wait $lp $bp $mp
    notify_terminal_sessions
    ;;
  post-reboot)
    send_mail
    logger "Escapod: Reboot has completed successfully."
    rm -f "$REBOOT_FLAG"
    ;;
esac