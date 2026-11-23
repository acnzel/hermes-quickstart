# 에이전트 지시문

이 레포를 연 코딩 에이전트가 읽는 문서다. 사용자가 "Hermes 세팅해 줘"라고 하면 아래 순서대로 진행한다.

목표: 사용자의 Oracle 무료 VM 에 Hermes Agent 를 올리고, 디스코드에서 답하게 만든다.
완료 조건: `vm-hermes.sh verify` 가 `conversation=ok` 를 출력한다.

## 원칙

1. **사람을 부르는 횟수를 줄인다.** 사람이 할 일은 최대 5번으로 정해져 있다 (`docs/prerequisites.md`). 그 밖에는 묻지 않고 진행한다.
2. **사람을 부를 때는 한 번에 하나만, 무엇을 누르는지까지 말한다.** 아래 "사람에게 하는 말"의 문구를 쓴다.
3. **비밀값을 화면에 찍지 않는다.** 봇 토큰은 파이프로만 옮긴다. 채팅, 로그, 파일에 남기지 않는다.
4. **끝났다고 말하기 전에 확인한다.** 각 단계의 "확인" 명령이 통과해야 다음으로 간다.
5. **무료 범위를 벗어나지 않는다.** Oracle 에서는 `VM.Standard.E2.1.Micro` 만 만든다. 유료 자원, 추가 리전 구독, 계정 업그레이드는 하지 않는다.
6. **이미 있는 것을 지우지 않는다.** 기존 VM, 기존 디스코드 앱, 기존 서버는 건드리지 않는다.

막혔을 때는 `docs/golden-path.md` 를 본다. 실제로 겪은 함정과 해결이 단계별로 있다.

## 0. 시작할 때 한 번 확인

사용자에게 아래를 한 번에 묻는다. 답을 받으면 이후로는 묻지 않는다.

- 디스코드 서버 이름 (본인이 만든 서버)
- `docs/prerequisites.md` 의 준비물이 갖춰졌는지. 특히 디스코드 2단계 인증 앱이 옆에 있는지
- 아래 일을 대신 해도 되는지: 디스코드 개발자 약관 동의 체크, 봇 토큰 발급과 VM 저장, Oracle VM 생성

진행 상태는 `.setup-state.json` 에 적는다 (`{"vmIp": "...", "phase": "..."}`). 중간에 끊기면 이 파일과 `vm-hermes.sh status` 로 어디까지 했는지 확인하고 이어서 한다.

## 1. 사전 점검

```bash
aside --version
aside repl 'const t = await listBrowserTabs(); console.log(t.length)'
ls ~/.ssh/oracle.key 2>/dev/null || ssh-keygen -t ed25519 -f ~/.ssh/oracle.key -N "" -C hermes-quickstart
```

- `aside repl` 이 실패하면 **수동 모드**로 간다 (아래 "Aside 가 안 될 때").
- `aside <주소>` 형태는 쓰지 않는다. Aside 의 AI 를 거쳐서 크레딧이 없으면 `402` 로 실패한다. `aside repl` 과 `open -a Aside` 만 쓴다.
- 사람이 봐야 하는 페이지는 `open -a Aside <주소>` 로 연다. `aside repl` 의 `openTab` 으로 연 탭은 사람 화면에 보이지 않는다.

Oracle 콘솔과 디스코드 개발자 포털을 열고 로그인 여부를 확인한다. 로그인이 안 돼 있으면 사람에게 요청한다.

```bash
open -a Aside "https://cloud.oracle.com/compute/instances"
open -a Aside "https://discord.com/developers/applications"
```

## 2. Oracle VM

`playbooks/oracle-create-vm.js` 의 `VM_NAME`, `REGION`, `SSH_PUBLIC_KEY` 를 채워서 실행한다.
`REGION` 은 콘솔 주소의 `region=` 값이다. 이름은 `hermes-agent` 를 쓴다.

```bash
sed -e "s|__SSH_PUBLIC_KEY__|$(cat ~/.ssh/oracle.key.pub)|" playbooks/oracle-create-vm.js > /tmp/create-vm.js
cat playbooks/lib/oracle-helpers.js /tmp/create-vm.js | aside repl --file -
```

- 출력 JSON 의 `needsPublicIp` 가 `true` 면 `playbooks/oracle-assign-public-ip.js` 를 이어서 실행한다.
- 스크립트가 중간에 멈추면 `tree()` 로 화면을 읽고 남은 단계를 직접 진행한다. Aside REPL 의 ref 는 호출마다 바뀌므로 같은 호출 안에서 찾고 누른다.
- 같은 이름의 VM 이 이미 있으면 새로 만들지 말고 사용자에게 그 VM 을 쓸지 묻는다.

확인:

```bash
ssh -i ~/.ssh/oracle.key -o StrictHostKeyChecking=accept-new ubuntu@<IP> hostname
```

## 3. Hermes 설치

```bash
ssh -i ~/.ssh/oracle.key ubuntu@<IP> 'mkdir -p ~/hermes-quickstart'
scp -i ~/.ssh/oracle.key scripts/*.sh ubuntu@<IP>:hermes-quickstart/
ssh -i ~/.ssh/oracle.key ubuntu@<IP> 'cd ~/hermes-quickstart && nohup bash vm-hermes.sh setup > setup.log 2>&1 < /dev/null &'
```

- `< /dev/null` 을 빼면 SSH 가 끝나지 않고 붙잡힌다.
- IP 를 셸 변수에 담았다면 `"ubuntu@${IP}:hermes-quickstart/"` 처럼 중괄호로 감싼다.
  zsh 는 `$IP:h` 의 `:h` 를 변수 수식어로 읽어서 주소가 깨진다.

30분쯤 걸린다 (빈 VM 에서 32분). SSH 를 붙잡고 기다리지 말고 `nohup` 으로 띄운 뒤 1~2분 간격으로 확인한다.

```bash
ssh -i ~/.ssh/oracle.key ubuntu@<IP> 'tail -2 ~/hermes-quickstart/setup.log'
```

`setup 완료` 가 나오면 끝이다. 기다리는 동안 5단계의 `create`, `intents` 를 먼저 해도 된다.

확인: `vm-hermes.sh status` 에서 `hermes=v...`, `gateway=active`, `weekly_update_timer=active`.

## 4. ChatGPT 로그인 (사람 1번)

**코드를 띄우기 전에 사용자가 지금 승인할 수 있는지 확인한다.** 코드는 15분 뒤 만료된다.

```bash
ssh -i ~/.ssh/oracle.key ubuntu@<IP> 'bash ~/hermes-quickstart/vm-hermes.sh login-start'
```

출력된 `url` 과 `code` 를 사용자에게 보여 준다. 사용자가 끝났다고 하면:

```bash
ssh -i ~/.ssh/oracle.key ubuntu@<IP> 'cd ~/hermes-quickstart && bash vm-hermes.sh login-status && bash vm-hermes.sh model'
```

`model` 은 `gpt-5.6-luna` 를 설정하고 한 번 호출해 본다. 구독으로 안 되는 모델(`gpt-5-nano` 등)을 넣으면 오류로 끝난다.

## 5. 디스코드 봇 (사람 3번)

각 단계는 상태 JSON 을 출력한다. `human` 값이 `captcha`, `mfa`, `login` 이면 사람에게 요청하고, 끝났다고 하면 `status` 로 다시 확인한다.

```bash
run() { (echo "const STEP=\"$1\", APP_NAME=\"Hermes\", SERVER_NAME=\"<서버 이름>\";"; \
         cat playbooks/lib/discord-helpers.js playbooks/discord-bot.js) | aside repl --file -; }

run create      # → 캡차가 뜰 수 있다 (사람). 안 뜰 때도 있다
run intents
run reset       # → 다단계 인증 (사람). 사용자에게 화면을 닫지 말라고 한다
```

토큰은 화면에서 VM 으로 바로 보낸다. **`run token` 을 단독으로 실행하지 않는다.** 출력이 곧 토큰이다.

```bash
run token 2>/dev/null | grep -oE '^TOK=[A-Za-z0-9_.-]+$' \
  | ssh -i ~/.ssh/oracle.key ubuntu@<IP> 'bash ~/hermes-quickstart/vm-hermes.sh set-token'
```

`bot_name=...` 이 나오면 저장과 검증이 끝난 것이다.

```bash
run invite      # → 캡차 (사람)
ssh -i ~/.ssh/oracle.key ubuntu@<IP> 'bash ~/hermes-quickstart/vm-hermes.sh discord-connect "<서버 이름>"'
```

`discord-connect` 는 사용자 ID 와 채널 ID 를 봇 토큰으로 조회해서 넣는다. 사용자에게 ID 를 묻지 않는다.
홈 채널은 멘션 없이 답하도록 설정한다.

`intents`, `reset`, `invite` 는 앱 화면에서 실행해야 한다. 다른 페이지로 갔다가 돌아왔으면 `run open` 으로
앱의 봇 화면에 다시 들어간다. `open -a Aside <주소>` 는 디스코드 탭을 그 주소로 옮기므로, 앱을 만든 뒤에는 쓰지 않는다.

기존 앱이 있어도 재사용하지 않는다. 그 앱의 토큰을 초기화하면 다른 곳에서 쓰던 봇이 멈춘다.

## 6. 대화 확인 (사람 1번)

사용자에게 홈 채널에 멘션 없이 메시지를 보내 달라고 한다. 그 뒤:

```bash
ssh -i ~/.ssh/oracle.key ubuntu@<IP> 'bash ~/hermes-quickstart/vm-hermes.sh verify'
```

`conversation=ok` 가 나오면 끝이다. 답이 없으면 `docs/golden-path.md` 8절을 본다.
권한이나 intent 를 의심하기 전에, 사용자가 봇이 아니라 같은 이름의 역할을 멘션하지 않았는지부터 확인한다.

## 사람에게 하는 말

필요한 순간에 아래 문구를 그대로 쓴다. 한 번에 하나만 요청한다.

| 순간 | 문구 |
|---|---|
| 로그인 필요 | "Aside 창에 <사이트> 로그인 화면을 띄웠습니다. 로그인하고 알려 주세요." |
| ChatGPT 승인 | "브라우저에서 <url> 을 열고 ChatGPT 로 로그인한 뒤 코드 <code> 를 입력해 주세요. 15분 안에 해야 합니다." |
| 캡차 | "Aside 창의 디스코드 탭에 '로봇 아니고 사람 맞죠?' 창이 떴습니다. '사람입니다'를 눌러 주세요." |
| 다단계 인증 | "Aside 창의 디스코드 탭에 '다단계 인증' 창이 떴습니다. 인증 앱의 6자리 코드를 넣고 제출해 주세요. 그 뒤 화면은 닫지 말고 알려 주세요." |
| 대화 확인 | "디스코드 <서버>의 #<채널>에 멘션 없이 아무 말이나 보내 주세요." |

## Aside 가 안 될 때 (수동 모드)

Aside 가 설치돼 있지 않거나 `aside repl` 이 실패하면 브라우저 조작만 사람에게 넘긴다. 나머지는 그대로 에이전트가 한다.

- 사람이 하는 것: `docs/manual-fallback.md` 의 클릭 순서. 어떤 브라우저든 된다.
- 에이전트가 하는 것: SSH 키 생성, 3·4·6단계 전부, 5단계의 `set-token` 이후.
- 토큰은 사람이 채팅에 붙여 넣지 않는다. `docs/manual-fallback.md` 의 명령을 사람이 자기 터미널에서 실행하면 숨김 입력으로 VM 에 바로 들어간다.

수동 모드로 바꿀 때는 이유를 한 줄로 말하고 `docs/manual-fallback.md` 의 해당 절을 안내한다.

Aside 크레딧이 0 인 것은 수동 모드로 갈 이유가 아니다. `aside repl` 은 크레딧을 쓰지 않는다.

## 끝난 뒤 보고

- 서버 IP, 접속 명령, 봇 이름, 홈 채널
- 사람이 손댄 횟수
- 매주 월요일 04:00 에 자동 업데이트가 돈다는 것
- 확인하지 못한 것이 있으면 무엇인지
