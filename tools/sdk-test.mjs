import { pathToFileURL } from "node:url";
import path from "node:path";
import os from "node:os";

const pkgDir = path.join(os.homedir(), "AppData", "Roaming", "npm", "node_modules", "@earendil-works", "pi-coding-agent");
const mod = await import(pathToFileURL(path.join(pkgDir, "dist", "index.js")).href);
const {
  createAgentSession,
  DefaultResourceLoader,
  getAgentDir,
  SessionManager,
} = mod;
console.log("exports ok:", typeof createAgentSession, typeof SessionManager);

async function makeSession(systemPrompt) {
  const loader = new DefaultResourceLoader({
    cwd: process.cwd(),
    agentDir: getAgentDir(),
    systemPromptOverride: () => systemPrompt,
    appendSystemPromptOverride: () => [],
  });
  await loader.reload();
  const { session } = await createAgentSession({
    resourceLoader: loader,
    sessionManager: SessionManager.inMemory(),
    noTools: true,
    thinkingLevel: "off",
  });
  return session;
}

const t0 = Date.now();
const s1 = await makeSession("你是一个赛博朋克中间人，语气冷漠、简短。只输出一句中文台词。");
console.log("session1 ready in", Date.now() - t0, "ms; model:", s1.model?.id, "thinking:", s1.thinkingLevel);

let first = 0;
s1.subscribe((ev) => {
  if (ev.type === "message_update" && ev.assistantMessageEvent.type === "text_delta") {
    if (!first) first = Date.now();
    process.stdout.write(ev.assistantMessageEvent.delta);
  }
});
await s1.prompt("向一个刚上线的新手黑客打招呼。");
console.log("\nfirst token", first - t0, "ms; total", Date.now() - t0, "ms");

const s2 = await makeSession("你是一个暴躁的街头佣兵，说话粗鲁。只输出一句中文台词。");
s2.subscribe((ev) => {
  if (ev.type === "message_update" && ev.assistantMessageEvent.type === "text_delta") {
    process.stdout.write(ev.assistantMessageEvent.delta);
  }
});
console.log("\n[second session]");
await s2.prompt("有人想雇你去偷某个公司的数据，你怎么回答？");
console.log();
s1.dispose();
s2.dispose();
