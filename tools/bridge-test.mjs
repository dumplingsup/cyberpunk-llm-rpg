import assert from "node:assert/strict";

const URL = process.env.WS_URL || "ws://127.0.0.1:8791/ws";
const ws = new WebSocket(URL);
const pending = new Map();
let streamed = new Map();
let readyResolve;
const ready = new Promise((r) => (readyResolve = r));

ws.addEventListener("open", () => {
  ws.send(JSON.stringify({ type: "hello", campaign: process.env.CAMPAIGN || "test-campaign-1", player: "GHOST" }));
});

ws.addEventListener("message", (ev) => {
  const msg = JSON.parse(ev.data);
  if (msg.type === "ready") {
    console.log("READY", JSON.stringify(msg));
    readyResolve(msg);
    return;
  }
  if (msg.type === "delta") {
    streamed.set(msg.id, (streamed.get(msg.id) || "") + msg.text);
    return;
  }
  if (msg.type === "done" || msg.type === "error") {
    const p = pending.get(msg.id);
    if (p) {
      pending.delete(msg.id);
      p(msg);
    }
  }
});

let seq = 0;
function ask(task, input, opts = {}) {
  return new Promise((resolve) => {
    const id = `t${++seq}`;
    pending.set(id, resolve);
    ws.send(JSON.stringify({ type: "ask", id, task, input, stream: opts.stream ?? true, ...opts }));
  });
}

function waitReady(timeout = 10000) {
  return Promise.race([ready, new Promise((_, rej) => setTimeout(() => rej(new Error("ready timeout")), timeout))]);
}

const t0 = Date.now();
await waitReady();
const state = {
  player: { handle: "GHOST", specialty: "幽灵", day: 1, credits: 900, rep: 12, heat: 1, skills: { intrusion: 4, ew: 2, analysis: 2, nerve: 2 }, gear: [] },
  crew: [],
  chronicle: [],
  fixerTrust: 50,
};

const c = await ask("contracts", { state, count: 3, recentContracts: [] }, { stream: false });
console.log("contracts:", c.ok, c.degraded, c.data?.contracts?.length, (Date.now() - t0) + "ms");
assert.equal(c.data.contracts.length, 3);
console.log("first contract:", c.data.contracts[0].codename, c.data.contracts[0].pay, c.data.contracts[0].twist.slice(0, 30));

const w = await ask("crew", { state: { ...state, contract: c.data.contracts[0] }, count: 3 }, { stream: false });
console.log("crew:", w.ok, w.degraded, w.data?.crew?.map((x) => `${x.name}/${x.role}`).join(", "));
assert.ok(w.data.crew.length >= 2);

const crew = w.data.crew.slice(0, 2);
state.crew = crew;
state.contract = { ...c.data.contracts[0], accepted: true };
const start = await ask("run_start", { state, plan: { approach: "潜入", entry: "维护梯", exit: "后巷", crew, gear: [] } });
console.log("run_start:", start.ok, start.degraded, "narration chars", (start.narration || "").length, "beat", start.data?.beat?.name, "actions", start.data?.beat?.actions?.length, "stream", (streamed.get(`t${seq}`) || "").length);
assert.ok(start.data?.beat?.actions?.length >= 2);

const beat = start.data.beat;
const action = beat.actions[0];
const actorCrew = crew.find((x) => x.id === action.actor) || crew[0];
const check = { actorName: actorCrew.name, skill: action.skill, roll: 7, stat: actorCrew.skills[action.skill] || 3, bonus: 1, total: 11, dc: 9 };
const b2 = await ask("run_beat", {
  state,
  beatIndex: 0,
  beat,
  action,
  check,
  tier: "成功",
  finalBeat: true,
});
console.log("run_beat:", b2.ok, b2.degraded, "narration chars", (b2.narration || "").length, "effects", JSON.stringify(b2.data?.effects), "next", b2.data?.next?.name);
assert.ok((b2.narration || "").length > 20);

const fixer = await ask("dialogue", { state, message: "这单报酬能不能再加点？我最近动静有点大。" }, { stream: true, actor: { kind: "fixer", id: "fixer", persona: { id: "fixer", name: "蜃楼" } } });
console.log("fixer dialogue:", fixer.ok, fixer.degraded, "chars", (fixer.text || "").length, "markers", JSON.stringify(fixer.markers));
assert.ok((fixer.text || "").length > 5);

const crewTalk = await ask("dialogue", { state, message: "铁娘子，明天的活，你有几成把握？" }, { stream: true, actor: { kind: "crew", id: crew[0].id, persona: crew[0] } });
console.log("crew dialogue:", crewTalk.ok, crewTalk.degraded, "chars", (crewTalk.text || "").length, "markers", JSON.stringify(crewTalk.markers));

const settle = await ask("settle", {
  state,
  results: { successes: 3, alarms: 1, pay: state.contract.pay, cuts: crew.reduce((a, x) => a + x.price, 0), net: 700, heat: 2, rep: 3, injuries: [], loot: [], highlights: ["从维护梯进入", "循环了摄像头"] },
});
console.log("settle:", settle.ok, settle.degraded, "narration chars", (settle.narration || "").length, "world", settle.data?.world_change?.slice(0, 40));
assert.ok((settle.narration || "").length > 20);

ws.send(JSON.stringify({ type: "status" }));
await new Promise((r) => setTimeout(r, 300));
ws.close();
console.log("=== ALL BRIDGE TESTS PASSED ===", (Date.now() - t0) + "ms");
