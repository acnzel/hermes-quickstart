# 수동 실행 기록 (golden path)

자동화의 기준이 되는 실측 기록이다. 여기 적힌 것은 2026-11-23 에 실제로 실행해서 확인한 것만이다.
확인하지 못한 것은 "미확인"이라고 적는다.

실행 환경: macOS, Aside CLI 1.26.1121.1917, Oracle Cloud Free Tier (홈 리전 ap-osaka-1).

## 사람 개입 횟수

| 단계 | 개입 | 내용 |
|---|---|---|
| Oracle 가입, 카드 등록, 리전 선택 | 1 | 자동화하지 않는다 |
| Aside 에서 Oracle 콘솔 로그인 | 1 | 이후 세션이 유지됐다 |
| VM 생성, 공인 IP, SSH, 스왑, Hermes 설치 | 0 | |
| OpenAI 기기 승인 | 1 | 주소를 열고 코드 입력. 15분 안에 해야 한다 |
| 디스코드 봇 | 3 | 캡차 2번, 2단계 인증 1번. 로그인은 미리 해 둔다 |

## 1. Oracle VM

스크립트: `playbooks/oracle-create-vm.js`

| 항목 | 값 |
|---|---|
| Shape | VM.Standard.E2.1.Micro (Always Free, 1 OCPU, 1GB). 계정당 2대까지 |
| 이미지 | Canonical Ubuntu 24.04 |
| 디스크 | 기본 46.6GB |
| 생성부터 Running 까지 | 30~40초 |

### 확인된 함정

1. **홈 리전은 바꿀 수 없다.** Free Tier 는 리전 1개만 쓸 수 있고 추가 구독도 막혀 있다.
   Manage regions 화면에 "You have exceeded the maximum number of regions allowed" 가 뜬다.
   한국 리전은 가입 화면에서 선택이 안 될 때가 있다. 일본(오사카)으로 해도 동작에 문제는 없다.
2. **새 VCN 을 같이 만들면 공인 IP 가 안 붙는다.** "Automatically assign public IPv4 address"
   스위치가 꺼진 채 잠긴다. 생성 뒤 VNIC → IP administration → Private IP 의 Edit →
   "Ephemeral public IP" 로 붙인다. 기존 public subnet 을 고르면 스위치가 켜져 있고 IP 가 바로 붙는다.
3. **"View critical resources" 패널을 열지 않는다.** 두 번째 VM 을 만들 때 한도 경고(1 of 2)가 뜬다.
   그 패널을 열었다 닫으면 Name 입력란이 사라진다. 페이지를 새로 열면 돌아온다.
4. **이미지 목록에서 Ubuntu 를 고르기 전에 목록 행을 누르면** Autonomous Linux 약관 창이 뜬다.
   Cancel 하고 Ubuntu 라디오부터 누른다.
5. **SSH 키는 로컬에서 만든다.** 콘솔의 "Generate a key pair" 는 파일 다운로드가 필요하다.
   `ssh-keygen -t ed25519 -f ~/.ssh/oracle.key -N ""` 로 만들고 공개키를 "Paste public key" 에 넣는다.
6. **Aside REPL 의 ref 는 호출마다 바뀐다.** 같은 호출 안에서 snapshot 을 뜨고 텍스트로 ref 를 찾아야 한다
   (`playbooks/lib/oracle-helpers.js`). 메뉴를 여는 클릭과 메뉴 항목 클릭도 같은 호출에 넣는다.

## 2. VM 초기 설정

```bash
ssh -i ~/.ssh/oracle.key ubuntu@<공인 IP>
cloud-init status --wait
sudo fallocate -l 2G /swapfile && sudo chmod 600 /swapfile
sudo mkswap /swapfile && sudo swapon /swapfile
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
sudo timedatectl set-timezone Asia/Seoul
```

설정 직후: 메모리 952MB 중 가용 724MB, 스왑 2GB, 디스크 40G 남음.

## 3. Hermes 설치

```bash
curl -fsSL https://hermes-agent.nousresearch.com/install.sh -o ~/install.sh
bash ~/install.sh --skip-browser --skip-computer-use --non-interactive
```

- `--skip-browser`: Chromium 을 깔지 않는다. 1GB VM 에서 브라우저 도구는 쓰지 않는다.
- `--non-interactive`: 입력이 필요한 단계를 건너뛴다. 모델 로그인과 게이트웨이 설정은 뒤에서 따로 한다.

| 측정 | 값 |
|---|---|
| 설치된 버전 | v0.23.3 (stable) |
| 소요 시간 | 1450초 (약 24분). 병목은 CPU (로드 3 이상) |
| 설치 중 가용 메모리 최저 | 211MB |
| 설치 중 스왑 최대 | 1031MB (웹 UI 빌드 단계). **스왑 없이는 1GB VM 에서 설치가 안 된다고 봐야 한다** |
| 설치 후 디스크 | `~/.hermes` 2.6G, 루트 38G 남음 |

설치 뒤 `hermes` 는 `~/.local/bin` 에 있다. SSH 로 명령을 보낼 때는 `export PATH=$HOME/.local/bin:$PATH` 를 앞에 붙인다.

### 디스코드 의존성

기본 설치에는 `discord.py` 가 없다. `hermes doctor` 가 "discord.py (optional, not installed)" 로 알려 준다.

```bash
hermes pm install --extra discord    # 160초
```

## 4. 게이트웨이 서비스 등록

```bash
sudo loginctl enable-linger ubuntu
export XDG_RUNTIME_DIR=/run/user/$(id -u)
hermes gateway install --start-now
systemctl --user is-active hermes-gateway
```

- **`sudo hermes gateway install --system` 은 쓰지 않는다.** root 로 실행하면 Hermes 가 `/root/.hermes` 를
  데이터 폴더로 잡고 "owned by uid 1001" 오류로 멈춘다. 사용자 서비스와 linger 조합이면 sudo 없이
  부팅 때 자동으로 뜬다.
- SSH 비대화 세션에는 `XDG_RUNTIME_DIR` 이 없어서 `systemctl --user` 가 실패한다. 직접 넣어 준다.

| 측정 (재부팅 후 대기 상태, 플랫폼 미연결) | 값 |
|---|---|
| 재부팅 후 자동 시작 | 됨 (부팅 2분 안에 active) |
| 게이트웨이 메모리 | 219MB |
| 시스템 가용 메모리 | 606MB / 952MB |
| 스왑 사용 | 0 |

메신저를 연결하고 대화 중일 때의 메모리는 미확인이다.

## 5. ChatGPT 구독 로그인 (사람 개입 1번)

VM 에서 실행한다. 주소와 코드를 출력하고 승인을 기다린다.

```bash
nohup hermes auth add openai-codex --type oauth --no-browser --timeout 900 > ~/codex-auth.log 2>&1 &
# 로그에서 주소와 코드를 읽어 사람에게 보여 준다
#   https://auth.openai.com/codex/device
#   XXXX-XXXXX
```

사람이 할 일: 자기 브라우저에서 주소를 열고, ChatGPT 로 로그인한 뒤 코드를 입력한다.

- 코드는 약 15분 뒤 만료된다. 첫 시도는 사람이 자리에 없어서 만료됐고, 다시 띄워서 성공했다.
  에이전트는 코드를 띄우기 전에 사람이 지금 승인할 수 있는지 먼저 확인해야 한다.
- 성공하면 로그에 `Added openai-codex OAuth credential #1` 이 찍히고,
  `hermes auth status openai-codex` 가 `logged in` 을 돌려준다.

### 모델 설정

로그인만으로는 구독을 쓰지 않는다. 설치 직후 기본값이 `model.default: anthropic/claude-opus-4.6`,
`model.provider: auto` 다.

```bash
hermes config set model.provider openai-codex
hermes config set model.default gpt-6-sol
hermes -z "hostname 을 확인해서 알려줘"     # 한 번 호출해 확인
```

| 측정 | 값 |
|---|---|
| 테스트 호출 | 성공. `gpt-6-sol` 이 `hostname` 도구를 실행하고 답함 |
| 응답 시간 | 24초 (CLI 기동 포함) |
| 호출 직후 가용 메모리 | 372MB (게이트웨이가 같이 떠 있는 상태) |

`gpt-6-sol` 은 Hermes 소스(`hermes_cli/codex_models.py`)가 구독용 기본값으로 두는 모델이다.
요금제별로 쓸 수 있는 모델이 다른지는 미확인이다.

### 구독 로그인으로 되는 모델과 안 되는 모델

API 에 있는 모델이 전부 되는 것은 아니다. 이 계정에서 `hermes -z "1+1은?" -m <모델>` 로 하나씩 호출했다.

| 모델 | 결과 |
|---|---|
| `gpt-6-sol` | 됨 |
| `gpt-6-luna` | 됨 (7초) |
| `gpt-5.6-luna` | 됨 (8초) |
| `gpt-5-nano` | 거절. HTTP 400 "not supported when using Codex with a ChatGPT account" |
| `gpt-5-mini` | 거절 |
| `gpt-5.4-mini` | 거절. Hermes 의 구독용 목록에는 들어 있는데도 거절됐다 |

가벼운 모델을 원하면 luna 계열을 쓴다. 설정 스크립트는 모델을 바꾼 뒤 반드시 한 번 호출해서
확인해야 한다. 거절된 모델을 넣어 두면 봇이 모든 메시지에 오류로 답한다.

모델을 바꾼 뒤에는 게이트웨이를 재시작한다: `systemctl --user restart hermes-gateway`

## 6. 디스코드 봇 (사람 개입 3번: 캡차 2번, 2단계 인증 1번)

Aside 로 `discord.com/developers/applications` 를 조작한다. 사람이 미리 로그인해 둬야 한다.
준비물과 사람이 할 일은 `docs/prerequisites.md` 에 있다.

### 순서

1. **신규 애플리케이션** → 이름 입력, 약관 체크박스, **만들기**
   - 약관 체크박스는 클릭으로 안 바뀐다 ("Checkbox click did not change checked state").
     focus 한 뒤 Space 키로 누른다. intent 스위치도 같은 방식으로 누른다.
   - **만들기** 를 누르면 hCaptcha 가 뜬다. 사람이 푼다. (개입 1)
2. 왼쪽 **봇** 메뉴 → Server Members Intent, Message Content Intent 켜기 → **변경 사항 저장**
   - 새로고침해서 두 스위치가 켜진 채로 남아 있는지 확인한다.
   - "공개 봇" 은 켠 채로 둔다. Hermes 문서(discord.md 126행)의 권장이다.
3. **토큰 초기화** → **네, 할게요!**
   - "다단계 인증" 창이 뜬다. 사람이 6자리 코드를 넣는다. (개입 2)
   - 제출하면 토큰이 화면에 한 번만 표시된다.
4. 토큰을 VM 으로 옮긴다. Aside 출력에서 SSH 로 바로 파이프해서 채팅과 로그에 값이 남지 않게 한다.

   ```bash
   cat playbooks/lib/discord-helpers.js <토큰을 TOK=... 한 줄로 출력하는 스크립트> | aside repl --file - 2>/dev/null \
     | grep -oE '^TOK=[A-Za-z0-9_.-]+$' \
     | ssh -i ~/.ssh/oracle.key ubuntu@<IP> 'IFS= read -r line; t="${line#TOK=}"; ...'
   ```

   VM 쪽은 `~/.hermes/.env` 의 `DISCORD_BOT_TOKEN=` 줄을 교체하고 권한을 600 으로 맞춘다.
   화면을 읽을 때는 토큰 형식 `[\w-]{20,}\.[\w-]{5,8}\.[\w-]{20,}` 을 가리고 출력한다.
5. 토큰 검증: VM 에서 `curl -H "Authorization: Bot $t" https://discord.com/api/v10/users/@me`.
   봇 이름이 돌아오면 정상이다.
6. 초대: `https://discord.com/oauth2/authorize?client_id=<앱 ID>&scope=bot+applications.commands&permissions=309237763136`
   - 앱 ID 는 개발자 포털 주소의 숫자다.
   - "서버에 추가" 에서 서버를 고르고 **계속하기** → 권한 8개 확인 → **승인**
   - 권한: 채널 보기, 메시지 보내기, 스레드에서 메시지 보내기, 공개 스레드 만들기, 링크 첨부, 파일 첨부,
     메시지 기록 보기, 반응 추가하기. 관리자 권한은 없다.
   - **승인** 을 누르면 hCaptcha 가 한 번 더 뜬다. 사람이 푼다. (개입 3)

### 함정

- `aside repl` 로 연 탭은 사람 화면에 보이지 않는다. 사람이 봐야 하는 페이지는 `open -a Aside <주소>` 로 연다.
- `aside <주소>` 는 Aside 의 AI 를 거쳐서 크레딧이 없으면 `402 Insufficient credits` 로 실패한다.
  `aside repl` 과 `open -a Aside` 는 크레딧 없이 된다.
- 로그인된 브라우저를 써도 캡차는 뜬다. 앱 생성과 봇 초대에서 각각 한 번씩 떴다.

## 7. 이후 (미확인)

- 초대 캡차 통과 뒤 봇이 서버에 들어갔는지 확인
- 사용자 ID, 채널 ID 조회와 `DISCORD_ALLOWED_USERS`, `DISCORD_HOME_CHANNEL` 설정
- 게이트웨이 재시작, 디스코드에서 대화 확인, 대화 중 메모리

- 디스코드 봇 생성과 `DISCORD_BOT_TOKEN`, `DISCORD_ALLOWED_USERS`, `DISCORD_HOME_CHANNEL`
