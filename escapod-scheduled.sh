#!/usr/bin/env bash
set -euo pipefail

FILE="/run/systemd/shutdown/scheduled"

if [[ -f "$FILE" ]]; then
    echo "===== Shutdown/reboot schedule detected =====" | systemd-cat -t shutdown-watch
    cat "$FILE" | systemd-cat -t shutdown-watch
else
    echo "No shutdown/reboot schedule file found." | systemd-cat -t shutdown-watch
fi
