extends Control
## Gear shop / loadout reference.

var main = null
var grid: GridContainer
var credit_label: Label

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
	tv.add_child(UI.mk_kicker("GEAR / 装备库"))
	tv.add_child(UI.mk_label("装备", 24, UI.C_TEXT, {"bold": true}))
	var sub := UI.mk_label("硬件不会替你冒险，但能让冒险少一点。在 PLAN 里选择携带。", 12, UI.C_MUTED)
	sub.size_flags_vertical = Control.SIZE_SHRINK_END
	head.add_child(sub)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(sp)
	credit_label = UI.mk_label("¥ 0", 20, UI.C_AMBER, {"mono": true, "bold": true})
	head.add_child(credit_label)

	var panel := UI.mk_panel(Color(0.012, 0.024, 0.034, 0.92), UI.C_BORDER_DIM, {"margin": 16})
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(panel)
	var scroll := UI.mk_scroll()
	panel.add_child(scroll)
	grid = GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(grid)

func refresh() -> void:
	if grid == null:
		return
	credit_label.text = "¥ " + UI.fmt_money(GS.credits)
	for ch in grid.get_children():
		ch.queue_free()
	for item in GS.GEAR_CATALOG:
		var owned := GS.owns_gear(str(item.id))
		var card := UI.mk_panel(Color(0.016, 0.036, 0.048, 0.95) if not owned else Color(0.018, 0.05, 0.045, 0.95), UI.C_GREEN_DIM if owned else UI.C_BORDER_DIM, {"margin": 14})
		card.custom_minimum_size = Vector2(400, 190)
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 6)
		card.add_child(v)
		var top := HBoxContainer.new()
		top.add_theme_constant_override("separation", 8)
		v.add_child(top)
		top.add_child(UI.mk_sigil(str(item.name).substr(0, 1), UI.C_AMBER, 30))
		top.add_child(UI.mk_label(str(item.name), 17, UI.C_TEXT, {"bold": true}))
		var sp := Control.new()
		sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
		top.add_child(sp)
		if owned:
			top.add_child(UI.mk_tag("已拥有", UI.C_GREEN))
		v.add_child(UI.mk_label(str(item.desc), 12, UI.C_CYAN, {"wrap": true}))
		v.add_child(UI.mk_spacer(2))
		var bottom := HBoxContainer.new()
		bottom.add_theme_constant_override("separation", 8)
		v.add_child(bottom)
		bottom.add_child(UI.mk_label("¥ " + UI.fmt_money(int(item.price)), 16, UI.C_AMBER, {"mono": true}))
		var sp2 := Control.new()
		sp2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sp2.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bottom.add_child(sp2)
		var b := UI.mk_button("购买", "primary" if not owned else "ghost", 100, 36)
		b.disabled = owned or GS.credits < int(item.price)
		var iid := str(item.id)
		b.pressed.connect(func(): _buy(iid))
		bottom.add_child(b)
		grid.add_child(card)
	FX.stagger(grid, 0.04, 0.965)
	main._refresh_header()

func _buy(id: String) -> void:
	if GS.buy_gear(id):
		Sfx.play("confirm")
		main.toast("装备已入库。在 PLAN 里选择它。", UI.C_GREEN)
	else:
		main.toast("买不起，或者已经拥有。", UI.C_AMBER)
	refresh()



