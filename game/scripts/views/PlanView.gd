extends Control
## Plan: choose entry, approach, exit, crew and gear, then commit to the run.

const ENTRY_OPTIONS := [
	{"value": "消防梯", "label": "消防梯", "desc": "避开正门的身份核验", "skill": "stealth"},
	{"value": "正门", "label": "正门", "desc": "靠一张假脸走进去", "skill": "social"},
	{"value": "维护管道", "label": "维护管道", "desc": "慢，但没人会看那里", "skill": "tech"},
	{"value": "伪装后勤", "label": "伪装后勤", "desc": "赌值班表上刚好缺人", "skill": "social"},
]
const APPROACH_OPTIONS := [
	{"value": "潜入", "label": "潜入", "desc": "低热度，偏好潜行与技术"},
	{"value": "强攻", "label": "强攻", "desc": "高热度，战斗判定更简单"},
	{"value": "社交", "label": "社交", "desc": "靠嘴和身份过关"},
	{"value": "电子战", "label": "电子战", "desc": "让设备先失明"},
]
const EXIT_OPTIONS := [
	{"value": "后巷", "label": "后巷", "desc": "湿滑、狭窄、没人看见"},
	{"value": "天台", "label": "天台", "desc": "需要提前切断门禁"},
	{"value": "混入人流", "label": "混入人流", "desc": "慢一步，但最不像逃亡"},
	{"value": "强行突破", "label": "强行突破", "desc": "快，而且会留下痕迹"},
]

var main = null
var left_box: VBoxContainer
var right_box: VBoxContainer
var audit: Dictionary = {}
var audit_loading := false

func _ready() -> void:
	if GS.plan.is_empty():
		GS.plan = {"approach": "潜入", "entry": "消防梯", "exit": "后巷", "crew_ids": [], "gear_ids": GS.selected_gear_ids()}
	if str(GS.plan.get("approach", "")) == "":
		GS.plan["approach"] = "潜入"
	if str(GS.plan.get("entry", "")) == "":
		GS.plan["entry"] = "消防梯"
	if str(GS.plan.get("exit", "")) == "":
		GS.plan["exit"] = "后巷"
	if not GS.plan.has("crew_ids"):
		GS.plan["crew_ids"] = []
	if GS.plan["crew_ids"].is_empty() and not GS.hired_crew().is_empty():
		var ids: Array = []
		for c in GS.hired_crew():
			ids.append(str(c.get("id", "")))
		GS.plan["crew_ids"] = ids
	_build()
	refresh()

func _build() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var root := MarginContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	root.add_child(vb)
	left_box = VBoxContainer.new()
	right_box = VBoxContainer.new()
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	vb.add_child(head)
	var titles := VBoxContainer.new()
	titles.add_theme_constant_override("separation", 0)
	head.add_child(titles)
	var c: Dictionary = GS.active_contract if GS.active_contract != null else {}
	titles.add_child(UI.mk_kicker("PLAN / 行动方案"))
	titles.add_child(UI.mk_label("制定计划", 24, UI.C_TEXT, {"bold": true}))
	var goal := UI.mk_label("%s ｜ %s" % [str(c.get("codename", "无委托")), str(c.get("objective", ""))], 12, UI.C_CYAN)
	goal.size_flags_vertical = Control.SIZE_SHRINK_END
	head.add_child(goal)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(spacer)
	var talk := UI.mk_button("和蜃楼谈条件", "ghost", 140, 36)
	talk.pressed.connect(func(): main.open_chat("fixer"))
	head.add_child(talk)
	var back := UI.mk_button("返回委托板", "ghost", 120, 36)
	back.pressed.connect(func(): main.navigate("inbox"))
	head.add_child(back)

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 10)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(body)

	var left := UI.mk_panel(Color(0.012, 0.024, 0.034, 0.92), UI.C_BORDER_DIM, {"margin": 0})
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(left)
	var lscroll := UI.mk_scroll()
	left.add_child(lscroll)
	var lpad := MarginContainer.new()
	lpad.add_theme_constant_override("margin_left", 18)
	lpad.add_theme_constant_override("margin_right", 18)
	lpad.add_theme_constant_override("margin_top", 16)
	lpad.add_theme_constant_override("margin_bottom", 16)
	lpad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lscroll.add_child(lpad)
	lpad.add_child(left_box)
	left_box.add_theme_constant_override("separation", 14)

	var right := UI.mk_panel(Color(0.014, 0.026, 0.036, 0.95), UI.C_BORDER_DIM, {"margin": 0})
	right.custom_minimum_size.x = 420
	body.add_child(right)
	var rscroll := UI.mk_scroll()
	right.add_child(rscroll)
	var rpad := MarginContainer.new()
	rpad.add_theme_constant_override("margin_left", 18)
	rpad.add_theme_constant_override("margin_right", 18)
	rpad.add_theme_constant_override("margin_top", 16)
	rpad.add_theme_constant_override("margin_bottom", 16)
	rpad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rscroll.add_child(rpad)
	rpad.add_child(right_box)
	right_box.add_theme_constant_override("separation", 12)

func refresh() -> void:
	_build_left()
	_refresh_assessment()
	main._refresh_header()

func _build_left() -> void:
	for ch in left_box.get_children():
		ch.queue_free()
	var c: Dictionary = GS.active_contract if GS.active_contract != null else {}
	left_box.add_child(_contract_strip(c))
	left_box.add_child(_option_block("ENTRY / 进入方式", "第一拍更容易。选一个和现场匹配的入口。", ENTRY_OPTIONS, "entry"))
	left_box.add_child(_option_block("APPROACH / 行动手段", "决定整体判定倾向与起始热度。", APPROACH_OPTIONS, "approach"))
	left_box.add_child(_option_block("EXTRACTION / 撤离方式", "最后一拍更容易，但会留下不同的痕迹。", EXIT_OPTIONS, "exit"))
	left_box.add_child(_crew_block())
	left_box.add_child(_gear_block())
	FX.stagger(left_box, 0.035, 0.99)

func _contract_strip(c: Dictionary) -> Control:
	var p := UI.mk_panel(Color(0.018, 0.038, 0.05, 0.95), UI.C_BORDER_DIM, {"margin": 12})
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 16)
	p.add_child(h)
	h.add_child(_mini("CLIENT / 雇主", str(c.get("client", "未知"))))
	h.add_child(_mini("TARGET / 目标", str(c.get("target", "未知"))))
	h.add_child(_mini("LOCATION / 地点", str(c.get("location", "未知"))))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(sp)
	var v := VBoxContainer.new()
	v.add_child(UI.mk_kicker("PAYOUT / 报酬"))
	v.add_child(UI.mk_label("¥ " + UI.fmt_money(int(c.get("pay", 0))), 20, UI.C_AMBER, {"mono": true, "bold": true}))
	h.add_child(v)
	var risk := VBoxContainer.new()
	risk.add_child(UI.mk_kicker("RISK / 风险"))
	risk.add_child(UI.mk_label(str(c.get("risk", "中")), 20, UI.risk_color(str(c.get("risk", "中"))), {"bold": true}))
	h.add_child(risk)
	return p

func _mini(kicker: String, value: String) -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 1)
	v.add_child(UI.mk_kicker(kicker))
	v.add_child(UI.mk_label(value, 12, UI.C_TEXT, {"wrap": true, "width": 220}))
	return v

func _option_block(title: String, subtitle: String, options: Array, field: String) -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	head.add_child(UI.mk_kicker(title))
	head.add_child(UI.mk_label(subtitle, 10, UI.C_DIM))
	v.add_child(head)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	v.add_child(grid)
	var group := ButtonGroup.new()
	var current := str(GS.plan.get(field, options[0].value))
	for opt in options:
		var b := Button.new()
		b.toggle_mode = true
		b.button_group = group
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.text = "%s\n%s" % [str(opt.label), str(opt.desc)]
		b.custom_minimum_size = Vector2(0, 58)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_font_override("font", UI.font_ui)
		b.add_theme_font_size_override("font_size", 12)
		b.add_theme_stylebox_override("normal", UI.button_style("default", false))
		b.add_theme_stylebox_override("hover", UI.button_style("default", true))
		var sel := UI.button_style("primary", true)
		sel.bg_color = Color(0.03, 0.13, 0.16, 0.96)
		b.add_theme_stylebox_override("pressed", sel)
		b.add_theme_color_override("font_color", UI.C_MUTED)
		b.add_theme_color_override("font_pressed_color", UI.C_CYAN)
		b.add_theme_color_override("font_hover_color", UI.C_TEXT)
		if str(opt.value) == current:
			b.set_pressed_no_signal(true)
		var val := str(opt.value)
		b.toggled.connect(func(on: bool):
			if on:
				GS.plan[field] = val
				Sfx.play("click")
				_refresh_assessment()
		)
		grid.add_child(b)
	return v

func _crew_block() -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	v.add_child(UI.mk_kicker("FIELD TEAM / 随行队友"))
	var hired := GS.hired_crew()
	if hired.is_empty():
		var warn := HBoxContainer.new()
		warn.add_theme_constant_override("separation", 10)
		warn.add_child(UI.mk_label("没有队友。你可以独自远程行动，但所有物理动作都会更难。", 11, UI.C_AMBER, {"wrap": true, "width": 520}))
		var b := UI.mk_button("去团队招募", "primary", 130, 34)
		b.pressed.connect(func(): main.navigate("crew"))
		warn.add_child(b)
		v.add_child(warn)
		return v
	v.add_child(UI.mk_label("行动最多带 3 人。不在名单里的佣兵不会出现在现场。", 10, UI.C_DIM))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	v.add_child(grid)
	var selected: Array = GS.plan.get("crew_ids", [])
	for c in hired:
		var cid := str(c.get("id", ""))
		var b := Button.new()
		b.toggle_mode = true
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var skills: Dictionary = c.get("skills", {})
		var top := _top_skills(skills)
		b.text = "%s · %s\n%s · 分成 ¥%s · 伤 %d" % [
			str(c.get("name", "")), str(c.get("role", "")), top,
			UI.fmt_money(int(c.get("price", 0))), int(c.get("injury", 0)),
		]
		b.custom_minimum_size = Vector2(0, 56)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_font_override("font", UI.font_ui)
		b.add_theme_font_size_override("font_size", 12)
		b.add_theme_stylebox_override("normal", UI.button_style("default", false))
		b.add_theme_stylebox_override("hover", UI.button_style("default", true))
		var sel := UI.button_style("primary", true)
		sel.bg_color = Color(0.03, 0.13, 0.16, 0.96)
		b.add_theme_stylebox_override("pressed", sel)
		b.add_theme_color_override("font_color", UI.C_MUTED)
		b.add_theme_color_override("font_pressed_color", UI.C_CYAN)
		b.set_pressed_no_signal(selected.has(cid))
		b.toggled.connect(func(on: bool):
			var ids: Array = GS.plan.get("crew_ids", [])
			if on:
				if ids.size() >= GS.MAX_CREW:
					b.set_pressed_no_signal(false)
					return
				if not ids.has(cid):
					ids.append(cid)
			else:
				ids.erase(cid)
			GS.plan["crew_ids"] = ids
			Sfx.play("click")
			_refresh_assessment()
		)
		grid.add_child(b)
	return v

func _top_skills(skills: Dictionary) -> String:
	var keys := skills.keys()
	keys.sort_custom(func(a, b): return int(skills[a]) > int(skills[b]))
	var parts: Array = []
	for i in range(mini(3, keys.size())):
		var k := str(keys[i])
		var names := {"intrusion": "入侵", "ew": "电子战", "analysis": "分析", "stealth": "潜行", "tech": "技术", "social": "交涉", "combat": "战斗", "nerve": "意志"}
		parts.append("%s%d" % [names.get(k, k), int(skills[k])])
	return " ".join(PackedStringArray(parts))

func _gear_block() -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	v.add_child(UI.mk_kicker("LOADOUT / 携带装备"))
	var owned: Array = GS.player.get("gear", [])
	if owned.is_empty():
		v.add_child(UI.mk_label("没有装备。去 GEAR 买点东西，或者靠手速。", 11, UI.C_DIM, {"wrap": true}))
		return v
	var grid := GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	v.add_child(grid)
	var selected: Array = GS.plan.get("gear_ids", [])
	for id in owned:
		var item := GS.gear_item(str(id))
		var b := Button.new()
		b.toggle_mode = true
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.text = "%s\n%s" % [str(item.get("name", id)), str(item.get("desc", ""))]
		b.custom_minimum_size = Vector2(0, 52)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_font_override("font", UI.font_ui)
		b.add_theme_font_size_override("font_size", 12)
		b.add_theme_stylebox_override("normal", UI.button_style("default", false))
		b.add_theme_stylebox_override("hover", UI.button_style("default", true))
		var sel := UI.button_style("primary", true)
		sel.bg_color = Color(0.03, 0.13, 0.16, 0.96)
		b.add_theme_stylebox_override("pressed", sel)
		b.add_theme_color_override("font_color", UI.C_MUTED)
		b.add_theme_color_override("font_pressed_color", UI.C_CYAN)
		var gid := str(id)
		b.set_pressed_no_signal(selected.has(gid))
		b.toggled.connect(func(on: bool):
			var ids: Array = GS.plan.get("gear_ids", [])
			if on:
				if not ids.has(gid):
					ids.append(gid)
			else:
				ids.erase(gid)
			GS.plan["gear_ids"] = ids
			Sfx.play("click")
			_refresh_assessment()
		)
		grid.add_child(b)
	return v

func _plan_payload() -> Dictionary:
	var crew_list: Array = []
	for id in GS.plan.get("crew_ids", []):
		var c = GS.crew_by_id(str(id))
		if c != null:
			crew_list.append(c)
	var gear: Array = []
	for id in GS.plan.get("gear_ids", []):
		var item := GS.gear_item(str(id))
		if not item.is_empty():
			gear.append({"name": item.name, "desc": item.desc})
	return {
		"approach": str(GS.plan.get("approach", "潜入")),
		"entry": str(GS.plan.get("entry", "")),
		"exit": str(GS.plan.get("exit", "")),
		"crew": crew_list,
		"gear": gear,
	}

func _refresh_assessment() -> void:
	if right_box == null:
		return
	for ch in right_box.get_children():
		ch.queue_free()
	var c: Dictionary = GS.active_contract if GS.active_contract != null else {}
	var payload := _plan_payload()
	var crew_list: Array = payload.crew
	var cuts := 0
	for m in crew_list:
		cuts += int(m.get("price", 0))
	var gross := int(c.get("pay", 0))
	var advance := int(c.get("advance", 0))
	var net_full := maxi(0, gross - advance - cuts)

	right_box.add_child(UI.mk_kicker("SIMULATION / 计划推演"))
	var risk := UI.mk_panel(Color(0.02, 0.045, 0.058, 0.95), UI.C_BORDER_DIM, {"margin": 12})
	var rv := VBoxContainer.new()
	rv.add_theme_constant_override("separation", 8)
	risk.add_child(rv)
	var rrow := HBoxContainer.new()
	rrow.add_theme_constant_override("separation", 14)
	rv.add_child(rrow)
	rrow.add_child(_stat_block("预估净收入", "¥ " + UI.fmt_money(net_full), UI.C_AMBER))
	rrow.add_child(_stat_block("队友分成", "¥ " + UI.fmt_money(cuts), UI.C_MUTED))
	rrow.add_child(_stat_block("起始热度", "+%d" % int(GS.approach_heat(str(GS.plan.get("approach", "潜入")))), UI.C_MAGENTA))
	rv.add_child(UI.mk_hline(UI.C_BORDER_DIM))
	var stages := ["接近", "渗透", "目标", "撤离"]
	var best_skill := "stealth"
	match str(GS.plan.get("approach", "潜入")):
		"强攻":
			best_skill = "combat"
		"社交":
			best_skill = "social"
		"电子战":
			best_skill = "intrusion"
		_:
			best_skill = "stealth"
	for i in range(4):
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		row.add_child(UI.mk_label(stages[i], 11, UI.C_MUTED, {"width": 46}))
		var dc := _preview_dc(i, best_skill, crew_list)
		var stat := _best_stat(best_skill, crew_list)
		var chance := clampi((11 - (dc - stat)) * 10, 5, 95)
		row.add_child(UI.mk_label("DC %d" % dc, 11, UI.C_AMBER, {"mono": true, "width": 52}))
		row.add_child(UI.mk_meter(chance, 100, UI.C_CYAN if chance >= 60 else UI.C_AMBER, 130, 10))
		row.add_child(UI.mk_label("%d%%" % chance, 11, UI.C_TEXT, {"mono": true}))
		rv.add_child(row)
	right_box.add_child(risk)

	var team := UI.mk_panel(Color(0.016, 0.032, 0.044, 0.92), UI.C_BORDER_DIM, {"margin": 12})
	var tv := VBoxContainer.new()
	tv.add_theme_constant_override("separation", 6)
	team.add_child(tv)
	tv.add_child(UI.mk_kicker("FIELD TEAM / 现场配置"))
	if crew_list.is_empty():
		if GS.hired_crew().is_empty():
			tv.add_child(UI.mk_label("独自行动。没有队友替你承担现场风险。", 12, UI.C_AMBER, {"wrap": true}))
		else:
			tv.add_child(UI.mk_label("尚未选择随行队友。直接开始会独自行动。", 12, UI.C_AMBER, {"wrap": true}))
	else:
		for m in crew_list:
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 8)
			row.add_child(UI.mk_label(str(m.get("name", "")), 12, UI.C_TEXT, {"width": 68}))
			row.add_child(UI.mk_label(str(m.get("role", "")), 10, UI.C_CYAN_DIM, {"width": 40}))
			row.add_child(UI.mk_label(_top_skills(m.get("skills", {})), 10, UI.C_MUTED))
			var sp := Control.new()
			sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
			row.add_child(sp)
			row.add_child(UI.mk_label("¥%s" % UI.fmt_money(int(m.get("price", 0))), 10, UI.C_AMBER, {"mono": true}))
			tv.add_child(row)
	tv.add_child(UI.mk_hline(UI.C_BORDER_DIM))
	tv.add_child(UI.mk_label("装备：" + _gear_names(), 10, UI.C_DIM, {"wrap": true}))
	right_box.add_child(team)

	var audit_panel := UI.mk_panel(Color(0.016, 0.032, 0.044, 0.92), UI.C_BORDER_DIM, {"margin": 12})
	var av := VBoxContainer.new()
	av.add_theme_constant_override("separation", 6)
	audit_panel.add_child(av)
	var ah := HBoxContainer.new()
	ah.add_theme_constant_override("separation", 8)
	ah.add_child(UI.mk_portrait(Vector2(44, 52), UI.C_CYAN))
	ah.add_child(UI.mk_kicker("MIRAGE AUDIT / 蜃楼评估"))
	var sp2 := Control.new()
	sp2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sp2.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ah.add_child(sp2)
	var ab := UI.mk_button("请求评估", "ghost", 100, 28)
	ab.add_theme_font_size_override("font_size", 11)
	ab.disabled = audit_loading
	ab.pressed.connect(_request_audit)
	ah.add_child(ab)
	av.add_child(ah)
	if audit_loading:
		av.add_child(UI.mk_label("蜃楼正在看你的计划……", 12, UI.C_AMBER))
	elif not audit.is_empty():
		av.add_child(UI.mk_label("%s · 风险 %d/100" % [str(audit.get("verdict", "")), int(audit.get("risk_score", 0))], 13, UI.risk_color("高" if int(audit.get("risk_score", 0)) > 65 else "中")))
		for note in audit.get("notes", []):
			av.add_child(UI.mk_label("· " + str(note), 11, UI.C_MUTED, {"wrap": true}))
		if str(audit.get("line", "")) != "":
			av.add_child(UI.mk_label("「%s」" % str(audit.get("line", "")), 11, UI.C_CYAN_DIM, {"wrap": true}))
	else:
		av.add_child(UI.mk_label("让蜃楼先看一遍计划，能提前发现一些愚蠢的死法。", 11, UI.C_DIM, {"wrap": true}))
	right_box.add_child(audit_panel)

	var start := UI.mk_button("开始行动 / EXECUTE", "primary", 380, 54)
	start.pressed.connect(_start_run)
	right_box.add_child(start)
	right_box.add_child(UI.mk_label("开始后无法退出，除非中止行动。判定由系统掷骰，叙事由 PI 生成。", 10, UI.C_DIM, {"wrap": true}))

func _stat_block(label: String, value: String, color: Color) -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	v.add_child(UI.mk_label(label, 10, UI.C_DIM, {"mono": true}))
	v.add_child(UI.mk_label(value, 16, color, {"mono": true, "bold": true}))
	return v

func _preview_dc(beat_index: int, skill: String, crew_list: Array) -> int:
	var c: Dictionary = GS.active_contract if GS.active_contract != null else {}
	var dc := 6 + GS.risk_index(str(c.get("risk", "中"))) + beat_index
	dc += GS.approach_modifier(skill, str(GS.plan.get("approach", "潜入")))
	if beat_index == 0 and str(GS.plan.get("entry", "")) != "":
		dc -= 1
	if beat_index == 3 and str(GS.plan.get("exit", "")) != "":
		dc -= 1
	if not crew_list.is_empty():
		dc += int(crew_list[0].get("injury", 0))
	return clampi(dc, 4, 14)

func _best_stat(skill: String, crew_list: Array) -> int:
	var best := int(GS.player.get("skills", {}).get(skill, 2))
	for m in crew_list:
		best = maxi(best, int(m.get("skills", {}).get(skill, 2)) - int(m.get("injury", 0)))
	return best

func _gear_names() -> String:
	var names: Array = []
	for id in GS.plan.get("gear_ids", []):
		var item := GS.gear_item(str(id))
		if not item.is_empty():
			names.append(str(item.name))
	return "、".join(PackedStringArray(names)) if not names.is_empty() else "无"

func debug_audit() -> void:
	_request_audit()

func _request_audit() -> void:
	audit_loading = true
	_refresh_assessment()
	var res: Dictionary = await Bridge.request("plan_audit", {
		"state": GS.state_for_bridge(),
		"plan": _plan_payload(),
	}, {"stream": false})
	audit_loading = false
	if bool(res.get("ok", false)) and res.get("data", null) != null:
		audit = res.data
	else:
		main.toast("蜃楼没有回应。" , UI.C_AMBER)
	_refresh_assessment()

func _start_run() -> void:
	if GS.active_contract == null:
		main.toast("没有进行中的委托。", UI.C_RED)
		return
	if GS.plan.get("crew_ids", []).is_empty():
		main.show_modal("独自行动？", "没有现场队友，所有物理动作只能由你远程处理，判定难度会更高。\n\n仍然开始吗？", [
			{"label": "仍然开始", "kind": "danger", "callback": _execute},
			{"label": "回去组队", "kind": "ghost", "callback": func(): main.navigate("crew")},
		], UI.C_AMBER)
	else:
		_execute()

func _execute() -> void:
	GS.save_game()
	GS.begin_run()
	Sfx.play("alert")
	main.navigate("run")





