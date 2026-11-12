import { pathToFileURL } from "node:url";
import path from "node:path";
import os from "node:os";

const pkgDir = path.join(os.homedir(), "AppData", "Roaming", "npm", "node_modules", "@earendil-works", "pi-coding-agent");
const { createAgentSession, DefaultResourceLoader, getAgentDir, SessionManager } =
  await import(pathToFileURL(path.join(pkgDir, "dist", "index.js")).href);

const sys = `你是《霓虹帷幕 NEON VEIL》的叙事引擎与游戏主持人（GM）。这是一个赛博朋克黑客 RPG：玩家是一名从不露面的黑客，坐在安全屋的工作台前，通过中间人接活、招募现场队友、远程入侵支援、结算报酬。玩家永远不出现在现场。

【世界】2087 年，垂直都市「澜港」。永不停歇的酸雨，层层叠叠的霓虹招牌，义体诊所与数据井。三大势力：垄断义体与医疗的「穹顶生物科技」；掌管治安与城市 AI 的市政厅「沧溟协议」；盘踞旧城区的黑帮「赤潮」。地下黑客组织「夜航」在暗网里交换情报。中间人「蜃楼 MIRAGE-7」只以加密语音出现，没有人见过其真面目。

【语气】冷硬、具体、克制。用感官细节写赛博朋克：雨声、霓虹反光、义体的嗡鸣、旧伤、信号噪声。每段不超过 200 字。全部用简体中文。

【硬规则】
- 玩家是唯一决策者。绝不替玩家说话、决定或行动。
- 严格遵守给定的数值与判定结果，不得自行改变成功或失败。
- 记住之前事件造成的后果，并在新内容中自然回收（人物、地点、债务、伤疤、仇恨）。
- 技术描写保持虚构与氛围化，不输出现实世界可执行的入侵步骤。
- 只输出要求的格式，不解释，不加 markdown 代码块。`;

const loader = new DefaultResourceLoader({
  cwd: process.cwd(),
  agentDir: getAgentDir(),
  systemPromptOverride: () => sys,
  appendSystemPromptOverride: () => [],
});
await loader.reload();
const t0 = Date.now();
const { session } = await createAgentSession({
  resourceLoader: loader,
  sessionManager: SessionManager.inMemory(),
  noTools: true,
  thinkingLevel: "low",
});
console.log("session", Date.now() - t0, "ms");

const prompt = `[TASK: contracts]
生成 3 份新的中间人（蜃楼）委托，供玩家选择。玩家代号 GHOST，声望 12（新人），信用点 900，通缉热度 1，第 1 天，没有前科。
输出严格 JSON：
{"contracts":[{"codename":"行动代号","client":"雇主/中间人转述","target":"目标","objective":"一句话目标","location":"澜港的具体地点","pay":1200,"advance":0,"risk":"低|中|高","heat":1,"tags":["2-3个短标签"],"brief":"给玩家的加密委托文本，80-140字，有画面感","hook":"一句吸引人的话","twist":"隐藏转折，玩家暂时看不到，一句话"}]}
要求：金额 800-4000；三份委托的难度与风格要有差异（潜入/社交/破坏各一倾向）；twist 必须具体、可被后续剧情回收；不要 markdown。`;

let text = "";
let first = 0;
session.subscribe((ev) => {
  if (ev.type === "message_update" && ev.assistantMessageEvent.type === "text_delta") {
    if (!first) first = Date.now();
    text += ev.assistantMessageEvent.delta;
  }
});
await session.prompt(prompt);
const t1 = Date.now();
console.log("first token", first - t0, "ms; total", t1 - t0, "ms; chars", text.length);
console.log("=== RAW ===\n" + text);
try {
  const obj = JSON.parse(text.trim());
  console.log("=== PARSED OK ===", obj.contracts.length);
  console.log(JSON.stringify(obj.contracts[0], null, 2));
} catch (e) {
  console.log("=== PARSE FAIL ===", e.message);
}
session.dispose();
