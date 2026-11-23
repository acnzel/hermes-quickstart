// Oracle Cloud 콘솔에서 Always Free VM 을 만드는 Aside REPL 스크립트.
// 실행: cat playbooks/lib/oracle-helpers.js playbooks/oracle-create-vm.js | aside repl --file -
// 전제: Aside 에 Oracle Cloud 콘솔 탭이 로그인된 상태로 열려 있다.
//
// 상태: 2026-11-23 에 이 순서를 여러 번의 호출로 나눠 실행해 VM 2대를 만들었다.
//       한 파일로 이어 붙인 이 버전은 아직 통으로 돌려 보지 않았다.
//
// 바꿔 넣을 값
const VM_NAME = "hermes-agent";
const REGION = "ap-osaka-1"; // 가입 때 정한 홈 리전. 바꿀 수 없다.
const SSH_PUBLIC_KEY = "__SSH_PUBLIC_KEY__"; // ~/.ssh/oracle.key.pub 내용

// 주의: 생성 화면의 "Service limits status" 경고에서 "View critical resources" 를 누르지 않는다.
//       그 패널을 열었다 닫으면 Name 입력란이 폼에서 사라진다. 사라졌으면 페이지를 새로 연다.
await page.goto(`https://cloud.oracle.com/compute/instances/create?region=${REGION}`);
await sleep(9000);

// 1. Basic information: 이름, Ubuntu 24.04. Shape 기본값은 VM.Standard.E2.1.Micro (Always Free).
await fil(/textbox "Name"/, VM_NAME);
await clk(/button "Change image"/);
await sleep(2500);
await clk(/radio "Ubuntu"/);
await sleep(2500);
await clk(/radio "Select Canonical Ubuntu 24\.04"/);
await sleep(800);
await clk(/button "Select image"/);
await sleep(2500);

// 2. Security: 기본값.
await clk(/button "Next"/);
await sleep(2500);

// 3. Networking.
await clk(/button "Next"/);
await sleep(3500);
const net = await tree();
const hasVcn = /combobox "Virtual cloud network" [^\n]*: "/.test(net);
if (!hasVcn) {
  // VCN 이 하나도 없으면 새로 만든다. 이 경우 공인 IP 자동 할당 스위치가 꺼진 채 잠긴다.
  // 생성 뒤 VNIC 의 Private IP 를 편집해 Ephemeral public IP 를 붙여야 한다 (docs/golden-path.md 함정 2).
  await clk(/radio "Create new virtual cloud network"/);
  await sleep(2000);
  await fil(/textbox "New virtual cloud network name"/, `${VM_NAME}-vcn`);
  await fil(/textbox "New subnet name"/, `${VM_NAME}-subnet`);
}
// 기존 VCN 이 있으면 public subnet 이 자동 선택되고 공인 IP 스위치가 켜져 있다.
await clk(/radio "Paste public key"/);
await sleep(1000);
await fil(/textbox "SSH public key"/, SSH_PUBLIC_KEY);

// 4. Storage: 기본값 (46.6GB).
await clk(/button "Next"/);
await sleep(2500);

// 5. Review → Create.
await clk(/button "Next"/);
await sleep(3000);
const review = await tree(true);
if (!review.includes(`Name ${VM_NAME}`) || !review.includes("VM.Standard.E2.1.Micro") || !review.includes("Canonical Ubuntu 24.04")) {
  throw new Error("Review 내용이 기대와 다르다. Create 를 누르지 않고 멈춘다.");
}
await clk(/button "Create"/);
await sleep(12000);

// 6. Running 까지 대기 (보통 30~40초).
let state = "";
for (let i = 0; i < 12; i++) {
  state = ((await tree(true)).match(/status: "(\w+)"/) || [])[1];
  if (state === "Running") break;
  await sleep(10000);
}
if (state !== "Running") throw new Error(`인스턴스 상태가 Running 이 아니다: ${state}`);

await clk(/tab "Details"/);
await sleep(2500);
const ip = ((await tree(true)).match(/Public IP address ?([\d.]+)/) || [])[1];
console.log(JSON.stringify({ name: VM_NAME, state, publicIp: ip || null, needsPublicIp: !ip }));
