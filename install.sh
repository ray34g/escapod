#!/usr/bin/env bash
set -euo pipefail

echo "=== escapod インストール開始 ==="

# --------- 配置先 ---------
BIN_DIR="/usr/local/bin"
CONFIG_DIR="/etc/escapod"
UNIT_DIR="/etc/systemd/system"

# --------- バイナリ設置 ---------
echo "-- スクリプトを配置しています: $BIN_DIR"
install -m 755 escapod.sh "${BIN_DIR}/escapod.sh"
install -m 755 log-shutdown-schedule.sh "${BIN_DIR}/log-shutdown-schedule.sh"

# SELinux (CoreOS/SELinux有効環境)
if command -v restorecon >/dev/null 2>&1; then
  restorecon "${BIN_DIR}/escapod.sh" || true
  restorecon "${BIN_DIR}/log-shutdown-schedule.sh" || true
fi

# --------- 環境ファイル ---------
echo "-- 環境ファイルを配置: $CONFIG_DIR"
mkdir -p "$CONFIG_DIR"
if [[ ! -f "${CONFIG_DIR}/escapod.env" ]]; then
  cp escapod.env "${CONFIG_DIR}/"
  echo "  (新規に escapod.env を配置しました)"
else
  echo "  (既存の escapod.env を保持しました)"
fi

# SELinux (envディレクトリとファイル)
if command -v restorecon >/dev/null 2>&1; then
  restorecon -R "$CONFIG_DIR" || true
fi

# --------- systemd unit ---------
echo "-- systemd ユニット配置: $UNIT_DIR"
for unit in systemd/*.service systemd/*.path; do
  cp "$unit" "$UNIT_DIR/"
done

# SELinux (unitディレクトリ)
if command -v restorecon >/dev/null 2>&1; then
  restorecon -R "$UNIT_DIR" || true
fi

# --------- systemd反映と有効化 ---------
echo "-- systemd daemon-reload"
systemctl daemon-reload

echo "-- ユニット有効化と起動"
systemctl enable escapod.service
systemctl enable --now shutdown-scheduled-watch.path

# --------- 完了メッセージ ---------
echo "=== インストール完了 ==="
echo "・escapod.sh が $BIN_DIR にインストールされました"
echo "・log-shutdown-schedule.sh が $BIN_DIR にインストールされました"
echo "・escapod.service と shutdown-scheduled-watch が有効化済みです"