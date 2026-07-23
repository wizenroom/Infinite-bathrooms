@tool
extends Control
class_name VSCurveEdit

## Tiny embedded curve editor.
## Left-drag handles to move, left-click empty space to add a point,
## right-click a handle to remove it.

signal curve_changed
signal clicked

var curve: Curve
var editable := true
var _dragging := -1
const _HANDLE := 5.0


func _init() -> void:
	custom_minimum_size = Vector2(0, 64)
	mouse_filter = Control.MOUSE_FILTER_STOP


func set_curve(c: Curve) -> void:
	curve = c
	queue_redraw()


func _to_px(p: Vector2) -> Vector2:
	return Vector2(p.x * size.x, (1.0 - p.y) * size.y)


func _to_curve(px: Vector2) -> Vector2:
	return Vector2(
		clampf(px.x / maxf(size.x, 1.0), 0.0, 1.0),
		clampf(1.0 - px.y / maxf(size.y, 1.0), 0.0, 1.0))


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.12, 0.12, 0.14, 1.0), true)
	var grid := Color(1, 1, 1, 0.06)
	for i in range(1, 4):
		var x := size.x * i / 4.0
		var y := size.y * i / 4.0
		draw_line(Vector2(x, 0), Vector2(x, size.y), grid)
		draw_line(Vector2(0, y), Vector2(size.x, y), grid)
	if curve == null:
		return
	var pts := PackedVector2Array()
	var steps := 48
	for i in steps + 1:
		var t := float(i) / steps
		pts.append(Vector2(t * size.x, (1.0 - clampf(curve.sample_baked(t), 0.0, 1.0)) * size.y))
	draw_polyline(pts, Color(0.4, 0.8, 1.0, 0.95), 1.5, true)
	for i in curve.point_count:
		var p := _to_px(curve.get_point_position(i))
		draw_circle(p, _HANDLE, Color(1, 1, 1, 0.95))
		draw_circle(p, _HANDLE - 2.0, Color(0.2, 0.5, 0.9, 1.0))


func _gui_input(event: InputEvent) -> void:
	if curve == null:
		return
	if not editable:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			clicked.emit()
		return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			var hit := _handle_at(event.position)
			if hit >= 0:
				_dragging = hit
			else:
				var cp := _to_curve(event.position)
				curve.add_point(cp)
				_emit()
		elif event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
			_dragging = -1
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			var hit := _handle_at(event.position)
			if hit >= 0 and curve.point_count > 2:
				curve.remove_point(hit)
				_emit()
	elif event is InputEventMouseMotion and _dragging >= 0:
		var cp := _to_curve(event.position)
		if _dragging == 0:
			cp.x = 0.0
		elif _dragging == curve.point_count - 1:
			cp.x = 1.0
		curve.set_point_offset(_dragging, cp.x)
		curve.set_point_value(_dragging, cp.y)
		_emit()


func _handle_at(px: Vector2) -> int:
	for i in curve.point_count:
		if _to_px(curve.get_point_position(i)).distance_to(px) <= _HANDLE + 3.0:
			return i
	return -1


func _emit() -> void:
	queue_redraw()
	curve_changed.emit()
