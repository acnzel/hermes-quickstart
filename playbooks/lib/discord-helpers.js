const tl = await listBrowserTabs();
const dt = tl.find(t=>t.url.includes("discord.com"));
if(!dt) throw new Error("no discord tab: "+JSON.stringify(tl.map(t=>t.url.slice(0,60))));
await attachBrowserTab(dt.targetId);
async function refOf(re){ const s = await snapshot(page,{interactive:true}); const m = s.tree.match(new RegExp("^.*(?:"+re.source+").*$","m")); if(!m) throw new Error("not found "+re+"\n"+s.tree); return m[0].match(/\[ref=(\w+)\]/)[1]; }
async function clk(re){ const r = await refOf(re); await page.locator(r).click(); }
async function fil(re,v){ const r = await refOf(re); await page.locator(r).fill(v); }
async function tree(full){ const s = await snapshot(page, full?{}:{interactive:true}); return s.tree; }
