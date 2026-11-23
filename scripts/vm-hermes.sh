#!/usr/bin/env bash
# VM 안에서 Hermes 를 설치하고 연결하는 스크립트. 여러 번 실행해도 된다.
#   bash vm-hermes.sh <명령>
#
#   setup            스왑, 시간대, Hermes 설치, 디스코드 의존성, 게이트웨이 서비스, 주간 업데이트
#   status           현재 상태를 key=value 로 출력
#   login-start      ChatGPT 기기 승인 코드를 띄우고 주소와 코드를 출력
#   login-status     ChatGPT 로그인 여부
#   model [이름]     모델을 설정하고 한 번 호출해서 확인 (기본 gpt-5.6-luna)
#   set-token        디스코드 봇 토큰을 표준 입력으로 받아 저장. 터미널에서 실행하면 숨김 입력
#   discord-connect  사용자·채널 ID 를 조회해 설정하고 게이트웨이 재시작, 연결 확인
#   verify           게이트웨이가 메시지를 받고 답했는지 로그로 확인
set -euo pipefail

export PATH="$HOME/.local/bin:$PATH"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
ENV_FILE="$HOME/.hermes/.env"
GW_LOG="$HOME/.hermes/logs/gateway.log"
HERE="$(cd "$(dirname "$0")" && pwd)"
DEFAULT_MODEL="gpt-5.6-luna"

say() { echo "[hermes-quickstart] $*"; }
die() { echo "[hermes-quickstart] 오류: $*" >&2; exit 1; }
plain() { sed 's/\x1b\[[0-9;]*m//g'; }

set_env() { # key value
  local key="$1" value="$2" tmp
  umask 077
  mkdir -p "$(dirname "$ENV_FILE")"; touch "$ENV_FILE"
  tmp="$(mktemp "$ENV_FILE.XXXXXX")"
  grep -vE "^${key}=" "$ENV_FILE" > "$tmp" || true
  printf '%s=%s\n' "$key" "$value" >> "$tmp"
  mv "$tmp" "$ENV_FILE"; chmod 600 "$ENV_FILE"
}
get_env() { grep -E "^$1=" "$ENV_FILE" 2>/dev/null | head -1 | cut -d= -f2-; }
gateway_state() { systemctl --user is-active hermes-gateway 2>/dev/null || true; }
is_set() { [ -n "$(get_env "$1")" ] && echo set || echo none; }
last_ts() { grep "$1" "$GW_LOG" 2>/dev/null | tail -1 | cut -c1-19 || true; }
# 명령의 출력을 색 코드 없이 돌려준다. pipefail 에서 `명령 | grep -q` 는 grep 이 먼저 끝나면
# 앞 명령이 SIGPIPE 로 죽어 실패로 잡히므로, 출력 검사는 항상 이 함수로 받아서 한다.
capture() { "$@" 2>&1 | plain || true; }
# `hermes auth status` 는 로그인 여부와 관계없이 exit 0 이라 문구로 판단한다.
codex_logged_in() { grep -q 'logged in' <<< "$(capture hermes auth status openai-codex)"; }

cmd_setup() {
  cloud-init status --wait >/dev/null 2>&1 || true

  # 스왑이 없으면 1GB VM 에서 설치가 실패한다 (설치 중 스왑을 1GB 까지 썼다).
  if ! swapon --show | grep -q '/swapfile'; then
    say "스왑 2GB 생성"
    sudo fallocate -l 2G /swapfile && sudo chmod 600 /swapfile
    sudo mkswap /swapfile >/dev/null && sudo swapon /swapfile
    grep -q '^/swapfile ' /etc/fstab || echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab >/dev/null
  fi
  sudo timedatectl set-timezone "${TZ_NAME:-Asia/Seoul}"

  if ! command -v hermes >/dev/null; then
    say "Hermes 설치 (1 OCPU VM 에서 25분쯤 걸린다)"
    curl -fsSL https://hermes-agent.nousresearch.com/install.sh -o "$HOME/hermes-install.sh"
    bash "$HOME/hermes-install.sh" --skip-browser --skip-computer-use --non-interactive
    export PATH="$HOME/.local/bin:$PATH"
  fi

  # 기본 설치에는 discord.py 가 없다.
  if ! grep -q '✓ discord.py' <<< "$(capture hermes doctor)"; then
    say "디스코드 의존성 설치"
    hermes pm install --extra discord
  fi

  # root 로 설치하면 /root/.hermes 를 잡고 실패한다. 사용자 서비스와 linger 를 쓴다.
  sudo loginctl enable-linger "$USER"
  if ! systemctl --user cat hermes-gateway >/dev/null 2>&1; then
    say "게이트웨이 서비스 등록"
    hermes gateway install --start-now
  fi

  if [ -f "$HERE/install-weekly-update.sh" ] && ! systemctl --user cat hermes-weekly-update.timer >/dev/null 2>&1; then
    say "주간 업데이트 타이머 설치"
    bash "$HERE/install-weekly-update.sh" >/dev/null
  fi

  say "setup 완료"
  cmd_status
}

cmd_status() {
  echo "swap_mb=$(free -m | awk '/^Swap:/{print $2}')"
  echo "mem_available_mb=$(free -m | awk '/^Mem:/{print $7}')"
  if command -v hermes >/dev/null; then
    echo "hermes=$(hermes --version 2>/dev/null | head -1 | sed -E 's/^Hermes Agent (v[0-9.]+).*/\1/')"
    echo "model_provider=$(hermes config get model.provider 2>/dev/null | tail -1)"
    echo "model_default=$(hermes config get model.default 2>/dev/null | tail -1)"
    echo "codex_login=$(codex_logged_in && echo yes || echo no)"
  else
    echo "hermes=none"
  fi
  echo "gateway=$(gateway_state)"
  echo "weekly_update_timer=$(systemctl --user is-active hermes-weekly-update.timer 2>/dev/null || true)"
  echo "discord_token=$(is_set DISCORD_BOT_TOKEN)"
  echo "discord_allowed_users=$(is_set DISCORD_ALLOWED_USERS)"
  echo "discord_connected=$(grep -q 'discord connected' <<< "$(capture tail -200 "$GW_LOG")" && echo yes || echo no)"
}

cmd_login_start() {
  local log="$HOME/codex-auth.log"
  pkill -u "$USER" -f 'auth add openai-codex' 2>/dev/null || true
  : > "$log"
  nohup hermes auth add openai-codex --type oauth --no-browser --timeout 900 > "$log" 2>&1 &
  for _ in $(seq 1 12); do
    sleep 5
    grep -q 'Enter this code' "$log" && break
  done
  local url code
  url="$(plain < "$log" | grep -oE 'https://[^ ]+' | head -1)"
  code="$(plain < "$log" | grep -A1 'Enter this code' | tail -1 | tr -d ' ')"
  [ -n "$url" ] && [ -n "$code" ] || die "승인 코드를 받지 못했다. 로그: $log"
  echo "url=$url"
  echo "code=$code"
  echo "expires_in_minutes=15"
}

cmd_login_status() {
  if codex_logged_in; then echo "codex_login=yes"; else echo "codex_login=no"; exit 1; fi
}

cmd_model() {
  local model="${1:-$DEFAULT_MODEL}" out rc=0
  hermes config set model.provider openai-codex >/dev/null
  hermes config set model.default "$model" >/dev/null
  # 구독으로 안 되는 모델이 있다. 설정한 뒤 반드시 한 번 호출해서 확인한다.
  # 거절되면 hermes 가 exit 2 로 끝난다 (정상은 0).
  out="$(timeout 240 hermes -z '한 단어로 답해: 1+1은?' 2>&1)" || rc=$?
  out="$(plain <<< "$out")"
  [ "$rc" -eq 0 ] || die "모델 $model 호출 실패 (exit $rc). 이 ChatGPT 계정으로 쓸 수 없는 모델일 수 있다. gpt-5.6-luna, gpt-6-luna, gpt-6-sol 중에서 고른다."
  [ -n "$(tr -d '[:space:]' <<< "$out")" ] || die "모델이 답하지 않았다."
  # 디스코드가 아직 연결 전이면 discord-connect 가 어차피 재시작한다.
  if [ "$(is_set DISCORD_BOT_TOKEN)" = set ] && [ "$(gateway_state)" = active ]; then systemctl --user restart hermes-gateway; fi
  echo "model=$model"
  echo "test_reply=$(grep -vE '^\s*$' <<< "$out" | tail -1 | cut -c1-80)"
}

cmd_set_token() {
  local token
  if [ -t 0 ]; then
    read -rsp "디스코드 봇 토큰을 붙여 넣고 Enter (화면에 표시되지 않습니다): " token; echo
  else
    IFS= read -r token || true
  fi
  token="${token#TOK=}"
  [[ "$token" =~ ^[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{5,8}\.[A-Za-z0-9_-]{20,}$ ]] || die "토큰 형식이 아니다."
  local name
  name="$(curl -fsS -H "Authorization: Bot $token" https://discord.com/api/v10/users/@me \
          | python3 -c 'import sys,json; print(json.load(sys.stdin).get("username",""))')" || die "디스코드가 이 토큰을 거절했다."
  [ -n "$name" ] || die "디스코드가 이 토큰을 거절했다."
  set_env DISCORD_BOT_TOKEN "$token"
  echo "bot_name=$name"
}

cmd_discord_connect() {
  [ -n "$(get_env DISCORD_BOT_TOKEN)" ] || die "DISCORD_BOT_TOKEN 이 없다. set-token 을 먼저 실행한다."
  local found
  found="$(SERVER_NAME="${1:-}" python3 - "$ENV_FILE" <<'PY'
import json, os, sys, urllib.request
env = dict(l.split("=", 1) for l in open(sys.argv[1]).read().splitlines() if "=" in l and not l.startswith("#"))
def api(path):
    req = urllib.request.Request("https://discord.com/api/v10" + path,
        headers={"Authorization": "Bot " + env["DISCORD_BOT_TOKEN"], "User-Agent": "DiscordBot (hermes-quickstart, 1.0)"})
    return json.load(urllib.request.urlopen(req))
guilds = api("/users/@me/guilds")
want = os.environ.get("SERVER_NAME", "")
if want:
    guilds = [g for g in guilds if g["name"] == want]
if not guilds:
    sys.exit("봇이 들어간 서버가 없다. 초대가 끝났는지 확인한다.")
guild = api("/guilds/" + guilds[0]["id"])
texts = sorted((c for c in api("/guilds/" + guild["id"] + "/channels") if c["type"] == 0), key=lambda c: c["position"])
if not texts:
    sys.exit("텍스트 채널이 없다.")
# 서버를 만든 사람이 곧 사용자다. 홈 채널은 맨 위 텍스트 채널.
print(guild["owner_id"], texts[0]["id"], texts[0]["name"], guild["name"], sep="\t")
PY
)" || die "디스코드 조회 실패"
  local owner channel channel_name server
  IFS=$'\t' read -r owner channel channel_name server <<< "$found"
  set_env DISCORD_ALLOWED_USERS "$owner"
  set_env DISCORD_HOME_CHANNEL "$channel"
  set_env DISCORD_HOME_CHANNEL_NAME "$channel_name"
  # 봇과 같은 이름의 역할을 멘션하면 답하지 않는다. 홈 채널은 멘션 없이 답하게 한다.
  set_env DISCORD_FREE_RESPONSE_CHANNELS "$channel"

  local since; since="$(date '+%Y-%m-%d %H:%M:%S')"
  systemctl --user restart hermes-gateway
  local connected=no
  for _ in $(seq 1 24); do
    sleep 5
    if grep -q 'discord connected' <<< "$(capture awk -v s="$since" '$0 >= s' "$GW_LOG")"; then connected=yes; break; fi
  done
  [ "$connected" = yes ] || die "게이트웨이가 디스코드에 연결되지 않았다. 로그: $GW_LOG"
  hermes send -t discord "Hermes 가 연결됐어요. 이 채널에 멘션 없이 아무 말이나 보내 보세요." >/dev/null
  echo "server=$server"
  echo "home_channel=$channel_name"
  echo "discord_connected=yes"
}

cmd_verify() {
  echo "gateway=$(gateway_state)"
  local inbound reply
  inbound="$(last_ts 'inbound message: platform=discord')"
  reply="$(last_ts 'response ready: platform=discord')"
  echo "last_inbound=${inbound:-none}"
  echo "last_reply=${reply:-none}"
  [ -n "$inbound" ] && [ -n "$reply" ] && [[ ! "$reply" < "$inbound" ]] || die "아직 디스코드에서 받은 메시지에 답한 기록이 없다."
  echo "conversation=ok"
}

case "${1:-}" in
  setup) cmd_setup ;;
  status) cmd_status ;;
  login-start) cmd_login_start ;;
  login-status) cmd_login_status ;;
  model) cmd_model "${2:-}" ;;
  set-token) cmd_set_token ;;
  discord-connect) cmd_discord_connect "${2:-}" ;;
  verify) cmd_verify ;;
  *) sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'; exit 2 ;;
esac
