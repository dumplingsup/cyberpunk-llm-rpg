import fs from "node:fs";
import path from "node:path";
import crypto from "node:crypto";
import { CAMPAIGN_ROOT, THINKING, TASK_TIMEOUT_MS, loadPiSdk } from "./config.mjs";

let sdk = null;
async function getSdk() {
  if (!sdk) sdk = await loadPiSdk();
  return sdk;
}

function sanitizeId(id) {
  return String(id || "actor").replace(/[^a-zA-Z0-9_-]/g, "_").slice(0, 64);
}

function readJson(file, fallback) {
  try {
    return JSON.parse(fs.readFileSync(file, "utf8"));
  } catch {
    return fallback;
  }
}

function writeJson(file, data) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, JSON.stringify(data, null, 2), "utf8");
}

function extractAssistantText(message) {
  if (!message || message.role !== "assistant") return null;
  const content = message.content;
  if (typeof content === "string") return content;
  if (!Array.isArray(content)) return null;
  return content
    .filter((block) => block && block.type === "text")
    .map((block) => block.text)
    .join("");
}

export class Actor {
  constructor(ctx, { id, kind, systemPrompt, personaHash }) {
    this.ctx = ctx;
    this.id = id;
    this.kind = kind;
    this.systemPrompt = systemPrompt;
    this.personaHash = personaHash;
    this.session = null;
    this.queue = Promise.resolve();
    this.lastError = null;
    this.lastUsed = Date.now();
    this.stats = { calls: 0, inputTokens: 0, outputTokens: 0 };
  }

  async init() {
    if (this.session) return this.session;
    const { createAgentSession, DefaultResourceLoader, getAgentDir, SessionManager } = await getSdk();
    const dir = this.ctx.sessionsDir;
    fs.mkdirSync(dir, { recursive: true });
    const indexFile = path.join(dir, "index.json");
    const index = readJson(indexFile, {});
    const key = `${this.kind}:${this.id}`;
    let manager = null;
    const existing = index[key];
    if (existing && fs.existsSync(existing.file)) {
      try {
        manager = SessionManager.open(existing.file);
      } catch (err) {
        this.ctx.log("warn", `打开旧会话失败 ${key}: ${err.message}`);
        manager = null;
      }
    }
    if (!manager) {
      manager = SessionManager.create(this.ctx.cwd, dir);
    }

    const loader = new DefaultResourceLoader({
      cwd: this.ctx.cwd,
      agentDir: getAgentDir(),
      systemPromptOverride: () => this.systemPrompt,
      appendSystemPromptOverride: () => [],
    });
    await loader.reload();

    const result = await createAgentSession({
      resourceLoader: loader,
      sessionManager: manager,
      noTools: true,
      thinkingLevel: THINKING.dialogue || "off",
    });
    this.session = result.session;
    if (result.modelFallbackMessage) this.ctx.log("warn", `模型回退: ${result.modelFallbackMessage}`);
    const file = this.session.sessionFile;
    if (file) {
      index[key] = { file, updatedAt: new Date().toISOString(), kind: this.kind, id: this.id };
      writeJson(indexFile, index);
    }
    this.ctx.log("info", `actor ready ${key} model=${this.session.model?.id ?? "?"} session=${file ? path.basename(file) : "(none)"}`);
    return this.session;
  }

  _run(text, { onDelta, thinking, timeoutMs }) {
    return new Promise((resolve, reject) => {
      let settled = false;
      let finalText = null;
      let streamed = "";
      let usage = null;
      let timer = null;
      let unsubscribe = null;

      const finish = (err) => {
        if (settled) return;
        settled = true;
        if (timer) clearTimeout(timer);
        if (unsubscribe) {
          try {
            unsubscribe();
          } catch {
            /* ignore */
          }
        }
        if (err) reject(err);
        else resolve({ text: finalText ?? streamed, streamed, usage });
      };

      try {
        this.session.setThinkingLevel(thinking || THINKING.dialogue || "off");
      } catch {
        /* model may not support thinking; ignore */
      }

      unsubscribe = this.session.subscribe((event) => {
        if (event.type === "message_update" && event.assistantMessageEvent?.type === "text_delta") {
          const delta = event.assistantMessageEvent.delta || "";
          streamed += delta;
          if (onDelta) {
            try {
              onDelta(delta);
            } catch {
              /* client gone */
            }
          }
        } else if (event.type === "message_end" && event.message?.role === "assistant") {
          const text = extractAssistantText(event.message);
          if (text != null) finalText = text;
          if (event.message?.usage) usage = event.message.usage;
        } else if (event.type === "auto_retry_start") {
          this.ctx.log("warn", `actor ${this.id} 自动重试 ${event.attempt}/${event.maxAttempts}: ${event.errorMessage}`);
        } else if (event.type === "compaction_start") {
          this.ctx.log("info", `actor ${this.id} 压缩上下文: ${event.reason}`);
        }
      });

      timer = setTimeout(async () => {
        this.lastError = `timeout after ${timeoutMs}ms`;
        try {
          await this.session.abort();
        } catch {
          /* ignore */
        }
        finish(new Error(`LLM 响应超时（${Math.round(timeoutMs / 1000)}s）`));
      }, timeoutMs || TASK_TIMEOUT_MS);

      this.session.prompt(text).then(
        () => {
          const textOut = finalText ?? streamed;
          if (!textOut || !String(textOut).trim()) {
            finish(new Error("LLM 返回为空"));
            return;
          }
          finish(null);
        },
        (err) => {
          this.lastError = err?.message || String(err);
          finish(new Error(this.lastError));
        },
      );
    });
  }

  ask(text, opts = {}) {
    this.queue = this.queue.then(
      () => this._askInner(text, opts),
      () => this._askInner(text, opts),
    );
    return this.queue;
  }

  async _askInner(text, opts = {}) {
    this.lastUsed = Date.now();
    await this.init();
    if (this.session.isStreaming) {
      try {
        await this.session.waitForIdle();
      } catch {
        /* ignore */
      }
    }
    const started = Date.now();
    try {
      const result = await this._run(text, opts);
      this.stats.calls += 1;
      if (result.usage) {
        this.stats.inputTokens += result.usage.input || 0;
        this.stats.outputTokens += result.usage.output || 0;
      }
      return { ...result, ms: Date.now() - started };
    } catch (err) {
      this.stats.calls += 1;
      throw err;
    }
  }

  async reset() {
    if (this.session) {
      try {
        this.session.dispose();
      } catch {
        /* ignore */
      }
      this.session = null;
    }
  }

  async dispose() {
    await this.reset();
  }
}

export class CampaignContext {
  constructor({ id, player, log }) {
    this.id = sanitizeId(id || "campaign");
    this.player = player || "GHOST";
    this.cwd = CAMPAIGN_ROOT;
    this.sessionsDir = path.join(CAMPAIGN_ROOT, this.id);
    this.log = log || (() => {});
    this.actors = new Map();
    this.createdAt = Date.now();
  }

  actorKey(actorId, kind) {
    return `${kind}:${actorId}`;
  }

  async ensureActor({ id, kind, systemPrompt, persona }) {
    const key = `${kind}:${id}`;
    const stablePersona = persona
      ? {
          name: persona.name,
          handle: persona.handle,
          role: persona.role,
          origin: persona.origin,
          look: persona.look,
          voice: persona.voice,
          personality: persona.personality,
          quirk: persona.quirk,
          like: persona.like,
          dislike: persona.dislike,
          perk: persona.perk,
          secret: persona.secret,
          skills: persona.skills,
        }
      : null;
    const personaHash = stablePersona ? crypto.createHash("sha1").update(JSON.stringify(stablePersona)).digest("hex") : "none";
    const existing = this.actors.get(key);
    if (existing && existing.personaHash === personaHash) return existing;
    if (existing) await existing.dispose();
    const actor = new Actor(this, { id, kind, systemPrompt, personaHash });
    this.actors.set(key, actor);
    return actor;
  }

  async reset() {
    for (const actor of this.actors.values()) await actor.dispose();
    this.actors.clear();
    try {
      fs.rmSync(this.sessionsDir, { recursive: true, force: true });
    } catch {
      /* ignore */
    }
  }

  stats() {
    return {
      campaign: this.id,
      actors: [...this.actors.entries()].map(([key, actor]) => ({
        key,
        calls: actor.stats.calls,
        inputTokens: actor.stats.inputTokens,
        outputTokens: actor.stats.outputTokens,
        lastError: actor.lastError,
        session: actor.session?.sessionFile ? path.basename(actor.session.sessionFile) : null,
      })),
    };
  }
}

export function newCampaign({ id, player, log }) {
  return new CampaignContext({ id, player, log });
}
