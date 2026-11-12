extends Control
## NEON VEIL — main workbench shell, navigation, campaign bootstrap.

const NAV := [
	{"id": "inbox", "num": "01", "label": "委托", "en": "INBOX"},
	{"id": "crew", "num": "02", "label": "团队", "en": "CREW"},
	{"id": "plan", "num": "03", "label": "计划", "en": "PLAN"},
	{"id": "run", "num": "04", "label": "行动", "en": "RUN"},
	{"id": "gear", "num": "05", "label": "装备", "en": "GEAR"},
	{"id": "archive", "num": "06", "label": "档案", "en": "ARCHIVE"},
]

const VIEW_SCRIPTS := {
	"inbox": preload("res://scripts/views/InboxView.gd"),
	"crew": preload("res://scripts/views/CrewView.gd"),
	"plan": preload("res://scripts/views/PlanView.gd"),
	"run": preload("res://scripts/views/RunView.gd"),
	"gear": preload("res://scripts/views/GearView.gd"),
	"archive": preload("res://scripts/views/ArchiveView.gd"),
	"settle": preload("res://scripts/views/SettleView.gd"),
}

var content_holder: MarginContainer
var current_view = null
var current_nav := ""
var nav_buttons: Dictionary = {}
var nav_group: ButtonGroup
var credit_stat: PanelContainer
var rep_stat: PanelContainer
var day_stat: PanelContainer
var heat_meter = null
var heat_label: Label
var heat_box: PanelContainer
var _prev_heat := -1
var _prev_credits := -1
var _prev_rep := -1
var link_dot: PanelContainer
var link_label: Label
var model_label: Label
var active_label: Label
var shell: Control
var scrim: ColorRect
var ticker_label: Label
var save_label: Label

var toast_layer: VBoxContainer
var modal_layer: Control
var chat_layer: Control
var loading_layer: Control
var loading_title: Label
var loading_sub: Label
var loading_time: Label
var loading_hint: Label
var loading_bar: ProgressBar
var loading_active := false
var loading_t0 := 0
var loading_started := false

var title_layer: Control
var title_menu: Control
var title_creation: Control
var creation_handle: LineEdit
var selected_specialty := "ghost"
var specialty_buttons: Dictionary = {}
var begin_button: Button

var offers_generating := false
var crew_generating := false
var status_timer: Timer

func _ready() -> void:
	theme = UI.theme
	_build_background()
	_build_scrim()
	_build_shell()
	_build_overlays()
	_connect_bridge()
	status_timer = Timer.new()
	status_timer.wait_time = 25.0
	status_timer.autostart = true
	status_timer.timeout.connect(func(): Bridge.request_status())
	add_child(status_timer)
	if OS.get_cmdline_user_args().has("--test-loop"):
		call_deferred("_run_loop_test")
		return
	_show_title()
	GS.note_added.connect(_on_note)
	GS.state_changed.connect(_refresh_header)
	_handle_debug_shot()

func _run_loop_test() -> void:
	print("=== NEON VEIL LOOP TEST ===")
	var fails: Array = []
	var check := func(cond: bool, msg: String) -> void:
		if cond:
			print("  [ok] ", msg)
		else:
			print("  [FAIL] ", msg)
			fails.append(msg)
	GS.new_game("TESTER", "ghost")
	Bridge.connect_bridge(GS.campaign_id, "TESTER")
	var waited := 0.0
	while not Bridge.server_ready and waited < 20.0:
		await get_tree().create_timer(0.2).timeout
		waited += 0.2
	check.call(Bridge.server_ready, "bridge handshake")
	var state := GS.state_for_bridge()
	var cres: Dictionary = await Bridge.request("contracts", {"state": state, "count": 3}, {"stream": false})
	check.call(bool(cres.get("ok", false)), "contracts response ok")
	var clist: Array = cres.get("data", {}).get("contracts", [])
	check.call(clist.size() == 3, "3 contracts generated")
	GS.contracts = clist
	GS.save_game()
	check.call(GS.accept_contract(str(clist[0].get("id", ""))), "accept contract")
	check.call(GS.active_contract != null, "active contract set")
	var wres: Dictionary = await Bridge.request("crew", {"state": GS.state_for_bridge(), "count": 3}, {"stream": false})
	check.call(bool(wres.get("ok", false)), "crew response ok")
	var wlist: Array = wres.get("data", {}).get("crew", [])
	check.call(wlist.size() >= 2, "at least 2 crew candidates")
	GS.add_crew_candidates(wlist)
	var hired := 0
	for c in GS.available_crew():
		if hired >= 2:
			break
		if GS.hire_crew(str(c.get("id", ""))):
			hired += 1
	check.call(hired == 2, "hire 2 crew")
	GS.plan = {"approach": "潜入", "entry": "消防梯", "exit": "后巷", "crew_ids": [], "gear_ids": GS.player.get("gear", [])}
	for c in GS.hired_crew():
		GS.plan["crew_ids"].append(str(c.get("id", "")))
	GS.save_game()
	GS.begin_run()
	check.call(not GS.run.is_empty(), "run initialized")
	var sres: Dictionary = await Bridge.request("run_start", {"state": GS.state_for_bridge(), "plan": {"approach": "潜入", "entry": "消防梯", "exit": "后巷", "crew": GS.crew_for_run(), "gear": []}}, {"stream": true})
	check.call(bool(sres.get("ok", false)), "run_start response ok")
	check.call(sres.get("data", {}).get("beat", null) != null, "run_start returned a beat")
	GS.run["beat"] = sres.get("data", {}).get("beat", {})
	GS.run["beat_index"] = 0
	var beats := 0
	var last_narration := ""
	for step in range(4):
		var beat = GS.run.get("beat", null)
		if typeof(beat) != TYPE_DICTIONARY:
			break
		var actions: Array = beat.get("actions", [])
		if actions.is_empty():
			break
		var free_text := ""
		var action: Dictionary = actions[0]
		if step == 1:
			free_text = "让针贴在摄像头死角，等我把走廊画面循环起来"
			action = {"label": free_text.substr(0, 48), "skill": "intrusion", "actor": "player", "risk": "中"}
		var result := GS.roll_action(action, free_text != "")
		print("  beat ", step + 1, " tier=", result.tier, " total=", result.total, " dc=", result.dc)
		var final_beat := int(GS.run.get("beat_index", 0)) >= 3
		var check_payload := {
			"actorName": str(result.actor_name), "skill": str(result.skill), "roll": int(result.roll),
			"stat": int(result.stat), "bonus": int(result.bonus), "total": int(result.total), "dc": int(result.dc),
		}
		var bres: Dictionary = await Bridge.request("run_beat", {
			"state": GS.state_for_bridge(), "beatIndex": int(GS.run.get("beat_index", 0)), "beat": beat,
			"action": action, "check": check_payload, "tier": str(result.tier), "finalBeat": final_beat,
			"freeText": free_text,
		}, {"stream": true})
		check.call(bool(bres.get("ok", false)), "run_beat %d response ok" % (step + 1))
		last_narration = str(bres.get("narration", ""))
		var data: Dictionary = bres.get("data", {})
		GS.apply_effects(data.get("effects", []))
		if bool(GS.run.get("broken", false)) or final_beat or data.get("next", null) == null:
			beats += 1
			break
		GS.run["beat"] = data.next
		GS.run["beat_index"] = int(GS.run.get("beat_index", 0)) + 1
		beats += 1
	check.call(beats >= 1, "at least one beat resolved")
	check.call(last_narration.length() > 30, "beat narration is substantive")
	var results := GS.finalize_run()
	check.call(GS.active_contract == null, "contract finalized")
	check.call(results.has("net"), "settlement computed")
	check.call(int(results.get("successes", 0)) >= 0, "successes recorded")
	check.call(GS.credits >= 0, "credits non-negative")
	var settle_res: Dictionary = await Bridge.request("settle", {"state": GS.state_for_bridge(), "results": results}, {"stream": true})
	check.call(bool(settle_res.get("ok", false)), "settle response ok")
	check.call(str(settle_res.get("narration", "")).length() > 50, "epilogue narration is substantive")
	print("=== RESULT: ", ("PASS" if fails.is_empty() else "FAIL %d" % fails.size()), " | beats=", beats, " net=", results.get("net", 0), " ===")
	get_tree().quit(0 if fails.is_empty() else 1)

func _handle_debug_shot() -> void:
	var shot := ""
	var delay := 1.4
	var auto_new := false
	var auto_accept := false
	var auto_hire := 0
	var auto_run := false
	var auto_continue := false
	var auto_creation := false
	var auto_recruit := false
	var auto_audit := false
	var auto_negotiate := false
	var auto_settle := false
	var view := ""
	var auto_actions := 0
	var debug_wait := 2.5
	var debug_chat := ""
	var debug_chat_text := ""
	var debug_free := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shot="):
			shot = arg.substr(7)
		elif arg.begins_with("--shot-delay="):
			delay = float(arg.substr(13))
		elif arg == "--debug-new":
			auto_new = true
		elif arg == "--debug-accept":
			auto_accept = true
		elif arg.begins_with("--debug-hire="):
			auto_hire = int(arg.substr(13))
		elif arg == "--debug-run":
			auto_run = true
		elif arg == "--debug-continue":
			auto_continue = true
		elif arg == "--debug-creation":
			auto_creation = true
		elif arg == "--debug-recruit":
			auto_recruit = true
		elif arg == "--debug-audit":
			auto_audit = true
		elif arg == "--debug-negotiate":
			auto_negotiate = true
		elif arg == "--debug-settle":
			auto_settle = true
		elif arg.begins_with("--debug-view="):
			view = arg.substr(13)
		elif arg.begins_with("--debug-actions="):
			auto_actions = int(arg.substr(16))
		elif arg.begins_with("--debug-wait="):
			debug_wait = float(arg.substr(13))
		elif arg.begins_with("--debug-chat="):
			debug_chat = arg.substr(13)
		elif arg.begins_with("--debug-chat-send="):
			debug_chat_text = arg.substr(18)
		elif arg.begins_with("--debug-free="):
			debug_free = arg.substr(13)
	if not auto_new and not auto_continue and not auto_creation and shot == "":
		return
	if auto_creation:
		await get_tree().create_timer(0.3).timeout
		_show_creation()
	if auto_continue:
		await get_tree().create_timer(0.3).timeout
		_continue_game()
		await get_tree().create_timer(debug_wait).timeout
		if view != "":
			navigate(view)
	if auto_new:
		await get_tree().create_timer(0.3).timeout
		creation_handle.text = "GHOST"
		_begin_new_game()
		await get_tree().create_timer(debug_wait).timeout
		if auto_accept and not GS.open_contracts().is_empty():
			GS.accept_contract(str(GS.open_contracts()[0].get("id", "")))
		if auto_hire > 0:
			var count := 0
			for c in GS.crew:
				if count >= auto_hire:
					break
				if GS.hire_crew(str(c.get("id", ""))):
					count += 1
		if auto_run and GS.active_contract != null:
			var ids: Array = []
			for c in GS.hired_crew():
				ids.append(str(c.get("id", "")))
			GS.plan["crew_ids"] = ids
			GS.begin_run()
			navigate("run")
		elif view != "":
			navigate(view)
		if debug_chat != "":
			var chat
			if debug_chat == "crew" and not GS.crew.is_empty():
				chat = open_chat("crew", str(GS.crew[0].get("id", "")))
			else:
				chat = open_chat("fixer")
			if debug_chat_text != "":
				await get_tree().create_timer(0.6).timeout
				chat.debug_send(debug_chat_text)
		if auto_settle and GS.active_contract != null:
			var ids: Array = []
			for c2 in GS.hired_crew():
				ids.append(str(c2.get("id", "")))
			GS.plan["crew_ids"] = ids
			GS.begin_run()
			GS.run["successes"] = 3
			GS.run["alarms"] = 1
			GS.run["failures"] = 1
			GS.run["highlights"] = ["针接入目标接口", "老猫压制走廊摄像头"]
			GS.run["approach"] = "潜入"
			GS.finalize_run()
			navigate("settle")
		if auto_audit:
			navigate("plan")
			await get_tree().create_timer(0.8).timeout
			if current_view != null and current_view.has_method("debug_audit"):
				current_view.debug_audit()
			await get_tree().create_timer(3.0).timeout
		if auto_negotiate:
			var offer = GS.open_contracts()
			if not offer.is_empty():
				GS.negotiating_contract = offer[0]
				var nchat = open_chat("fixer")
				await get_tree().create_timer(0.5).timeout
				nchat.debug_send("这单报酬能不能再加一点？再给我一条内部消息。" )
				await get_tree().create_timer(3.0).timeout
		if auto_recruit:
			var crew_wait := 0.0
			while GS.crew.is_empty() and crew_wait < 45.0:
				await get_tree().create_timer(0.5).timeout
				crew_wait += 0.5
			navigate("crew")
			await get_tree().create_timer(0.8).timeout
			if current_view != null and current_view.has_method("debug_recruit_first"):
				current_view.debug_recruit_first()
			await get_tree().create_timer(4.0).timeout
		if debug_free != "" and current_nav == "run" and current_view != null:
			await get_tree().create_timer(1.5).timeout
			if current_view.has_method("debug_free_input"):
				current_view.debug_free_input(debug_free)
			await get_tree().create_timer(2.5).timeout
		if auto_run and auto_actions > 0:
			for i in range(auto_actions):
				await get_tree().create_timer(1.1).timeout
				if current_nav == "run" and current_view != null and current_view.has_method("debug_take_action"):
					current_view.debug_take_action()
	if shot == "":
		return
	await get_tree().create_timer(delay).timeout
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var err := img.save_png(shot)
	print("[shot] ", shot, " err=", err, " size=", img.get_width(), "x", img.get_height())
	get_tree().quit()

func _build_scrim() -> void:
	scrim = ColorRect.new()
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scrim.color = Color(0.004, 0.008, 0.014, 0.46)
	scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(scrim)

func _build_background() -> void:
	var bg := preload("res://scripts/ui/Background.gd").new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

func _build_scanlines() -> void:
	var layer := ColorRect.new()
	layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = """
shader_type canvas_item;
float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}
void fragment() {
	float scan = 0.5 + 0.5 * sin(UV.y * 1500.0);
	float n = hash(floor(UV * vec2(1440.0, 810.0)) + floor(TIME * 7.0));
	float a = 0.008 + scan * 0.010 + n * 0.008;
	COLOR = vec4(0.0, 0.045, 0.055, a);
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = sh
	layer.material = mat
	add_child(layer)

func _build_shell() -> void:
	var margin := MarginContainer.new()
	shell = margin
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_bottom", 10)
	add_child(margin)
	_build_scanlines()
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 10)
	margin.add_child(outer)
	outer.add_child(_build_header())
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 10)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(body)
	body.add_child(_build_rail())
	content_holder = MarginContainer.new()
	content_holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(content_holder)
	outer.add_child(_build_footer())

func _build_header() -> Control:
	var panel := UI.mk_panel(Color(0.012, 0.022, 0.030, 0.94), UI.C_BORDER_DIM, {"margin": 10})
	panel.custom_minimum_size.y = 66
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)
	panel.add_child(h)

	var logo_box := VBoxContainer.new()
	logo_box.add_theme_constant_override("separation", -4)
	var logo := UI.mk_label("NEON VEIL", 28, UI.C_CYAN, {"bold": true})
	logo_box.add_child(logo)
	logo_box.add_child(UI.mk_label("霓虹帷幕 · 黑客工作台", 11, UI.C_MAGENTA, {"mono": true}))
	h.add_child(logo_box)
	h.add_child(UI.mk_vline(UI.C_BORDER_DIM, 1))

	var link_box := VBoxContainer.new()
	link_box.add_theme_constant_override("separation", 2)
	var link_row := HBoxContainer.new()
	link_row.add_theme_constant_override("separation", 6)
	link_dot = UI.mk_dot(UI.C_AMBER, 7)
	link_row.add_child(link_dot)
	link_row.add_child(UI.mk_label("PI NEURAL LINK", 10, UI.C_MUTED, {"mono": true}))
	link_label = UI.mk_label("STANDBY", 11, UI.C_AMBER, {"mono": true})
	link_row.add_child(link_label)
	link_box.add_child(link_row)
	model_label = UI.mk_label("LOCAL AGENT / DEEPSEEK", 10, UI.C_DIM, {"mono": true})
	link_box.add_child(model_label)
	h.add_child(link_box)

	active_label = UI.mk_label("", 11, UI.C_AMBER, {"mono": true})
	active_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	active_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	h.add_child(active_label)

	credit_stat = UI.mk_stat("CREDITS", "¥ 0", UI.C_AMBER, 128)
	h.add_child(credit_stat)
	rep_stat = UI.mk_stat("REP", "0", UI.C_CYAN, 92)
	h.add_child(rep_stat)
	day_stat = UI.mk_stat("DAY", "01", UI.C_MUTED, 82)
	h.add_child(day_stat)

	heat_box = PanelContainer.new()
	heat_box.add_theme_stylebox_override("panel", UI.style_bg(Color(0.012, 0.024, 0.033, 0.92), UI.C_BORDER_DIM, 1, 8, 2))
	var hv := VBoxContainer.new()
	hv.add_theme_constant_override("separation", 3)
	heat_box.add_child(hv)
	var hrow := HBoxContainer.new()
	hrow.add_theme_constant_override("separation", 6)
	hrow.add_child(UI.mk_label("HEAT", 10, UI.C_RED, {"mono": true}))
	heat_label = UI.mk_label("0/10", 11, UI.C_MUTED, {"mono": true})
	hrow.add_child(heat_label)
	hv.add_child(hrow)
	heat_meter = UI.mk_meter(0, 10, UI.C_MAGENTA, 92, 10)
	hv.add_child(heat_meter)
	heat_box.custom_minimum_size.x = 112
	h.add_child(heat_box)
	return panel

func _build_rail() -> Control:
	var panel := UI.mk_panel(Color(0.010, 0.020, 0.028, 0.92), UI.C_BORDER_DIM, {"margin": 10})
	panel.custom_minimum_size.x = 156
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	panel.add_child(v)
	v.add_child(UI.mk_kicker("WORKBENCH"))
	v.add_child(UI.mk_hline(UI.C_BORDER_DIM))
	nav_group = ButtonGroup.new()
	for item in NAV:
		var b := UI.mk_button("", "default", 0, 46)
		b.toggle_mode = true
		b.button_group = nav_group
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.text = "%s  %s\n      %s" % [item.num, item.label, item.en]
		b.add_theme_font_size_override("font_size", 13)
		b.add_theme_color_override("font_color", UI.C_MUTED)
		b.add_theme_color_override("font_pressed_color", UI.C_CYAN)
		b.add_theme_color_override("font_hover_color", UI.C_TEXT)
		b.add_theme_stylebox_override("normal", UI.style_bg(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 10, 0))
		var hov := UI.style_bg(Color(0.035, 0.085, 0.105, 0.7), UI.C_BORDER_DIM, 1, 10, 1)
		hov.border_width_left = 2
		hov.border_color = UI.C_CYAN_DIM
		b.add_theme_stylebox_override("hover", hov)
		var sel := UI.style_bg(Color(0.035, 0.105, 0.13, 0.95), UI.C_CYAN_DIM, 1, 10, 1)
		sel.border_width_left = 3
		sel.border_color = UI.C_CYAN
		b.add_theme_stylebox_override("pressed", sel)
		var id := str(item.id)
		b.toggled.connect(func(on: bool):
			if on:
				navigate(id)
		)
		v.add_child(b)
		nav_buttons[id] = b
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(spacer)
	v.add_child(UI.mk_hline(UI.C_BORDER_DIM))
	var rest := UI.mk_button("休整 / REST", "ghost", 0, 36)
	rest.tooltip_text = "推进一天：降低热度、恢复队友伤势，消耗 80 信用点"
	rest.pressed.connect(_on_rest)
	v.add_child(rest)
	save_label = UI.mk_label("SAVED", 9, UI.C_DIM, {"mono": true})
	v.add_child(save_label)
	v.add_child(UI.mk_label("BUILD 0.9.0", 9, UI.C_DIM, {"mono": true}))
	return panel

func _build_footer() -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	h.custom_minimum_size.y = 18
	ticker_label = UI.mk_label("安全屋系统就绪。所有通讯均在本地桥接层加密。", 11, UI.C_DIM, {"mono": true})
	ticker_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ticker_label.clip_text = true
	h.add_child(ticker_label)
	h.add_child(UI.mk_label("F1 静音", 10, UI.C_DIM, {"mono": true}))
	return h

func _build_overlays() -> void:
	FX.attach(self)
	toast_layer = VBoxContainer.new()
	toast_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	toast_layer.alignment = BoxContainer.ALIGNMENT_END
	toast_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast_layer.add_theme_constant_override("separation", 6)
	toast_layer.offset_left = 900
	toast_layer.offset_right = -24
	toast_layer.offset_top = -260
	toast_layer.offset_bottom = -46
	add_child(toast_layer)

	loading_layer = _build_loading_layer()
	add_child(loading_layer)
	loading_layer.visible = false

	chat_layer = Control.new()
	chat_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	chat_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(chat_layer)

	modal_layer = Control.new()
	modal_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	modal_layer.visible = false
	add_child(modal_layer)

	title_layer = _build_title_layer()
	add_child(title_layer)

func _build_loading_layer() -> Control:
	var layer := Control.new()
	layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0.005, 0.008, 0.012, 0.78)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	layer.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(center)
	var panel := UI.mk_panel(Color(0.015, 0.028, 0.038, 0.985), UI.C_CYAN_DIM, {"margin": 22, "min_width": 760})
	center.add_child(panel)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 20)
	panel.add_child(h)
	h.add_child(UI.mk_portrait(Vector2(104, 128), UI.C_CYAN))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(v)
	v.add_child(UI.mk_kicker("ENCRYPTED CHANNEL / PI AGENT"))
	loading_title = UI.mk_label("正在建立神经链路", 24, UI.C_TEXT, {"bold": true})
	v.add_child(loading_title)
	loading_sub = UI.mk_label("等待中间人回应……", 14, UI.C_MUTED, {"wrap": true, "width": 520})
	v.add_child(loading_sub)
	loading_bar = ProgressBar.new()
	loading_bar.custom_minimum_size = Vector2(520, 6)
	loading_bar.show_percentage = false
	loading_bar.max_value = 100
	loading_bar.value = 8
	v.add_child(loading_bar)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	loading_time = UI.mk_label("00:00", 11, UI.C_AMBER, {"mono": true})
	row.add_child(loading_time)
	loading_hint = UI.mk_label("链路加密中 · 正在解译", 11, UI.C_DIM, {"mono": true})
	row.add_child(loading_hint)
	v.add_child(row)
	return layer

func _build_title_layer() -> Control:
	var layer := Control.new()
	layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0.004, 0.007, 0.012, 0.28)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(dim)
	var grad := ColorRect.new()
	grad.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	grad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var gsh := Shader.new()
	gsh.code = """
shader_type canvas_item;
void fragment() {
	float left = 1.0 - smoothstep(0.02, 0.60, UV.x);
	float bottom = 1.0 - smoothstep(0.58, 0.96, UV.y);
	float a = 0.80 * left + 0.16 * bottom;
	COLOR = vec4(0.003, 0.006, 0.011, clamp(a, 0.0, 0.86));
}
"""
	var gmat := ShaderMaterial.new()
	gmat.shader = gsh
	grad.material = gmat
	layer.add_child(grad)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 90)
	margin.add_theme_constant_override("margin_right", 90)
	margin.add_theme_constant_override("margin_top", 70)
	margin.add_theme_constant_override("margin_bottom", 60)
	layer.add_child(margin)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 60)
	margin.add_child(h)

	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 8)
	h.add_child(left)
	var logo := UI.mk_label("NEON VEIL", 74, UI.C_CYAN, {"bold": true})
	left.add_child(logo)
	left.add_child(UI.mk_label("霓 虹 帷 幕", 22, Color("#ff5f95"), {"mono": false}))
	var accent := HBoxContainer.new()
	accent.add_theme_constant_override("separation", 0)
	var accent_parts := [[380.0, UI.C_CYAN], [80.0, UI.C_MAGENTA], [50.0, UI.C_BORDER]]
	for ap in accent_parts:
		var cr := ColorRect.new()
		cr.color = ap[1]
		cr.custom_minimum_size = Vector2(float(ap[0]), 2)
		cr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		accent.add_child(cr)
	left.add_child(accent)
	left.add_child(UI.mk_spacer(12))
	left.add_child(UI.mk_label("NO FACE. NO NAME. ONLY THE WORK.", 12, UI.C_MUTED, {"mono": true}))
	left.add_child(UI.mk_spacer(18))
	var boot := UI.mk_rich(12, UI.C_MUTED)
	boot.fit_content = true
	boot.scroll_active = false
	boot.custom_minimum_size = Vector2(620, 220)
	boot.bbcode_enabled = true
	boot.add_theme_constant_override("line_separation", 4)
	boot.text = "[color=#45626d]> BOOT NEON_VEIL/2.7[/color]\n[color=#45626d]  MOUNT /workbench ............ [/color][color=#63ffb4]OK[/color]\n[color=#45626d]  ANON ROUTING ................ [/color][color=#63ffb4]OK[/color]\n[color=#45626d]  LOCAL PI AGENT .............. [/color][color=#ffb454]STANDBY[/color]\n[color=#45626d]  IDENTITY .................... [/color][color=#ff2f78]UNKNOWN[/color]\n\n[color=#7896a0]你是澜港的一名黑客。没有人见过你，\n也没有人需要见到你。[/color]\n[color=#7896a0]屏幕那头的世界，由你决定谁活着、\n谁消失、谁的秘密被卖给出价最高的人。[/color]"
	left.add_child(boot)
	left.add_child(UI.mk_spacer(10, true))
	left.add_child(UI.mk_label("SECURE CHANNEL · 127.0.0.1:8791 · PI NEURAL LINK STANDBY · NO IDENTITY", 9, UI.C_CYAN_DIM, {"mono": true}))
	var blink := UI.mk_label("▍", 12, UI.C_MAGENTA, {"mono": true})
	left.add_child(blink)
	var blink_tw := create_tween().set_loops()
	blink_tw.tween_property(blink, "modulate:a", 0.1, 0.7)
	blink_tw.tween_property(blink, "modulate:a", 1.0, 0.7)
	left.add_child(UI.mk_label("LOCAL BUILD · GODOT 4.6 · PI AGENT 1.4 · PURE LOCAL SESSIONS", 9, UI.C_DIM, {"mono": true}))

	var vert := VBoxContainer.new()
	vert.anchor_left = 1.0
	vert.anchor_right = 1.0
	vert.offset_left = -38.0
	vert.offset_right = -12.0
	vert.offset_top = 140.0
	vert.offset_bottom = 420.0
	vert.add_theme_constant_override("separation", 6)
	layer.add_child(vert)
	for ch in ["澜", "港", "二", "〇", "八", "七"]:
		var vl := UI.mk_label(ch, 13, Color(0.35, 0.75, 0.82, 0.22), {"mono": true, "align": HORIZONTAL_ALIGNMENT_CENTER})
		vl.custom_minimum_size.x = 26
		vert.add_child(vl)

	title_menu = _build_title_menu()
	h.add_child(title_menu)
	title_creation = _build_creation_panel()
	title_creation.visible = false
	h.add_child(title_creation)
	return layer

func _build_title_menu() -> Control:
	var panel := UI.mk_panel(Color(0.014, 0.026, 0.036, 0.97), UI.C_BORDER_DIM, {"margin": 24, "min_width": 390})
	panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	panel.add_child(v)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 12)
	top.add_child(UI.mk_portrait(Vector2(90, 108), UI.C_CYAN))
	var tv := VBoxContainer.new()
	tv.add_theme_constant_override("separation", 1)
	tv.add_child(UI.mk_kicker("ACCESS TERMINAL // 进入工作台"))
	tv.add_child(UI.mk_label("蜃楼 MIRAGE-7", 15, UI.C_TEXT, {"bold": true}))
	tv.add_child(UI.mk_label("加密语音在线 / 中间人", 9, UI.C_CYAN_DIM, {"mono": true}))
	top.add_child(tv)
	v.add_child(top)
	v.add_child(UI.mk_label("你准备好上线了吗？", 22, UI.C_TEXT, {"bold": true}))
	v.add_child(UI.mk_label("所有记忆保存在本地。中间人、队友和这座城都会记住你做过的事。", 12, UI.C_MUTED, {"wrap": true, "width": 340}))
	v.add_child(UI.mk_spacer(8))
	var cont := UI.mk_button("继续行动 / CONTINUE", "primary", 340, 48)
	cont.pressed.connect(_continue_game)
	cont.disabled = not GS.has_save()
	cont.tooltip_text = "" if GS.has_save() else "还没有本地档案"
	v.add_child(cont)
	var newb := UI.mk_button("新的档案 / NEW CAMPAIGN", "default", 340, 44)
	newb.pressed.connect(_show_creation)
	v.add_child(newb)
	var quit := UI.mk_button("离开 / DISCONNECT", "ghost", 340, 36)
	quit.pressed.connect(func(): get_tree().quit())
	v.add_child(quit)
	if GS.has_save():
		v.add_child(UI.mk_hline(UI.C_BORDER_DIM))
		v.add_child(UI.mk_kicker("LAST KNOWN STATE"))
		var preview := GS.peek_save()
		var pl: Dictionary = preview.get("player", {})
		var text := "档案 %s ｜ 第 %d 天 ｜ ¥%s ｜ 声望 %d" % [
			str(pl.get("handle", "GHOST")),
			int(preview.get("day", 1)),
			UI.fmt_money(int(preview.get("credits", 0))),
			int(preview.get("rep", 0)),
		]
		v.add_child(UI.mk_label(text, 11, UI.C_AMBER, {"mono": true}))
	return panel

func _build_creation_panel() -> Control:
	var panel := UI.mk_panel(Color(0.014, 0.026, 0.036, 0.97), UI.C_BORDER_DIM, {"margin": 24, "min_width": 470})
	panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	panel.add_child(v)
	v.add_child(UI.mk_kicker("NEW IDENTITY // 建立档案"))
	v.add_child(UI.mk_label("起一个代号。", 22, UI.C_TEXT, {"bold": true}))
	creation_handle = LineEdit.new()
	creation_handle.text = "GHOST"
	creation_handle.placeholder_text = "代号 / HANDLE"
	creation_handle.max_length = 16
	creation_handle.custom_minimum_size = Vector2(420, 44)
	creation_handle.add_theme_font_override("font", UI.font_mono)
	creation_handle.add_theme_font_size_override("font_size", 18)
	v.add_child(creation_handle)
	v.add_child(UI.mk_label("选择你的专精。它决定你远程介入现场的方式。", 12, UI.C_MUTED, {"wrap": true, "width": 410}))
	var group := ButtonGroup.new()
	var specs := ["ghost", "weaver", "oracle"]
	for sid in specs:
		var spec: Dictionary = GS.SPECIALTIES[sid]
		var sk: Dictionary = spec.skills
		var skill_line := "入侵%d / 电子战%d / 分析%d / 意志%d" % [int(sk.get("intrusion", 0)), int(sk.get("ew", 0)), int(sk.get("analysis", 0)), int(sk.get("nerve", 0))]
		var b := Button.new()
		b.toggle_mode = true
		b.button_group = group
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.text = "%s · %s    %s\n%s" % [spec.name, spec.tag, skill_line, spec.desc]
		b.custom_minimum_size = Vector2(420, 78)
		b.add_theme_font_override("font", UI.font_ui)
		b.add_theme_font_size_override("font_size", 14)
		b.add_theme_stylebox_override("normal", UI.button_style("default", false))
		b.add_theme_stylebox_override("hover", UI.button_style("default", true))
		var sel := UI.button_style("primary", true)
		sel.bg_color = Color(0.03, 0.13, 0.16, 0.96)
		sel.border_color = UI.C_CYAN
		b.add_theme_stylebox_override("pressed", sel)
		b.add_theme_color_override("font_color", UI.C_MUTED)
		b.add_theme_color_override("font_pressed_color", UI.C_CYAN)
		b.add_theme_color_override("font_hover_color", UI.C_TEXT)
		b.button_pressed = sid == "ghost"
		var id := str(sid)
		b.toggled.connect(func(on: bool):
			if on:
				selected_specialty = id
		)
		v.add_child(b)
		specialty_buttons[id] = b
	v.add_child(UI.mk_spacer(6))
	begin_button = UI.mk_button("接入工作台 / JACK IN", "primary", 420, 50)
	begin_button.pressed.connect(_begin_new_game)
	v.add_child(begin_button)
	var back := UI.mk_button("返回", "ghost", 420, 32)
	back.pressed.connect(func():
		title_creation.visible = false
		title_menu.visible = true
	)
	v.add_child(back)
	return panel

func _show_title() -> void:
	if shell != null:
		shell.visible = false
	if scrim != null:
		scrim.visible = false
	title_layer.visible = true
	FX.fade_in(title_layer, 0.35)
	title_menu.visible = true
	title_creation.visible = false
	_refresh_header()
	if GS.has_save():
		pass

func _show_creation() -> void:
	title_menu.visible = false
	title_creation.visible = true
	creation_handle.grab_focus()
	creation_handle.select_all()

func _begin_new_game() -> void:
	var handle := creation_handle.text.strip_edges()
	if handle == "":
		handle = "GHOST"
	GS.new_game(handle, selected_specialty)
	title_layer.visible = false
	shell.visible = true
	_enter_campaign(true)

func _continue_game() -> void:
	if not GS.load_game():
		toast("存档读取失败，开始新的档案。", UI.C_RED)
		_show_creation()
		return
	title_layer.visible = false
	shell.visible = true
	_enter_campaign(false)

func _enter_campaign(is_new: bool) -> void:
	if scrim != null:
		scrim.visible = true
	Bridge.connect_bridge(GS.campaign_id, str(GS.player.get("handle", "GHOST")))
	if GS.active_contract != null:
		if not GS.run.is_empty() and not bool(GS.run.get("done", false)):
			navigate("run")
		else:
			navigate("plan")
	else:
		navigate("inbox")
	if is_new or GS.open_contracts().is_empty():
		if GS.active_contract == null:
			_ensure_offers(true)
	if GS.crew.size() < 3:
		_ensure_crew()

func _ensure_offers(force: bool = false) -> void:
	if offers_generating:
		return
	if not force and not GS.open_contracts().is_empty():
		return
	offers_generating = true
	show_loading("正在解译加密委托", "蜃楼正在把新的活塞进你的信箱。")
	var state := GS.state_for_bridge()
	var recent: Array = []
	for c in GS.contracts:
		recent.append(str(c.get("codename", "")))
	var res: Dictionary = await Bridge.request("contracts", {"state": state, "count": 3, "recentContracts": recent}, {"stream": false})
	offers_generating = false
	hide_loading()
	if bool(res.get("ok", false)) and res.get("data", {}).has("contracts"):
		var list: Array = res.data.contracts
		if not list.is_empty():
			GS.expire_open_contracts()
			GS.contracts = list
			GS.offers_day = GS.day
			GS.save_game()
			toast("收到 %d 份新的加密委托。" % list.size(), UI.C_CYAN)
			if bool(res.get("degraded", false)):
				toast("LINK DEGRADED · 本地叙事引擎接管。", UI.C_AMBER)
			if current_nav == "inbox" and current_view != null:
				current_view.refresh()
			elif current_nav != "run":
				navigate("inbox")
	else:
		toast("委托解译失败：%s" % str(res.get("message", "链路无响应")), UI.C_RED)

func _ensure_crew() -> void:
	if crew_generating:
		return
	crew_generating = true
	var state := GS.state_for_bridge()
	var res: Dictionary = await Bridge.request("crew", {"state": state, "count": 3}, {"stream": false})
	crew_generating = false
	if bool(res.get("ok", false)) and res.get("data", {}).has("crew"):
		var list: Array = res.data.crew
		if not list.is_empty():
			GS.add_crew_candidates(list)
			toast("%d 名新的佣兵上线。" % list.size(), UI.C_GREEN)
			if current_nav == "crew" and current_view != null:
				current_view.refresh()

func _connect_bridge() -> void:
	Bridge.link_changed.connect(_on_link_changed)
	Bridge.ready_received.connect(_on_bridge_ready)
	Bridge.status_received.connect(_on_bridge_status)
	Bridge.bridge_closed.connect(func(): toast("PI 神经网络链路断开，正在重连……", UI.C_RED))

func _on_bridge_ready(info: Dictionary) -> void:
	model_label.text = "PI %s / %s" % [str(info.get("pi", {}).get("version", "?")), str(info.get("model", "?")).to_upper()]
	_refresh_header()
	if not loading_active:
		toast("PI 神经链路已建立。" , UI.C_CYAN)

func _on_bridge_status(data: Dictionary) -> void:
	if data.has("mode"):
		model_label.text = "PI %s / %s" % [str(data.get("piVersion", "?")), str(data.get("model", "?")).to_upper()]

func _on_link_changed(online: bool, label: String) -> void:
	if link_label == null:
		return
	link_label.text = label
	if online:
		link_label.add_theme_color_override("font_color", UI.C_GREEN)
		link_dot.get_theme_stylebox("panel").bg_color = UI.C_GREEN
	elif label == "LINKING…" or label == "HANDSHAKE…":
		link_label.add_theme_color_override("font_color", UI.C_AMBER)
		link_dot.get_theme_stylebox("panel").bg_color = UI.C_AMBER
	else:
		link_label.add_theme_color_override("font_color", UI.C_RED)
		link_dot.get_theme_stylebox("panel").bg_color = UI.C_RED

func _refresh_header() -> void:
	if credit_stat == null:
		return
	credit_stat.get_meta("value").text = "¥ " + UI.fmt_money(GS.credits)
	rep_stat.get_meta("value").text = str(GS.rep)
	day_stat.get_meta("value").text = "%02d" % GS.day
	heat_label.text = "%d/10" % GS.heat
	heat_meter.set_value(GS.heat)
	if GS.heat >= 7:
		heat_label.add_theme_color_override("font_color", UI.C_RED)
	elif GS.heat >= 4:
		heat_label.add_theme_color_override("font_color", UI.C_AMBER)
	else:
		heat_label.add_theme_color_override("font_color", UI.C_MUTED)
	if GS.active_contract != null:
		active_label.text = "ACTIVE CONTRACT · %s" % str(GS.active_contract.get("codename", ""))
	else:
		active_label.text = ""
	if _prev_credits >= 0 and GS.credits != _prev_credits:
		FX.pulse(credit_stat, 1.055, 0.26)
	if _prev_rep >= 0 and GS.rep != _prev_rep:
		FX.pulse(rep_stat, 1.05, 0.24)
	if _prev_heat >= 0 and GS.heat != _prev_heat:
		if GS.heat > _prev_heat:
			FX.pulse(heat_box, 1.07, 0.3)
			FX.flash(UI.C_MAGENTA, 0.10, 0.42)
			Sfx.play("alert")
		else:
			FX.pulse(heat_box, 1.03, 0.24)
			FX.flash(UI.C_GREEN, 0.045, 0.3)
	_prev_credits = GS.credits
	_prev_rep = GS.rep
	_prev_heat = GS.heat

func _process(delta: float) -> void:
	if loading_active:
		var elapsed := int((Time.get_ticks_msec() - loading_t0) / 1000)
		loading_time.text = "%02d:%02d" % [elapsed / 60, elapsed % 60]
		var hints := ["建立匿名路由", "定位中间人频段", "模型正在写入澜港的雨", "核对委托的细节", "即将完成"]
		var hint_idx := clampi(elapsed / 4, 0, hints.size() - 1)
		loading_hint.text = "%s%s" % [hints[hint_idx], ".".repeat(1 + (elapsed % 3))]
		loading_bar.value = minf(92.0, 8.0 + float(elapsed) * 2.2)

func navigate(id: String) -> void:
	if not VIEW_SCRIPTS.has(id):
		return
	if current_nav == id and current_view != null:
		return
	if GS.active_contract != null and not GS.run.is_empty() and not bool(GS.run.get("done", false)) and id != "run":
		toast("行动进行中，不能离开现场。", UI.C_RED)
		return
	if GS.active_contract != null and id == "run" and (GS.run.is_empty() or bool(GS.run.get("done", false))):
		toast("先进入 PLAN 制定计划并开始行动。", UI.C_AMBER)
		return
	if id == "plan" and GS.active_contract == null:
		toast("没有进行中的委托。先接一单。", UI.C_AMBER)
		return
	if id == "run" and GS.active_contract == null:
		toast("没有可以支援的现场。", UI.C_AMBER)
		return
	if current_view != null:
		current_view.queue_free()
		current_view = null
	current_nav = id
	var script = VIEW_SCRIPTS[id]
	current_view = script.new()
	current_view.main = self
	content_holder.add_child(current_view)
	FX.fade_in(current_view, 0.22)
	if nav_buttons.has(id):
		nav_buttons[id].set_pressed_no_signal(true)
	else:
		for b in nav_buttons.values():
			b.set_pressed_no_signal(false)
	_refresh_header()

func refresh_current() -> void:
	if current_view != null and current_view.has_method("refresh"):
		current_view.refresh()
	_refresh_header()

func show_loading(title: String, sub: String) -> void:
	loading_title.text = title
	loading_sub.text = sub
	loading_t0 = Time.get_ticks_msec()
	loading_time.text = "00:00"
	loading_layer.visible = true
	loading_layer.modulate.a = 0.0
	var ltw := create_tween()
	ltw.tween_property(loading_layer, "modulate:a", 1.0, 0.2)
	loading_active = true

func hide_loading() -> void:
	loading_active = false
	loading_layer.visible = false

func toast(text: String, color: Color = UI.C_CYAN, ttl: float = 4.0) -> void:
	var panel := UI.mk_panel(Color(0.015, 0.035, 0.045, 0.97), Color(color.r, color.g, color.b, 0.55), {"margin": 10, "min_width": 380})
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	panel.add_child(row)
	var bar := ColorRect.new()
	bar.color = color
	bar.custom_minimum_size = Vector2(3, 0)
	bar.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_child(bar)
	var l := UI.mk_label(text, 12, UI.C_TEXT, {"wrap": true, "width": 340})
	row.add_child(l)
	toast_layer.add_child(panel)
	FX.message_in(panel, 0.0)
	while toast_layer.get_child_count() > 3:
		toast_layer.get_child(0).queue_free()
	var tw := create_tween()
	tw.tween_interval(ttl)
	tw.tween_property(panel, "modulate:a", 0.0, 0.6)
	tw.tween_callback(panel.queue_free)

func show_modal(title: String, body: String, actions: Array, color: Color = UI.C_CYAN) -> void:
	for ch in modal_layer.get_children():
		ch.queue_free()
	modal_layer.visible = true
	var dim := ColorRect.new()
	dim.color = Color(0.004, 0.007, 0.012, 0.28)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	modal_layer.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	modal_layer.add_child(center)
	var panel := UI.mk_panel(Color(0.014, 0.028, 0.038, 0.99), Color(color.r, color.g, color.b, 0.6), {"margin": 24, "min_width": 620})
	panel.modulate.a = 0.0
	center.add_child(panel)
	var mtw := create_tween()
	mtw.tween_property(panel, "modulate:a", 1.0, 0.18)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	panel.add_child(v)
	v.add_child(UI.mk_kicker("TRANSMISSION // 加密通讯"))
	v.add_child(UI.mk_label(title, 22, color, {"bold": true}))
	var body_label := UI.mk_label(body, 14, UI.C_TEXT, {"wrap": true, "width": 570})
	body_label.custom_minimum_size.y = 60
	v.add_child(body_label)
	v.add_child(UI.mk_hline(UI.C_BORDER_DIM))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.alignment = BoxContainer.ALIGNMENT_END
	v.add_child(row)
	for act in actions:
		var b := UI.mk_button(str(act.get("label", "关闭")), str(act.get("kind", "default")), 150, 40)
		var cb: Callable = act.get("callback", Callable())
		b.pressed.connect(func():
			modal_layer.visible = false
			for ch in modal_layer.get_children():
				ch.queue_free()
			if cb.is_valid():
				cb.call()
		)
		row.add_child(b)

func close_modal() -> void:
	modal_layer.visible = false
	for ch in modal_layer.get_children():
		ch.queue_free()

func open_chat(kind: String, actor_id: String = "") -> Control:
	for ch in chat_layer.get_children():
		ch.queue_free()
	var chat = preload("res://scripts/ui/ChatPanel.gd").new()
	chat.main = self
	chat.kind = kind
	chat.actor_id = actor_id
	chat_layer.add_child(chat)
	return chat

func _on_rest() -> void:
	if GS.active_contract != null:
		toast("手上有委托，不能休整。", UI.C_AMBER)
		return
	if not GS.rest():
		toast("信用点不足 80，连休整都付不起。", UI.C_RED)
		return
	Sfx.play("confirm")
	_refresh_header()
	refresh_current()
	var res: Dictionary = await Bridge.request("event", {"state": GS.state_for_bridge()}, {"stream": false})
	if bool(res.get("ok", false)) and res.get("data", null) != null:
		var ev: Dictionary = res.data
		GS.pending_event = ev
		GS.apply_effects(ev.get("effects", []))
		GS.note("[%s] %s" % [str(ev.get("title", "澜港夜讯")), str(ev.get("text", ""))], UI.C_AMBER)
		GS.archive_add("世界事件 · %s" % str(ev.get("title", "")), str(ev.get("text", "")))
		GS.save_game()
		show_modal(str(ev.get("title", "澜港夜讯")), str(ev.get("text", "")), [{"label": "继续", "kind": "primary"}], UI.C_AMBER)
	else:
		toast("休整完成。雨还在下。", UI.C_MUTED)

func _on_note(text: String, color: Color) -> void:
	if ticker_label != null:
		ticker_label.text = ">> " + text
		ticker_label.add_theme_color_override("font_color", color)

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F1:
			Sfx.toggle()
			toast("音效已%s。" % ("开启" if Sfx.enabled else "关闭"), UI.C_MUTED)
		elif event.keycode == KEY_ESCAPE:
			if modal_layer.visible:
				close_modal()
			elif chat_layer.get_child_count() > 0:
				for ch in chat_layer.get_children():
					ch.queue_free()
























