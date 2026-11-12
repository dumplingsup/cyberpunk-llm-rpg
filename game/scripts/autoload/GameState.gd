extends Node
## Authoritative game state and mechanics. The LLM writes the fiction; this
## script owns money, heat, dice, injuries, loyalty, saves.

signal state_changed
signal note_added(text: String, color: Color)
signal save_done

const SAVE_PATH := "user://campaign.json"
const VERSION := 3
const MAX_CREW := 3
const MAX_INJURY := 3

const SPECIALTIES := {
	"ghost": {
		"name": "幽灵",
		"tag": "入侵专精",
		"desc": "你把门锁当成建议。破冰与潜伏系统是你的本能，代价是你不太擅长让人喜欢你。",
		"skills": {"intrusion": 4, "ew": 2, "analysis": 2, "nerve": 2},
		"gear": "icebreaker",
	},
	"weaver": {
		"name": "织网",
		"tag": "电子战专精",
		"desc": "你听的比看的多。信号、频段、无人机的呼吸——你让整座城市短暂失聪。",
		"skills": {"intrusion": 2, "ew": 4, "analysis": 2, "nerve": 2},
		"gear": "ghost_signal",
	},
	"oracle": {
		"name": "观星",
		"tag": "情报专精",
		"desc": "你先看完所有可能性，再决定要不要动手。信息是你的武器，也是你的瘾。",
		"skills": {"intrusion": 2, "ew": 2, "analysis": 4, "nerve": 2},
		"gear": "oracle_lens",
	},
}

const GEAR_CATALOG := [
	{"id": "icebreaker", "name": "破冰器 MK-II", "desc": "入侵判定 +1", "price": 320, "skill": "intrusion", "bonus": 1},
	{"id": "ghost_signal", "name": "幽灵信号器", "desc": "电子战判定 +1", "price": 320, "skill": "ew", "bonus": 1},
	{"id": "oracle_lens", "name": "战术分析仪", "desc": "分析判定 +1", "price": 300, "skill": "analysis", "bonus": 1},
	{"id": "silence", "name": "静默协议", "desc": "结算时热度 -1", "price": 520, "heat": -1, "bonus": 0},
	{"id": "medkit", "name": "医疗无人机", "desc": "每单抵消第一次队友受伤", "price": 460, "prevent_injury": 1, "bonus": 0},
	{"id": "mask", "name": "假身份套件", "desc": "潜行/技术判定 +1", "price": 360, "skill": "stealth", "bonus": 1},
]

var campaign_id: String = ""
var player: Dictionary = {}
var day: int = 1
var credits: int = 900
var rep: int = 8
var heat: int = 0
var fixer_trust: int = 50
var contracts: Array = []
var crew: Array = []
var active_contract = null
var negotiating_contract = null
var last_contract = null
var plan: Dictionary = {}
var run: Dictionary = {}
var last_run: Dictionary = {}
var last_settlement: Dictionary = {}
var chronicle: Array = []
var archive: Array = []
var flags: Array = []
var stats: Dictionary = {}
var offers_day: int = 0
var pending_event = null

func _ready() -> void:
	randomize()
	if player.is_empty():
		player = {
			"handle": "GHOST",
			"specialty": "幽灵",
			"specialty_id": "ghost",
			"skills": SPECIALTIES["ghost"].skills.duplicate(true),
			"gear": [],
		}
	stats = _fresh_stats()

func _fresh_stats() -> Dictionary:
	return {"jobs": 0, "successes": 0, "failures": 0, "credits_earned": 0, "runs": 0, "best_net": 0}

func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)

func new_game(handle: String, specialty_id: String) -> void:
	var spec: Dictionary = SPECIALTIES.get(specialty_id, SPECIALTIES["ghost"])
	campaign_id = "cp_%d_%d" % [int(Time.get_unix_time_from_system()), randi() % 100000]
	player = {
		"handle": handle.strip_edges().to_upper() if handle.strip_edges() != "" else "GHOST",
		"specialty": spec.name,
		"specialty_id": specialty_id,
		"skills": spec.skills.duplicate(true),
		"gear": [spec.gear],
	}
	day = 1
	credits = 900
	rep = 8
	heat = 0
	fixer_trust = 50
	contracts = []
	crew = []
	active_contract = null
	last_contract = null
	plan = {}
	run = {}
	last_run = {}
	last_settlement = {}
	archive = []
	flags = []
	offers_day = 0
	pending_event = null
	stats = _fresh_stats()
	chronicle = [
		"你在澜港旧城区第七层租下这间安全屋。窗外是永不停歇的酸雨，和你一样，没人知道这扇门后面住着谁。",
		"中间人「蜃楼」发来第一条加密语音：欢迎上线，幽灵。规矩很简单——不问雇主是谁，不留痕迹，钱到账，活结束。",
	]
	archive_add("安全屋", "旧城区第七层，一间没有窗户的隔间。三条独立网络出口，一台靠墙的旧服务器，一把会硌背的椅子。")
	save_game()
	state_changed.emit()

func save_game() -> bool:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		push_warning("无法写入存档: %s" % SAVE_PATH)
		return false
	f.store_string(JSON.stringify(to_dict(), "\t"))
	f.close()
	save_done.emit()
	return true

func load_game() -> bool:
	if not has_save():
		return false
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return false
	var txt := f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(txt)
	if typeof(parsed) != TYPE_DICTIONARY:
		return false
	if int(parsed.get("version", 0)) != VERSION:
		push_warning("存档版本不匹配，忽略旧档")
		return false
	from_dict(parsed)
	state_changed.emit()
	return true

func peek_save() -> Dictionary:
	if not has_save():
		return {}
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return {}
	var txt := f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(txt)
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	return parsed

func wipe_save() -> void:
	var abs := ProjectSettings.globalize_path(SAVE_PATH)
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(abs)

func to_dict() -> Dictionary:
	return {
		"version": VERSION,
		"campaign_id": campaign_id,
		"player": player,
		"day": day,
		"credits": credits,
		"rep": rep,
		"heat": heat,
		"fixer_trust": fixer_trust,
		"contracts": contracts,
		"crew": crew,
		"active_contract": active_contract,
		"last_contract": last_contract,
		"plan": plan,
		"run": run,
		"last_run": last_run,
		"last_settlement": last_settlement,
		"chronicle": chronicle,
		"archive": archive,
		"flags": flags,
		"stats": stats,
		"offers_day": offers_day,
		"pending_event": pending_event,
	}

func from_dict(d: Dictionary) -> void:
	campaign_id = str(d.get("campaign_id", ""))
	player = d.get("player", {})
	day = int(d.get("day", 1))
	credits = int(d.get("credits", 900))
	rep = int(d.get("rep", 8))
	heat = int(d.get("heat", 0))
	fixer_trust = int(d.get("fixer_trust", 50))
	contracts = d.get("contracts", [])
	crew = d.get("crew", [])
	active_contract = d.get("active_contract", null)
	last_contract = d.get("last_contract", null)
	plan = d.get("plan", {})
	run = d.get("run", {})
	last_run = d.get("last_run", {})
	last_settlement = d.get("last_settlement", {})
	chronicle = d.get("chronicle", [])
	archive = d.get("archive", [])
	flags = d.get("flags", [])
	stats = d.get("stats", _fresh_stats())
	offers_day = int(d.get("offers_day", 0))
	pending_event = d.get("pending_event", null)
	if not player.has("skills"):
		player["skills"] = SPECIALTIES["ghost"].skills.duplicate(true)

func state_for_bridge() -> Dictionary:
	var crew_payload: Array = []
	for c in hired_crew():
		crew_payload.append(c)
	var gear_payload: Array = []
	for id in selected_gear_ids():
		var item := gear_item(id)
		if not item.is_empty():
			gear_payload.append({"name": item.name, "desc": item.desc})
	return {
		"player": {
			"handle": player.get("handle", "GHOST"),
			"specialty": player.get("specialty", "黑客"),
			"day": day,
			"credits": credits,
			"rep": rep,
			"heat": heat,
			"skills": player.get("skills", {}),
			"gear": gear_payload,
		},
		"crew": crew_payload,
		"contract": active_contract,
		"chronicle": chronicle.slice(maxi(0, chronicle.size() - 10)),
		"fixerTrust": fixer_trust,
		"flags": flags.slice(maxi(0, flags.size() - 12)),
	}

func note(text: String, color: Color = Color("#7896a0")) -> void:
	if text.strip_edges() == "":
		return
	chronicle.append(text)
	while chronicle.size() > 60:
		chronicle.pop_front()
	note_added.emit(text, color)
	state_changed.emit()

func archive_add(title: String, text: String) -> void:
	archive.push_front({"title": title, "text": text, "day": day})
	while archive.size() > 40:
		archive.pop_back()

func add_flag(flag: String) -> void:
	if flag != "" and not flags.has(flag):
		flags.append(flag)
		if flags.size() > 24:
			flags.pop_front()

func gear_item(id: String) -> Dictionary:
	for item in GEAR_CATALOG:
		if item.id == id:
			return item
	return {}

func owns_gear(id: String) -> bool:
	return player.get("gear", []).has(id)

func buy_gear(id: String) -> bool:
	var item := gear_item(id)
	if item.is_empty() or owns_gear(id) or credits < int(item.price):
		return false
	credits -= int(item.price)
	player["gear"].append(id)
	note("购入装备「%s」。" % item.name, UI.C_AMBER)
	save_game()
	state_changed.emit()
	return true

func selected_gear_ids() -> Array:
	if not plan.is_empty() and plan.has("gear_ids"):
		return plan.gear_ids
	var owned: Array = player.get("gear", [])
	if owned.is_empty():
		return []
	return [owned[0]]

func crew_by_id(id: String) -> Variant:
	for c in crew:
		if str(c.get("id", "")) == id:
			return c
	return null

func hired_crew() -> Array:
	var out: Array = []
	for c in crew:
		if bool(c.get("hired", false)) and not bool(c.get("dead", false)):
			out.append(c)
	return out

func available_crew() -> Array:
	var out: Array = []
	for c in crew:
		if not bool(c.get("hired", false)) and not bool(c.get("dead", false)):
			out.append(c)
	return out

func add_crew_candidates(list: Array) -> void:
	var existing := {}
	for c in crew:
		existing[str(c.get("handle", "")).to_upper()] = true
	for c in list:
		var h := str(c.get("handle", "")).to_upper()
		if h == "" or existing.has(h):
			continue
		c["hired"] = false
		c["injury"] = 0
		c["missions"] = 0
		c["secret_revealed"] = false
		crew.append(c)
		existing[h] = true
	while crew.size() > 12:
		var drop := -1
		for i in range(crew.size()):
			if not bool(crew[i].get("hired", false)):
				drop = i
				break
		if drop < 0:
			break
		crew.remove_at(drop)
	save_game()
	state_changed.emit()

func open_contracts() -> Array:
	var out: Array = []
	for c in contracts:
		if str(c.get("status", "open")) == "open":
			out.append(c)
	return out

func contract_by_id(id: String) -> Variant:
	for c in contracts:
		if str(c.get("id", "")) == id:
			return c
	return null

func accept_contract(id: String) -> bool:
	var c = contract_by_id(id)
	if c == null:
		return false
	if active_contract != null:
		return false
	c["status"] = "active"
	active_contract = c
	credits += int(c.get("advance", 0))
	negotiating_contract = null
	plan = {"approach": "潜入", "entry": "", "exit": "", "crew_ids": [], "gear_ids": selected_gear_ids()}
	note("接受委托「%s」。预付款 %s 信用点已到账。" % [c.get("codename", ""), UI.fmt_money(int(c.get("advance", 0)))], UI.C_CYAN)
	add_flag("接受过委托")
	save_game()
	state_changed.emit()
	return true

func decline_contract(id: String) -> void:
	var c = contract_by_id(id)
	if c != null:
		if negotiating_contract == c:
			negotiating_contract = null
		c["status"] = "declined"
		note("你推掉了「%s」。" % c.get("codename", ""))
		save_game()
		state_changed.emit()

func expire_open_contracts() -> void:
	for c in contracts:
		if str(c.get("status", "open")) == "open":
			c["status"] = "expired"

func hire_crew(id: String, offer_cut: int = -1) -> bool:
	var c = crew_by_id(id)
	if c == null or bool(c.get("hired", false)):
		return false
	if hired_crew().size() >= MAX_CREW:
		return false
	var old_price := int(c.get("price", 300))
	var cut := offer_cut if offer_cut >= 0 else old_price
	c["price"] = clampi(cut, 50, 900)
	c["hired"] = true
	c["loyalty"] = clampi(int(c.get("loyalty", 50)) + (2 if cut >= old_price else -3), 0, 100)
	note("「%s」加入行动名单，分成 %s。" % [c.get("name", ""), UI.fmt_money(int(c["price"]))], UI.C_GREEN)
	save_game()
	state_changed.emit()
	return true

func fire_crew(id: String) -> void:
	var c = crew_by_id(id)
	if c == null:
		return
	c["hired"] = false
	c["loyalty"] = clampi(int(c.get("loyalty", 50)) - 6, 0, 100)
	if plan.has("crew_ids"):
		plan["crew_ids"].erase(id)
	note("你解除了与「%s」的合作。" % c.get("name", ""), UI.C_MAGENTA)
	save_game()
	state_changed.emit()

func crew_for_run() -> Array:
	var ids: Array = plan.get("crew_ids", [])
	var out: Array = []
	for id in ids:
		var c = crew_by_id(str(id))
		if c != null and bool(c.get("hired", false)) and not bool(c.get("dead", false)):
			out.append(c)
	return out

func risk_index(risk: String) -> int:
	match risk:
		"低":
			return 1
		"高":
			return 3
		_:
			return 2

func approach_heat(approach: String) -> int:
	match approach:
		"强攻":
			return 1
		"潜入":
			return 0
		"电子战":
			return 0
		"社交":
			return 0
		_:
			return 0

func approach_modifier(skill: String, approach: String) -> int:
	match approach:
		"潜入":
			if skill in ["stealth", "tech", "intrusion"]:
				return -1
			if skill == "combat":
				return 1
		"强攻":
			if skill == "combat":
				return -1
			if skill in ["stealth", "social"]:
				return 1
		"社交":
			if skill == "social":
				return -1
			if skill in ["combat", "stealth"]:
				return 1
		"电子战":
			if skill in ["intrusion", "ew", "analysis"]:
				return -1
			if skill == "combat":
				return 1
	return 0

func compute_dc(action: Dictionary, free_text: bool = false) -> int:
	var c: Dictionary = active_contract if active_contract != null else {}
	var risk := risk_index(str(c.get("risk", "中")))
	var beat_index := int(run.get("beat_index", 0))
	var dc := 6 + risk + beat_index
	dc += approach_modifier(str(action.get("skill", "tech")), str(plan.get("approach", "潜入")))
	var ar := str(action.get("risk", "中"))
	if ar == "低":
		dc -= 1
	elif ar == "高":
		dc += 1
	if beat_index == 0 and str(plan.get("entry", "")) != "":
		dc -= 1
	if beat_index == 3 and str(plan.get("exit", "")) != "":
		dc -= 1
	if int(run.get("alarms", 0)) >= 2:
		dc += 1
	var crew_id := str(action.get("actor", "player"))
	if crew_id != "player":
		var crew_member = crew_by_id(crew_id)
		if crew_member != null:
			dc += int(crew_member.get("injury", 0))
	if free_text:
		dc += 1
	return clampi(dc, 4, 14)

func stat_for(action: Dictionary) -> int:
	var skill := str(action.get("skill", "tech"))
	var actor := str(action.get("actor", "player"))
	if actor == "player":
		return int(player.get("skills", {}).get(skill, 2))
	var crew_member = crew_by_id(actor)
	if crew_member == null:
		return 2
	var base := int(crew_member.get("skills", {}).get(skill, 2))
	return maxi(1, base - int(crew_member.get("injury", 0)))

func gear_bonus_for(skill: String) -> int:
	var total := 0
	for id in selected_gear_ids():
		var item := gear_item(str(id))
		if not item.is_empty() and str(item.get("skill", "")) == skill:
			total += int(item.get("bonus", 1))
	return total

func compute_bonus(action: Dictionary) -> int:
	var bonus := gear_bonus_for(str(action.get("skill", "tech")))
	bonus += int(run.get("support_bonus", 0))
	return bonus

func chance_for(action: Dictionary, free_text: bool = false) -> int:
	var dc := compute_dc(action, free_text)
	var need := dc - stat_for(action) - compute_bonus(action)
	return clampi((11 - need) * 10, 5, 95)

func begin_run() -> void:
	if active_contract == null:
		return
	run = {
		"contract_id": str(active_contract.get("id", "")),
		"beat_index": 0,
		"beat": null,
		"alarms": 0,
		"successes": 0,
		"crits": 0,
		"failures": 0,
		"highlights": [],
		"injuries": [],
		"loot": [],
		"support_bonus": 0,
		"support_note": "",
		"bandwidth": 4,
		"approach": str(plan.get("approach", "潜入")),
		"tier_log": [],
		"broken": false,
		"done": false,
		"aborted": false,
		"prevent_injury": false,
	}
	for id in selected_gear_ids():
		if str(id) == "medkit":
			run["prevent_injury"] = true
	heat = clampi(heat + approach_heat(str(plan.get("approach", "潜入"))), 0, 10)
	note("行动「%s」开始。链路加密完成，进入现场。" % active_contract.get("codename", ""), UI.C_CYAN)
	save_game()
	state_changed.emit()

func abort_run() -> void:
	if run.is_empty():
		return
	run["aborted"] = true
	run["broken"] = true
	run["failures"] = int(run.get("failures", 0)) + 1
	note("你切断了现场链路。队友按紧急预案撤离，耳机里最后传来一声很轻的咒骂。", UI.C_MAGENTA)
	save_game()
	state_changed.emit()

func roll_action(action: Dictionary, free_text: bool = false) -> Dictionary:
	var dc := compute_dc(action, free_text)
	var stat := stat_for(action)
	var bonus := compute_bonus(action)
	var roll := randi_range(1, 10)
	var total := roll + stat + bonus
	var tier := "失败"
	if total >= dc + 4:
		tier = "大成功"
	elif total >= dc:
		tier = "成功"
	elif total >= dc - 2:
		tier = "勉强"
	if roll == 10 and tier in ["成功", "勉强"]:
		tier = "大成功" if tier == "成功" else "成功"
	if roll == 1 and tier == "成功":
		tier = "勉强"
	var actor := str(action.get("actor", "player"))
	var actor_name := str(player.get("handle", "GHOST")) if actor == "player" else str(crew_by_id(actor).get("name", "队友") if crew_by_id(actor) != null else "队友")
	var result := {
		"roll": roll,
		"stat": stat,
		"bonus": bonus,
		"total": total,
		"dc": dc,
		"tier": tier,
		"skill": str(action.get("skill", "tech")),
		"actor": actor,
		"actor_name": actor_name,
		"free_text": free_text,
	}
	run["support_bonus"] = 0
	run["support_note"] = ""
	_apply_action_consequences(result, action)
	run["tier_log"].append({"tier": tier, "total": total, "dc": dc, "skill": result.skill})
	run["highlights"].append("%s用%s完成「%s」，%s（%d vs DC%d）" % [actor_name, _skill_name(result.skill), str(action.get("label", "行动")), tier, total, dc])
	while run["highlights"].size() > 8:
		run["highlights"].pop_front()
	save_game()
	state_changed.emit()
	return result

func _skill_name(skill: String) -> String:
	var names := {"intrusion": "入侵", "ew": "电子战", "analysis": "分析", "stealth": "潜行", "tech": "技术", "social": "交涉", "combat": "战斗", "nerve": "意志"}
	return str(names.get(skill, skill))

func _apply_action_consequences(r: Dictionary, action: Dictionary) -> void:
	match str(r.tier):
		"大成功":
			run["successes"] = int(run.get("successes", 0)) + 1
			run["crits"] = int(run.get("crits", 0)) + 1
			run["alarms"] = maxi(0, int(run.get("alarms", 0)) - 1)
		"成功":
			run["successes"] = int(run.get("successes", 0)) + 1
		"勉强":
			run["alarms"] = mini(3, int(run.get("alarms", 0)) + 1)
		"失败":
			run["failures"] = int(run.get("failures", 0)) + 1
			run["alarms"] = mini(3, int(run.get("alarms", 0)) + 2)
			heat = clampi(heat + 1, 0, 10)
			if int(r.get("roll", 10)) <= 3 and str(action.get("actor", "player")) != "player":
				_injure_crew(str(action.get("actor", "")))
	if int(run.get("alarms", 0)) >= 3:
		run["broken"] = true
		note("警报升到 3 级。现场已经失控，必须立刻撤离。", UI.C_RED)

func _injure_crew(crew_id: String) -> void:
	var c = crew_by_id(crew_id)
	if c == null:
		return
	if bool(run.get("prevent_injury", false)):
		run["prevent_injury"] = false
		note("医疗无人机抢在致死量前稳定了「%s」。这次伤没有留下。" % c.get("name", ""), UI.C_AMBER)
		return
	c["injury"] = mini(MAX_INJURY, int(c.get("injury", 0)) + 1)
	run["injuries"].append(str(c.get("name", "")))
	note("「%s」受伤（%d/%d）。" % [c.get("name", ""), int(c["injury"]), MAX_INJURY], UI.C_RED)
	if int(c["injury"]) >= MAX_INJURY:
		c["dead"] = true
		c["hired"] = false
		note("「%s」倒下了。链路里只剩下雨声。" % c.get("name", ""), UI.C_RED)
		add_flag("失去队友:%s" % c.get("name", ""))

func use_support(skill: String, label: String) -> Dictionary:
	if int(run.get("bandwidth", 0)) < 1:
		return {"ok": false, "reason": "带宽不足"}
	run["bandwidth"] = int(run.get("bandwidth", 0)) - 1
	var dc := 4 + risk_index(str(active_contract.get("risk", "中"))) + int(run.get("beat_index", 0))
	var stat := int(player.get("skills", {}).get(skill, 2))
	var bonus := gear_bonus_for(skill)
	var roll := randi_range(1, 10)
	var total := roll + stat + bonus
	var success := total >= dc
	if success:
		run["support_bonus"] = 2
		run["support_note"] = label
		note("远程支援「%s」成功（%d vs DC%d），下一次现场行动 +2。" % [label, total, dc], UI.C_CYAN)
	else:
		note("远程支援「%s」失败（%d vs DC%d），带宽已经烧掉。" % [label, total, dc], UI.C_AMBER)
	save_game()
	state_changed.emit()
	return {"ok": true, "success": success, "roll": roll, "stat": stat, "bonus": bonus, "total": total, "dc": dc, "skill": skill}

func compute_settlement() -> Dictionary:
	var c: Dictionary = active_contract if active_contract != null else last_contract
	if c == null:
		c = {}
	var successes := int(run.get("successes", 0))
	var alarms := int(run.get("alarms", 0))
	var ratio := clampf(0.3 + 0.7 * (float(successes) / 4.0), 0.2, 1.0)
	if bool(run.get("aborted", false)):
		ratio = minf(ratio, 0.35)
	var gross := int(round(float(c.get("pay", 0)) * ratio))
	if alarms >= 3:
		gross = int(round(gross * 0.8))
	var cuts := 0
	for member in crew_for_run():
		cuts += int(member.get("price", 0))
	var injuries: Array = run.get("injuries", [])
	var expenses := injuries.size() * 90
	var loot_value := 0
	for item in run.get("loot", []):
		loot_value += int(item.get("value", 0))
	var advance := int(c.get("advance", 0))
	var net := maxi(0, gross - advance - cuts - expenses + loot_value)
	if successes >= 2 and not bool(run.get("aborted", false)):
		net = maxi(net, int(round(float(c.get("pay", 0)) * 0.08)))
	var heat_gain := int(c.get("heat", 1)) + int(run.get("failures", 0))
	heat_gain += approach_heat(str(run.get("approach", "潜入")))
	var heat_reduction := 0
	for id in selected_gear_ids():
		var item := gear_item(str(id))
		if not item.is_empty():
			heat_reduction += int(item.get("heat", 0))
	heat_gain += heat_reduction
	if alarms >= 3:
		heat_gain += 1
	if bool(run.get("aborted", false)):
		heat_gain += 1
	if alarms == 0 and successes >= 3:
		heat_gain -= 1
	heat_gain = clampi(heat_gain, 0, 5)
	var rep_gain := clampi(1 + successes - (1 if alarms >= 3 else 0), 0, 6)
	return {
		"successes": successes,
		"alarms": alarms,
		"pay": int(c.get("pay", 0)),
		"gross": gross,
		"advance": advance,
		"cuts": cuts,
		"expenses": expenses,
		"net": net,
		"heat": heat_gain,
		"rep": rep_gain,
		"injuries": injuries,
		"loot": run.get("loot", []),
		"loot_value": loot_value,
		"highlights": run.get("highlights", []),
		"ratings": run.get("tier_log", []),
	}

func finalize_run() -> Dictionary:
	var results := compute_settlement()
	var c: Dictionary = active_contract if active_contract != null else last_contract
	if c == null:
		c = {}
	credits += int(results.net)
	stats["credits_earned"] = int(stats.get("credits_earned", 0)) + int(results.net)
	stats["jobs"] = int(stats.get("jobs", 0)) + 1
	stats["runs"] = int(stats.get("runs", 0)) + 1
	stats["best_net"] = maxi(int(stats.get("best_net", 0)), int(results.net))
	if int(results.successes) >= 2:
		stats["successes"] = int(stats.get("successes", 0)) + 1
	else:
		stats["failures"] = int(stats.get("failures", 0)) + 1
	heat = clampi(heat + int(results.heat), 0, 10)
	rep = clampi(rep + int(results.rep), 0, 100)
	for member in crew_for_run():
		var bonus := 2 if int(results.successes) >= 3 else (1 if int(results.successes) >= 2 else -1)
		if not results.injuries.has(member.get("name", "")):
			bonus += 1
		member["loyalty"] = clampi(int(member.get("loyalty", 50)) + bonus, 0, 100)
		member["missions"] = int(member.get("missions", 0)) + 1
	var summary := "行动「%s」结束：%d/4 拍成功，警报 %d，净收入 %s 信用点。" % [
		c.get("codename", ""),
		int(results.successes),
		int(results.alarms),
		UI.fmt_money(int(results.net)),
	]
	note(summary, UI.C_CYAN if int(results.net) > 0 else UI.C_AMBER)
	archive_add("行动档案 · %s" % c.get("codename", ""), summary + "\n" + "；".join(PackedStringArray(run.get("highlights", []))))
	c["status"] = "done"
	last_contract = c
	last_run = run.duplicate(true)
	last_settlement = results.duplicate(true)
	active_contract = null
	plan = {}
	run = {}
	day += 1
	if heat >= 8:
		note("沧溟协议的通缉等级已经高到危险。你听见楼下有无人机悬停的声音。", UI.C_RED)
		add_flag("高热通缉")
	save_game()
	state_changed.emit()
	return results

func rest() -> bool:
	if active_contract != null:
		return false
	if credits < 80:
		return false
	credits -= 80
	day += 1
	heat = maxi(0, heat - 1)
	for c in crew:
		c["injury"] = maxi(0, int(c.get("injury", 0)) - 1)
		if bool(c.get("hired", false)):
			c["loyalty"] = clampi(int(c.get("loyalty", 50)) + 2, 0, 100)
	note("你在安全屋里休整了一天。雨没有停，但通缉热度降了一点。" , UI.C_MUTED)
	save_game()
	state_changed.emit()
	return true

func apply_effects(effects: Array) -> void:
	for e in effects:
		var t := str(e.get("type", ""))
		var d := int(e.get("delta", 0))
		match t:
			"heat":
				heat = clampi(heat + d, 0, 10)
				if d > 0:
					note("热度 +%d。" % d, UI.C_MAGENTA)
			"rep":
				rep = clampi(rep + d, 0, 100)
			"credits":
				credits = maxi(0, credits + d)
			"alarm":
				run["alarms"] = clampi(int(run.get("alarms", 0)) + d, 0, 3)
				if int(run["alarms"]) >= 3:
					run["broken"] = true
			"bandwidth":
				run["bandwidth"] = clampi(int(run.get("bandwidth", 0)) + d, 0, 6)
			"loyalty":
				var c = crew_by_id(str(e.get("crew", "")))
				if c != null:
					c["loyalty"] = clampi(int(c.get("loyalty", 50)) + d, 0, 100)
			"injury":
				var c2 = crew_by_id(str(e.get("crew", "")))
				if c2 != null and d > 0:
					c2["injury"] = mini(MAX_INJURY, int(c2.get("injury", 0)) + d)
					if int(c2["injury"]) >= MAX_INJURY:
						c2["dead"] = true
						c2["hired"] = false
					if not run.get("injuries", []).has(c2.get("name", "")):
						run["injuries"].append(c2.get("name", ""))
					note("「%s」伤情加重。" % c2.get("name", ""), UI.C_RED)
	save_game()
	state_changed.emit()

func apply_dialogue_markers(markers: Dictionary, actor_kind: String, actor_id: String) -> Array:
	var applied: Array = []
	var bonds := int(markers.get("bonds", 0))
	if bonds != 0:
		if actor_kind == "fixer":
			fixer_trust = clampi(fixer_trust + bonds * 3, 0, 100)
			applied.append("蜃楼信任 %+d" % (bonds * 3))
		else:
			var c = crew_by_id(actor_id)
			if c != null:
				c["loyalty"] = clampi(int(c.get("loyalty", 50)) + bonds * 2, 0, 100)
				applied.append("%s 忠诚 %+d" % [c.get("name", ""), bonds * 2])
	for deal in markers.get("deals", []):
		var target = active_contract if active_contract != null else negotiating_contract
		if actor_kind == "fixer" and target != null:
			var pay_delta := int(deal.get("pay", 0))
			var adv_delta := int(deal.get("advance", 0))
			if pay_delta != 0:
				target["pay"] = int(target.get("pay", 0)) + pay_delta
				applied.append("报酬 %+d" % pay_delta)
			if adv_delta != 0:
				target["advance"] = int(target.get("advance", 0)) + adv_delta
				if active_contract != null:
					credits += adv_delta
				applied.append("预付款 %+d" % adv_delta)
			var intel := str(deal.get("intel", ""))
			if intel != "":
				archive_add("蜃楼的情报", intel)
				note("蜃楼给了一条情报：%s" % intel, UI.C_AMBER)
				applied.append("获得情报")
		elif actor_kind == "crew":
			var c2 = crew_by_id(actor_id)
			if c2 != null and deal.has("cut"):
				c2["price"] = clampi(int(deal.cut), 50, 900)
				applied.append("分成改为 %s" % UI.fmt_money(int(c2["price"])))
	for secret in markers.get("secrets", []):
		if actor_kind == "crew":
			var c3 = crew_by_id(actor_id)
			if c3 != null:
				c3["secret_revealed"] = true
				archive_add("秘密 · %s" % c3.get("name", ""), str(secret))
				note("「%s」向你透露了秘密。" % c3.get("name", ""), UI.C_MAGENTA)
				applied.append("得知秘密")
	for warning in markers.get("warnings", []):
		note("警告：%s" % warning, UI.C_AMBER)
	for flag in markers.get("flags", []):
		add_flag(str(flag))
	var heat_delta := int(markers.get("heat", 0))
	if heat_delta != 0:
		heat = clampi(heat + heat_delta, 0, 10)
	if not applied.is_empty():
		save_game()
		state_changed.emit()
	return applied

func complete_contract_pay_adjust() -> void:
	save_game()

func reset_campaign() -> void:
	wipe_save()
	negotiating_contract = null
	pending_event = null
	offers_day = 0
	campaign_id = ""
	player = {}
	contracts = []
	crew = []
	archive = []
	chronicle = []
	stats = _fresh_stats()
	active_contract = null
	last_contract = null
	plan = {}
	run = {}
	last_run = {}
	day = 1
	credits = 900
	rep = 8
	heat = 0
	fixer_trust = 50













