import { pathToFileURL } from "node:url";
import path from "node:path";
import os from "node:os";

const pkgDir = path.join(os.homedir(), "AppData", "Roaming", "npm", "node_modules", "@earendil-works", "pi-coding-agent");
const { createAgentSession, DefaultResourceLoader, getAgentDir, SessionManager } =
  await import(pathToFileURL(path.join(pkgDir, "dist", "index.js")).href);

const GM = `你是《霓虹帷幕 NEON VEIL》的叙事引擎与游戏主持人（GM）。赛博朋克黑客 RPG：玩家是从不露面的黑客，在安全屋远程指挥现场队友、入侵设备、支援行动。玩家永远不出现在现场。
【世界】2087 年垂直都市「澜港」。酸雨、霓虹、义体诊所、数据井。穹顶生物科技（义体/医疗）、沧溟协议（市政/治安 AI）、赤潮（旧城黑帮）、夜航（黑客网络）。中间人「蜃楼 MIRAGE-7」只以加密语音出现。
【语气】冷硬、具体、克制。感官细节：雨声、霓虹反光、义体嗡鸣、旧伤、信号噪声。简体中文。叙事每段 120-220 字。
【硬规则】
- 玩家是唯一决策者，绝不替玩家说话/决定/行动，也不描述玩家没做的事。
- 严格遵守给定的判定数值，不得改变成功或失败。
- 回收之前事件造成的后果（人物、地点、债务、伤疤、仇恨）。
- 技术细节保持虚构氛围化，不写现实可执行的入侵步骤。
- 只按指定格式输出，不解释，不用 markdown 代码块。
【输出协议】需要叙事时，先输出 <<<NARRATION>>> 然后纯文本叙事，再输出 <<<DATA>>> 然后严格 JSON。`;

const CREW = `你在赛博朋克 RPG《霓虹帷幕》中扮演一名现场佣兵「铁娘子 IRONMAIDEN」。玩家是只通过加密语音联系你的黑客雇主，你们从未见过面。
【你的人设】前穹顶生物科技安保主管，四十岁，左臂是旧式工业义体，说话短、硬、护短。你讨厌废话和空头承诺，但对守规矩的雇主有奇特的忠诚。你知道自己被公司抹掉了工号，这件事你从不主动提。
【规则】永远以角色身份用简体中文说话，不要替玩家行动。回复 2-5 句，像真实语音通讯。可以讨价还价、怀疑、开玩笑，但不要跳出角色。若玩家提出的条件涉及具体金额或风险，按人设给出态度。`;

async function make(sys, thinking) {
  const loader = new DefaultResourceLoader({
    cwd: process.cwd(), agentDir: getAgentDir(),
    systemPromptOverride: () => sys, appendSystemPromptOverride: () => [],
  });
  await loader.reload();
  const { session } = await createAgentSession({ resourceLoader: loader, sessionManager: SessionManager.inMemory(), noTools: true, thinkingLevel: thinking });
  return session;
}

async function run(session, prompt, label) {
  let text = "", first = 0;
  const t0 = Date.now();
  const unsub = session.subscribe((ev) => {
    if (ev.type === "message_update" && ev.assistantMessageEvent.type === "text_delta") {
      if (!first) first = Date.now();
      text += ev.assistantMessageEvent.delta;
    }
  });
  await session.prompt(prompt);
  unsub();
  console.log(`\n===== ${label} ===== first=${first - t0}ms total=${Date.now() - t0}ms chars=${text.length}`);
  console.log(text.slice(0, 1600));
  return text;
}

const crew = await make(CREW, "off");
await run(crew, `[通讯] 雇主 GHOST：铁娘子，明天凌晨三点，回澜诊所三楼，离线服务器。你负责进楼，我远程清路。酬劳八百，外加我帮你查一件事。去不去？`, "crew dialogue");

const gm = await make(GM, "off");
const state = `玩家 GHOST｜声望 12｜信用点 900｜热度 1｜团队：铁娘子（忠诚 55，无伤）
委托「静水回廊」：潜入回澜义体诊所三楼机房，拷贝离线服务器镜像并抹日志。报酬 1400，难度中。
现场：铁娘子已从消防梯进入二层。`;
await run(gm, `[TASK: run_beat] 起始节拍，生成行动开场与第一个现场节拍。
${state}
输出：<<<NARRATION>>> 之后 150 字左右开场；<<<DATA>>> 之后严格 JSON：
{"beat":{"name":"接近","situation":"具体处境，60-100字","pressure":"时间/风险压力，一句话","actions":[{"label":"玩家可选动作，10-20字","skill":"stealth|tech|social|combat|nerve","actor":"crew id 或 player","risk":"低|中|高"},{"label":"...","skill":"...","actor":"...","risk":"..."},{"label":"...","skill":"...","actor":"...","risk":"..."}],"support_ops":[{"label":"远程支援动作，10-18字","skill":"intrusion|ew|analysis","cost":1,"hint":"可能的效果"}]},"secret_hint":null}`, "run start");

await run(gm, `[TASK: run_beat] 现场节拍推进。
判定结果：铁娘子 潜行 掷出 7 + 潜行3 + 支援1 = 11，DC 9，结果：成功。
玩家动作：让铁娘子从消防梯绕到机房后门，同时我黑掉走廊摄像头循环播放。
${state}
输出：<<<NARRATION>>> 之后 140-220 字叙事（必须体现判定成功）；<<<DATA>>> 之后严格 JSON：
{"effects":[{"type":"heat","delta":1}],"next":{"name":"渗透","situation":"...","pressure":"...","actions":[...3个...],"support_ops":[...2个...]},"reveal":null,"crew_line":"铁娘子一句短台词"}`,"beat 2");
crew.dispose(); gm.dispose();
