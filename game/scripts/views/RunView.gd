extends Control
## Run: live site feed, crew status, remote support, free-form action input.

const SKILL_LABELS := {
	"intrusion": "入侵", "ew": "电子战", "analysis": "分析", "stealth": "潜行",
	"tech": "技术", "social": "交涉", "combat": "战斗", "nerve": "意志",
}
const STAGES := ["接近", "渗透", "目标", "撤离"]

const SCENE_SHADER := """
shader_type canvas_item;
uniform vec2 parallax = vec2(0.0);
uniform float stage = 0.0;
float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}
void fragment() {
	vec2 uv = (UV - 0.5) / 1.045 + 0.5 + parallax + vec2(stage * 0.005, -stage * 0.004);
	vec3 col = texture(TEXTURE, clamp(uv, vec2(0.001), vec2(0.999))).rgb;
	col *= 0.70;
	float lane = floor(UV.x * 140.0);
	float fall = fract(UV.y * 0.65 - TIME * (0.18 + hash(vec2(lane, 2.0)) * 0.12));
	float streak = smoothstep(0.86, 1.0, fall) * step(0.55, hash(vec2(lane, 5.0)));
	col += vec3(0.24, 0.58, 0.72) * streak * 0.06;
	col *= 0.94 + 0.06 * sin(UV.y * 900.0 + TIME * 0.5);
	col *= smoothstep(1.15, 0.35, length(UV - 0.5));
	COLOR = vec4(col, 1.0);
}
"""

var main = null
var busy := false
var finishing := false
var stream_id := ""
var streamed_chars := 0

var terminal: RichTextLabel
var beat_name: Label
var beat_situation: Label
var beat_pressure: Label
var stage_row: HBoxContainer
var alarm_label: Label
var bw_label: Label
var heat_label: Label
var roll_strip: PanelContainer
var roll_label: Label
var action_box: VBoxContainer
var support_box: VBoxContainer
var crew_box: VBoxContainer
var input_line: LineEdit
var skill_pick: OptionButton
var send_button: Button
var situation_panel: PanelContainer
var scene_tex: TextureRect
var scene_mat: ShaderMaterial
var _scene_parallax := Vector2.ZERO
var fx_layer: Control
var roll_overlay: PanelContainer
var roll_big: Label
var roll_result: Label
var roll_backdrop: ColorRect
var _prev_alarms := -1
var _prev_bw := -1
var _prev_stage := -1

func _ready() -> void:
	_build()
	Bridge.task_delta.connect(_on_delta)
	call_deferred("_boot")

func _build() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var root := MarginContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	root.add_child(vb)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	vb.add_child(head)
	var c: Dictionary = GS.active_contract if GS.active_contract != null else {}
	var tv := VBoxContainer.new()
	tv.add_theme_constant_override("separation", 0)
	head.add_child(tv)
	tv.add_child(UI.mk_kicker("LIVE OPERATION / 现场链路"))
	tv.add_child(UI.mk_label(str(c.get("codename", "行动")), 22, UI.C_TEXT, {"bold": true}))
	var obj := UI.mk_label(str(c.get("objective", "")), 12, UI.C_CYAN)
	obj.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(obj)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(sp)
	var status_row := HBoxContainer.new()
	status_row.add_theme_constant_override("separation", 16)
	head.add_child(status_row)
	var bwv := VBoxContainer.new()
	bwv.add_theme_constant_override("separation", 1)
	bwv.add_child(UI.mk_label("BANDWIDTH", 9, UI.C_DIM, {"mono": true}))
	bw_label = UI.mk_label("4", 18, UI.C_CYAN, {"mono": true, "bold": true})
	bwv.add_child(bw_label)
	status_row.add_child(bwv)
	var alv := VBoxContainer.new()
	alv.add_theme_constant_override("separation", 1)
	alv.add_child(UI.mk_label("ALARM", 9, UI.C_DIM, {"mono": true}))
	alarm_label = UI.mk_label("0/3", 18, UI.C_AMBER, {"mono": true, "bold": true})
	alv.add_child(alarm_label)
	status_row.add_child(alv)
	var hv := VBoxContainer.new()
	hv.add_theme_constant_override("separation", 1)
	hv.add_child(UI.mk_label("HEAT", 9, UI.C_DIM, {"mono": true}))
	heat_label = UI.mk_label("%d/10" % GS.heat, 18, UI.C_MAGENTA, {"mono": true, "bold": true})
	hv.add_child(heat_label)
	status_row.add_child(hv)

	stage_row = HBoxContainer.new()
	stage_row.add_theme_constant_override("separation", 6)
	vb.add_child(stage_row)

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 8)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(body)

	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 8)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(left)

	var sit := UI.mk_panel(Color(0.008, 0.020, 0.028, 0.96), UI.C_BORDER_DIM, {"margin": 0})
	sit.custom_minimum_size.y = 180
	sit.clip_contents = true
	situation_panel = sit
	left.add_child(sit)
	var sit_h := HBoxContainer.new()
	sit_h.add_theme_constant_override("separation", 0)
	sit.add_child(sit_h)
	var scene_wrap := Control.new()
	scene_wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scene_wrap.size_flags_stretch_ratio = 1.4
	scene_wrap.custom_minimum_size = Vector2(420, 180)
	scene_wrap.clip_contents = true
	scene_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sit_h.add_child(scene_wrap)
	scene_tex = TextureRect.new()
	scene_tex.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scene_tex.texture = UI.operation_texture
	scene_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	scene_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	scene_tex.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	scene_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scene_mat = ShaderMaterial.new()
	var scene_sh := Shader.new()
	scene_sh.code = SCENE_SHADER
	scene_mat.shader = scene_sh
	scene_tex.material = scene_mat
	scene_wrap.add_child(scene_tex)
	var cam_tag := UI.mk_panel(Color(0.005, 0.010, 0.015, 0.72), Color(0.9, 0.2, 0.3, 0.55), {"margin": 6})
	cam_tag.position = Vector2(8, 8)
	cam_tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cam_tag.add_child(UI.mk_label("● SITE CAM 03 // LIVE", 9, UI.C_RED, {"mono": true}))
	scene_wrap.add_child(cam_tag)
	var sep := ColorRect.new()
	sep.color = UI.C_BORDER_DIM
	sep.custom_minimum_size.x = 1
	sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sit_h.add_child(sep)
	var text_wrap := MarginContainer.new()
	text_wrap.custom_minimum_size.x = 388
	text_wrap.add_theme_constant_override("margin_left", 14)
	text_wrap.add_theme_constant_override("margin_right", 14)
	text_wrap.add_theme_constant_override("margin_top", 10)
	text_wrap.add_theme_constant_override("margin_bottom", 10)
	sit_h.add_child(text_wrap)
	var sv := VBoxContainer.new()
	sv.add_theme_constant_override("separation", 3)
	text_wrap.add_child(sv)
	var sit_head := HBoxContainer.new()
	sit_head.add_theme_constant_override("separation", 8)
	sit_head.add_child(UI.mk_kicker("SITUATION / 当前节拍"))
	beat_name = UI.mk_label("等待现场信号", 13, UI.C_AMBER, {"mono": true})
	sit_head.add_child(beat_name)
	sv.add_child(sit_head)
	beat_pressure = UI.mk_label("", 10, UI.C_RED, {"mono": true})
	sv.add_child(beat_pressure)
	beat_situation = UI.mk_label("正在接入现场链路……", 13, UI.C_TEXT, {"wrap": true})
	beat_situation.custom_minimum_size.y = 66
	beat_situation.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.55))
	beat_situation.add_theme_constant_override("outline_size", 2)
	sv.add_child(beat_situation)

	roll_strip = UI.mk_panel(Color(0.05, 0.02, 0.05, 0.95), UI.C_MAGENTA_DIM, {"margin": 8})
	roll_strip.visible = false
	roll_label = UI.mk_label("", 13, UI.C_MAGENTA, {"mono": true})
	roll_strip.add_child(roll_label)
	left.add_child(roll_strip)

	var term_panel := UI.mk_panel(Color(0.008, 0.017, 0.024, 0.97), UI.C_BORDER_DIM, {"margin": 10})
	term_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	term_panel.custom_minimum_size.y = 170
	left.add_child(term_panel)
	var tvv := VBoxContainer.new()
	tvv.add_theme_constant_override("separation", 6)
	term_panel.add_child(tvv)
	var thead := HBoxContainer.new()
	thead.add_theme_constant_override("separation", 8)
	thead.add_child(UI.mk_kicker("SITE FEED / 现场回传"))
	var rec := UI.mk_label("● REC", 10, UI.C_RED, {"mono": true})
	thead.add_child(rec)
	tvv.add_child(thead)
	tvv.add_child(UI.mk_hline(UI.C_BORDER_DIM))
	terminal = UI.mk_rich(14, UI.C_TEXT)
	terminal.size_flags_vertical = Control.SIZE_EXPAND_FILL
	terminal.scroll_following = true
	tvv.add_child(terminal)

	var action_panel := UI.mk_panel(Color(0.013, 0.028, 0.038, 0.96), UI.C_BORDER_DIM, {"margin": 10})
	left.add_child(action_panel)
	var av := VBoxContainer.new()
	av.add_theme_constant_override("separation", 6)
	action_panel.add_child(av)
	av.add_child(UI.mk_kicker("DECISION / 你的决定"))
	action_box = VBoxContainer.new()
	action_box.add_theme_constant_override("separation", 6)
	av.add_child(action_box)
	var free_row := HBoxContainer.new()
	free_row.add_theme_constant_override("separation", 6)
	av.add_child(free_row)
	input_line = LineEdit.new()
	input_line.placeholder_text = "自由指令：例如「把走廊的灯和摄像头一起关掉」"
	input_line.max_length = 120
	input_line.custom_minimum_size.y = 40
	input_line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	input_line.text_submitted.connect(func(_t: String): _send_free())
	free_row.add_child(input_line)
	skill_pick = OptionButton.new()
	skill_pick.custom_minimum_size = Vector2(112, 40)
	skill_pick.add_item("分析")
	skill_pick.add_item("入侵")
	skill_pick.add_item("电子战")
	skill_pick.add_item("意志")
	skill_pick.selected = 0
	free_row.add_child(skill_pick)
	send_button = UI.mk_button("发送", "primary", 82, 40)
	send_button.pressed.connect(_send_free)
	free_row.add_child(send_button)
	av.add_child(UI.mk_label("自由指令按所选远程技能判定，DC +1。PI 会按判定结果继续写现场。", 10, UI.C_DIM))

	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 8)
	right.custom_minimum_size.x = 326
	body.add_child(right)
	var sup := UI.mk_panel(Color(0.014, 0.03, 0.042, 0.95), UI.C_BORDER_DIM, {"margin": 10})
	right.add_child(sup)
	var supv := VBoxContainer.new()
	supv.add_theme_constant_override("separation", 6)
	sup.add_child(supv)
	var sh := HBoxContainer.new()
	sh.add_theme_constant_override("separation", 6)
	sh.add_child(UI.mk_kicker("REMOTE LINK / 远程支援"))
	var bw_dot := UI.mk_label("BW", 10, UI.C_CYAN_DIM, {"mono": true})
	sh.add_child(bw_dot)
	supv.add_child(sh)
	support_box = VBoxContainer.new()
	support_box.add_theme_constant_override("separation", 6)
	supv.add_child(support_box)
	supv.add_child(UI.mk_label("支援成功会让下一次现场行动 +2。每次消耗 1 带宽。", 10, UI.C_DIM, {"wrap": true}))

	var crew_panel := UI.mk_panel(Color(0.014, 0.03, 0.042, 0.95), UI.C_BORDER_DIM, {"margin": 10})
	crew_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(crew_panel)
	var cv := VBoxContainer.new()
	cv.add_theme_constant_override("separation", 6)
	crew_panel.add_child(cv)
	cv.add_child(UI.mk_kicker("FIELD TEAM / 现场队友"))
	crew_box = VBoxContainer.new()
	crew_box.add_theme_constant_override("separation", 8)
	cv.add_child(crew_box)

	var abort := UI.mk_button("中止行动 / ABORT", "danger", 300, 38)
	abort.pressed.connect(_confirm_abort)
	right.add_child(abort)

	fx_layer = Control.new()
	fx_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fx_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(fx_layer)
	roll_backdrop = ColorRect.new()
	roll_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	roll_backdrop.color = Color(0.002, 0.005, 0.009, 0.0)
	roll_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	roll_backdrop.visible = false
	fx_layer.add_child(roll_backdrop)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fx_layer.add_child(center)
	roll_overlay = UI.mk_panel(Color(0.008, 0.020, 0.028, 0.96), UI.C_CYAN_DIM, {"margin": 18, "min_width": 360, "min_height": 152})
	roll_overlay.visible = false
	roll_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(roll_overlay)
	var rv := VBoxContainer.new()
	rv.add_theme_constant_override("separation", 2)
	roll_overlay.add_child(rv)
	rv.add_child(UI.mk_kicker("DICE / 神经判定"))
	roll_big = UI.mk_label("D10", 52, UI.C_CYAN, {"bold": true, "mono": true, "align": HORIZONTAL_ALIGNMENT_CENTER})
	rv.add_child(roll_big)
	roll_result = UI.mk_label("", 12, UI.C_MUTED, {"mono": true, "align": HORIZONTAL_ALIGNMENT_CENTER})
	rv.add_child(roll_result)
	var corners := preload("res://scripts/ui/FrameCorners.gd").new()
	corners.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	corners.color = Color(0.30, 0.92, 1.0, 0.8)
	roll_overlay.add_child(corners)

func _process(delta: float) -> void:
	if scene_mat == null:
		return
	var vp := get_viewport_rect().size
	if vp.x < 2.0:
		return
	var mp := get_viewport().get_mouse_position() / vp - Vector2(0.5, 0.5)
	_scene_parallax = _scene_parallax.lerp(mp * Vector2(0.015, 0.010), clampf(delta * 2.0, 0.0, 1.0))
	scene_mat.set_shader_parameter("parallax", _scene_parallax)

func _boot() -> void:
	_prev_alarms = int(GS.run.get("alarms", 0))
	_prev_bw = int(GS.run.get("bandwidth", 0))
	_prev_stage = int(GS.run.get("beat_index", 0))
	_render_stages()
	_render_crew()
	_render_support()
	_update_status()
	if GS.run.is_empty():
		_terminal_system("没有可用的行动数据。返回计划重新开始。", UI.C_RED)
		return
	if GS.run.get("beat", null) == null:
		_terminal_system("链路加密完成。正在同步现场……", UI.C_CYAN)
		_request_start()
	else:
		var b: Dictionary = GS.run.beat
		_render_beat_header()
		_terminal_system("链路重连。现场状况已同步。", UI.C_AMBER)
		_render_actions()
		_update_status()

func _request_start() -> void:
	if busy:
		return
	busy = true
	var state := GS.state_for_bridge()
	var plan := _plan_payload()
	var id := Bridge.ask_now("run_start", {
		"state": state,
		"plan": plan,
	}, {"stream": true})
	stream_id = id
	streamed_chars = 0
	await _wait_task(id)
	busy = false

func _wait_task(id: String) -> void:
	while true:
		var args: Array = await Bridge.task_finished
		if str(args[0]) != id:
			continue
		var res: Dictionary = args[1]
		if str(res.get("type", "")) == "error" or not bool(res.get("ok", false)):
			_terminal_system("现场链路无响应：%s" % str(res.get("message", "未知错误")), UI.C_RED)
			_add_retry("重新接入")
			return
		if streamed_chars == 0 and str(res.get("narration", "")) != "":
			_terminal_narration(str(res.get("narration", "")))
		_terminal_newline()
		busy = false
		_handle_start_or_beat(res)
		return

func _handle_start_or_beat(res: Dictionary) -> void:
	var data: Dictionary = res.get("data", {})
	if data.has("beat"):
		GS.run["beat"] = data.beat
		GS.run["beat_index"] = 0
		GS.save_game()
		var hint = data.get("secret_hint", null)
		if hint != null and str(hint) != "":
			_terminal_system("直觉：%s" % str(hint), UI.C_MAGENTA)
		_render_stage_state()
		_render_beat_header()
		_render_actions()
		_render_support()
		_update_status()
		return
	# beat resolution
	if data.has("effects"):
		GS.apply_effects(data.get("effects", []))
	if data.get("reveal", null) != null and str(data.get("reveal", "")) != "":
		_terminal_system("情报：%s" % str(data.get("reveal", "")), UI.C_AMBER)
		GS.archive_add("现场情报", str(data.get("reveal", "")))
		GS.note("在「%s」现场发现了新情报。" % str(GS.active_contract.get("codename", "")), UI.C_AMBER)
	if data.get("crew_line", null) != null and str(data.get("crew_line", "")) != "":
		_terminal_dialogue("现场通讯", str(data.get("crew_line", "")), UI.C_CYAN)
	_terminal_newline()
	_update_status()
	var final_beat := int(GS.run.get("beat_index", 0)) >= 3
	if bool(GS.run.get("broken", false)) or final_beat or data.get("next", null) == null:
		_finish_run()
		return
	GS.run["beat"] = data.next
	GS.run["beat_index"] = int(GS.run.get("beat_index", 0)) + 1
	GS.save_game()
	_render_stage_state()
	_render_beat_header()
	_render_actions()
	_render_support()
	_render_crew()
	_update_status()
	input_line.grab_focus()

func _on_delta(id: String, text: String) -> void:
	if id != stream_id or text == "":
		return
	if streamed_chars == 0:
		_terminal_narration("")
	streamed_chars += text.length()
	terminal.add_text(text)
	terminal.scroll_to_line(terminal.get_line_count() - 1)

func _take_action(action: Dictionary, free_text: bool = false) -> void:
	if busy or GS.run.get("beat", null) == null:
		return
	busy = true
	_clear_actions()
	var result := GS.roll_action(action, free_text)
	roll_strip.visible = false
	_update_status()
	_render_crew()
	_terminal_system("判定 · %s / %s：D10 %d + %d + %d = %d 对 DC %d → %s" % [
		str(result.actor_name), str(SKILL_LABELS.get(str(result.skill), result.skill)),
		int(result.roll), int(result.stat), int(result.bonus), int(result.total), int(result.dc), str(result.tier),
	], UI.risk_color("低" if str(result.tier) in ["成功", "大成功"] else ("中" if str(result.tier) == "勉强" else "高")))
	_terminal_newline()
	await _play_roll_animation(result)
	_show_roll(result)
	var beat: Dictionary = GS.run.beat
	var final_beat := int(GS.run.get("beat_index", 0)) >= 3
	var check := {
		"actorName": str(result.actor_name),
		"skill": str(result.skill),
		"roll": int(result.roll),
		"stat": int(result.stat),
		"bonus": int(result.bonus),
		"total": int(result.total),
		"dc": int(result.dc),
	}
	var id := Bridge.ask_now("run_beat", {
		"state": GS.state_for_bridge(),
		"beatIndex": int(GS.run.get("beat_index", 0)),
		"beat": beat,
		"action": action,
		"check": check,
		"tier": str(result.tier),
		"finalBeat": final_beat,
		"freeText": str(action.get("label", "")) if free_text else "",
		"alarm": int(GS.run.get("alarms", 0)),
		"support": {"note": str(GS.run.get("support_note", "")), "bonus": int(result.bonus)},
	}, {"stream": true})
	stream_id = id
	streamed_chars = 0
	await _wait_task(id)

func _send_free() -> void:
	if busy:
		return
	var text := input_line.text.strip_edges()
	if text == "":
		return
	var skills := ["analysis", "intrusion", "ew", "nerve"]
	var idx := clampi(skill_pick.selected, 0, skills.size() - 1)
	var skill := str(skills[idx])
	var action := {"label": text.substr(0, 48), "skill": skill, "actor": "player", "risk": "中"}
	input_line.text = ""
	_take_action(action, true)

func _use_support(op: Dictionary) -> void:
	if busy:
		return
	if int(GS.run.get("bandwidth", 0)) < int(op.get("cost", 1)):
		main.toast("带宽不足。", UI.C_RED)
		return
	var res := GS.use_support(str(op.get("skill", "intrusion")), str(op.get("label", "远程支援")))
	if not bool(res.get("ok", false)):
		main.toast(str(res.get("reason", "无法支援")), UI.C_RED)
		return
	var color := UI.C_GREEN if bool(res.get("success", false)) else UI.C_RED
	_terminal_system("远程支援 · %s：D10 %d + %d + %d = %d 对 DC %d → %s%s" % [
		str(op.get("label", "")), int(res.get("roll", 0)), int(res.get("stat", 0)), int(res.get("bonus", 0)),
		int(res.get("total", 0)), int(res.get("dc", 0)), "成功" if bool(res.get("success", false)) else "失败",
		"（下一次行动 +2）" if bool(res.get("success", false)) else "",
	], color)
	_update_status()
	_render_actions()
	_render_support()
	FX.flash(color, 0.06, 0.25)
	FX.pulse(support_box, 1.025, 0.22)
	terminal.scroll_to_line(terminal.get_line_count() - 1)

func _render_beat_header() -> void:
	if beat_name == null:
		return
	var beat: Dictionary = {}
	if not GS.run.is_empty() and typeof(GS.run.get("beat", null)) == TYPE_DICTIONARY:
		beat = GS.run.get("beat")
	if beat.is_empty():
		beat_name.text = "等待现场信号"
		beat_situation.text = "正在接入现场链路……"
		beat_pressure.text = ""
		return
	beat_name.text = "第 %d/4 拍 · %s" % [int(GS.run.get("beat_index", 0)) + 1, str(beat.get("name", ""))]
	beat_situation.text = str(beat.get("situation", ""))
	beat_pressure.text = "压力：" + str(beat.get("pressure", ""))
	if scene_mat != null:
		scene_mat.set_shader_parameter("stage", float(int(GS.run.get("beat_index", 0))))
	beat_situation.modulate.a = 0.0
	var bt := create_tween()
	bt.tween_property(beat_situation, "modulate:a", 1.0, 0.28).set_trans(Tween.TRANS_SINE)
	FX.pulse(beat_name, 1.04, 0.24)

func _render_actions() -> void:
	_clear_actions()
	var beat: Dictionary = {}
	if not GS.run.is_empty() and typeof(GS.run.get("beat", null)) == TYPE_DICTIONARY:
		beat = GS.run.get("beat")
	if beat.is_empty() or beat.get("actions", []).is_empty():
		action_box.add_child(UI.mk_label("等待现场指令……", 12, UI.C_DIM))
		return
	var actions: Array = beat.get("actions", [])
	var idx := 1
	for a in actions:
		var actor := str(a.get("actor", "player"))
		var actor_name := str(GS.player.get("handle", "GHOST")) if actor == "player" else str(GS.crew_by_id(actor).get("name", "队友") if GS.crew_by_id(actor) != null else "队友")
		var b := UI.mk_button("", "default", 0, 50)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var chance := GS.chance_for(a)
		var dc := GS.compute_dc(a)
		var skill := str(a.get("skill", "tech"))
		b.text = "%d. %s\n%s · %s · DC %d · %d%%" % [idx, str(a.get("label", "行动")), str(SKILL_LABELS.get(skill, skill)), actor_name, dc, chance]
		b.add_theme_font_size_override("font_size", 13)
		b.disabled = busy
		var action: Dictionary = a
		b.pressed.connect(func(): _take_action(action))
		action_box.add_child(b)
		idx += 1
	FX.stagger(action_box, 0.04, 0.98)

func _clear_actions() -> void:
	if action_box == null:
		return
	for ch in action_box.get_children():
		ch.queue_free()

func _add_retry(label: String) -> void:
	_clear_actions()
	var b := UI.mk_button(label, "primary", 220, 42)
	b.pressed.connect(func():
		busy = false
		_request_start()
	)
	action_box.add_child(b)
	busy = false

func _render_support() -> void:
	if support_box == null:
		return
	for ch in support_box.get_children():
		ch.queue_free()
	var beat: Dictionary = {}
	if not GS.run.is_empty() and typeof(GS.run.get("beat", null)) == TYPE_DICTIONARY:
		beat = GS.run.get("beat")
	var ops: Array = beat.get("support_ops", []) if not beat.is_empty() else []
	if ops.is_empty():
		support_box.add_child(UI.mk_label("现场没有可接入的设备。", 11, UI.C_DIM))
		return
	for op in ops:
		var b := UI.mk_button("", "default", 300, 48)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.text = "%s  ·  BW %d\n%s" % [str(op.get("label", "")), int(op.get("cost", 1)), str(op.get("hint", ""))]
		b.add_theme_font_size_override("font_size", 11)
		b.disabled = busy or int(GS.run.get("bandwidth", 0)) < int(op.get("cost", 1))
		b.add_theme_color_override("font_color", UI.C_TEXT)
		b.add_theme_color_override("font_hover_color", UI.C_CYAN)
		b.add_theme_stylebox_override("normal", UI.style_bg(Color(0.02, 0.055, 0.07, 0.95), UI.C_BORDER, 1, 12, 2))
		b.add_theme_stylebox_override("hover", UI.style_bg(Color(0.03, 0.10, 0.125, 1), UI.C_CYAN, 1, 12, 2))
		var o: Dictionary = op
		b.pressed.connect(func(): _use_support(o))
		support_box.add_child(b)
	FX.stagger(support_box, 0.04, 0.98)

func _render_crew() -> void:
	if crew_box == null:
		return
	for ch in crew_box.get_children():
		ch.queue_free()
	var members := GS.crew_for_run()
	if members.is_empty():
		crew_box.add_child(UI.mk_label("独自行动。没有人在现场替你承担后果。", 11, UI.C_AMBER, {"wrap": true}))
		return
	for m in members:
		var p := UI.mk_panel(Color(0.016, 0.034, 0.046, 0.95), UI.C_BORDER_DIM, {"margin": 8})
		var hh := HBoxContainer.new()
		hh.add_theme_constant_override("separation", 8)
		p.add_child(hh)
		hh.add_child(UI.mk_merc_portrait(m, Vector2(44, 44), true))
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 3)
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hh.add_child(v)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		row.add_child(UI.mk_label(str(m.get("name", "")), 13, UI.C_TEXT, {"bold": true}))
		var sp := Control.new()
		sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(sp)
		row.add_child(UI.mk_tag(str(m.get("role", "")), UI.C_CYAN_DIM))
		v.add_child(row)
		var srow := HBoxContainer.new()
		srow.add_theme_constant_override("separation", 5)
		srow.add_child(UI.mk_label("伤", 10, UI.C_DIM, {"mono": true}))
		srow.add_child(UI.mk_meter(int(m.get("injury", 0)), GS.MAX_INJURY, UI.C_RED, 62, 3))
		srow.add_child(UI.mk_label("忠", 10, UI.C_DIM, {"mono": true}))
		srow.add_child(UI.mk_meter(int(m.get("loyalty", 50)), 100, UI.C_CYAN, 62, 10))
		v.add_child(srow)
		crew_box.add_child(p)

func _render_stages() -> void:
	for ch in stage_row.get_children():
		ch.queue_free()
	for i in range(4):
		var p := UI.mk_panel(Color(0.012, 0.026, 0.036, 0.92), UI.C_BORDER_DIM, {"margin": 6, "min_width": 120})
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 6)
		p.add_child(h)
		h.add_child(UI.mk_label("0%d" % (i + 1), 10, UI.C_DIM, {"mono": true}))
		h.add_child(UI.mk_label(STAGES[i], 12, UI.C_MUTED, {"mono": true, "bold": true}))
		stage_row.add_child(p)
	_render_stage_state()

func _render_stage_state() -> void:
	if stage_row == null:
		return
	var idx := int(GS.run.get("beat_index", 0)) if not GS.run.is_empty() else 0
	var tiers: Array = GS.run.get("tier_log", []) if not GS.run.is_empty() else []
	for i in range(stage_row.get_child_count()):
		var p: PanelContainer = stage_row.get_child(i)
		var done := i < idx or i < tiers.size()
		var current := i == idx
		var border := UI.C_CYAN if current else (UI.C_GREEN_DIM if done else UI.C_BORDER_DIM)
		var bg := Color(0.03, 0.10, 0.12, 0.95) if current else (Color(0.016, 0.045, 0.04, 0.9) if done else Color(0.012, 0.026, 0.036, 0.92))
		p.add_theme_stylebox_override("panel", UI.panel_style(bg, border, 6, 2))
		var h: HBoxContainer = p.get_child(0)
		var name_label: Label = h.get_child(1)
		name_label.add_theme_color_override("font_color", UI.C_CYAN if current else (UI.C_GREEN if done else UI.C_MUTED))
	if idx != _prev_stage and idx >= 0 and idx < stage_row.get_child_count():
		FX.pulse(stage_row.get_child(idx), 1.05, 0.32)
		Sfx.play("click")
	_prev_stage = idx

func _update_status() -> void:
	if bw_label == null:
		return
	var alarms := int(GS.run.get("alarms", 0))
	var bw := int(GS.run.get("bandwidth", 0))
	bw_label.text = str(bw)
	alarm_label.text = "%d/3" % alarms
	heat_label.text = "%d/10" % GS.heat
	if alarms >= 2:
		alarm_label.add_theme_color_override("font_color", UI.C_RED)
	else:
		alarm_label.add_theme_color_override("font_color", UI.C_AMBER)
	if _prev_alarms >= 0 and alarms > _prev_alarms:
		FX.pulse(alarm_label, 1.25, 0.32)
		FX.flash(UI.C_RED, 0.11, 0.42)
		Sfx.play("alert")
	if _prev_bw >= 0 and bw < _prev_bw:
		FX.pulse(bw_label, 1.18, 0.25)
	_prev_alarms = alarms
	_prev_bw = bw
	main._refresh_header()

func _show_roll(result: Dictionary) -> void:
	roll_strip.visible = true
	var tier := str(result.get("tier", ""))
	var color := UI.C_GREEN if tier in ["成功", "大成功"] else (UI.C_AMBER if tier == "勉强" else UI.C_RED)
	roll_label.add_theme_color_override("font_color", color)
	roll_label.text = "D10 %d  +  %d  +  %d  =  %d    /    DC %d    →    %s" % [
		int(result.get("roll", 0)), int(result.get("stat", 0)), int(result.get("bonus", 0)),
		int(result.get("total", 0)), int(result.get("dc", 0)), tier,
	]
	roll_strip.modulate.a = 0.2
	var tw := create_tween()
	tw.tween_property(roll_strip, "modulate:a", 1.0, 0.18)
	tw.tween_interval(4.0)
	tw.tween_property(roll_strip, "modulate:a", 0.0, 0.5)
	tw.tween_callback(func(): roll_strip.visible = false)

func _play_roll_animation(result: Dictionary) -> void:
	if roll_overlay == null:
		return
	var tier := str(result.get("tier", "成功"))
	var color := UI.C_GREEN if tier in ["成功", "大成功"] else (UI.C_AMBER if tier == "勉强" else UI.C_RED)
	roll_overlay.add_theme_stylebox_override("panel", UI.style_bg(Color(0.006, 0.016, 0.022, 1.0), Color(color.r, color.g, color.b, 0.8), 1, 18, 2))
	roll_backdrop.visible = true
	roll_backdrop.color = Color(0.002, 0.005, 0.009, 0.0)
	var btw := create_tween()
	btw.tween_property(roll_backdrop, "color:a", 0.94, 0.12)
	roll_overlay.visible = true
	roll_overlay.modulate.a = 1.0
	roll_overlay.pivot_offset = roll_overlay.size * 0.5
	roll_overlay.scale = Vector2(0.94, 0.94)
	var tw := create_tween()
	tw.tween_property(roll_overlay, "scale", Vector2.ONE, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	Sfx.play("dice")
	for i in range(7):
		roll_big.text = str(randi_range(1, 10))
		roll_big.add_theme_color_override("font_color", UI.C_CYAN)
		await get_tree().create_timer(0.045).timeout
	roll_big.text = "D10 " + str(int(result.get("roll", 1)))
	roll_big.add_theme_color_override("font_color", color)
	roll_result.text = "%s  ·  %d + %d + %d = %d   /   DC %d" % [
		tier, int(result.get("roll", 0)), int(result.get("stat", 0)), int(result.get("bonus", 0)),
		int(result.get("total", 0)), int(result.get("dc", 0)),
	]
	FX.flash(color, 0.10, 0.30)
	FX.pulse(roll_overlay, 1.05, 0.22)
	if scene_tex != null:
		var scene_tint := Color(0.78, 1.0, 0.86) if tier in ["成功", "大成功"] else Color(1.0, 0.72, 0.72)
		scene_tex.modulate = scene_tint
		var stw := create_tween()
		stw.tween_property(scene_tex, "modulate", Color.WHITE, 0.55)
	if tier in ["成功", "大成功"]:
		Sfx.play("confirm")
	else:
		Sfx.play("deny")
	await get_tree().create_timer(0.72).timeout
	var out := create_tween()
	out.tween_property(roll_overlay, "modulate:a", 0.0, 0.22)
	out.parallel().tween_property(roll_backdrop, "color:a", 0.0, 0.22)
	await out.finished
	roll_overlay.visible = false
	roll_backdrop.visible = false

func _finish_run() -> void:
	if finishing:
		return
	finishing = true
	busy = true
	_terminal_system("现场链路开始撤离。耳机里只剩下雨声和呼吸。", UI.C_CYAN)
	await get_tree().create_timer(0.9).timeout
	var results := GS.finalize_run()
	Sfx.play("confirm")
	main.toast("行动结束。净收入 ¥%s。" % UI.fmt_money(int(results.get("net", 0))), UI.C_AMBER)
	main.navigate("settle")

func _confirm_abort() -> void:
	main.show_modal("中止行动", "切断链路意味着放弃现场。队友会按紧急预案撤离，报酬和声望都会受影响。\n\n确定中止？", [
		{"label": "中止并撤离", "kind": "danger", "callback": func(): _abort()},
		{"label": "继续行动", "kind": "ghost"},
	], UI.C_MAGENTA)

func _abort() -> void:
	if finishing:
		return
	GS.abort_run()
	_finish_run()

func debug_free_input(text: String) -> void:
	if busy:
		return
	input_line.text = text
	skill_pick.selected = 1
	_send_free()

func debug_take_action() -> void:
	if busy or GS.run.is_empty():
		return
	var beat = GS.run.get("beat", null)
	if typeof(beat) != TYPE_DICTIONARY:
		return
	var acts: Array = beat.get("actions", [])
	if acts.is_empty():
		return
	_take_action(acts[0])

func _plan_payload() -> Dictionary:
	var crew_list: Array = []
	for id in GS.plan.get("crew_ids", []):
		var m = GS.crew_by_id(str(id))
		if m != null:
			crew_list.append(m)
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

func _terminal_system(text: String, color: Color) -> void:
	terminal.append_text("[color=#%s]%s[/color]\n" % [color.to_html(false), _escape(text)])
	terminal.scroll_to_line(terminal.get_line_count() - 1)

func _terminal_dialogue(speaker: String, text: String, color: Color) -> void:
	terminal.append_text("[color=#%s]%s：[/color][i]%s[/i]\n" % [color.to_html(false), _escape(speaker), _escape(text)])
	terminal.scroll_to_line(terminal.get_line_count() - 1)

func _terminal_narration(text: String) -> void:
	if text != "":
		terminal.add_text(text)
	terminal.scroll_to_line(terminal.get_line_count() - 1)

func _terminal_newline() -> void:
	terminal.add_text("\n\n")
	terminal.scroll_to_line(terminal.get_line_count() - 1)

func _escape(text: String) -> String:
	return text.replace("[", "[lb]")


















