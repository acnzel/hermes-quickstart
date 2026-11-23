// VM 에 공인 IP 가 안 붙었을 때 임시(ephemeral) 공인 IP 를 붙이는 Aside REPL 스크립트.
// 새 VCN 을 같이 만들면 생성 화면의 공인 IP 스위치가 꺼진 채 잠겨서 이 상황이 된다.
//
// 실행: (echo 'const VM_NAME="hermes-agent", REGION="ap-osaka-1";'; \
//        cat playbooks/lib/oracle-helpers.js playbooks/oracle-assign-public-ip.js) | aside repl --file -
//
// 상태: 2026-11-23 에 이 순서를 여러 번의 호출로 나눠 실행해 IP 를 붙였다.
//       한 파일로 이어 붙인 이 버전은 아직 통으로 돌려 보지 않았다.

await page.goto(`https://cloud.oracle.com/compute/instances?region=${REGION}`);
await sleep(6000);
await clk(new RegExp(`link "${VM_NAME}"`));
await sleep(5000);

// 인스턴스 → Networking 탭 → Attached VNICs 의 VNIC 이름(인스턴스 이름과 같다)
await clk(/tab "Networking"/);
await sleep(3000);
await clk(new RegExp(`link "${VM_NAME}" \\[`));
await sleep(4000);

// VNIC → IP administration → Private IP 행의 Actions → Edit
await clk(/tab "IP administration"/);
await sleep(3000);
// 메뉴를 여는 클릭과 항목 클릭은 같은 호출 안에서 한다. 호출이 나뉘면 메뉴가 닫힌다.
await clk(/button "Actions" \[ref=f\d+e\d+\]/);
await sleep(1200);
await clk(/menuitem "Edit"/);
await sleep(3000);

// Public IP type → Ephemeral public IP → Update
await clk(/radio "Help availableEphemeral/);
await sleep(1500);
await clk(/button "Update"/);
await sleep(6000);

const ip = ((await tree(true)).match(/(\d+\.\d+\.\d+\.\d+) \(Ephemeral\)/) || [])[1];
if (!ip) throw new Error("공인 IP 가 붙지 않았다. IP administration 탭을 직접 확인한다.");
console.log(JSON.stringify({ name: VM_NAME, publicIp: ip }));
