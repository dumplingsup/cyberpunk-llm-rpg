import path from "node:path";
import os from "node:os";
import { fileURLToPath, pathToFileURL } from "node:url";
import fs from "node:fs";
import { execFileSync } from "node:child_process";

export const BRIDGE_ROOT = path.dirname(fileURLToPath(import.meta.url));
export const PORT = Number(process.env.BRIDGE_PORT || 8791);
export const HOST = process.env.BRIDGE_HOST || "127.0.0.1";
export const CAMPAIGN_ROOT = path.join(BRIDGE_ROOT, "sessions");
export const LOG_DIR = path.join(BRIDGE_ROOT, "logs");
export const DEFAULT_MODEL = process.env.PI_MODEL || "deepseek-flash";

function findPiPackage() {
  const candidates = [];
  if (process.env.PI_AGENT_PACKAGE) candidates.push(process.env.PI_AGENT_PACKAGE);
  candidates.push(path.join(os.homedir(), "AppData", "Roaming", "npm", "node_modules", "@earendil-works", "pi-coding-agent"));
  candidates.push(path.join(os.homedir(), ".npm-global", "lib", "node_modules", "@earendil-works", "pi-coding-agent"));
  try {
    const root = execFileSync(process.platform === "win32" ? "npm.cmd" : "npm", ["root", "-g"], {
      encoding: "utf8",
      timeout: 15000,
      windowsHide: true,
    }).trim();
    if (root) candidates.push(path.join(root, "@earendil-works", "pi-coding-agent"));
  } catch {
    /* ignore */
  }
  for (const c of candidates) {
    if (c && fs.existsSync(path.join(c, "dist", "index.js"))) return c;
  }
  throw new Error("找不到本地 Pi agent（@earendil-works/pi-coding-agent）。请先安装 pi 或设置 PI_AGENT_PACKAGE。");
}

export const PI_PACKAGE_DIR = findPiPackage();
export const PI_ENTRY = path.join(PI_PACKAGE_DIR, "dist", "index.js");
export const PI_VERSION = JSON.parse(fs.readFileSync(path.join(PI_PACKAGE_DIR, "package.json"), "utf8")).version;

let sdkPromise = null;
export function loadPiSdk() {
  if (!sdkPromise) sdkPromise = import(pathToFileURL(PI_ENTRY).href);
  return sdkPromise;
}

export const THINKING = {
  contracts: process.env.PI_THINK_CONTRACTS || "low",
  crew: process.env.PI_THINK_CREW || "low",
  dialogue: process.env.PI_THINK_DIALOGUE || "off",
  run_start: process.env.PI_THINK_RUN || "off",
  run_beat: process.env.PI_THINK_RUN || "off",
  settle: process.env.PI_THINK_SETTLE || "low",
  event: process.env.PI_THINK_EVENT || "off",
  plan_audit: process.env.PI_THINK_PLAN || "low",
  recruit: process.env.PI_THINK_DIALOGUE || "off",
};

export const TASK_TIMEOUT_MS = Number(process.env.PI_TIMEOUT_MS || 150000);

fs.mkdirSync(CAMPAIGN_ROOT, { recursive: true });
fs.mkdirSync(LOG_DIR, { recursive: true });
