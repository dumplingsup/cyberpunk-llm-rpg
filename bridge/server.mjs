import http from "node:http";
import fs from "node:fs";
import path from "node:path";
import crypto from "node:crypto";
import { HOST, PORT, DEFAULT_MODEL, PI_VERSION, LOG_DIR, TASK_TIMEOUT_MS, THINKING } from "./config.mjs";
import { attachWebSocketServer } from "./ws.mjs";
import { newCampaign } from "./pi.mjs";
import { buildPrompt, GM_SYSTEM, fixerSystem, crewSystem } from "./prompts.mjs";
import {
  parseJsonLoose,
  parseTagged,
  parseMarkers,
  normalizeContracts,
  normalizeCrew,
  normalizeBeat,
  normalizeEffects,
  normalizeSettleData,
  normalizeEvent,
  normalizeAudit,
} from "./parse.mjs";
import { mockTask } from "./mock.mjs";

const TASKS = new Set(["contracts", "crew", "run_start", "run_beat", "settle", "plan_audit", "event", "recruit", "dialogue"]);
const STREAM_TASKS = new Set(["dialogue", "recruit", "run_start", "run_beat", "settle"]);
const RUN_TASKS = new Set(["run_start", "run_beat", "settle"]);

const campaigns = new Map();
const clients = new Set();
const runtime = {
  mode: process.env.BRIDGE_MODE === "mock" ? "mock" : "real",
  model: DEFAULT_MODEL,
  startedAt: Date.now(),
  requests: 0,
  realCalls: 0,
  mockCalls: 0,
  fallbacks: 0,
  errors: 0,
  lastError: null,
  failureStreak: 0,
  degradedUntil: 0,
};

class PartialError extends Error {
  constructor(message, partial) {
    super(message);
    this.partial = partial;
  }
}

function nowIso() {
  return new Date().toISOString();
}

function logFile() {
  const d = new Date();
  const name = `bridge-${d.getFullYear()}${String(d.getMonth() + 1).padStart(2, "0")}${String(d.getDate()).padStart(2, "0")}.log`;
  return path.join(LOG_DIR, name);
}

function log(level, msg) {
  const line = `${nowIso()} [${level}] ${msg}`;
  console.log(line);
  try {
    fs.appendFileSync(logFile(), line + "\n", "utf8");
  } catch {
    /* ignore */
  }
}

function evidence(record) {
  try {
    const d = new Date();
    const name = `llm-${d.getFullYear()}${String(d.getMonth() + 1).padStart(2, "0")}${String(d.getDate()).padStart(2, "0")}.jsonl`;
    fs.appendFileSync(path.join(LOG_DIR, name), JSON.stringify({ ts: nowIso(), ...record }) + "\n", "utf8");
  } catch {
    /* ignore */
  }
}

function send(conn, obj) {
  try {
    conn.send(obj);
  } catch {
    /* client gone */
  }
}

function broadcast(obj) {
  for (const c of clients) send(c, obj);
}

function sanitizeInput(input, task) {
  const safe = input && typeof input === "object" ? input : {};
  if (typeof safe.message === "string") safe.message = safe.message.slice(0, 2000);
  if (typeof safe.freeText === "string") safe.freeText = safe.freeText.slice(0, 600);
  if (safe.state && typeof safe.state === "object") {
    const st = safe.state;
    if (Array.isArray(st.chronicle)) st.chronicle = st.chronicle.slice(-14).map((x) => String(x).slice(0, 240));
    if (Array.isArray(st.crew)) st.crew = st.crew.slice(0, 6);
    if (Array.isArray(st.flags)) st.flags = st.flags.slice(-14).map((x) => String(x).slice(0, 60));
  }
  return safe;
}

function crewIdsOf(input) {
  return (input.state?.crew || []).map((c) => c.id).filter(Boolean);
}

function capDeals(markers, state) {
  const contract = state.contract || {};
  const pay = Number(contract.pay) || 1000;
  for (const deal of markers.deals || []) {
    if (deal.pay != null) deal.pay = Math.max(0, Math.min(Math.ceil(pay * 0.2), Math.abs(Math.round(deal.pay))));
    if (deal.advance != null) deal.advance = Math.max(0, Math.min(Math.floor(pay * 0.3), Math.abs(Math.round(deal.advance))));
    if (deal.cut != null) deal.cut = Math.max(50, Math.min(900, Math.abs(Math.round(deal.cut))));
    if (deal.heat != null) deal.heat = Math.max(-2, Math.min(2, Math.round(deal.heat)));
  }
  return markers;
}

function parseForTask(task, text) {
  if (task === "dialogue" || task === "recruit") {
    const { text: clean, markers } = parseMarkers(text);
    if (!clean.trim()) throw new Error("对话内容为空");
    return { text: clean, markers };
  }
  if (RUN_TASKS.has(task)) {
    const tagged = parseTagged(text);
    return { narration: tagged.narration, data: tagged.data, markers: null };
  }
  return { data: parseJsonLoose(text), narration: "", markers: null };
}

function normalizeResponse(task, raw, input) {
  const crewIds = crewIdsOf(input);
  switch (task) {
    case "contracts": {
      const list = normalizeContracts(raw.data, input.count || 3);
      if (!list.length) throw new Error("委托 JSON 解析失败");
      return { data: { contracts: list } };
    }
    case "crew": {
      const existing = (input.state?.crew || []).map((c) => c.handle);
      const list = normalizeCrew(raw.data, input.count || 3, existing);
      if (!list.length) throw new Error("佣兵 JSON 解析失败");
      return { data: { crew: list } };
    }
    case "run_start": {
      const beat = normalizeBeat(raw.data?.beat, crewIds, 0);
      if (!beat) throw new PartialError("开场节拍解析失败", raw);
      return {
        narration: raw.narration || beat.situation,
        data: { beat, secret_hint: typeof raw.data?.secret_hint === "string" ? raw.data.secret_hint.slice(0, 160) : null },
      };
    }
    case "run_beat": {
      const index = Number(input.beatIndex) || 0;
      const finalBeat = !!input.finalBeat;
      const effects = normalizeEffects(raw.data?.effects, crewIds);
      let next = null;
      if (!finalBeat) {
        next = normalizeBeat(raw.data?.next, crewIds, index + 1);
        if (!next) throw new PartialError("下一节拍解析失败", raw);
      }
      if (!raw.narration) throw new PartialError("叙事为空", raw);
      return {
        narration: raw.narration,
        data: {
          effects,
          next,
          reveal: typeof raw.data?.reveal === "string" ? raw.data.reveal.slice(0, 200) : null,
          crew_line: typeof raw.data?.crew_line === "string" ? raw.data.crew_line.slice(0, 120) : null,
          alarm: Math.max(0, Math.min(1, Math.round(Number(raw.data?.alarm) || 0))),
        },
      };
    }
    case "settle": {
      const data = normalizeSettleData(raw.data, crewIds);
      if (!data) throw new PartialError("结算解析失败", raw);
      if (!raw.narration) throw new PartialError("收尾叙事为空", raw);
      return { narration: raw.narration, data };
    }
    case "event": {
      const data = normalizeEvent(raw.data);
      if (!data) throw new Error("事件 JSON 解析失败");
      return { data };
    }
    case "plan_audit": {
      const data = normalizeAudit(raw.data);
      if (!data) throw new Error("评估 JSON 解析失败");
      return { data };
    }
    case "dialogue":
    case "recruit":
      return { text: raw.text, markers: capDeals(raw.markers || {}, input.state || {}) };
    default:
      throw new Error(`未知任务 ${task}`);
  }
}

function mockResponse(task, input, actorKind, persona) {
  const m = mockTask(task, { ...input, actorKind, actor: persona }, { campaign: input.campaign });
  if (task === "dialogue" || task === "recruit") {
    return { text: m.text || "……", markers: capDeals(m.markers || {}, input.state || {}) };
  }
  const normalized = normalizeResponse(task, { narration: m.narration, data: m.data }, input);
  return normalized;
}

function failureShouldOpenCircuit() {
  runtime.failureStreak += 1;
  if (runtime.failureStreak >= 2) {
    runtime.degradedUntil = Date.now() + 90_000;
    log("warn", `连续失败 ${runtime.failureStreak} 次，90 秒内使用本地叙事引擎`);
  }
}

function circuitOpen() {
  return runtime.mode === "mock" || Date.now() < runtime.degradedUntil;
}

function actorSpecFor(task, msg) {
  if (task === "dialogue" || task === "recruit") {
    const a = msg.actor || msg.input?.actor || {};
    const kind = a.kind === "fixer" ? "fixer" : "crew";
    const persona = a.persona || (task === "recruit" ? msg.input?.crew : null) || {};
    const id = String(a.id || persona.id || (kind === "fixer" ? "fixer" : "crew_unknown"));
    if (kind === "fixer") return { id, kind, persona: null, system: fixerSystem() };
    return { id, kind, persona, system: crewSystem(persona) };
  }
  return { id: "gm", kind: "gm", persona: null, system: GM_SYSTEM };
}

class NarrationStream {
  constructor(emit) {
    this.emit = emit;
    this.buf = "";
    this.mode = "pre";
  }

  push(chunk) {
    this.buf += chunk;
    if (this.mode === "pre") {
      const i = this.buf.indexOf("<<<NARRATION>>>");
      if (i >= 0) {
        this.buf = this.buf.slice(i + 15);
        this.mode = "narration";
      } else {
        if (this.buf.length > 600) this.buf = this.buf.slice(-60);
        return;
      }
    }
    const d = this.buf.indexOf("<<<DATA>>>");
    if (d >= 0) {
      if (d > 0) this.emit(this.buf.slice(0, d));
      this.buf = "";
      this.mode = "done";
      return;
    }
    const safe = this.buf.length - 12;
    if (safe > 0) {
      this.emit(this.buf.slice(0, safe));
      this.buf = this.buf.slice(safe);
    }
  }

  flush() {
    if (this.mode === "narration" && this.buf.trim()) {
      this.emit(this.buf.replace(/<<<DATA>>>/g, ""));
    }
    this.buf = "";
  }
}

class PlainStream {
  constructor(emit) {
    this.emit = emit;
    this.buf = "";
  }

  push(chunk) {
    this.buf += chunk;
    // Hold back only from the last possible marker opener, so normal prose
    // streams immediately while [DEAL: ...]/[BOND: ...] never flashes in the UI.
    const bracket = Math.max(this.buf.lastIndexOf("["), this.buf.lastIndexOf("【"));
    const safe = bracket >= 0 ? bracket : this.buf.length;
    if (safe > 0) {
      this.emit(this.buf.slice(0, safe));
      this.buf = this.buf.slice(safe);
    }
  }

  flush() {
    this.buf = "";
  }
}

async function handleAsk(conn, msg) {
  const id = String(msg.id || crypto.randomUUID());
  const task = String(msg.task || "");
  if (!TASKS.has(task)) {
    send(conn, { type: "error", id, message: `未知任务: ${task}` });
    return;
  }
  const ctx = conn.campaign;
  if (!ctx) {
    send(conn, { type: "error", id, message: "尚未 hello，无法生成内容" });
    return;
  }
  const input = sanitizeInput(msg.input, task);
  input.campaign = ctx.id;
  const stream = STREAM_TASKS.has(task) && msg.stream !== false;
  const allowFallback = msg.fallback !== false;
  const spec = actorSpecFor(task, msg);
  const startedAt = Date.now();
  runtime.requests += 1;

  let streamer = null;
  if (stream) {
    streamer = RUN_TASKS.has(task) ? new NarrationStream((chunk) => send(conn, { type: "delta", id, text: chunk })) : new PlainStream((chunk) => send(conn, { type: "delta", id, text: chunk }));
  }

  send(conn, { type: "accepted", id, task });

  const runMock = (reason) => {
    const m = mockResponse(task, input, spec.kind, spec.persona);
    runtime.mockCalls += 1;
    runtime.fallbacks += 1;
    const result = {
      type: "done",
      id,
      task,
      ok: true,
      degraded: true,
      fallbackReason: reason,
      ms: Date.now() - startedAt,
      ...m,
    };
    if (streamer) streamer.flush();
    send(conn, result);
    log("warn", `任务 ${task} 使用本地叙事引擎: ${reason}`);
  };

  if (circuitOpen()) {
    runMock(runtime.mode === "mock" ? "bridge 处于 mock 模式" : "模型链路暂时降级");
    return;
  }

  try {
    const promptText = buildPrompt(task, input);
    const actor = await ctx.ensureActor({
      id: spec.id,
      kind: spec.kind,
      systemPrompt: spec.system,
      persona: spec.persona,
    });
    if (spec.kind === "gm" && actor.session?.model?.id) runtime.model = actor.session.model.id;
    runtime.realCalls += 1;
    const res = await actor.ask(promptText, {
      onDelta: streamer ? (chunk) => streamer.push(chunk) : null,
      thinking: THINKING[task] || "off",
      timeoutMs: Math.max(30000, Math.min(TASK_TIMEOUT_MS, Number(msg.timeoutMs) || TASK_TIMEOUT_MS)),
    });
    if (streamer) streamer.flush();
    const parsed = parseForTask(task, res.text);
    const normalized = normalizeResponse(task, parsed, input);
    runtime.failureStreak = 0;
    evidence({
      campaign: ctx.id,
      task,
      actor: `${spec.kind}:${spec.id}`,
      promptChars: promptText.length,
      response: res.text.slice(0, 6000),
      ms: res.ms,
      usage: res.usage,
      degraded: false,
    });
    send(conn, {
      type: "done",
      id,
      task,
      ok: true,
      degraded: false,
      ms: Date.now() - startedAt,
      usage: res.usage,
      ...normalized,
    });
    log("info", `任务 ${task} 完成 ${Date.now() - startedAt}ms chars=${res.text.length}`);
  } catch (err) {
    runtime.errors += 1;
    runtime.lastError = err?.message || String(err);
    log("error", `任务 ${task} 失败: ${runtime.lastError}`);
    if (err instanceof PartialError && err.partial) {
      // Keep the streamed narration; fill the missing mechanics from the offline engine.
      try {
        const m = mockResponse(task, input, spec.kind, spec.persona);
        runtime.fallbacks += 1;
        send(conn, {
          type: "done",
          id,
          task,
          ok: true,
          degraded: true,
          fallbackReason: `数据解析失败，已使用本地结算：${err.message}`,
          ms: Date.now() - startedAt,
          narration: err.partial.narration || m.narration || "",
          data: m.data,
          text: undefined,
          usage: null,
        });
        if (streamer) streamer.flush();
        return;
      } catch (inner) {
        log("error", `本地回退也失败: ${inner.message}`);
      }
    }
    failureShouldOpenCircuit();
    if (!allowFallback) {
      if (streamer) streamer.flush();
      send(conn, { type: "error", id, task, message: runtime.lastError, retryable: true });
      return;
    }
    runMock(runtime.lastError);
  }
}

async function handleHello(conn, msg) {
  const campaignId = String(msg.campaign || "default").slice(0, 64);
  let ctx = campaigns.get(campaignId);
  if (!ctx) {
    ctx = newCampaign({ id: campaignId, player: msg.player, log });
    campaigns.set(campaignId, ctx);
    log("info", `建立战役 ${campaignId} player=${msg.player || "GHOST"}`);
  }
  conn.campaign = ctx;
  send(conn, {
    type: "ready",
    campaign: ctx.id,
    mode: runtime.mode,
    model: runtime.model,
    pi: { version: PI_VERSION, sdk: "@earendil-works/pi-coding-agent" },
    host: HOST,
    port: PORT,
    degradedUntil: runtime.degradedUntil,
  });
  const gm = ctx.actors.get("gm:gm");
  if (gm?.session?.model?.id) {
    runtime.model = gm.session.model.id;
    send(conn, { type: "model", model: runtime.model });
  }
}

async function handleReset(conn, msg) {
  const ctx = conn.campaign;
  if (!ctx) {
    send(conn, { type: "error", message: "没有活动战役" });
    return;
  }
  await ctx.reset();
  campaigns.delete(ctx.id);
  conn.campaign = null;
  send(conn, { type: "reset_ok", campaign: ctx.id });
  log("info", `战役 ${ctx.id} 已重置，会话与记忆已清除`);
}

async function handleMessage(conn, msg) {
  const type = String(msg?.type || "");
  switch (type) {
    case "hello":
      await handleHello(conn, msg);
      break;
    case "ask":
      await handleAsk(conn, msg);
      break;
    case "abort": {
      const ctx = conn.campaign;
      if (!ctx) break;
      const a = msg.actor || {};
      const key = `${a.kind || "gm"}:${a.id || "gm"}`;
      const actor = ctx.actors.get(key);
      if (actor?.session) {
        try {
          await actor.session.abort();
        } catch {
          /* ignore */
        }
      }
      send(conn, { type: "aborted", id: msg.id, actor: key });
      break;
    }
    case "status": {
      const ctx = conn.campaign;
      send(conn, {
        type: "status",
        data: {
          mode: runtime.mode,
          model: runtime.model,
          piVersion: PI_VERSION,
          uptimeSec: Math.round((Date.now() - runtime.startedAt) / 1000),
          requests: runtime.requests,
          realCalls: runtime.realCalls,
          mockCalls: runtime.mockCalls,
          fallbacks: runtime.fallbacks,
          errors: runtime.errors,
          lastError: runtime.lastError,
          failureStreak: runtime.failureStreak,
          degradedUntil: runtime.degradedUntil,
          campaign: ctx?.stats() ?? null,
        },
      });
      break;
    }
    case "set_mode": {
      const m = msg.mode === "mock" ? "mock" : "real";
      runtime.mode = m;
      runtime.failureStreak = 0;
      runtime.degradedUntil = 0;
      send(conn, { type: "mode_ok", mode: m });
      log("info", `模式切换为 ${m}`);
      break;
    }
    case "reset":
      await handleReset(conn, msg);
      break;
    case "ping":
      send(conn, { type: "pong", t: msg.t ?? Date.now() });
      break;
    default:
      send(conn, { type: "error", message: `未知消息类型: ${type}` });
  }
}

const server = http.createServer((req, res) => {
  if (req.url === "/health" || req.url === "/") {
    const body = {
      ok: true,
      name: "NEON VEIL bridge",
      mode: runtime.mode,
      model: runtime.model,
      piVersion: PI_VERSION,
      uptimeSec: Math.round((Date.now() - runtime.startedAt) / 1000),
      campaigns: [...campaigns.keys()],
      requests: runtime.requests,
      fallbacks: runtime.fallbacks,
      errors: runtime.errors,
      ws: `ws://${HOST}:${PORT}/ws`,
    };
    res.writeHead(200, { "Content-Type": "application/json; charset=utf-8" });
    res.end(JSON.stringify(body, null, 2));
    return;
  }
  res.writeHead(404, { "Content-Type": "text/plain; charset=utf-8" });
  res.end("not found");
});

attachWebSocketServer(server, (conn) => {
  clients.add(conn);
  log("info", "Godot 客户端已连接");
  let alive = true;
  const heartbeat = setInterval(() => {
    if (!alive) {
      clearInterval(heartbeat);
      return;
    }
    alive = false;
    try {
      conn._sendFrame(0x9, Buffer.from("hb"));
    } catch {
      /* ignore */
    }
  }, 25000);
  conn.on("message", (raw) => {
    alive = true;
    let msg;
    try {
      msg = JSON.parse(raw);
    } catch {
      send(conn, { type: "error", message: "JSON 解析失败" });
      return;
    }
    handleMessage(conn, msg).catch((err) => {
      log("error", `处理消息失败: ${err.stack || err.message}`);
      send(conn, { type: "error", message: err.message });
    });
  });
  conn.on("close", () => {
    clearInterval(heartbeat);
    clients.delete(conn);
    log("info", "Godot 客户端断开");
  });
  conn.on("error", (err) => log("warn", `WebSocket 错误: ${err.message}`));
});

server.listen(PORT, HOST, () => {
  log("info", `NEON VEIL bridge 已启动 http://${HOST}:${PORT}  ws://${HOST}:${PORT}/ws`);
  log("info", `Pi ${PI_VERSION}｜模型 ${DEFAULT_MODEL}｜模式 ${runtime.mode}`);
});

async function shutdown(signal) {
  log("info", `收到 ${signal}，正在关闭…`);
  for (const conn of clients) {
    try {
      conn.close(1001, "bridge shutdown");
    } catch {
      /* ignore */
    }
  }
  for (const ctx of campaigns.values()) await ctx.reset().catch(() => {});
  server.close(() => process.exit(0));
  setTimeout(() => process.exit(0), 1500);
}

process.on("SIGINT", () => shutdown("SIGINT"));
process.on("SIGTERM", () => shutdown("SIGTERM"));
