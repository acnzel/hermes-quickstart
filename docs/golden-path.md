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
| OpenAI 기기 승인 | 미확인 | |
| 디스코드 서버·봇 | 미확인 | |

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

## 5. 이후 (미확인)

- `hermes auth add openai-codex --type oauth --no-browser` 기기 승인
- 디스코드 봇 생성과 `DISCORD_BOT_TOKEN`, `DISCORD_ALLOWED_USERS`, `DISCORD_HOME_CHANNEL`
