@tool
extends PanelContainer
class_name VSPanel

## Vertex Studio side/main panel

signal action_requested(name: StringName)
signal eyedrop_requested(dest: StringName)
signal eyedrop_cancelled
signal snapshot_selected(path: String)
signal runtime_toggled(enabled: bool)
signal swatch_menu(action: StringName)
signal vgroup_action(action: StringName, group_name: String)
signal select_linked_material(index: int)
signal theme_refreshed

var state: VSState

var _targets_label: Label
var _snapshot_list: ItemList
var _snapshot_list_updating := false
var _runtime_cb: CheckBox
var _runtime_syncing := false

var _vgroup_list: ItemList
var _vgroup_list_updating := false
var _vgroup_active := ""
var _vgroup_has_selection := false
var _vgroup_new_btn: Button
var _vgroup_save_btn: Button
var _vgroup_reload_btn: Button
var _vgroup_delete_btn: Button

var _selection_section: Control
var _material_lists: Array[ItemList] = []
var _material_labels := PackedStringArray()
var _material_list_updating := false
var _link_by := 0

var _popup_paint_wrap: Control
var _popup_selection_wrap: Control

var _undo_btn: Button
var _redo_btn: Button
var _replace_target_btn: ColorPickerButton
var _replace_new_btn: ColorPickerButton
var _replace_btn: Button
var _select_buttons: Array = []
var _fill_btns: Array[Button] = []
var _erase_btns: Array[Button] = []
var _fill_smooth_btn: Button
var _fill_hard_btn: Button
var _select_hints: Array = []

var _paint_op_buttons: Array = []
var _value_rows: Array[Control] = []
var _brush_size_rows: Array[Control] = []
var _normals_hide: Array[Control] = []
var _color_hide: Array[Control] = []
var _normals_show: Array[Control] = []
var _replace_section: Control
var _fill_normals_section: Control
var _eyedrop_btns: Array[Button] = []
var _curve_previews: Array[VSCurveEdit] = []
var _pro_dialog: AcceptDialog

var _syncers: Array[Callable] = []
var _syncing := false
var _swatch_boxes: Array = []
var _brush_popup: PopupPanel

const LABEL_W := 82

var _swatch_edge := 26
var _color_btn_size := Vector2(54, 26)
var _ui_scale := 1.0
var _built := false


func setup(p_state: VSState) -> void:
	state = p_state
	custom_minimum_size = Vector2(320, 0)
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	_ui_scale = EditorInterface.get_editor_scale()
	_swatch_edge = int(round(26.0 * _ui_scale))
	_color_btn_size = Vector2(54, 26) * _ui_scale
	_build()
	_built = true


#region UI build
# ---------------------------------------------------------------- 
# Editor theme
# ---------------------------------------------------------------- 

func _ed_font(name: String) -> Font:
	var t := EditorInterface.get_editor_theme()
	if t and t.has_font(name, "EditorFonts"):
		return t.get_font(name, "EditorFonts")
	return null


func _ed_font_size(name: String) -> int:
	var t := EditorInterface.get_editor_theme()
	if t and t.has_font_size(name, "EditorFonts"):
		return t.get_font_size(name, "EditorFonts")
	return 0


func _ed_icon(name: String) -> Texture2D:
	var t := EditorInterface.get_editor_theme()
	if t and t.has_icon(name, "EditorIcons"):
		return t.get_icon(name, "EditorIcons")
	return null


func _ed_color(name: String, type: String, fallback: Color) -> Color:
	var t := EditorInterface.get_editor_theme()
	if t and t.has_color(name, type):
		return t.get_color(name, type)
	return fallback


func _theme_text_color() -> Color:
	var t := EditorInterface.get_editor_theme()
	if t:
		if t.has_color("font_color", "Label"):
			return t.get_color("font_color", "Label")
		if t.has_color("font_color", "Editor"):
			return t.get_color("font_color", "Editor")
	return Color(0.85, 0.85, 0.85)


func _tint_icon_button(b: Button) -> void:
	b.set_meta("vs_icon_tint", true)
	var tint := _theme_text_color()
	var accent := _ed_color("accent_color", "Editor", tint)
	b.add_theme_color_override("icon_normal_color", tint)
	b.add_theme_color_override("icon_hover_color", tint)
	b.add_theme_color_override("icon_focus_color", tint)
	b.add_theme_color_override("icon_disabled_color", Color(tint.r, tint.g, tint.b, 0.4))
	b.add_theme_color_override("icon_pressed_color", accent)
	b.add_theme_color_override("icon_hover_pressed_color", accent)


func _apply_section_header_colors(header: Button) -> void:
	var text_col := _theme_text_color()
	for c in ["font_color", "font_pressed_color", "font_hover_color",
			"font_hover_pressed_color", "font_focus_color"]:
		header.add_theme_color_override(c, text_col)
	var arrow_col := Color(text_col.r, text_col.g, text_col.b, 0.8)
	for c in ["icon_normal_color", "icon_pressed_color", "icon_hover_color",
			"icon_hover_pressed_color", "icon_focus_color"]:
		header.add_theme_color_override(c, arrow_col)


func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED and _built:
		_refresh_theme_tints(self)
		theme_refreshed.emit()


func _refresh_theme_tints(node: Node) -> void:
	for child in node.get_children():
		if child is Button:
			var b := child as Button
			if b.has_meta("vs_icon_gold"):
				_gold_icon(b)
			elif b.has_meta("vs_section_header"):
				_apply_section_header_colors(b)
			elif b.has_meta("vs_icon_tint"):
				_tint_icon_button(b)
		_refresh_theme_tints(child)


func _swap_icon() -> Texture2D:
	for name in ["ReverseGradient", "Loop", "MirrorX"]:
		var ic := _ed_icon(name)
		if ic:
			return ic
	return null


func _build() -> void:
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(312, 240)
	add_child(scroll)

	var root := VBoxContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_theme_constant_override("separation", 6)
	scroll.add_child(root)

	_build_header(root)
	_build_material(root)
	_build_view(root)
	_build_tool(root)
	_build_selection_settings(root)
	_build_paint(root)
	_build_actions(root)
	_build_fill_normals(root)
	_build_vgroups(root)
	_build_snapshot(root)
	_build_runtime(root)
	_build_source_mesh(root)

	if not state.changed.is_connected(_refresh_actions_hint):
		state.changed.connect(_refresh_actions_hint)
	if not state.changed.is_connected(_refresh_value_row):
		state.changed.connect(_refresh_value_row)
	if not state.changed.is_connected(_sync_ui):
		state.changed.connect(_sync_ui)
	if not state.changed.is_connected(_refresh_select_hint):
		state.changed.connect(_refresh_select_hint)

	_refresh_tool_buttons()
	_refresh_value_row()
	refresh()


# ---------------------------------------------------------------- 
# Header
# ---------------------------------------------------------------- 

func _build_header(root: VBoxContainer) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)

	var title := Label.new()
	title.text = "Vertex Studio"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var bf := _ed_font("bold")
	if bf:
		title.add_theme_font_override("font", bf)
	var ts := _ed_font_size("title_size")
	if ts <= 0:
		ts = _ed_font_size("large_size")
	if ts > 0:
		title.add_theme_font_size_override("font_size", ts)
	row.add_child(title)

	var links := HBoxContainer.new()
	links.add_theme_constant_override("separation", 2)
	links.alignment = BoxContainer.ALIGNMENT_CENTER
	links.add_child(_header_link_button("book",
		"https://alfredbaudisch.github.io/godot-vertex-studio-docs/index.html",
		"Manual and Documentation"))
	links.add_child(_header_link_button("help",
		"https://splitpainter.itch.io/vertex-studio/community",
		"Forums"))
	links.add_child(_header_link_button("bug",
		"https://github.com/alfredbaudisch/godot-vertex-studio-docs/issues",
		"Bug reports"))
	if not VSPro.IS_PRO:
		links.add_child(_header_link_button("star", VSPro.STORE_URL,
			"Get Vertex Studio Pro!"))
	row.add_child(links)
	root.add_child(row)


func _header_link_button(icon_name: String, url: String, tip: String) -> Button:
	return _icon_button(icon_name, tip, false, func(): OS.shell_open(url))


# ---------------------------------------------------------------- 
# Targets
# ---------------------------------------------------------------- 

func _build_targets(root: VBoxContainer) -> void:
	var body := _section(root, "Targets")
	_targets_label = Label.new()
	_targets_label.text = "No mesh selected"
	body.add_child(_targets_label)

	var cb := CheckBox.new()
	cb.text = "Include Children"
	cb.button_pressed = state.include_children
	cb.toggled.connect(func(v):
		state.include_children = v
		action_requested.emit(&"retarget"))
	body.add_child(cb)


# ---------------------------------------------------------------- 
# Material
# ---------------------------------------------------------------- 

func _build_material(root: VBoxContainer) -> void:
	var body := _section(root, "Material")

	var setup_tip := "Apply the Vertex Studio setup material as a per-surface override (texture + vertex color + debug views). Non-destructive."
	var row1 := HBoxContainer.new()
	row1.add_theme_constant_override("separation", 2)
	row1.alignment = BoxContainer.ALIGNMENT_CENTER
	row1.add_child(_material_dual_button("checkerboard_circle", "cog", "Setup Unlit",
		"Setup Unlit: %s Uses the unlit paint shader." % setup_tip,
		&"setup_material_unlit"))
	row1.add_child(_material_dual_button("checkerboard_circle", "cog", "Setup Lit",
		"Setup Lit: %s Uses the lit paint shader (shows normal edits while painting)." % setup_tip,
		&"setup_material_lit"))
	body.add_child(row1)

	var row2 := HBoxContainer.new()
	var lbl := Label.new()
	lbl.text = "On restore"
	lbl.custom_minimum_size.x = LABEL_W
	row2.add_child(lbl)
	var opt := OptionButton.new()
	opt.add_item("Original Material", VSState.CommitMode.RESTORE)
	opt.add_item("StandardMaterial3D", VSState.CommitMode.STANDARD)
	opt.add_item("Keep Setup Material", VSState.CommitMode.KEEP)
	opt.selected = state.commit_mode
	opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	opt.tooltip_text = "Applied when Vertex Studio closes / leaves this mesh. Setup is re-applied automatically when reopened on a previously set-up mesh."
	opt.item_selected.connect(func(idx):
		state.commit_mode = idx
		state.emit_changed())
	row2.add_child(opt)
	row2.add_child(_icon_button("restore",
		"Restore Material: apply the \"On restore\" material now.",
		false, func(): action_requested.emit(&"commit_material")))
	body.add_child(row2)


# ---------------------------------------------------------------- 
# View
# ---------------------------------------------------------------- 

func _build_view(root: VBoxContainer) -> void:
	var body := _section(root, "View")

	var row1 := HBoxContainer.new()
	row1.add_theme_constant_override("separation", 2)
	row1.alignment = BoxContainer.ALIGNMENT_CENTER
	row1.add_child(_view_toggle(_icon("MeshInstance3D"), "Show Wireframe",
		func(): return state.show_wireframe, func(v): state.show_wireframe = v))
	row1.add_child(_view_toggle(_icon("vertex"), "Show Vertex Colors",
		func(): return state.show_vertex_colors, func(v): state.show_vertex_colors = v))
	row1.add_child(_view_toggle(_icon("image"), "Show Textured",
		func(): return state.show_textured, func(v): state.show_textured = v))
	row1.add_child(_view_toggle(_icon("eye"), "Show Vertices",
		func(): return state.show_vertices, func(v): state.show_vertices = v))
	row1.add_child(_view_toggle(_icon("field_of_view"), "Always Show Vertices (off: only vertices under the brush/cursor or selected. Keep off if you are suffering from performance issues)",
		func(): return state.always_show_vertices, func(v): state.always_show_vertices = v))
	row1.add_child(_view_toggle(_icon("face"), "Show Front Verts Only",
		func(): return state.front_verts_only, func(v): state.front_verts_only = v))
	body.add_child(row1)

	var sv_row := HBoxContainer.new()
	sv_row.add_theme_constant_override("separation", 2)
	sv_row.alignment = BoxContainer.ALIGNMENT_CENTER
	var sv_group := ButtonGroup.new()
	sv_row.add_child(_shared_verts_button("vertex_shared",
		"Merge Shared Vertices: paint every vertex sharing a position together (smooth/soft-normal corners and smooth, soft-normal look). Default vertex painting mode.",
		VSState.SharedVerts.MERGE, sv_group))
	sv_row.add_child(_shared_verts_button("vertex_split",
		"Split Shared Vertices: fan coincident hard-edge vertices apart so each face's corner can hold its own color. Requires hard edges / flat shading. You can create hard edges with the \"Paint Normals\" brush tool.",
		VSState.SharedVerts.SPLIT, sv_group, VSPro.Feature.SPLIT_VERTS))
	body.add_child(sv_row)

	body.add_child(_row("Vertex Size", _slider(2.0, 40.0, 0.5,
		func(): return state.dot_size,
		func(v): state.dot_size = v)))
	body.add_child(_row("Draw Dist", _slider(1.0, 500.0, 1.0,
		func(): return state.draw_distance,
		func(v): state.draw_distance = v)))

	var dbg := _segmented(["Off", "R", "G", "B", "A"],
		func(): return state.debug_channel,
		func(i): state.debug_channel = i)
	var dbg_row := _row("Debug", dbg)
	dbg_row.tooltip_text = "Isolate a single vertex-color channel as grayscale (requires the \"Setup Material\")"
	body.add_child(dbg_row)

	var rt := CheckBox.new()
	rt.text = "Real-time painting"
	rt.button_pressed = state.realtime_painting
	rt.tooltip_text = "In case of performance issues, disable real-time painting. The vertex color painting will be updated on mouse release"
	rt.toggled.connect(func(v):
		state.realtime_painting = v
		state.emit_changed())
	body.add_child(rt)

	var fn := CheckBox.new()
	fn.text = "Hide Inspector while active"
	fn.button_pressed = state.auto_focus_node_tab
	fn.tooltip_text = "While a tool is active, switch the editor's Node to Signals or Groups so the Inspector doesn't repaint on every stroke (fixes slow or \"jumping\" painting)."
	fn.toggled.connect(func(v):
		state.auto_focus_node_tab = v
		state.emit_changed())
	body.add_child(fn)


func _view_toggle(icon: Texture2D, tip: String, getter: Callable, setter: Callable) -> Button:
	var b := Button.new()
	b.icon = icon
	b.tooltip_text = tip
	b.toggle_mode = true
	b.focus_mode = Control.FOCUS_NONE
	b.expand_icon = false
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var s := int(round(32 * _ui_scale))
	b.custom_minimum_size = Vector2(s, s)
	b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	b.add_theme_constant_override("icon_max_width", int(round(20 * _ui_scale)))
	_tint_icon_button(b)
	b.button_pressed = getter.call()
	b.toggled.connect(func(v):
		setter.call(v)
		state.view_changed.emit()
		state.emit_changed())
	return b


func _dual_icon(name_a: String, name_b: String) -> Texture2D:
	var ta := _icon(name_a)
	var tb := _icon(name_b)
	if ta == null:
		return tb
	if tb == null:
		return ta
	var ia := ta.get_image()
	var ib := tb.get_image()
	var w := ia.get_width() + ib.get_width()
	var h := maxi(ia.get_height(), ib.get_height())
	var out := Image.create(w, h, false, Image.FORMAT_RGBA8)
	out.fill(Color(0, 0, 0, 0))
	out.blit_rect(ia, Rect2i(0, 0, ia.get_width(), ia.get_height()), Vector2i(0, 0))
	out.blit_rect(ib, Rect2i(0, 0, ib.get_width(), ib.get_height()), Vector2i(ia.get_width(), 0))
	return ImageTexture.create_from_image(out)


func _material_dual_button(icon_a: String, icon_b: String, label: String, tip: String, action: StringName) -> Button:
	var b := Button.new()
	b.text = label
	b.icon = _dual_icon(icon_a, icon_b)
	b.tooltip_text = tip
	b.focus_mode = Control.FOCUS_NONE
	b.expand_icon = false
	b.alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
	var h := int(round(40 * _ui_scale))
	b.custom_minimum_size = Vector2(0, h)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	b.add_theme_constant_override("icon_max_width", int(round(36 * _ui_scale)))
	b.add_theme_constant_override("h_separation", int(round(4 * _ui_scale)))
	_tint_icon_button(b)
	b.pressed.connect(func(): action_requested.emit(action))
	return b


func _shared_verts_button(icon_name: String, tip: String, mode: int, group: ButtonGroup, feature := -1) -> Button:
	var b := Button.new()
	b.icon = _icon(icon_name)
	b.focus_mode = Control.FOCUS_NONE
	b.expand_icon = false
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var s := int(round(40 * _ui_scale))
	b.custom_minimum_size = Vector2(s, s)
	b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	b.add_theme_constant_override("icon_max_width", int(round(30 * _ui_scale)))
	_tint_icon_button(b)

	if feature != -1 and VSPro.locked(feature):
		b.tooltip_text = tip + " (PRO VERSION)"
		b.pressed.connect(func(): _show_pro_alert())
		_gold_icon(b)
		return b

	b.tooltip_text = tip
	b.toggle_mode = true
	b.button_group = group
	b.button_pressed = (state.shared_verts == mode)
	b.pressed.connect(func():
		if _syncing:
			return
		state.shared_verts = mode
		state.view_changed.emit()
		state.emit_changed())
	_syncers.append(func():
		b.button_pressed = (state.shared_verts == mode))
	return b


# ---------------------------------------------------------------- 
# Tool
# ---------------------------------------------------------------- 

func _build_tool(root: VBoxContainer) -> void:
	var body := _section(root, "Tools")
	_build_tool_fields(body)


func _build_tool_fields(container: Control) -> void:
	var row1 := HBoxContainer.new()
	row1.add_theme_constant_override("separation", 2)
	row1.alignment = BoxContainer.ALIGNMENT_CENTER
	var stypes := [
		["cursor", "Selection: Single", VSState.SelectType.POINT],
		["select_lasso", "Selection: Lasso", VSState.SelectType.LASSO],
		["select_rectangle", "Selection: Rectangle", VSState.SelectType.RECTANGLE],
		["select_ellipse", "Selection: Ellipse", VSState.SelectType.ELLIPSE],
		["select_linked", "Select Linked: pick a material to select all vertices of its faces.", VSState.SelectType.LINKED],
	]

	var stype_feature := {
		VSState.SelectType.LASSO: VSPro.Feature.SELECT_LASSO,
		VSState.SelectType.RECTANGLE: VSPro.Feature.SELECT_RECTANGLE,
		VSState.SelectType.ELLIPSE: VSPro.Feature.SELECT_ELLIPSE,
		VSState.SelectType.LINKED: VSPro.Feature.SELECT_LINKED,
	}

	for entry in stypes:
		var st: int = entry[2]
		var b: Button
		if stype_feature.has(st) and VSPro.locked(stype_feature[st]):
			b = _pro_icon_button(entry[0], entry[1], true, stype_feature[st], Callable())
		else:
			b = _icon_button(entry[0], entry[1], true, func(): toggle_select_tool(st))
			_select_buttons.append({"btn": b, "stype": st})
		row1.add_child(b)
	row1.add_child(_icon_button("select_all", "Select All", false, func(): action_requested.emit(&"select_all")))
	row1.add_child(_icon_button("deselect", "Deselect", false, func(): action_requested.emit(&"deselect")))
	row1.add_child(_pro_icon_button("select_invert", "Invert Selection", false,
		VSPro.Feature.INVERT_SELECTION, func(): action_requested.emit(&"invert_selection")))
	container.add_child(row1)

	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 2)
	row2.alignment = BoxContainer.ALIGNMENT_CENTER
	row2.add_child(_paint_op_button("brush", "Paint Vertex Colors", VSState.Op.REPLACE))
	row2.add_child(_paint_op_button("mode_add", "Paint Add (additive blending)", VSState.Op.ADD))
	row2.add_child(_paint_op_button("mode_erase", "Eraser", VSState.Op.ERASE))
	row2.add_child(_paint_op_button("mode_precision", "Paint Precision: click individual vertices to set the color (no brush size).", VSState.Op.PRECISION, VSPro.Feature.PAINT_PRECISION))
	row2.add_child(_paint_op_button("mode_normals", "Paint Normals: brush over vertices to make edges hard or smooth.", VSState.Op.NORMALS, VSPro.Feature.PAINT_NORMALS))
	row2.add_child(_paint_op_button("mode_blur", "Blur: smooth vertex colors toward their neighbors (Laplacian).", VSState.Op.BLUR))
	container.add_child(row2)

	var row3 := HBoxContainer.new()
	row3.add_theme_constant_override("separation", 2)
	row3.alignment = BoxContainer.ALIGNMENT_CENTER
	var fill := _icon_button("fill_all", "Fill All", false, func(): action_requested.emit(&"fill_all"))
	var erase := _icon_button("erase_all", "Erase All", false, func(): action_requested.emit(&"erase_all"))
	_fill_btns.append(fill)
	_erase_btns.append(erase)
	row3.add_child(fill)
	row3.add_child(erase)
	_color_hide.append(row3)
	container.add_child(row3)

	var hint_row := HBoxContainer.new()
	hint_row.add_theme_constant_override("separation", 4)
	var info := TextureRect.new()
	info.texture = _icon("info")
	info.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	info.custom_minimum_size = Vector2(16, 16) * _ui_scale
	info.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hint_row.add_child(info)
	var hint := Label.new()
	hint.text = "Click or drag to select. Shift adds, Alt removes."
	hint.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hint.custom_minimum_size.x = round(160 * _ui_scale)
	hint_row.add_child(hint)
	_select_hints.append(hint_row)
	container.add_child(hint_row)

	set_selection_active(false)
	_refresh_select_hint()


func _paint_op_button(icon_name: String, tip: String, op: int, feature := -1) -> Button:
	if feature != -1 and VSPro.locked(feature):
		return _pro_icon_button(icon_name, tip, true, feature, Callable())
	var b := _icon_button(icon_name, tip, true, func(): toggle_paint_tool(op))
	_paint_op_buttons.append({"btn": b, "op": op})
	return b


func _refresh_tool_buttons() -> void:
	for e in _paint_op_buttons:
		var b: Button = e["btn"]
		if is_instance_valid(b):
			b.button_pressed = state.tool_enabled \
				and state.tool_mode == VSState.ToolMode.PAINT and state.operation == e["op"]
	for e in _select_buttons:
		var sb: Button = e["btn"]
		if is_instance_valid(sb):
			sb.button_pressed = state.tool_enabled \
				and state.tool_mode == VSState.ToolMode.SELECT and state.select_type == e["stype"]


func _refresh_select_hint() -> void:
	var show_hint := state.tool_enabled and state.tool_mode == VSState.ToolMode.SELECT \
		and state.select_type != VSState.SelectType.LINKED
	var hint_text := "Click or drag to select. Shift adds, Alt removes."
	if state.select_type == VSState.SelectType.POINT and VSPro.locked(VSPro.Feature.SELECT_POINT_DRAG):
		hint_text = "Click to select. Shift+click adds, Alt+click removes."
	for h in _select_hints:
		if is_instance_valid(h):
			h.visible = show_hint
			for c in h.get_children():
				if c is Label:
					(c as Label).text = hint_text
	_refit_popup()


# ---------------------------------------------------------------- 
# Selection Settings
# ---------------------------------------------------------------- 

func _build_selection_settings(root: VBoxContainer) -> void:
	var body := _section(root, "Selection Settings", true)
	_selection_section = body.get_parent().get_parent()
	_build_selection_fields(body)


func _build_selection_fields(container: Control) -> void:
	var link_row := _row("Select linked", _segmented(
		["Material"],
		func(): return _link_by,
		func(i): _link_by = i))
	link_row.tooltip_text = "What to match when selecting linked vertices."
	container.add_child(link_row)

	var mlist := ItemList.new()
	mlist.custom_minimum_size = Vector2(0, 96)
	mlist.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mlist.size_flags_vertical = Control.SIZE_EXPAND_FILL
	mlist.select_mode = ItemList.SELECT_SINGLE
	mlist.auto_height = false
	mlist.item_selected.connect(func(idx: int):
		if _material_list_updating:
			return
		if VSPro.locked(VSPro.Feature.SELECT_LINKED):
			_show_pro_alert()
			return
		select_linked_material.emit(idx))
	_material_lists.append(mlist)
	container.add_child(mlist)
	_fill_material_list(mlist)


func _fill_material_list(ml: ItemList) -> void:
	ml.clear()
	for l in _material_labels:
		var i := ml.add_item(l)
		ml.set_item_tooltip(i, l + " (click to select vertices of the faces that have this material assigned)")


func set_materials(labels: PackedStringArray) -> void:
	_material_labels = labels
	_material_list_updating = true
	for ml in _material_lists:
		if is_instance_valid(ml):
			_fill_material_list(ml)
	_material_list_updating = false


# ---------------------------------------------------------------- 
# Paint
# ---------------------------------------------------------------- 

func _build_paint(root: VBoxContainer) -> void:
	var body := _section(root, "Paint Settings")
	_build_paint_fields(body)


func _build_paint_fields(container: Control) -> void:
	var value_row := _row("Value", _slider(0.0, 1.0, 0.01,
		func(): return state.channel_value,
		func(v): state.channel_value = v))
	value_row.tooltip_text = "Value painted into the selected single channel (R/G/B/A). Only shown when a single channel is selected."
	_value_rows.append(value_row)
	container.add_child(value_row)

	var opacity_row := _row("Opacity", _slider(0.0, 1.0, 0.01,
		func(): return state.opacity,
		func(v): state.opacity = v))
	_normals_hide.append(opacity_row)
	container.add_child(opacity_row)

	var size_row := _row("Brush Size", _slider(2.0, 1000.0, 1.0,
		func(): return state.radius,
		func(v): state.radius = v))
	_brush_size_rows.append(size_row)
	container.add_child(size_row)

	var mode_row := _row("Mode", _segmented(
		["Hard", "Smooth"],
		func(): return state.normals_mode,
		func(i): state.normals_mode = i))
	mode_row.tooltip_text = "Hard: painting makes edges faceted (each face keeps its own normal).\nSmooth: painting averages normals so edges shade smoothly."
	_normals_show.append(mode_row)
	container.add_child(mode_row)

	var col_row := HBoxContainer.new()
	var col_lbl := Label.new()
	col_lbl.text = "Color"
	col_lbl.custom_minimum_size.x = LABEL_W
	col_row.add_child(col_lbl)
	var cp := ColorPickerButton.new()
	cp.custom_minimum_size = Vector2(0, 26)
	cp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cp.edit_alpha = true
	cp.color = state.color
	cp.color_changed.connect(func(c):
		if _syncing:
			return
		set_color(c)
		state.color_changed.emit()
		state.emit_changed())
	cp.toggled.connect(func(on):
		if on:
			_on_color_picker_pressed())
	_syncers.append(func():
		if not cp.color.is_equal_approx(state.color):
			cp.color = state.color)
	col_row.add_child(cp)
	var pick := _icon_button("pick", "Eyedropper: sample a vertex color from the viewport.", true, Callable())
	pick.toggled.connect(func(on):
		if on:
			_on_color_picker_pressed()
			eyedrop_requested.emit(&"color"))
	_eyedrop_btns.append(pick)
	col_row.add_child(pick)
	_color_hide.append(col_row)
	container.add_child(col_row)

	var sw_head := HBoxContainer.new()
	var sw_lbl := Label.new()
	sw_lbl.text = "Swatches"
	sw_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sw_head.add_child(sw_lbl)

	var opts := MenuButton.new()
	opts.text = "..."
	opts.tooltip_text = "Swatch options"
	opts.flat = false
	var pm := opts.get_popup()
	pm.add_item("Import PNG Palette…", 0)
	pm.add_item("Save Palette…", 1)
	pm.add_item("Load Palette…", 2)
	pm.add_separator()
	pm.add_item("Clear", 3)
	pm.id_pressed.connect(_on_swatch_menu_id)
	sw_head.add_child(opts)

	_color_hide.append(sw_head)
	container.add_child(sw_head)

	var box := HFlowContainer.new()
	_swatch_boxes.append(box)
	_color_hide.append(box)
	container.add_child(box)

	var ch_margin := MarginContainer.new()
	ch_margin.add_theme_constant_override("margin_top", 12)
	ch_margin.add_child(_row("Channel", _channel_segmented()))
	_normals_hide.append(ch_margin)
	container.add_child(ch_margin)

	var pro_locked := VSPro.locked(VSPro.Feature.FALLOFF)
	var falloff_title := "Falloff (PRO VERSION)" if pro_locked \
		else "Falloff"
	var falloff_body := _collapsible_section(container, falloff_title)
	_normals_hide.append(falloff_body.get_parent().get_parent())
	_add_falloff_ui(falloff_body)

	_rebuild_swatches()
	_refresh_value_row()


# ---------------------------------------------------------------- 
# Actions
# ---------------------------------------------------------------- 

func _build_actions(root: VBoxContainer) -> void:
	var body := _section(root, "Replace Colors")
	_replace_section = body.get_parent().get_parent()

	var rep := HBoxContainer.new()
	var t_lbl := Label.new(); t_lbl.text = "Replace"
	t_lbl.custom_minimum_size.x = LABEL_W
	rep.add_child(t_lbl)

	_replace_target_btn = _color_button(state.replace_target, func(c): state.replace_target = c)
	_replace_target_btn.tooltip_text = "Source color to look for. Click to pick."
	rep.add_child(_replace_target_btn)

	var arrow := Label.new(); arrow.text = "→"
	rep.add_child(arrow)

	_replace_new_btn = _color_button(state.replace_new, func(c): state.replace_new = c)
	_replace_new_btn.tooltip_text = "Color to write in its place. Click to pick."
	rep.add_child(_replace_new_btn)

	_replace_btn = _pro_icon_button("replace", "Replace", false,
		VSPro.Feature.REPLACE_COLORS, func(): action_requested.emit(&"replace"))
	_refresh_actions_hint()
	rep.add_child(_replace_btn)

	rep.add_child(_icon_button("swap", "Swap the source and target colors", false, func():
		var tmp := state.replace_target
		state.replace_target = state.replace_new
		state.replace_new = tmp
		_replace_target_btn.color = state.replace_target
		_replace_new_btn.color = state.replace_new))
	body.add_child(rep)

	var thr := _row("Threshold", _slider(0.0, 1.0, 0.005,
		func(): return state.replace_threshold,
		func(v): state.replace_threshold = v))
	thr.tooltip_text = "Color-match tolerance (per channel). 0 = exact match only; higher values also replace similar colors"
	body.add_child(thr)


# ---------------------------------------------------------------- 
# Fill Normals
# ---------------------------------------------------------------- 

func _build_fill_normals(root: VBoxContainer) -> void:
	var body := _section(root, "Fill Normals")
	_fill_normals_section = body.get_parent().get_parent()

	_fill_hard_btn = Button.new()
	_fill_hard_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if VSPro.locked(VSPro.Feature.PAINT_NORMALS):
		_fill_hard_btn.pressed.connect(func(): _show_pro_alert())
		_gold_icon(_fill_hard_btn)
	else:
		_fill_hard_btn.pressed.connect(func(): action_requested.emit(&"fill_hard"))
	body.add_child(_fill_hard_btn)

	_fill_smooth_btn = Button.new()
	_fill_smooth_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if VSPro.locked(VSPro.Feature.PAINT_NORMALS):
		_fill_smooth_btn.pressed.connect(func(): _show_pro_alert())
		_gold_icon(_fill_smooth_btn)
	else:
		_fill_smooth_btn.pressed.connect(func(): action_requested.emit(&"fill_smooth"))
	body.add_child(_fill_smooth_btn)

	_refresh_fill_normal_labels(false)


# ---------------------------------------------------------------- 
# Vertex Groups
# ---------------------------------------------------------------- 

func _build_vgroups(root: VBoxContainer) -> void:
	var body := _section(root, "Vertex Groups", true, false)

	var wrap := HBoxContainer.new()
	wrap.add_theme_constant_override("separation", 4)
	wrap.size_flags_vertical = Control.SIZE_EXPAND_FILL

	_vgroup_list = ItemList.new()
	_vgroup_list.custom_minimum_size = Vector2(0, 96)
	_vgroup_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_vgroup_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_vgroup_list.select_mode = ItemList.SELECT_SINGLE
	_vgroup_list.auto_height = false
	_vgroup_list.item_selected.connect(func(idx: int):
		if _vgroup_list_updating:
			return
		_vgroup_active = _vgroup_list.get_item_text(idx)
		_refresh_vgroup_buttons())
	_vgroup_list.item_activated.connect(func(idx: int):
		if _vgroup_list_updating:
			return
		if VSPro.locked(VSPro.Feature.VERTEX_GROUPS):
			_show_pro_alert()
			return
		_vgroup_active = _vgroup_list.get_item_text(idx)
		_refresh_vgroup_buttons()
		vgroup_action.emit(&"reload", _vgroup_active))
	wrap.add_child(_vgroup_list)

	var btns := VBoxContainer.new()
	btns.add_theme_constant_override("separation", 2)
	_vgroup_new_btn = _pro_icon_button("new_snapshot",
		"New group from the current selection (needs a selection).",
		false, VSPro.Feature.VERTEX_GROUPS, func(): vgroup_action.emit(&"new", ""))
	_vgroup_save_btn = _pro_icon_button("save_snapshot",
		"Overwrite the selected group with the current selection.",
		false, VSPro.Feature.VERTEX_GROUPS, func(): vgroup_action.emit(&"save", _vgroup_active))
	_vgroup_reload_btn = _pro_icon_button("reload_snapshot",
		"Select the vertices stored in this group.",
		false, VSPro.Feature.VERTEX_GROUPS, func(): vgroup_action.emit(&"reload", _vgroup_active))
	_vgroup_delete_btn = _pro_icon_button("trash_can",
		"Delete the selected group.",
		false, VSPro.Feature.VERTEX_GROUPS, func(): vgroup_action.emit(&"delete", _vgroup_active))
	btns.add_child(_vgroup_new_btn)
	btns.add_child(_vgroup_save_btn)
	btns.add_child(_vgroup_reload_btn)
	btns.add_child(_vgroup_delete_btn)
	wrap.add_child(btns)

	body.add_child(wrap)
	_refresh_vgroup_buttons()


func _refresh_vgroup_buttons() -> void:
	if VSPro.locked(VSPro.Feature.VERTEX_GROUPS):
		return
	var has_active := _vgroup_active != ""
	if is_instance_valid(_vgroup_new_btn):
		_vgroup_new_btn.disabled = not _vgroup_has_selection
	if is_instance_valid(_vgroup_save_btn):
		_vgroup_save_btn.disabled = not (_vgroup_has_selection and has_active)
	if is_instance_valid(_vgroup_reload_btn):
		_vgroup_reload_btn.disabled = not has_active
	if is_instance_valid(_vgroup_delete_btn):
		_vgroup_delete_btn.disabled = not has_active


# ---------------------------------------------------------------- 
# Snapshot (aka Variations)
# ---------------------------------------------------------------- 

func _build_snapshot(root: VBoxContainer) -> void:
	var body := _section(root, "Variations", true, false)

	var wrap := HBoxContainer.new()
	wrap.add_theme_constant_override("separation", 4)
	wrap.size_flags_vertical = Control.SIZE_EXPAND_FILL

	_snapshot_list = ItemList.new()
	_snapshot_list.custom_minimum_size = Vector2(0, 96)
	_snapshot_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_snapshot_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_snapshot_list.select_mode = ItemList.SELECT_SINGLE
	_snapshot_list.auto_height = false
	_snapshot_list.item_selected.connect(func(idx: int):
		if _snapshot_list_updating:
			return
		var p := str(_snapshot_list.get_item_metadata(idx))
		if p != "":
			set_snapshot_path(p))
	_snapshot_list.item_activated.connect(func(idx: int):
		if _snapshot_list_updating:
			return
		if VSPro.locked(VSPro.Feature.SNAPSHOTS):
			_show_pro_alert()
			return
		var p := str(_snapshot_list.get_item_metadata(idx))
		if p != "":
			snapshot_selected.emit(p))
	wrap.add_child(_snapshot_list)

	var btns := VBoxContainer.new()
	btns.add_theme_constant_override("separation", 2)
	for spec in [
		["new_snapshot", "New variation", &"snapshot_new"],
		["save_snapshot", "Save variation", &"snapshot_save"],
		["folder_open", "Load variation (browse)", &"snapshot_load"],
		["reload_snapshot", "Reload the active variation without browsing", &"snapshot_reload"],
		["trash_can", "Delete the active variation (also deletes the resource file from disk)", &"snapshot_delete"],
	]:
		var act: StringName = spec[2]
		btns.add_child(_pro_icon_button(spec[0], spec[1], false, VSPro.Feature.SNAPSHOTS, func(): action_requested.emit(act)))
	wrap.add_child(btns)

	body.add_child(wrap)


# ----------------------------------------------------------------
# Runtime
# ----------------------------------------------------------------

func _build_runtime(root: VBoxContainer) -> void:
	var body := _section(root, "Runtime", false, false)
	_runtime_cb = CheckBox.new()
	_runtime_cb.text = "Add runtime node"
	_runtime_cb.tooltip_text = (
		"Adds a VSRuntime child on the selected MeshInstance3D. Use its inspector or public API "
		+ "to swap snapshot variations without overwriting the base mesh. There's also an API for blending between variations at runtime.")
	_runtime_cb.toggled.connect(func(enabled: bool):
		if _runtime_syncing:
			return
		if VSPro.locked(VSPro.Feature.SNAPSHOTS):
			_runtime_syncing = true
			_runtime_cb.button_pressed = not enabled
			_runtime_syncing = false
			_show_pro_alert()
			return
		runtime_toggled.emit(enabled))
	body.add_child(_runtime_cb)


func set_runtime_node_present(present: bool) -> void:
	if _runtime_cb == null:
		return
	_runtime_syncing = true
	_runtime_cb.button_pressed = present
	_runtime_syncing = false


# ----------------------------------------------------------------
# History
# ----------------------------------------------------------------

func _build_history(root: VBoxContainer) -> void:
	var body := _section(root, "History")
	var row := HBoxContainer.new()
	_undo_btn = Button.new(); _undo_btn.text = "Undo"
	_undo_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_undo_btn.pressed.connect(func(): action_requested.emit(&"undo"))
	row.add_child(_undo_btn)
	_redo_btn = Button.new(); _redo_btn.text = "Redo"
	_redo_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_redo_btn.pressed.connect(func(): action_requested.emit(&"redo"))
	row.add_child(_redo_btn)
	body.add_child(row)


#endregion UI build


#region Helpers
# ---------------------------------------------------------------- 
# Helpers
# ---------------------------------------------------------------- 

func _section(root: VBoxContainer, title: String, expand := false, start_open := true) -> VBoxContainer:
	return _collapsible_section(root, title, expand, "", start_open)


func _collapsible_section(parent: Control, title: String, expand := false, tooltip := "", start_open := true) -> VBoxContainer:
	var wrap := VBoxContainer.new()
	wrap.add_theme_constant_override("separation", 2)
	if expand:
		wrap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(wrap)

	var open := start_open
	if state != null and state.section_open.has(title):
		open = bool(state.section_open[title])

	var open_icon := _ed_icon("GuiTreeArrowDown")
	var closed_icon := _ed_icon("GuiTreeArrowRight")

	var header := Button.new()
	header.toggle_mode = true
	header.button_pressed = open
	header.text = title
	header.alignment = HORIZONTAL_ALIGNMENT_LEFT
	header.flat = true
	header.focus_mode = Control.FOCUS_NONE
	if not tooltip.is_empty():
		header.tooltip_text = tooltip
	var bf := _ed_font("bold")
	if bf:
		header.add_theme_font_override("font", bf)
	var bs := _ed_font_size("main_size")
	if bs > 0:
		header.add_theme_font_size_override("font_size", bs)
	if open_icon:
		header.icon = open_icon if open else closed_icon

	header.set_meta("vs_section_header", true)
	_apply_section_header_colors(header)
	wrap.add_child(header)

	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 4)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_bottom", 4)
	if expand:
		body.size_flags_vertical = Control.SIZE_EXPAND_FILL
		margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(body)
	wrap.add_child(margin)
	margin.visible = open
	if expand and not open:
		wrap.size_flags_vertical = Control.SIZE_SHRINK_BEGIN

	header.toggled.connect(func(is_open):
		margin.visible = is_open
		if expand:
			wrap.size_flags_vertical = Control.SIZE_EXPAND_FILL if is_open else Control.SIZE_SHRINK_BEGIN
		if is_open and open_icon:
			header.icon = open_icon
		elif not is_open and closed_icon:
			header.icon = closed_icon
		if state != null:
			state.section_open[title] = is_open
			state.emit_changed())
	return body


func _row(label: String, control: Control, width: float = LABEL_W) -> HBoxContainer:
	var h := HBoxContainer.new()
	var l := Label.new()
	l.text = label
	l.custom_minimum_size.x = width
	h.add_child(l)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(control)
	return h


func _single_button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.toggle_mode = true
	b.button_pressed = true
	b.disabled = true
	return b


func _channel_segmented() -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 2)
	var labels := ["RGBA", "R", "G", "B", "A"]
	var buttons: Array[Button] = []
	var channel_indices: Array[int] = []
	var pro_locked := VSPro.locked(VSPro.Feature.SINGLE_CHANNEL)
	for i in labels.size():
		var b := Button.new()
		b.text = labels[i]
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.toggle_mode = true
		var tip := "Paint in all RGBA channels" if i == 0 \
			else "Paint in the %s channel. Hold Shift to add channel." % labels[i]
		if i > 0 and pro_locked:
			b.toggle_mode = false
			b.tooltip_text = tip + " (PRO VERSION)"
			b.pressed.connect(func(): _show_pro_alert())
			_gold_icon(b)
		else:
			b.button_pressed = state.channel_button_pressed(i)
			b.tooltip_text = tip
			var idx := i
			b.pressed.connect(func():
				if _syncing:
					return
				var shift := Input.is_key_pressed(KEY_SHIFT)
				state.apply_channel_button(idx, shift)
				state.emit_changed())
			buttons.append(b)
			channel_indices.append(i)
		h.add_child(b)
	if not buttons.is_empty():
		_syncers.append(func():
			for j in buttons.size():
				buttons[j].button_pressed = state.channel_button_pressed(channel_indices[j]))
	return h


func _segmented(options: Array, getter: Callable, setter: Callable) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 2)
	var group := ButtonGroup.new()
	var current: int = getter.call()
	var buttons: Array[Button] = []
	for i in options.size():
		var b := Button.new()
		b.text = options[i]
		b.toggle_mode = true
		b.button_group = group
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.button_pressed = (i == current)
		var idx := i
		b.pressed.connect(func():
			if _syncing:
				return
			setter.call(idx)
			state.emit_changed())
		buttons.append(b)
		h.add_child(b)
	_syncers.append(func():
		var v: int = getter.call()
		for j in buttons.size():
			buttons[j].button_pressed = (j == v))
	return h


func _slider(min_v: float, max_v: float, step: float, getter: Callable, setter: Callable) -> HBoxContainer:
	var h := HBoxContainer.new()
	var s := HSlider.new()
	s.min_value = min_v
	s.max_value = max_v
	s.step = step
	s.value = getter.call()
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var val := Label.new()
	val.custom_minimum_size.x = 42
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	val.text = _fmt(getter.call(), step)
	s.value_changed.connect(func(v):
		if _syncing:
			return
		setter.call(v)
		val.text = _fmt(v, step)
		state.emit_changed())
	_syncers.append(func():
		var gv: float = getter.call()
		if not is_equal_approx(s.value, gv):
			s.value = gv
		val.text = _fmt(gv, step))
	h.add_child(s)
	h.add_child(val)
	return h


func _fmt(v: float, step: float) -> String:
	if step >= 1.0:
		return str(int(round(v)))
	return "%.2f" % v


func _wide_button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.pressed.connect(cb)
	return b


func _pro_wide_button(text: String, feature: int, cb: Callable) -> Button:
	if VSPro.locked(feature):
		var b := _wide_button(text, func(): _show_pro_alert())
		_gold_icon(b)
		return b
	return _wide_button(text, cb)


const ICON_DIR := "res://addons/vertex_studio/icons/"

func _icon(name: String) -> Texture2D:
	var p := ICON_DIR + name + ".svg"
	return load(p) if ResourceLoader.exists(p) else null


func _icon_button(icon_name: String, tip: String, toggle: bool, cb: Callable) -> Button:
	var b := Button.new()
	b.icon = _icon(icon_name)
	b.tooltip_text = tip
	b.toggle_mode = toggle
	b.focus_mode = Control.FOCUS_NONE
	b.expand_icon = false
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var s := int(round(32 * _ui_scale))
	b.custom_minimum_size = Vector2(s, s)
	b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	b.add_theme_constant_override("icon_max_width", int(round(20 * _ui_scale)))
	_tint_icon_button(b)
	if cb.is_valid():
		b.pressed.connect(cb)
	return b


func _add_falloff_ui(container: Control) -> void:
	var pro_locked := VSPro.locked(VSPro.Feature.FALLOFF)

	var ce := VSCurveEdit.new()
	ce.editable = false
	ce.custom_minimum_size = Vector2(0, 64)
	ce.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ce.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	ce.tooltip_text = "Click to edit the falloff curve in the Inspector" \
		+ (" (PRO VERSION)" if pro_locked else "")
	ce.set_curve(state.falloff)
	if pro_locked:
		ce.clicked.connect(func(): _show_pro_alert())
	else:
		ce.clicked.connect(_open_falloff_editor)
	_curve_previews.append(ce)
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_right", 14)
	m.add_child(ce)
	container.add_child(m)

	var presets := HBoxContainer.new()
	presets.add_theme_constant_override("separation", 2)
	presets.add_child(_pro_wide_button("Constant", VSPro.Feature.FALLOFF,
		func(): _set_falloff_preset(&"constant")))
	presets.add_child(_pro_wide_button("Linear", VSPro.Feature.FALLOFF,
		func(): _set_falloff_preset(&"linear")))
	presets.add_child(_pro_wide_button("Smooth", VSPro.Feature.FALLOFF,
		func(): _set_falloff_preset(&"smooth")))
	container.add_child(presets)

	if not state.falloff.changed.is_connected(_on_falloff_changed):
		state.falloff.changed.connect(_on_falloff_changed)


func _open_falloff_editor() -> void:
	# Code stripped away in the free version.
	# Get Vertex Studio Pro to get access to all features and the full source-code.
	pass


func _on_falloff_changed() -> void:
	_redraw_curves()
	state.emit_changed()


func _redraw_curves() -> void:
	for ce in _curve_previews:
		if is_instance_valid(ce):
			ce.queue_redraw()


func _set_falloff_preset(_kind: StringName) -> void:
	# Code stripped away in the free version.
	# Get Vertex Studio Pro to get access to all features and the full source-code.
	pass


func _color_button(col: Color, on_changed: Callable) -> ColorPickerButton:
	var b := ColorPickerButton.new()
	b.custom_minimum_size = _color_btn_size
	b.edit_alpha = true
	b.color = col
	b.color_changed.connect(on_changed)
	return b


func _on_swatch_menu_id(id: int) -> void:
	match id:
		0: swatch_menu.emit(&"import_png")
		1: swatch_menu.emit(&"save")
		2: swatch_menu.emit(&"load")
		3:
			state.swatches.clear()
			_rebuild_swatches()
			state.emit_changed()


func refresh_swatches() -> void:
	_rebuild_swatches()


func _rebuild_swatches() -> void:
	for box in _swatch_boxes:
		if not is_instance_valid(box):
			continue
		for c in box.get_children():
			c.queue_free()
		box.add_child(_make_add_swatch())
		for i in state.swatches.size():
			box.add_child(_make_swatch(i))
	_refresh_swatch_highlight()


func _make_add_swatch() -> Button:
	var b := Button.new()
	b.icon = _icon("plus")
	b.tooltip_text = "Add current color as a swatch."
	b.custom_minimum_size = Vector2(_swatch_edge, _swatch_edge)
	b.expand_icon = true
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.add_theme_constant_override("icon_max_width", int(round(_swatch_edge * 0.6)))
	_tint_icon_button(b)
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(func():
		state.swatches.append(state.color)
		_rebuild_swatches()
		state.emit_changed())
	return b


func _make_swatch(i: int) -> ColorRect:
	var idx := i
	var sw := ColorRect.new()
	sw.set_meta("sw_idx", i)
	sw.color = state.swatches[i]
	sw.custom_minimum_size = Vector2(_swatch_edge, _swatch_edge)
	sw.tooltip_text = "Left-click: use.  Right-click: remove."
	var sel_line := ColorRect.new()
	sel_line.name = "sel"
	sel_line.color = Color(1, 1, 1)
	sel_line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sel_line.anchor_left = 0.0
	sel_line.anchor_right = 1.0
	sel_line.anchor_top = 1.0
	sel_line.anchor_bottom = 1.0
	sel_line.offset_top = -3.0
	sel_line.offset_bottom = 0.0
	sel_line.visible = false
	sw.add_child(sel_line)
	sw.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed:
			if e.button_index == MOUSE_BUTTON_LEFT:
				set_color(state.swatches[idx])
				state.color_changed.emit()
				state.emit_changed()
			elif e.button_index == MOUSE_BUTTON_RIGHT:
				state.swatches.remove_at(idx)
				_rebuild_swatches()
				state.emit_changed())
	return sw


func _refresh_swatch_highlight() -> void:
	for box in _swatch_boxes:
		if not is_instance_valid(box):
			continue
		for c in box.get_children():
			var sw := c as ColorRect
			if sw == null or not sw.has_meta("sw_idx"):
				continue
			var idx: int = sw.get_meta("sw_idx")
			var is_active: bool = idx < state.swatches.size() and state.swatches[idx].is_equal_approx(state.color)
			var sel_line := sw.get_node_or_null("sel")
			if sel_line:
				sel_line.visible = is_active


func _refresh_actions_hint() -> void:
	if not is_instance_valid(_replace_btn):
		return
	var base := "Replace every vertex whose color is within Threshold of the source color.\nApplying to: %s" % _channel_name()

	if VSPro.locked(VSPro.Feature.REPLACE_COLORS):
		base = base + " (PRO VERSION)"
	_replace_btn.tooltip_text = base


func _refresh_value_row() -> void:
	var op: int = state.operation if state.tool_enabled else -1
	var normals := op == VSState.Op.NORMALS
	var precision := op == VSState.Op.PRECISION
	var no_color := op == VSState.Op.NORMALS or op == VSState.Op.BLUR
	for r in _value_rows:
		if is_instance_valid(r):
			r.visible = state.is_single_channel() and not no_color
	for r in _brush_size_rows:
		if is_instance_valid(r):
			r.visible = not precision
	for c in _normals_hide:
		if is_instance_valid(c):
			c.visible = not normals
	for c in _normals_show:
		if is_instance_valid(c):
			c.visible = normals
	for c in _color_hide:
		if is_instance_valid(c):
			c.visible = not no_color
	if is_instance_valid(_replace_section):
		_replace_section.visible = not no_color
	if is_instance_valid(_fill_normals_section):
		_fill_normals_section.visible = normals
	var linked_sel := state.tool_enabled \
		and state.tool_mode == VSState.ToolMode.SELECT \
		and state.select_type == VSState.SelectType.LINKED
	if is_instance_valid(_selection_section):
		_selection_section.visible = linked_sel
	if is_instance_valid(_popup_selection_wrap):
		_popup_selection_wrap.visible = linked_sel
	if is_instance_valid(_popup_paint_wrap):
		_popup_paint_wrap.visible = not linked_sel
	_refit_popup()


func _refit_popup() -> void:
	if _brush_popup and _brush_popup.visible:
		_brush_popup.reset_size.call_deferred()


func _sync_ui() -> void:
	if _syncing:
		return
	_syncing = true
	for c in _syncers:
		if c.is_valid():
			c.call()
	_syncing = false
	_refresh_swatch_highlight()

#endregion Helpers


#region Brush popup / shortcuts
# ---------------------------------------------------------------- 
# Brush popup / shortcuts
# ---------------------------------------------------------------- 

func adjust_brush_size(delta: float) -> void:
	state.radius = clampf(state.radius + delta, 2.0, 1000.0)
	_sync_ui()
	state.emit_changed()


func toggle_paint_tool(op := -1) -> void:
	_cancel_eyedrop()
	var active := state.tool_enabled and state.tool_mode == VSState.ToolMode.PAINT
	if active and (op < 0 or state.operation == op):
		state.tool_enabled = false
	else:
		state.tool_enabled = true
		state.tool_mode = VSState.ToolMode.PAINT
		if op >= 0:
			state.operation = op
	_refresh_tool_buttons()
	state.emit_changed()


func _on_color_picker_pressed() -> void:
	if state.tool_enabled and (state.tool_mode == VSState.ToolMode.SELECT \
			or (state.tool_mode == VSState.ToolMode.PAINT and state.operation == VSState.Op.ERASE)):
		state.tool_enabled = true
		state.tool_mode = VSState.ToolMode.PAINT
		state.operation = VSState.Op.REPLACE
		_refresh_tool_buttons()
		_refresh_select_hint()
		state.emit_changed()


func toggle_select_tool(stype: int) -> void:
	_cancel_eyedrop()
	if state.tool_enabled and state.tool_mode == VSState.ToolMode.SELECT and state.select_type == stype:
		state.tool_enabled = false
	else:
		state.tool_enabled = true
		state.tool_mode = VSState.ToolMode.SELECT
		state.select_type = stype
	_refresh_tool_buttons()
	state.emit_changed()


func open_brush_popup(screen_pos: Vector2i) -> void:
	_ensure_brush_popup()
	_refresh_tool_buttons()
	_refresh_value_row()
	_refresh_select_hint()
	_sync_ui()
	_brush_popup.reset_size()
	_brush_popup.position = screen_pos
	_brush_popup.popup()
	_brush_popup.reset_size.call_deferred()


func _ensure_brush_popup() -> void:
	if _brush_popup:
		return
	_brush_popup = PopupPanel.new()
	add_child(_brush_popup)
	var margin := MarginContainer.new()
	for m in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(m, 8)
	_brush_popup.add_child(margin)
	var vb := VBoxContainer.new()
	vb.custom_minimum_size = Vector2(300, 0)
	vb.add_theme_constant_override("separation", 4)
	margin.add_child(vb)

	_build_tool_fields(vb)
	vb.add_child(HSeparator.new())
	_popup_paint_wrap = VBoxContainer.new()
	_popup_paint_wrap.add_theme_constant_override("separation", 4)
	_build_paint_fields(_popup_paint_wrap)
	vb.add_child(_popup_paint_wrap)
	_popup_selection_wrap = VBoxContainer.new()
	_popup_selection_wrap.add_theme_constant_override("separation", 4)
	_build_selection_fields(_popup_selection_wrap)
	vb.add_child(_popup_selection_wrap)


func _channel_name() -> String:
	if state.is_rgba_mode():
		return "RGBA channels"
	var names: PackedStringArray = []
	if state.channel_r:
		names.append("R")
	if state.channel_g:
		names.append("G")
	if state.channel_b:
		names.append("B")
	if state.channel_a:
		names.append("A")
	if names.size() == 1:
		return "%s channel" % names[0]
	return "%s channels" % ", ".join(names)


#endregion Brush popup / shortcuts


#region Public refresh
# ---------------------------------------------------------------- 
# Public refresh
# ---------------------------------------------------------------- 

func refresh() -> void:
	_sync_ui()


func set_selection_active(active: bool) -> void:
	for b in _fill_btns:
		if is_instance_valid(b):
			b.tooltip_text = "Fill Selection" if active else "Fill All"
	for b in _erase_btns:
		if is_instance_valid(b):
			b.tooltip_text = "Erase from Selection" if active else "Erase All"
	_refresh_fill_normal_labels(active)
	_vgroup_has_selection = active
	_refresh_vgroup_buttons()


func set_vertex_groups(names: PackedStringArray, active: String) -> void:
	if _vgroup_list == null:
		return
	_vgroup_active = active
	_vgroup_list_updating = true
	_vgroup_list.clear()
	for n in names:
		var i := _vgroup_list.add_item(n)
		_vgroup_list.set_item_tooltip(i, n + " (Double-click to load)")
		if n == active:
			_vgroup_list.select(i)
	_vgroup_list_updating = false
	_refresh_vgroup_buttons()


func _refresh_fill_normal_labels(active: bool) -> void:
	var scope := "Selection" if active else "All"
	var pro := VSPro.locked(VSPro.Feature.PAINT_NORMALS)
	if is_instance_valid(_fill_smooth_btn):
		_fill_smooth_btn.text = "Fill %s Smooth" % scope
		var tip := "Make %s edges smooth." % ("the selected" if active else "all")
		_fill_smooth_btn.tooltip_text = ("PRO VERSION: " + tip) if pro else tip
	if is_instance_valid(_fill_hard_btn):
		_fill_hard_btn.text = "Fill %s Hard" % scope
		var tip := "Make %s edges hard/faceted." % ("the selected" if active else "all")
		_fill_hard_btn.tooltip_text = ("PRO VERSION: " + tip) if pro else tip


func set_target_info(mesh_count: int, vert_count: int, selected_count: int = 0) -> void:
	if _targets_label == null:
		return
	if mesh_count == 0:
		_targets_label.text = "No paintable mesh selected"
	else:
		var txt := "%d mesh%s, %d verts" % [
			mesh_count, "" if mesh_count == 1 else "es", vert_count]
		if selected_count > 0:
			txt += "  (%d selected)" % selected_count
		_targets_label.text = txt


func set_snapshot_path(path: String) -> void:
	state.snapshot_path = path
	_select_snapshot_in_list(path)


func set_snapshot_history(paths: PackedStringArray, current: String) -> void:
	if _snapshot_list == null:
		return
	_snapshot_list_updating = true
	_snapshot_list.clear()
	for p in paths:
		var i := _snapshot_list.add_item(p.get_file())
		_snapshot_list.set_item_metadata(i, p)
		if FileAccess.file_exists(p):
			_snapshot_list.set_item_tooltip(i, p + " (Double-click to load)")
		else:
			_snapshot_list.set_item_tooltip(i, p + "\n(file missing)")
			_snapshot_list.set_item_custom_fg_color(i, Color(1.0, 0.5, 0.5))
		if p == current:
			_snapshot_list.select(i)
	_snapshot_list_updating = false


func _select_snapshot_in_list(path: String) -> void:
	if _snapshot_list == null:
		return
	_snapshot_list_updating = true
	_snapshot_list.deselect_all()
	for i in _snapshot_list.item_count:
		if str(_snapshot_list.get_item_metadata(i)) == path:
			_snapshot_list.select(i)
			break
	_snapshot_list_updating = false


func set_undo_redo_enabled(can_undo: bool, can_redo: bool) -> void:
	if _undo_btn:
		_undo_btn.disabled = not can_undo
	if _redo_btn:
		_redo_btn.disabled = not can_redo


func clear_eyedrop() -> void:
	for b in _eyedrop_btns:
		if is_instance_valid(b):
			b.button_pressed = false


func _cancel_eyedrop() -> void:
	var was_armed := false
	for b in _eyedrop_btns:
		if is_instance_valid(b) and b.button_pressed:
			was_armed = true
			b.button_pressed = false
	if was_armed:
		eyedrop_cancelled.emit()


func set_color(c: Color) -> void:
	state.color = c
	_sync_ui()


func set_replace_color(dest: StringName, c: Color) -> void:
	if dest == &"replace_target":
		state.replace_target = c
		if _replace_target_btn:
			_replace_target_btn.color = c
	elif dest == &"replace_new":
		state.replace_new = c
		if _replace_new_btn:
			_replace_new_btn.color = c


#endregion Public refresh


#region Pro gating

func _pro_icon_button(icon_name: String, tip: String, toggle: bool, feature: int, cb: Callable) -> Button:
	if VSPro.locked(feature):
		var b := _icon_button(icon_name, tip + " (PRO VERSION)", false, func(): _show_pro_alert())
		_gold_icon(b)
		return b
	return _icon_button(icon_name, tip, toggle, cb)


func _gold_icon(b: Button) -> void:
	b.set_meta("vs_icon_gold", true)
	var gold := Color(1.0, 0.78, 0.28)
	for c in ["icon_normal_color", "icon_hover_color", "icon_pressed_color",
			"icon_focus_color", "icon_hover_pressed_color", "icon_disabled_color"]:
		b.add_theme_color_override(c, gold)
	for c in ["font_color", "font_hover_color", "font_pressed_color",
			"font_focus_color", "font_hover_pressed_color", "font_disabled_color"]:
		b.add_theme_color_override(c, gold)
	if _is_light_theme():
		b.add_theme_stylebox_override("normal", _pro_dark_stylebox(0.18))
		b.add_theme_stylebox_override("hover", _pro_dark_stylebox(0.26))
		b.add_theme_stylebox_override("pressed", _pro_dark_stylebox(0.15))
		b.add_theme_stylebox_override("disabled", _pro_dark_stylebox(0.18))
	else:
		for s in ["normal", "hover", "pressed", "disabled"]:
			b.remove_theme_stylebox_override(s)


func _is_light_theme() -> bool:
	return _theme_text_color().get_luminance() < 0.5


func _pro_dark_stylebox(shade: float) -> StyleBox:
	var t := EditorInterface.get_editor_theme()
	if t and t.has_stylebox("normal", "Button"):
		var sb := t.get_stylebox("normal", "Button").duplicate()
		if sb is StyleBoxFlat:
			var f := sb as StyleBoxFlat
			f.bg_color = Color(shade, shade, shade)
			f.border_color = Color(shade * 0.6, shade * 0.6, shade * 0.6)
			return f
		return sb
	var flat := StyleBoxFlat.new()
	flat.bg_color = Color(shade, shade, shade)
	flat.set_corner_radius_all(int(round(3 * _ui_scale)))
	var pad := int(round(4 * _ui_scale))
	flat.content_margin_left = pad
	flat.content_margin_right = pad
	flat.content_margin_top = pad
	flat.content_margin_bottom = pad
	return flat


func _show_pro_alert() -> void:
	if _pro_dialog == null:
		_pro_dialog = AcceptDialog.new()
		_pro_dialog.title = "Vertex Studio Pro"
		var store_btn := _pro_dialog.add_button("Get Vertex Studio Pro", true)
		store_btn.pressed.connect(func(): OS.shell_open(VSPro.STORE_URL))
		add_child(_pro_dialog)
	_pro_dialog.dialog_text = VSPro.ALERT
	_pro_dialog.popup_centered()


#endregion Pro gating


#region Source Mesh
# ----------------------------------------------------------------
# Source Mesh
# ----------------------------------------------------------------

func _build_source_mesh(root: VBoxContainer) -> void:
	var body := _section(root, "Source Mesh", false, false)
	var btn := _pro_wide_button("Re-sync UVs", VSPro.Feature.RESYNC_UVS,
		func(): action_requested.emit(&"resync_uvs"))
	btn.tooltip_text = (
		"Re-imports the source model and replaces this mesh's UVs (and tangents) with the source's.\n"
		+ "Needs the source topology (vertex count) unchanged; surfaces whose count changed are skipped.")
	body.add_child(btn)

#endregion Source Mesh