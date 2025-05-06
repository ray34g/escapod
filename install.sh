#!/usr/bin/env bash
set -euo pipefail

echo "=== Escapod installation started ==="

# --------- Paths ---------
BIN_DIR="/usr/local/bin"
CONFIG_DIR="/etc/escapod"
UNIT_DIR="/etc/systemd/system"

# --------- Install script ---------
echo "-- Installing script to: $BIN_DIR"
install -m 755 escapod.sh "${BIN_DIR}/escapod.sh"

# SELinux relabeling (if enabled)
if command -v restorecon >/dev/null 2>&1; then
  restorecon "${BIN_DIR}/escapod.sh" || true
fi

# --------- Install environment file ---------
echo "-- Installing environment file to: $CONFIG_DIR"
mkdir -p "$CONFIG_DIR"
if [[ ! -f "${CONFIG_DIR}/escapod.env" ]]; then
  cp escapod.env "${CONFIG_DIR}/"
  echo "  (New escapod.env has been installed)"
else
  echo "  (Existing escapod.env preserved)"
fi

# SELinux relabeling for config directory and files
if command -v restorecon >/dev/null 2>&1; then
  restorecon -R "$CONFIG_DIR" || true
fi

# --------- Install systemd units ---------
echo "-- Installing systemd units to: $UNIT_DIR"
cp systemd/escapod.service "$UNIT_DIR/"
cp systemd/escapod-scheduled.service "$UNIT_DIR/"
cp systemd/escapod-scheduled.path "$UNIT_DIR/"
cp systemd/escapod-post.service "$UNIT_DIR/"

# SELinux relabeling for unit files
if command -v restorecon >/dev/null 2>&1; then
  restorecon -R "$UNIT_DIR" || true
fi

# --------- Reload systemd and enable units ---------
echo "-- Reloading systemd daemon"
systemctl daemon-reload

echo "-- Enabling and starting units"
systemctl enable escapod.service
systemctl enable escapod-scheduled.service
systemctl enable --now escapod-scheduled.path
systemctl enable escapod-post.service

echo "=== Installation completed ==="
echo " - escapod.sh has been installed to $BIN_DIR"
echo " - escapod.service, escapod-scheduled.service, escapod-scheduled.path, and escapod-post.service have been enabled"