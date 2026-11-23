# Aside 없이 진행하기 (수동 대체 경로)

에이전트가 브라우저를 조작하지 못할 때 쓰는 방법이다. 브라우저에서 누르는 일만 사람이 하고,
서버 설치와 설정은 그대로 에이전트가 한다. Chrome, Safari, ego lite 등 어떤 브라우저든 된다.

언제 쓰나:

- Aside 를 설치하지 않았거나 설치하고 싶지 않다.
- `aside repl` 이 오류를 낸다.
- Oracle 이나 디스코드 화면이 바뀌어서 스크립트가 멈췄다.

Aside 크레딧이 0 인 것은 이 경로로 올 이유가 아니다. 이 레포가 쓰는 `aside repl` 은 크레딧을 쓰지 않는다.

이 문서의 클릭 순서는 2026-11-23 에 에이전트가 Aside 로 누른 순서를 옮겨 적은 것이다.
사람이 이 문서만 보고 처음부터 끝까지 따라 해 본 적은 아직 없다.

## A. Oracle VM 만들기

시작 전에 에이전트에게 공개키를 받는다. `ssh-ed25519 AAAA...` 로 시작하는 한 줄이다. 공개키는 비밀이 아니다.

1. `cloud.oracle.com` 에 로그인한다.
2. 왼쪽 위 메뉴 → **Compute** → **Instances** → **Create instance**.
3. **Name** 에 `hermes-agent` 를 넣는다.
4. **Image and shape** 의 **Change image** → **Ubuntu** → **Canonical Ubuntu 24.04** → **Select image**.
   - Ubuntu 를 고르기 전에 목록의 다른 줄을 누르면 약관 창이 뜬다. Cancel 하고 Ubuntu 부터 누른다.
5. Shape 가 **VM.Standard.E2.1.Micro**, "Always Free-eligible" 인지 확인한다. 다르면 **Change shape** 로 바꾼다.
6. **Next** 를 두 번 눌러 **Networking** 으로 간다.
   - 기존 네트워크(VCN)가 있으면 그대로 둔다. "Automatically assign public IPv4 address" 가 켜져 있어야 한다.
   - 없으면 **Create new virtual cloud network** 를 고른다. 이 경우 공인 IP 스위치가 꺼진 채 잠긴다. 아래 "공인 IP 가 없을 때"를 이어서 한다.
7. **Add SSH keys** 에서 **Paste public key** 를 고르고 받은 공개키를 붙여 넣는다.
8. **Next** → **Next** → 내용을 확인하고 **Create**.
9. 상태가 **Running** 이 되면 **Public IP address** 를 에이전트에게 알려 준다.

"Service limits status" 경고의 **View critical resources** 는 누르지 않는다. 눌렀다 닫으면 Name 입력란이 사라진다.
사라졌으면 페이지를 새로 연다.

### 공인 IP 가 없을 때

1. 인스턴스 화면의 **Networking** 탭 → **Attached VNICs** 의 VNIC 이름을 누른다.
2. **IP administration** 탭 → 표 오른쪽 끝의 **Actions(⋯)** → **Edit**.
3. **Public IP type** 에서 **Ephemeral public IP** → **Update**.
4. 표에 나타난 공인 IP 를 에이전트에게 알려 준다.

## B. 디스코드 봇 만들기

1. `discord.com/developers/applications` 에 로그인한다.
2. **신규 애플리케이션 (New Application)** → 이름에 `Hermes` → 약관 체크 → **만들기**.
   - "사람 맞죠?" 창이 뜨면 "사람입니다"를 누른다.
3. 왼쪽 메뉴의 **봇 (Bot)**.
4. 아래로 내려 **Privileged Gateway Intents** 에서 두 개를 켠다.
   - **Server Members Intent**
   - **Message Content Intent**
5. 화면 아래의 **변경 사항 저장 (Save Changes)** 을 누른다.
6. 위로 올라가 **토큰 초기화 (Reset Token)** → **네, 할게요!**
   - "다단계 인증" 창에 인증 앱의 6자리 코드를 넣는다.
7. 토큰이 화면에 한 번만 표시된다. **복사** 를 누른다. 이 화면은 C 단계가 끝날 때까지 닫지 않는다.

## C. 토큰을 서버에 넣기

토큰은 채팅에 붙여 넣지 않는다. 내 터미널에서 아래 명령을 실행한다. `<IP>` 는 에이전트가 알려 준다.

```bash
ssh -t -i ~/.ssh/oracle.key ubuntu@<IP> 'bash ~/hermes-quickstart/vm-hermes.sh set-token'
```

"디스코드 봇 토큰을 붙여 넣고 Enter" 가 나오면 붙여 넣고 Enter 를 누른다. 입력한 내용은 화면에 보이지 않는다.
`bot_name=Hermes` 처럼 봇 이름이 나오면 성공이다. 에이전트에게 끝났다고 알려 준다.

## D. 봇을 서버에 초대하기

1. 개발자 포털 주소창의 숫자가 앱 ID 다. `.../applications/<앱 ID>/bot`
2. 아래 주소의 `<앱 ID>` 를 바꿔서 연다.

   ```
   https://discord.com/oauth2/authorize?client_id=<앱 ID>&scope=bot+applications.commands&permissions=309237763136
   ```

3. **서버에 추가** 에서 내 서버를 고르고 **계속하기**.
4. 권한 8개를 확인하고 **승인**. 관리자 권한은 목록에 없어야 한다.
   - "사람 맞죠?" 창이 뜨면 "사람입니다"를 누른다.
5. 에이전트에게 끝났다고 알려 준다. 에이전트가 연결을 마무리하고 채널에 테스트 메시지를 보낸다.

## 사람이 하는 일 비교

| | Aside 사용 | 수동 대체 경로 |
|---|---|---|
| Oracle VM 만들기 | 에이전트 | 사람 (A) |
| 디스코드 봇 만들기 | 에이전트. 캡차 2번과 인증 코드 1번만 사람 | 사람 (B, D) |
| 토큰을 서버에 넣기 | 에이전트 | 사람이 명령 한 줄 실행 (C) |
| Hermes 설치, 설정, 연결 확인 | 에이전트 | 에이전트 |
| ChatGPT 승인 코드 입력 | 사람 | 사람 |
