// 디스코드 개발자 포털에서 봇을 만드는 Aside REPL 스크립트. 단계(STEP)별로 나눠 실행한다.
//
// 실행:
//   (echo 'const STEP="create", APP_NAME="Hermes", SERVER_NAME="내 서버";'; \
//    cat playbooks/lib/discord-helpers.js playbooks/discord-bot.js) | aside repl --file -
//
// 전제: Aside 에 discord.com 탭이 로그인된 상태로 열려 있다.
//       사람이 봐야 하므로 탭은 `open -a Aside https://discord.com/developers/applications` 로 연다.
//
// STEP
//   status   지금 화면 상태만 출력
//   create   새 앱 생성. 끝나면 보통 캡차가 뜬다 (사람)
//   intents  Server Members, Message Content intent 켜고 저장
//   reset    토큰 초기화. 끝나면 다단계 인증 창이 뜬다 (사람)
//   token    화면의 토큰을 `TOK=...` 한 줄로 출력. 반드시 파이프로만 쓴다 (AGENTS.md 참고)
//   invite   봇을 SERVER_NAME 서버에 초대. 끝나면 보통 캡차가 뜬다 (사람)
//
// 모든 단계는 마지막에 상태 JSON 한 줄을 출력한다. token 단계만 예외다.
// 화면 문구는 한국어 포털에서 검증했다. 영어 문구는 함께 넣었지만 검증하지 않았다.

const TOKEN_RE = /[\w-]{20,}\.[\w-]{5,8}\.[\w-]{20,}/;

// 디스코드의 체크박스와 스위치는 클릭으로 안 바뀐다. focus 한 뒤 Space 로 누른다.
async function press(re) {
  const ref = await refOf(re);
  await page.locator(ref).focus();
  await page.keyboard.press("Space");
  await sleep(700);
}
async function isChecked(re) {
  const line = (await tree()).match(new RegExp("^.*(?:" + re.source + ").*$", "mi"));
  return !!line && line[0].includes("[checked]");
}
async function status(step) {
  const t = await tree(true);
  const out = {
    step,
    loggedIn: !/discord\.com\/login/.test(page.url()),
    appId: (page.url().match(/applications\/(\d+)/) || [])[1] ? "found" : "none",
    captcha: /hCaptcha/.test(t),
    mfa: /다단계 인증|Multi-Factor|Two-Factor/i.test(t),
    tokenVisible: TOKEN_RE.test(t),
  };
  // 사람이 할 일이 있으면 한 줄로 알려 준다.
  out.human = out.captcha ? "captcha" : out.mfa ? "mfa" : !out.loggedIn ? "login" : "none";
  console.log(JSON.stringify(out));
}

const SWITCH_MEMBERS = /switch ".*GUILD_MEMBERS/;
const SWITCH_CONTENT = /switch ".*(메시지 콘텐츠|message content)/;

if (STEP === "create") {
  await page.goto("https://discord.com/developers/applications");
  await sleep(4000);
  await clk(/button "(신규 애플리케이션|New Application)"/);
  await sleep(2000);
  await fil(/textbox "(이름|Name)\*?"/, APP_NAME);
  await press(/checkbox "/); // 개발자 약관 동의
  await clk(/button "(만들기|Create)"/);
  await sleep(7000);
  await status(STEP);
} else if (STEP === "intents") {
  await clk(/link "(봇|Bot)"/);
  await sleep(4000);
  if (!(await isChecked(SWITCH_MEMBERS))) await press(SWITCH_MEMBERS);
  if (!(await isChecked(SWITCH_CONTENT))) await press(SWITCH_CONTENT);
  const save = (await tree()).match(/button "(변경 사항 저장|Save Changes)"/);
  if (save) {
    await clk(/button "(변경 사항 저장|Save Changes)"/);
    await sleep(3500);
  }
  await page.reload();
  await sleep(5000);
  if (!(await isChecked(SWITCH_MEMBERS)) || !(await isChecked(SWITCH_CONTENT))) {
    throw new Error("intent 가 저장되지 않았다.");
  }
  await status(STEP);
} else if (STEP === "reset") {
  await clk(/button "(토큰 초기화|Reset Token)"/);
  await sleep(2500);
  await clk(/button "(네, 할게요!|Yes, do it!)"/);
  await sleep(4000);
  await status(STEP);
} else if (STEP === "token") {
  // 이 단계의 출력은 토큰이다. 터미널이나 채팅에 찍히지 않게 반드시 다음 명령으로 파이프한다.
  const m = (await tree(true)).match(TOKEN_RE);
  if (!m) throw new Error("화면에 토큰이 없다. reset 단계와 다단계 인증이 끝났는지 확인한다.");
  console.log("TOK=" + m[0]);
} else if (STEP === "invite") {
  const appId = (page.url().match(/applications\/(\d+)/) || [])[1];
  if (!appId) throw new Error("앱 페이지가 아니다. 개발자 포털의 앱 화면에서 실행한다.");
  // 권한 309237763136: 채널 보기, 메시지 보내기, 스레드, 링크·파일 첨부, 기록 보기, 반응. 관리자 권한 없음.
  await page.goto(`https://discord.com/oauth2/authorize?client_id=${appId}&scope=bot+applications.commands&permissions=309237763136`);
  await sleep(6000);
  await clk(/combobox "(서버에 추가:|Add to server:?)"/);
  await sleep(1500);
  await clk(new RegExp(`option "${SERVER_NAME.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}"`));
  await sleep(1200);
  await clk(/button "(계속하기|Continue)"/);
  await sleep(3500);
  await clk(/button "(승인|Authorize)"/);
  await sleep(5000);
  await status(STEP);
} else {
  await status("status");
}
