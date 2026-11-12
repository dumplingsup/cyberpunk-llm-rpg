// Tolerant parsing + normalization for LLM output. Godot must never receive
// malformed structures: every field is clamped and every array is bounded.

const SKILLS = ["intrusion", "ew", "analysis", "stealth", "tech", "social", "combat", "nerve"];
const PLAYER_SKILLS = ["intrusion", "ew", "analysis", "nerve"];
const PLAYER_SKILL_MAP = { stealth: "intrusion", tech: "intrusion", social: "analysis", combat: "intrusion" };
const RISKS = ["低", "中", "高"];
const STAGES = ["接近", "渗透", "目标", "撤离"];

export function stripFences(text) {
  let t = String(text || "").trim();
  t = t.replace(/^```(?:json|JSON)?\s*/m, "").replace(/```\s*$/m, "").trim();
  return t;
}

function findBalancedJson(text) {
  const start = text.indexOf("{");
  if (start < 0) return null;
  let depth = 0;
  let inStr = false;
  let esc = false;
  for (let i = start; i < text.length; i++) {
    const ch = text[i];
    if (inStr) {
      if (esc) esc = false;
      else if (ch === "\\") esc = true;
      else if (ch === '"') inStr = false;
    } else if (ch === '"') {
      inStr = true;
    } else if (ch === "{") {
      depth++;
    } else if (ch === "}") {
      depth--;
      if (depth === 0) return text.slice(start, i + 1);
    }
  }
  return null;
}

export function parseJsonLoose(text) {
  const raw = stripFences(text);
  if (!raw) return null;
  const candidates = [raw];
  const balanced = findBalancedJson(raw);
  if (balanced && balanced !== raw) candidates.push(balanced);
  for (const candidate of candidates) {
    try {
      return JSON.parse(candidate);
    } catch {
      /* try repairs */
    }
    const repaired = candidate
      .replace(/,\s*([}\]])/g, "$1")
      .replace(/[\u201c\u201d]/g, '"')
      .replace(/[\u2018\u2019]/g, "'");
    try {
      return JSON.parse(repaired);
    } catch {
      /* next */
    }
  }
  return null;
}

export function parseTagged(text) {
  const raw = String(text || "");
  const nIdx = raw.indexOf("<<<NARRATION>>>");
  const dIdx = raw.indexOf("<<<DATA>>>");
  if (nIdx >= 0) {
    const narrationStart = nIdx + "<<<NARRATION>>>".length;
    const narrationEnd = dIdx > nIdx ? dIdx : raw.length;
    const narration = raw.slice(narrationStart, narrationEnd).trim();
    const dataText = dIdx >= 0 ? raw.slice(dIdx + "<<<DATA>>>".length) : "";
    return { narration, data: parseJsonLoose(dataText), raw, dataText };
  }
  if (dIdx >= 0) {
    return { narration: raw.slice(0, dIdx).trim(), data: parseJsonLoose(raw.slice(dIdx + 9)), raw };
  }
  const obj = parseJsonLoose(raw);
  if (obj) return { narration: "", data: obj, raw };
  return { narration: raw.trim(), data: null, raw };
}

const MARKER_RE = /[\[【](DEAL|BOND|SECRET|WARN|HEAT|FLAG|ACCEPT|REFUSE|INTEL)(?:\s*[:：]\s*([^\]】]*))?[\]】]/g;

function parseDealBody(body) {
  const out = {};
  const re = /([a-zA-Z_]+)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s,，]+))/g;
  let m;
  while ((m = re.exec(body))) {
    const key = m[1].toLowerCase();
    const value = m[2] ?? m[3] ?? m[4] ?? "";
    if (["pay", "advance", "cut", "heat", "bond", "rep"].includes(key)) {
      const num = Number(String(value).replace(/[^0-9+.-]/g, ""));
      if (Number.isFinite(num)) out[key] = num;
    } else {
      out[key] = String(value).trim();
    }
  }
  return out;
}

export function parseMarkers(text) {
  const markers = { deals: [], bonds: 0, secrets: [], warnings: [], flags: [], accepted: false, refused: null, intel: [], heat: 0 };
  let cleaned = String(text || "");
  let m;
  MARKER_RE.lastIndex = 0;
  const found = [];
  while ((m = MARKER_RE.exec(cleaned))) found.push({ full: m[0], kind: m[1], body: (m[2] || "").trim() });
  for (const item of found) {
    switch (item.kind) {
      case "DEAL": {
        const deal = parseDealBody(item.body);
        if (Object.keys(deal).length) markers.deals.push(deal);
        break;
      }
      case "BOND": {
        const n = Number(item.body.replace(/[^0-9+.-]/g, ""));
        markers.bonds += Number.isFinite(n) && n !== 0 ? Math.max(-3, Math.min(3, n)) : 1;
        break;
      }
      case "SECRET":
        if (item.body) markers.secrets.push(item.body);
        break;
      case "WARN":
        if (item.body) markers.warnings.push(item.body);
        break;
      case "FLAG":
        if (item.body) markers.flags.push(item.body);
        break;
      case "INTEL":
        if (item.body) markers.intel.push(item.body);
        break;
      case "HEAT": {
        const n = Number(item.body.replace(/[^0-9+.-]/g, ""));
        markers.heat += Number.isFinite(n) ? n : 1;
        break;
      }
      case "ACCEPT":
        markers.accepted = true;
        break;
      case "REFUSE":
        markers.refused = item.body || "拒绝";
        break;
    }
    cleaned = cleaned.split(item.full).join("");
  }
  cleaned = cleaned.replace(/\n{3,}/g, "\n\n").trim();
  return { text: cleaned, markers };
}

function str(v, fallback = "") {
  if (typeof v === "string") return v.trim();
  if (v == null) return fallback;
  return String(v).trim();
}

function clamp(n, lo, hi, fallback = lo) {
  const num = Number(n);
  if (!Number.isFinite(num)) return fallback;
  return Math.max(lo, Math.min(hi, Math.round(num)));
}

function pickEnum(v, allowed, fallback) {
  const s = str(v);
  return allowed.includes(s) ? s : fallback;
}

function shortId(prefix, i) {
  return `${prefix}${Date.now().toString(36)}${i}${Math.floor(Math.random() * 1296).toString(36)}`;
}

export function normalizeContracts(obj, count = 3) {
  const rawList = Array.isArray(obj?.contracts) ? obj.contracts : Array.isArray(obj) ? obj : [];
  const contracts = [];
  for (let i = 0; i < Math.min(rawList.length, count); i++) {
    const c = rawList[i] || {};
    const pay = clamp(c.pay, 500, 5000, 1200);
    const risk = pickEnum(c.risk, RISKS, "中");
    contracts.push({
      id: shortId("c_", i),
      codename: str(c.codename, `未命名行动${i + 1}`).slice(0, 20),
      client: str(c.client, "匿名雇主").slice(0, 80),
      target: str(c.target, "未知目标").slice(0, 80),
      objective: str(c.objective, "完成委托").slice(0, 160),
      location: str(c.location, "澜港·旧城区").slice(0, 100),
      pay,
      advance: clamp(c.advance, 0, Math.floor(pay * 0.3), 0),
      risk,
      heat: clamp(c.heat, 0, 4, 1),
      tags: (Array.isArray(c.tags) ? c.tags : []).map((t) => str(t).slice(0, 8)).filter(Boolean).slice(0, 3),
      brief: str(c.brief, "蜃楼只发来一个坐标和一句话：别问太多。").slice(0, 400),
      hook: str(c.hook, "").slice(0, 120),
      twist: str(c.twist, "").slice(0, 300),
      approach_hint: str(c.approach_hint, "").slice(0, 120),
      accepted: false,
      status: "open",
    });
  }
  return contracts;
}

export function normalizeCrew(obj, count = 3, takenHandles = []) {
  const rawList = Array.isArray(obj?.crew) ? obj.crew : Array.isArray(obj) ? obj : [];
  const crew = [];
  const used = new Set(takenHandles.map((h) => String(h).toLowerCase()));
  for (let i = 0; i < Math.min(rawList.length, count); i++) {
    const c = rawList[i] || {};
    let handle = str(c.handle, `WIRE-${i + 1}`).slice(0, 18);
    if (used.has(handle.toLowerCase())) handle = `${handle}-2`;
    used.add(handle.toLowerCase());
    const skills = {};
    for (const k of SKILLS) skills[k] = clamp(c.skills?.[k] ?? c.skills?.[k.toLowerCase()], 1, 5, 2);
    crew.push({
      id: shortId("crew_", i),
      name: str(c.name, `佣兵${i + 1}`).slice(0, 20),
      handle: handle.toUpperCase(),
      role: pickEnum(c.role, ["潜入", "重装", "技术", "交涉", "撤离"], "技术"),
      origin: str(c.origin, "").slice(0, 120),
      look: str(c.look, "").slice(0, 120),
      voice: str(c.voice, "").slice(0, 120),
      personality: str(c.personality, "").slice(0, 160),
      quirk: str(c.quirk, "").slice(0, 80),
      like: str(c.like, "").slice(0, 60),
      dislike: str(c.dislike, "").slice(0, 60),
      price: clamp(c.price, 100, 800, 300),
      loyalty: clamp(c.loyalty, 30, 70, 50),
      skills,
      perk: str(c.perk, "").slice(0, 100),
      secret: str(c.secret, "").slice(0, 200),
      pitch: str(c.pitch, "").slice(0, 140),
      injury: 0,
      hired: false,
      missions: 0,
      dead: false,
    });
  }
  return crew;
}

function normalizeActions(list, crewIds, actorFallback) {
  const actions = [];
  const arr = Array.isArray(list) ? list : [];
  for (const a of arr.slice(0, 4)) {
    if (!a) continue;
    let actor = str(a.actor, actorFallback);
    const low = actor.toLowerCase();
    if (["player", "ghost", "玩家", "你", "黑客"].some((x) => low.includes(x))) actor = "player";
    else if (!crewIds.includes(actor)) actor = crewIds[0] || "player";
    let skill = pickEnum(a.skill, SKILLS, "tech");
    if (actor === "player" && !PLAYER_SKILLS.includes(skill)) {
      skill = PLAYER_SKILL_MAP[skill] || "intrusion";
    }
    actions.push({
      label: str(a.label, "按计划推进").slice(0, 40),
      skill,
      actor,
      risk: pickEnum(a.risk, RISKS, "中"),
    });
  }
  if (actions.length === 0) {
    actions.push({ label: "按原计划推进", skill: "tech", actor: crewIds[0] || "player", risk: "中" });
    actions.push({ label: "先观察再动手", skill: "analysis", actor: "player", risk: "低" });
  }
  if (actions.length === 1) {
    actions.push({ label: "让玩家远程清出一条路", skill: "intrusion", actor: "player", risk: "低" });
  }
  return actions;
}

function normalizeSupportOps(list) {
  const ops = [];
  const arr = Array.isArray(list) ? list : [];
  for (const o of arr.slice(0, 3)) {
    if (!o) continue;
    ops.push({
      label: str(o.label, "远程支援").slice(0, 36),
      skill: pickEnum(o.skill, PLAYER_SKILLS, "intrusion"),
      cost: clamp(o.cost, 1, 2, 1),
      hint: str(o.hint, "").slice(0, 60),
    });
  }
  if (!ops.length) {
    ops.push({ label: "扫描现场网络", skill: "analysis", cost: 1, hint: "寻找可利用的漏洞" });
  }
  return ops;
}

export function normalizeBeat(beat, crewIds = [], index = 0) {
  if (!beat || typeof beat !== "object") return null;
  const actions = normalizeActions(beat.actions, crewIds, crewIds[0] || "player");
  return {
    name: str(beat.name, STAGES[index] || "行动").slice(0, 16),
    situation: str(beat.situation, "现场陷入短暂的安静，只有雨声和电流声。").slice(0, 300),
    pressure: str(beat.pressure, "时间不多。").slice(0, 120),
    actions,
    support_ops: normalizeSupportOps(beat.support_ops),
  };
}

export function normalizeEffects(list, crewIds = []) {
  const effects = [];
  const arr = Array.isArray(list) ? list : [];
  for (const e of arr.slice(0, 4)) {
    if (!e) continue;
    const type = pickEnum(e.type, ["heat", "credits", "loyalty", "injury", "alarm", "bandwidth", "rep"], "heat");
    const delta = clamp(e.delta, type === "credits" ? -5000 : -5, type === "credits" ? 5000 : 5, 0);
    if (!delta) continue;
    let crew = null;
    if (["loyalty", "injury"].includes(type)) {
      const raw = str(e.crew);
      crew = crewIds.includes(raw) ? raw : crewIds[0] || null;
      if (!crew) continue;
    }
    effects.push({ type, crew, delta });
  }
  return effects;
}

export function normalizeLoot(list) {
  const arr = Array.isArray(list) ? list : [];
  return arr
    .slice(0, 2)
    .map((l) => ({
      name: str(l?.name, "不明物件").slice(0, 24),
      desc: str(l?.desc, "").slice(0, 100),
      value: clamp(l?.value, 0, 800, 0),
    }))
    .filter((l) => l.name);
}

export function normalizeSettleData(data, crewIds = []) {
  if (!data || typeof data !== "object") return null;
  const crewLines = [];
  if (Array.isArray(data.crew_lines)) {
    for (const item of data.crew_lines.slice(0, 4)) {
      if (!item) continue;
      const id = crewIds.includes(str(item.id)) ? str(item.id) : null;
      const line = str(item.line).slice(0, 120);
      if (line) crewLines.push({ id, line });
    }
  }
  const secrets = [];
  if (Array.isArray(data.secrets)) {
    for (const item of data.secrets.slice(0, 2)) {
      if (!item) continue;
      const id = crewIds.includes(str(item.crew)) ? str(item.crew) : null;
      const secret = str(item.secret).slice(0, 180);
      if (id && secret) secrets.push({ crew: id, secret });
    }
  }
  return {
    loot: normalizeLoot(data.loot),
    hook: str(data.hook, "").slice(0, 160),
    world_change: str(data.world_change, "").slice(0, 160),
    crew_lines: crewLines,
    secrets,
    fixer_line: str(data.fixer_line, "").slice(0, 140),
  };
}

export function normalizeEvent(obj) {
  if (!obj || typeof obj !== "object") return null;
  return {
    title: str(obj.title, "澜港夜讯").slice(0, 20),
    text: str(obj.text, "城市的雨声比平时更闷。").slice(0, 300),
    severity: pickEnum(obj.severity, RISKS, "低"),
    effects: normalizeEffects(obj.effects, []),
    hook: str(obj.hook, "").slice(0, 160),
  };
}

export function normalizeAudit(obj) {
  if (!obj || typeof obj !== "object") return null;
  const notes = Array.isArray(obj.notes) ? obj.notes.map((n) => str(n).slice(0, 80)).filter(Boolean).slice(0, 4) : [];
  return {
    verdict: pickEnum(obj.verdict, ["可用", "勉强", "危险"], "勉强"),
    risk_score: clamp(obj.risk_score, 0, 100, 50),
    notes,
    line: str(obj.line, "").slice(0, 100),
  };
}
