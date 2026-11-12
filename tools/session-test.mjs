import { pathToFileURL } from "node:url";
import path from "node:path";
import fs from "node:fs";
import os from "node:os";

const pkgDir = path.join(os.homedir(), "AppData", "Roaming", "npm", "node_modules", "@earendil-works", "pi-coding-agent");
const mod = await import(pathToFileURL(path.join(pkgDir, "dist", "index.js")).href);
const { createAgentSession, DefaultResourceLoader, getAgentDir, SessionManager } = mod;

const dir = path.join(process.cwd(), "bridge", "sessions", "test-campaign");
fs.mkdirSync(dir, { recursive: true });

async function make(manager) {
  const loader = new DefaultResourceLoader({
    cwd: process.cwd(), agentDir: getAgentDir(),
    systemPromptOverride: () => "你是一名沉默寡言的佣兵，回答极短。",
    appendSystemPromptOverride: () => [],
  });
  await loader.reload();
  return (await createAgentSession({ resourceLoader: loader, sessionManager: manager, noTools: true, thinkingLevel: "off" })).session;
}

const s1 = await make(SessionManager.create(process.cwd(), dir));
console.log("sessionFile:", s1.sessionFile, "exists:", fs.existsSync(s1.sessionFile ?? ""));
await s1.prompt("记住：我的代号是 GHOST，我欠你一条命。");
console.log("reply1:", s1.getLastAssistantText());
const file = s1.sessionFile;
s1.dispose();

const s2 = await make(SessionManager.open(file));
await s2.prompt("我的代号是什么？我欠你什么？只回答这两个信息。");
console.log("reply2:", s2.getLastAssistantText());
console.log("abort fn:", typeof s2.abort, "messages:", s2.messages?.length);
s2.dispose();
