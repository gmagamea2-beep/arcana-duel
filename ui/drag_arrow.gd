extends Control
## 공격·대상 지정 카드를 끌 때 보이는 화살표.

var from_pos := Vector2.ZERO
var to_pos := Vector2.ZERO
var color := Color("#f43f5e")
var active := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func show_arrow(a: Vector2, b: Vector2, col: Color) -> void:
	from_pos = a
	to_pos = b
	color = col
	active = true
	queue_redraw()


func hide_arrow() -> void:
	active = false
	queue_redraw()


func _draw() -> void:
	if not active:
		return
	var a := from_pos - global_position
	var b := to_pos - global_position
	var d := b - a
	if d.length() < 10.0:
		return
	var dir := d.normalized()
	var n := Vector2(-dir.y, dir.x)
	# 점선 몸통
	var step := 26.0
	var dist := 0.0
	var total := d.length() - 34.0
	while dist < total:
		var p1 := a + dir * dist
		var p2 := a + dir * minf(dist + 16.0, total)
		draw_line(p1, p2, Color(0, 0, 0, 0.6), 14.0)
		draw_line(p1, p2, color, 9.0)
		dist += step
	# 화살촉
	var tip := b
	var base := b - dir * 40.0
	var pts := PackedVector2Array([tip, base + n * 24.0, base - n * 24.0])
	draw_colored_polygon(pts, Color(0, 0, 0, 0.6))
	draw_colored_polygon(PackedVector2Array([tip - dir * 4.0, base + n * 19.0 + dir * 2.0, base - n * 19.0 + dir * 2.0]), color)
	draw_circle(b, 8.0, Color.WHITE)
