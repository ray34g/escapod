#!/usr/bin/env bash
set -euo pipefail

STAMP="${STAMP:-$(date '+%Y%m%d%H%M%S')}"
CONFIG_DIR="${CONFIG_DIR:-/etc/pre-reboot-hook}"
LOGDIR="${LOGDIR:-/var/log/pre-reboot-hook}"
LOGFILE="$LOGDIR/info_${STAMP}.log"
PREV="$LOGDIR/info_prev.log"
BACKUP_DIR="${BACKUP_DIR:-/var/log/pre-reboot-hook/backups}"

# --- Environment Variables ---
if [[ -f "$CONFIG_DIR/pre-reboot-hook.env" ]]; then
  set -a
  source "$CONFIG_DIR/pre-reboot-hook.env"
  set +a
fi

mkdir -p "$LOGDIR"

#----- Rotation -----
[[ -f "$LOGFILE" ]] && mv -f "$LOGFILE" "$PREV" || true

log() { printf "\n[%s]\n" "$1" >>"$LOGFILE"; shift; "$@" >>"$LOGFILE" 2>&1 || true; }

{
  echo "===== PRE‑REBOOT SNAPSHOT  $STAMP ====="
  echo "Host   : $(hostname)"
  echo "Kernel : $(uname -r)"
} >"$LOGFILE"

log uptime          uptime
log timedatectl     timedatectl
log who             who
log disk            df -hT
log memory          free -h
log "top‑5 cpu"     bash -c "ps -eo pid,comm,%cpu --sort=-%cpu | head -n6"
log "top‑5 mem"     bash -c "ps -eo pid,comm,%mem --sort=-%mem | head -n6"
log "ip addr"       ip -brief addr
log listening       ss -tunlp

log lscpu           lscpu
log lsblk           lsblk -o NAME,SIZE,TYPE,MOUNTPOINT
log dmesg-tail      dmesg -T | tail -n100
#--- Kubernetes / CRI-O / docker-compose ---
command -v kubectl &>/dev/null  && log "k8s pods"  kubectl get pods -A --no-headers
command -v crictl  &>/dev/null  && log "cri-o ctr" crictl ps
command -v docker-compose &>/dev/null && log "compose ps" docker-compose ps --all

#----- Backup -----
do_backup() {
  [[ -z "${BACKUP_PATHS:-}" ]] && return
  IFS=' ' read -ra paths <<< "$BACKUP_PATHS"
  for path in "${paths[@]}"; do
    [[ -e "$path" ]] || { echo "skip $path" >>"$LOGFILE"; continue; }
    name="$(basename "$path").tgz"
    tmpfile="$(mktemp "/var/tmp/${name}.XXXX")"
    tar -czf "$tmpfile" --absolute-names --preserve-permissions "$path"
    chmod 644 "$tmpfile"
    # --- S3 Upload ---
    if [[ "${UPLOAD_TO_S3}" == "true" ]]; then
      aws s3 cp "$(realpath "$tmpfile")" \
    "s3://${S3_BUCKET}/${S3_PREFIX}/$(hostname)_${STAMP}/${name}" \
    --region "$AWS_REGION" || true
      # podman run --rm --network host \
      #   --security-opt label=disable \
      #   -e AWS_DEFAULT_REGION="$AWS_REGION" \
      #   -v /root/.aws:/root/.aws:ro \
      #   -v "$(dirname "$tmpfile"):/var/tmp:ro" \
      #   amazon/aws-cli \
      #     s3 cp "/var/tmp/$(basename "$tmpfile")" \
      #     "s3://${S3_BUCKET}/${S3_PREFIX}/$(hostname)_${STAMP}/${name}"
    fi

    if [[ "${KEEP_LOCAL_BACKUP}" == "true" ]]; then
      mkdir -p "$BACKUP_DIR"
      mv "$tmpfile" "$BACKUP_DIR/${STAMP}_${name}"
    else
      rm -f "$tmpfile"
    fi

  done
}

#----- SES Email (Podman + aws-cli) -----
send_mail() {
  local subject="[system] $(hostname) is Scheduled to Reboot at $(date -d '+1 min' '+%Y-%m-%d %H:%M:%S')"
  local bodyfile="/var/tmp/mail_body_${STAMP}.txt"
  local emailfile="/var/tmp/email_raw_${STAMP}.txt"
  local encodedfile="/var/tmp/email_raw_${STAMP}.b64"
  local jsonfile="/var/tmp/email_raw_${STAMP}.json"
  local attachfile="$LOGFILE"

  local boundary="===BOUNDARY_${STAMP}==="

  # BODY 
  cat >"$bodyfile" <<EOF
[$(hostname)] is scheduled to reboot shortly.

⏰ Time: $(date -d '+1 min' '+%Y-%m-%d %H:%M:%S')
📍 Host: $(hostname)
🖥️ Kernel: $(uname -r)
📦 Snapshot ID: ${STAMP}

The following diagnostic and configuration information has been collected:
 - System status (uptime, load, users)
 - Network status and interfaces
 - Resource usage (CPU, memory, disk)
 - Running processes and services
 - System settings (sysctl, mount info)
 - Kubernetes / CRI-O / Docker Compose (if applicable)

$( [[ "${UPLOAD_TO_S3:-}" == "true" ]] && echo "Backup uploaded to: s3://${S3_BUCKET}/${S3_PREFIX}/$(hostname)_${STAMP}/" )
$( [[ "${KEEP_LOCAL_BACKUP:-}" == "true" ]] && echo "Local backup saved to: ${BACKUP_DIR}" )

(This message was automatically generated.)
EOF

  chmod 644 "$bodyfile"

  # MIME 
  {
    printf 'From:"%s" <%s>\n' "$FROM_NAME" "$FROM_ADDR"
    printf 'To:%s\n' "$TO_ADDRS"
    printf 'Subject:%s\n' "$subject"
    printf 'MIME-Version: 1.0\n'
    printf 'Content-Type: multipart/mixed; boundary="%s"\n' "$boundary"
    printf '\n'
    printf '%s\n' "--${boundary}"
    printf 'Content-Type: text/plain; charset=UTF-8\n'
    printf 'Content-Transfer-Encoding: 7bit\n\n'
    cat "$bodyfile"
    printf '\n%s\n' "--${boundary}"
    printf 'Content-Type: text/plain; name="%s"\n' "$(basename "$attachfile")"
    printf 'Content-Description: Reboot Log\n'
    printf 'Content-Disposition: attachment; filename="%s"\n' "$(basename "$attachfile")"
    printf 'Content-Transfer-Encoding: base64\n\n'
    base64 "$attachfile"
    printf '\n%s\n' "--${boundary}--"
  } > "$emailfile"

  base64 -w 0 "$emailfile" > "$encodedfile"
  cat > "$jsonfile" <<EOF
{
  "RawMessage": {
    "Data": "$(cat "$encodedfile")"
  }
}
EOF

  # Send
  aws ses send-raw-email \
  --cli-input-json "file://$(realpath "$jsonfile")" \
  --region "$AWS_REGION" || true
  # podman run --rm --network host \
  #   --security-opt label=disable \
  #   -e HOME=/root \
  #   -e AWS_DEFAULT_REGION="$AWS_REGION" \
  #   -v /root/.aws:/root/.aws:ro \
  #   -v /var/tmp:/mail:ro \
  #   amazon/aws-cli \
  #     ses send-raw-email \
  #       --cli-input-json file:///mail/$(basename "$jsonfile")

  # Cleanup
  rm -f "$bodyfile" "$emailfile" "$encodedfile" "$jsonfile"
}

notify_terminals() {
  msg="
[$(hostname)] will reboot in 1 minute.

Time: $(date -d '+1 min' '+%Y-%m-%d %H:%M:%S')
Please save your work and log out.

System status and configurations have been archived.
$( [[ "${UPLOAD_TO_S3:-}" == "true" ]] && echo "Backup sent to S3: ${S3_BUCKET}/${S3_PREFIX}/$(hostname)_${STAMP}/" )
$( [[ "${KEEP_LOCAL_BACKUP:-}" == "true" ]] && echo "Local copy saved in: ${BACKUP_DIR}" )
"
  echo "$msg" | wall
  logger "$msg"
}

do_backup &  bp=$!
send_mail  &  mp=$!
wait $bp $mp

notify_terminals