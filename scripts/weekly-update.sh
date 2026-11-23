#!/usr/bin/env bash
# Hermes 주간 업데이트. VM 에서 systemd 타이머가 실행한다.
# `hermes update --yes` 는 게이트웨이를 스스로 멈췄다가 새 코드로 다시 띄운다.
# 이 스크립트는 그 뒤에 게이트웨이가 살아 있는지 확인하고, 죽어 있으면 띄우고, 결과를 디스코드로 알린다.
set -uo pipefail

export PATH="$HOME/.local/bin:$PATH"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"

LOG="$HOME/.hermes/logs/weekly-update.log"
mkdir -p "$(dirname "$LOG")"
log() { echo "$(date -Iseconds) $*" >> "$LOG"; }
notify() { hermes send -t discord "$1" >/dev/null 2>&1 || log "디스코드 알림 실패"; }
version() { hermes --version 2>/dev/null | head -1 | sed -E 's/^Hermes Agent (v[0-9.]+).*/\1/'; }

before="$(version)"
log "시작: $before"

hermes update --yes >> "$LOG" 2>&1
rc=$?
after="$(version)"

# 업데이트가 끝나면 게이트웨이가 다시 떠 있어야 한다. 최대 2분 기다리고, 없으면 직접 띄운다.
gateway=inactive
for _ in $(seq 1 24); do
  gateway="$(systemctl --user is-active hermes-gateway 2>/dev/null)"
  [ "$gateway" = active ] && break
  sleep 5
done
if [ "$gateway" != active ]; then
  log "게이트웨이가 꺼져 있어 다시 시작한다"
  systemctl --user restart hermes-gateway
  sleep 30
  gateway="$(systemctl --user is-active hermes-gateway 2>/dev/null)"
fi

log "끝: update exit=$rc, $before → $after, gateway=$gateway"

# 평소에는 조용히 있고, 버전이 바뀌었거나 문제가 있을 때만 알린다.
if [ "$gateway" != active ]; then
  notify "Hermes 주간 업데이트 뒤 게이트웨이가 올라오지 않았어요. VM 에서 확인이 필요합니다: systemctl --user status hermes-gateway"
  exit 1
elif [ "$rc" -ne 0 ]; then
  notify "Hermes 주간 업데이트가 실패했어요 (exit $rc). 지금은 $after 로 계속 동작 중입니다. 로그: ~/.hermes/logs/weekly-update.log"
  exit 1
elif [ "$before" != "$after" ]; then
  notify "Hermes 를 $before 에서 $after 로 업데이트했어요."
fi
