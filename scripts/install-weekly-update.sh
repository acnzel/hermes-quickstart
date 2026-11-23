#!/usr/bin/env bash
# 주간 업데이트 타이머를 VM 에 설치한다. VM 에서, Hermes 를 설치한 사용자로 실행한다.
#   bash install-weekly-update.sh          # weekly-update.sh 가 같은 폴더에 있어야 한다
# 매주 월요일 04:00 (VM 시간대) 에 돈다. VM 이 그 시간에 꺼져 있었으면 켜진 뒤에 한 번 돈다.
set -euo pipefail

export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
SRC="$(cd "$(dirname "$0")" && pwd)/weekly-update.sh"
BIN="$HOME/.local/bin/hermes-weekly-update"
UNITS="$HOME/.config/systemd/user"

install -m 755 "$SRC" "$BIN"
mkdir -p "$UNITS"

cat > "$UNITS/hermes-weekly-update.service" <<EOF
[Unit]
Description=Hermes weekly update

[Service]
Type=oneshot
ExecStart=$BIN
# 1 OCPU VM 에서는 업데이트가 30분 넘게 걸릴 수 있다.
TimeoutStartSec=5400
EOF

cat > "$UNITS/hermes-weekly-update.timer" <<EOF
[Unit]
Description=Run Hermes weekly update every Monday 04:00

[Timer]
OnCalendar=Mon *-*-* 04:00:00
Persistent=true
RandomizedDelaySec=600

[Install]
WantedBy=timers.target
EOF

systemctl --user daemon-reload
systemctl --user enable --now hermes-weekly-update.timer
systemctl --user list-timers hermes-weekly-update.timer --no-pager
