extends Control
## Campaign archive: chronicle, discovered secrets and relationships.

var main = null
var chronicle_box: VBoxContainer
var archive_box: VBoxContainer
var relation_box: VBoxContainer
var flags_label: Label

func _ready() -> void:
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
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	vb.add_child(head)
	var tv := VBoxContainer.new()
	tv.add_theme_constant_override("separation", 0)
	head.add_child(tv)
	tv.add_child(UI.mk_kicker("ARCHIVE / 城市记忆"))
	tv.add_child(UI.mk_label("档案", 24, UI.C_TEXT, {"bold": true}))
	var sub := UI.mk_label("你做过的事，这座城都记着。", 12, UI.C_MUTED)
	sub.size_flags_vertical = Control.SIZE_SHRINK_END
	head.add_child(sub)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(sp)
	var reset := UI.mk_button("重置档案", "danger", 110, 36)
	reset.pressed.connect(_confirm_reset)
	head.add_child(reset)

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 10)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(body)

	var left := UI.mk_panel(Color(0.012, 0.024, 0.034, 0.92), UI.C_BORDER_DIM, {"margin": 16})
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(left)
	var lv := VBoxContainer.new()
	lv.add_theme_constant_override("separation", 8)
	left.add_child(lv)
	lv.add_child(UI.mk_kicker("CHRONICLE / 行动记录"))
	lv.add_child(UI.mk_hline(UI.C_BORDER_DIM))
	var scroll := UI.mk_scroll()
	lv.add_child(scroll)
	chronicle_box = VBoxContainer.new()
	chronicle_box.add_theme_constant_override("separation", 8)
	chronicle_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(chronicle_box)

	var right := UI.mk_panel(Color(0.014, 0.026, 0.036, 0.94), UI.C_BORDER_DIM, {"margin": 16})
	right.custom_minimum_size.x = 520
	body.add_child(right)
	var rscroll := UI.mk_scroll()
	right.add_child(rscroll)
	var rv := VBoxContainer.new()
	rv.add_theme_constant_override("separation", 10)
	rv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rscroll.add_child(rv)
	rv.add_child(UI.mk_kicker("RELATIONS / 关系"))
	relation_box = VBoxContainer.new()
	relation_box.add_theme_constant_override("separation", 6)
	rv.add_child(relation_box)
	rv.add_child(UI.mk_hline(UI.C_BORDER_DIM))
	rv.add_child(UI.mk_kicker("ARCHIVE / 已归档"))
	archive_box = VBoxContainer.new()
	archive_box.add_theme_constant_override("separation", 10)
	rv.add_child(archive_box)
	rv.add_child(UI.mk_hline(UI.C_BORDER_DIM))
	rv.add_child(UI.mk_kicker("FLAGS / 世界标记"))
	flags_label = UI.mk_label("无", 11, UI.C_MUTED, {"wrap": true})
	rv.add_child(flags_label)

func refresh() -> void:
	for ch in chronicle_box.get_children():
		ch.queue_free()
	for ch in archive_box.get_children():
		ch.queue_free()
	for ch in relation_box.get_children():
		ch.queue_free()
	var stats := "DAY %02d · JOBS %d · NET ¥%s · REP %d · HEAT %d" % [
		GS.day, int(GS.stats.get("jobs", 0)), UI.fmt_money(int(GS.stats.get("credits_earned", 0))), GS.rep, GS.heat,
	]
	chronicle_box.add_child(UI.mk_label(stats, 10, UI.C_AMBER, {"mono": true}))
	for i in range(GS.chronicle.size() - 1, -1, -1):
		var text := str(GS.chronicle[i])
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var idx := UI.mk_label("%02d" % (i + 1), 9, UI.C_DIM, {"mono": true, "width": 22})
		row.add_child(idx)
		var l := UI.mk_label(text, 12, UI.C_TEXT if i == GS.chronicle.size() - 1 else UI.C_MUTED, {"wrap": true, "width": 620})
		row.add_child(l)
		chronicle_box.add_child(row)

	var hired := GS.hired_crew()
	if GS.crew.is_empty():
		relation_box.add_child(UI.mk_label("还没有认识任何人。", 12, UI.C_DIM))
	for c in GS.crew:
		var p := UI.mk_panel(Color(0.016, 0.034, 0.046, 0.95) if bool(c.get("hired", false)) else Color(0.012, 0.024, 0.032, 0.9), UI.C_BORDER_DIM, {"margin": 8})
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 2)
		p.add_child(v)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		row.add_child(UI.mk_label(str(c.get("name", "")), 13, UI.C_TEXT if bool(c.get("hired", false)) else UI.C_MUTED, {"bold": true}))
		row.add_child(UI.mk_label(str(c.get("handle", "")), 9, UI.C_CYAN_DIM, {"mono": true}))
		var sp := Control.new()
		sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(sp)
		row.add_child(UI.mk_tag("入队" if bool(c.get("hired", false)) else "未招募", UI.C_GREEN if bool(c.get("hired", false)) else UI.C_DIM))
		v.add_child(row)
		v.add_child(UI.mk_label("忠诚 %d · 伤势 %d · 任务 %d" % [int(c.get("loyalty", 50)), int(c.get("injury", 0)), int(c.get("missions", 0))], 10, UI.C_MUTED, {"mono": true}))
		if bool(c.get("secret_revealed", false)) and str(c.get("secret", "")) != "":
			v.add_child(UI.mk_label("秘密：%s" % str(c.get("secret", "")), 10, UI.C_MAGENTA, {"wrap": true}))
		relation_box.add_child(p)

	if GS.archive.is_empty():
		archive_box.add_child(UI.mk_label("还没有归档。", 12, UI.C_DIM))
	for entry in GS.archive:
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 1)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		row.add_child(UI.mk_label(str(entry.get("title", "")), 12, UI.C_AMBER, {"bold": true}))
		var sp := Control.new()
		sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(sp)
		row.add_child(UI.mk_label("DAY %02d" % int(entry.get("day", 0)), 9, UI.C_DIM, {"mono": true}))
		v.add_child(row)
		v.add_child(UI.mk_label(str(entry.get("text", "")), 10, UI.C_MUTED, {"wrap": true, "width": 460}))
		archive_box.add_child(v)
	flags_label.text = "；".join(PackedStringArray(GS.flags)) if not GS.flags.is_empty() else "无"
	FX.stagger(chronicle_box, 0.02, 0.99)
	FX.stagger(relation_box, 0.025, 0.99)
	FX.stagger(archive_box, 0.025, 0.99)
	main._refresh_header()

func _confirm_reset() -> void:
	main.show_modal("重置档案", "这会删除当前存档、所有角色记忆和中间人会话。无法撤销。\n\n确定要抹掉自己吗？", [
		{"label": "抹掉一切", "kind": "danger", "callback": _do_reset},
		{"label": "取消", "kind": "ghost"},
	], UI.C_MAGENTA)

func _do_reset() -> void:
	Bridge.request_reset()
	GS.reset_campaign()
	main.toast("档案已删除。正在重启……", UI.C_MAGENTA)
	await get_tree().create_timer(0.6).timeout
	get_tree().reload_current_scene()


