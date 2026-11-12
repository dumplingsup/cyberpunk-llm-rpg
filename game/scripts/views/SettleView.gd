extends Control
## Debrief: authoritative payout table + LLM-written epilogue and consequences.

var main = null
var results: Dictionary = {}
var extras: Dictionary = {}
var epilogue: RichTextLabel
var extras_box: VBoxContainer
var stream_id := ""
var streamed := 0
var finish_button: Button
var net_label: Label
var row_values: Dictionary = {}
var back_button: Button
var _net_tween: Tween = null

func _ready() -> void:
	results = GS.last_settlement
	_build()
	var successes := int(results.get("successes", 0))
	var alarms := int(results.get("alarms", 0))
	var color := UI.C_GREEN if successes >= 3 and alarms < 3 else (UI.C_AMBER if successes >= 2 else UI.C_RED)
	FX.flash(color, 0.12, 0.5)
	_net_tween = FX.money_count(net_label, int(results.get("net", 0)), 1.0, "¥ ")
	FX.pulse(net_label, 1.06, 0.4)
	call_deferred("_animate_debrief")
	Bridge.task_delta.connect(_on_delta)
	call_deferred("_request")

func _build() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var root := MarginContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	root.add_child(vb)
	var c: Dictionary = GS.last_contract if GS.last_contract != null else {}
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	vb.add_child(head)
	var tv := VBoxContainer.new()
	tv.add_theme_constant_override("separation", 0)
	head.add_child(tv)
	tv.add_child(UI.mk_kicker("DEBRIEF / 行动结算"))
	tv.add_child(UI.mk_label("结算", 24, UI.C_TEXT, {"bold": true}))
	var sub := UI.mk_label("「%s」 · %s" % [str(c.get("codename", "")), str(c.get("objective", ""))], 12, UI.C_CYAN)
	sub.size_flags_vertical = Control.SIZE_SHRINK_END
	head.add_child(sub)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(sp)
	var archive_btn := UI.mk_button("查看档案", "ghost", 110, 36)
	archive_btn.pressed.connect(func(): main.navigate("archive"))
	head.add_child(archive_btn)
	finish_button = UI.mk_button("返回工作台", "primary", 150, 36)
	finish_button.disabled = true
	finish_button.pressed.connect(_return)
	head.add_child(finish_button)

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 10)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(body)

	var left := UI.mk_panel(Color(0.008, 0.017, 0.024, 0.97), UI.C_BORDER_DIM, {"margin": 12})
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(left)
	var lv := VBoxContainer.new()
	lv.add_theme_constant_override("separation", 8)
	left.add_child(lv)
	var lh := HBoxContainer.new()
	lh.add_theme_constant_override("separation", 10)
	lh.add_child(UI.mk_portrait(Vector2(42, 50), UI.C_CYAN))
	lh.add_child(UI.mk_kicker("AFTER ACTION / 行动之后"))
	lh.add_child(UI.mk_label("蜃楼 · 加密语音", 11, UI.C_MAGENTA, {"mono": true}))
	lv.add_child(lh)
	lv.add_child(UI.mk_hline(UI.C_BORDER_DIM))
	var scroll := UI.mk_scroll()
	lv.add_child(scroll)
	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_top", 8)
	pad.add_theme_constant_override("margin_right", 8)
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(pad)
	epilogue = UI.mk_rich(15, UI.C_TEXT)
	epilogue.fit_content = true
	epilogue.scroll_active = false
	epilogue.custom_minimum_size = Vector2(700, 400)
	pad.add_child(epilogue)

	var right := UI.mk_panel(Color(0.014, 0.026, 0.036, 0.95), UI.C_BORDER_DIM, {"margin": 0})
	right.custom_minimum_size.x = 440
	body.add_child(right)
	var rscroll := UI.mk_scroll()
	right.add_child(rscroll)
	var rpad := MarginContainer.new()
	rpad.add_theme_constant_override("margin_left", 20)
	rpad.add_theme_constant_override("margin_right", 20)
	rpad.add_theme_constant_override("margin_top", 18)
	rpad.add_theme_constant_override("margin_bottom", 18)
	rpad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rscroll.add_child(rpad)
	var rv := VBoxContainer.new()
	rv.add_theme_constant_override("separation", 10)
	rpad.add_child(rv)
	rv.add_child(UI.mk_kicker("PAYOUT / 账目"))
	net_label = UI.mk_label("¥ " + UI.fmt_money(int(results.get("net", 0))), 40, UI.C_AMBER, {"bold": true, "mono": true})
	rv.add_child(net_label)
	rv.add_child(UI.mk_label("净收入", 10, UI.C_DIM, {"mono": true}))
	rv.add_child(UI.mk_hline(UI.C_BORDER_DIM))
	var table := VBoxContainer.new()
	table.add_theme_constant_override("separation", 4)
	rv.add_child(table)
	_row(table, "成功节拍", "%d / 4" % int(results.get("successes", 0)), UI.C_GREEN)
	_row(table, "警报等级", "%d / 3" % int(results.get("alarms", 0)), UI.C_RED if int(results.get("alarms", 0)) >= 3 else UI.C_AMBER)
	_row(table, "基础报酬", "+ ¥" + UI.fmt_money(int(results.get("gross", results.get("pay", 0)))), UI.C_TEXT)
	_row(table, "预付款", "- ¥" + UI.fmt_money(int(results.get("advance", 0))), UI.C_MUTED)
	_row(table, "队友分成", "- ¥" + UI.fmt_money(int(results.get("cuts", 0))), UI.C_MUTED)
	_row(table, "医疗支出", "- ¥" + UI.fmt_money(int(results.get("expenses", 0))), UI.C_MUTED)
	_row(table, "战利品", "+ ¥" + UI.fmt_money(int(results.get("loot_value", 0))), UI.C_AMBER, "loot")
	rv.add_child(UI.mk_hline(UI.C_BORDER_DIM))
	var heat_row := HBoxContainer.new()
	heat_row.add_theme_constant_override("separation", 8)
	heat_row.add_child(UI.mk_label("热度", 11, UI.C_DIM, {"width": 90}))
	heat_row.add_child(UI.mk_label("+%d" % int(results.get("heat", 0)), 14, UI.C_MAGENTA, {"mono": true, "bold": true}))
	heat_row.add_child(UI.mk_label("声望", 11, UI.C_DIM, {"width": 46}))
	heat_row.add_child(UI.mk_label("+%d" % int(results.get("rep", 0)), 14, UI.C_CYAN, {"mono": true, "bold": true}))
	rv.add_child(heat_row)
	var injuries: Array = results.get("injuries", [])
	if not injuries.is_empty():
		rv.add_child(UI.mk_label("伤者：" + "、".join(PackedStringArray(injuries)), 11, UI.C_RED, {"wrap": true}))
	var loot: Array = results.get("loot", [])
	if not loot.is_empty():
		rv.add_child(UI.mk_hline(UI.C_BORDER_DIM))
		rv.add_child(UI.mk_kicker("LOOT / 战利品"))
		for item in loot:
			var row := VBoxContainer.new()
			row.add_theme_constant_override("separation", 0)
			row.add_child(UI.mk_label(str(item.get("name", "物件")), 13, UI.C_AMBER, {"bold": true}))
			row.add_child(UI.mk_label(str(item.get("desc", "")), 10, UI.C_MUTED, {"wrap": true}))
			rv.add_child(row)
	rv.add_child(UI.mk_hline(UI.C_BORDER_DIM))
	extras_box = VBoxContainer.new()
	extras_box.add_theme_constant_override("separation", 8)
	rv.add_child(extras_box)
	extras_box.add_child(UI.mk_kicker("CONSEQUENCES / 后果"))
	extras_box.add_child(UI.mk_label("正在等蜃楼把话说完……", 12, UI.C_DIM))
	rv.add_child(UI.mk_spacer(10))
	back_button = UI.mk_button("返回工作台 / CONTINUE", "primary", 380, 48)
	back_button.disabled = true
	back_button.pressed.connect(_return)
	rv.add_child(back_button)

func _row(parent: VBoxContainer, label: String, value: String, color: Color, key: String = "") -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.add_child(UI.mk_label(label, 11, UI.C_DIM, {"width": 120}))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(sp)
	var value_label := UI.mk_label(value, 13, color, {"mono": true})
	row.add_child(value_label)
	if key != "":
		row_values[key] = value_label
	parent.add_child(row)

func _animate_debrief() -> void:
	await get_tree().process_frame
	if is_instance_valid(net_label):
		net_label.pivot_offset = net_label.size * 0.5
	FX.stagger(extras_box.get_parent(), 0.025, 0.99)

func _request() -> void:
	get_tree().create_timer(8.0).timeout.connect(func():
		if is_instance_valid(finish_button):
			finish_button.disabled = false
			back_button.disabled = false
	)
	var state := GS.state_for_bridge()
	state["contract"] = GS.last_contract
	var payload := results.duplicate(true)
	if payload.has("loot"):
		var names: Array = []
		for item in payload.loot:
			names.append(str(item.get("name", "")))
		payload["loot"] = names
	finish_button.disabled = true
	var id := Bridge.ask_now("settle", {"state": state, "results": payload}, {"stream": true})
	stream_id = id
	streamed = 0
	while true:
		var args: Array = await Bridge.task_finished
		if str(args[0]) != id:
			continue
		var res: Dictionary = args[1]
		if str(res.get("type", "")) == "error" or not bool(res.get("ok", false)):
			if streamed == 0:
				epilogue.add_text(_fallback_epilogue())
			main.toast("结算叙事离线，账目已经结算完成。", UI.C_AMBER)
			finish_button.disabled = false
			back_button.disabled = false
			return
		if streamed == 0 and str(res.get("narration", "")) != "":
			epilogue.add_text(str(res.get("narration", "")))
		var d = res.get("data", {})
		if typeof(d) == TYPE_DICTIONARY:
			extras = d
			_apply_extras(extras)
		finish_button.disabled = false
		back_button.disabled = false
		return

func _on_delta(id: String, text: String) -> void:
	if id != stream_id or text == "":
		return
	streamed += text.length()
	epilogue.add_text(text)

func _apply_extras(data: Dictionary) -> void:
	if data.is_empty():
		return
	for item in data.get("loot", []):
		var loot_value := int(item.get("value", 0))
		GS.credits += loot_value
		GS.archive_add("战利品 · %s" % str(item.get("name", "")), str(item.get("desc", "")))
		GS.note("战利品：「%s」%s。" % [str(item.get("name", "")), ("（+¥%s）" % UI.fmt_money(loot_value)) if loot_value > 0 else ""], UI.C_AMBER)
	if str(data.get("world_change", "")) != "":
		GS.archive_add("世界变化", str(data.get("world_change", "")))
		GS.note(str(data.get("world_change", "")), UI.C_MAGENTA)
	if str(data.get("hook", "")) != "":
		GS.note("下一单的引子：%s" % str(data.get("hook", "")), UI.C_CYAN)
		GS.archive_add("后续钩子", str(data.get("hook", "")))
	for secret in data.get("secrets", []):
		var c = GS.crew_by_id(str(secret.get("crew", "")))
		if c != null:
			c["secret_revealed"] = true
			GS.archive_add("秘密 · %s" % str(c.get("name", "")), str(secret.get("secret", "")))
	for line in data.get("crew_lines", []):
		var c2 = GS.crew_by_id(str(line.get("id", "")))
		if c2 != null:
			GS.note("%s：%s" % [str(c2.get("name", "")), str(line.get("line", ""))], UI.C_CYAN_DIM)
	GS.save_game()
	_render_extras(data)

func _render_extras(data: Dictionary) -> void:
	for ch in extras_box.get_children():
		ch.queue_free()
	extras_box.add_child(UI.mk_kicker("CONSEQUENCES / 后果"))
	if str(data.get("world_change", "")) != "":
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 1)
		v.add_child(UI.mk_label("世界变化", 10, UI.C_DIM, {"mono": true}))
		v.add_child(UI.mk_label(str(data.get("world_change", "")), 12, UI.C_MAGENTA, {"wrap": true}))
		extras_box.add_child(v)
	var loot_items: Array = data.get("loot", [])
	var extra_loot := 0
	for li in loot_items:
		extra_loot += int(li.get("value", 0))
	if extra_loot > 0:
		results["net"] = int(results.get("net", 0)) + extra_loot
		results["loot_value"] = int(results.get("loot_value", 0)) + extra_loot
		GS.last_settlement = results.duplicate(true)
		if _net_tween != null and _net_tween.is_valid():
			_net_tween.kill()
		if net_label != null:
			net_label.text = "¥ " + UI.fmt_money(int(results.get("net", 0)))
			FX.pulse(net_label, 1.05, 0.3)
			FX.flash(UI.C_AMBER, 0.07, 0.3)
		if row_values.has("loot"):
			row_values["loot"].text = "+ ¥" + UI.fmt_money(int(results.get("loot_value", 0)))
		GS.save_game()
	if not loot_items.is_empty():
		extras_box.add_child(UI.mk_kicker("LOOT / 带回来的东西"))
		for item in loot_items:
			var lrow := HBoxContainer.new()
			lrow.add_theme_constant_override("separation", 8)
			lrow.add_child(UI.mk_label(str(item.get("name", "物件")), 12, UI.C_AMBER, {"width": 100}))
			lrow.add_child(UI.mk_label("%s%s" % [str(item.get("desc", "")), ("  +¥%s" % UI.fmt_money(int(item.get("value", 0)))) if int(item.get("value", 0)) > 0 else ""], 10, UI.C_MUTED, {"wrap": true, "width": 280}))
			extras_box.add_child(lrow)
	var crew_lines: Array = data.get("crew_lines", [])
	for line in crew_lines:
		var c = GS.crew_by_id(str(line.get("id", "")))
		if c == null:
			continue
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		row.add_child(UI.mk_label(str(c.get("name", "")), 12, UI.C_CYAN, {"width": 64}))
		row.add_child(UI.mk_label(str(line.get("line", "")), 11, UI.C_MUTED, {"wrap": true, "width": 280}))
		extras_box.add_child(row)
	if str(data.get("hook", "")) != "":
		var h := VBoxContainer.new()
		h.add_theme_constant_override("separation", 1)
		h.add_child(UI.mk_label("下一步", 10, UI.C_DIM, {"mono": true}))
		h.add_child(UI.mk_label(str(data.get("hook", "")), 12, UI.C_CYAN_DIM, {"wrap": true}))
		extras_box.add_child(h)
	if str(data.get("fixer_line", "")) != "":
		extras_box.add_child(UI.mk_label("蜃楼：「%s」" % str(data.get("fixer_line", "")), 11, UI.C_AMBER, {"wrap": true}))

func _fallback_epilogue() -> String:
	var c: Dictionary = GS.last_contract if GS.last_contract != null else {}
	return "雨把%s外的霓虹洗成一团模糊的光。你关掉最后一个窗口，手指还停在键盘上。\n\n「%s」结束了。钱到账，名声往前挪了一点，城市的某个角落多了一条关于你的痕迹。蜃楼没有再说话，只有数据流在耳机里轻轻响着。\n\n你还有下一单要接。" % [str(c.get("location", "现场")), str(c.get("codename", "行动"))]

func _return() -> void:
	main.navigate("inbox")
	main._ensure_offers(true)
	if int(GS.stats.get("jobs", 0)) % 2 == 0:
		main._ensure_crew()






