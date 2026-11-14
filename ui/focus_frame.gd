extends Control
## 튜토리얼에서 "여기를 누르세요"를 알려 주는 깜빡이는 노란 테두리 + 화살표.

var target_rect := Rect2()
var _t := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func set_target(r: Rect2) -> void:
	if r != target_rect:
		target_rect = r
		queue_redraw()


func _process(delta: float) -> void:
	_t += delta
	if target_rect.size != Vector2.ZERO:
		queue_redraw()


func _draw() -> void:
	if target_rect.size == Vector2.ZERO:
		return
	var r := Rect2(target_rect.position - global_position, target_rect.size).grow(10 + 4 * sin(_t * 5.0))
	var a := 0.55 + 0.45 * sin(_t * 5.0)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1, 0.85, 0.1, 0.08)
	sb.border_color = Color(1, 0.85, 0.1, a)
	sb.set_border_width_all(6)
	sb.set_corner_radius_all(14)
	draw_style_box(sb, r)
	# 위쪽(공간이 없으면 아래쪽)에 화살표
	var bob := 8.0 * sin(_t * 5.0)
	var cx := r.position.x + r.size.x / 2.0
	var col := Color(1, 0.85, 0.1, 0.95)
	if r.position.y > 70:
		var tip := Vector2(cx, r.position.y - 6 + bob)
		draw_colored_polygon(PackedVector2Array([tip, tip + Vector2(-22, -34), tip + Vector2(22, -34)]), col)
	else:
		var tip2 := Vector2(cx, r.end.y + 6 - bob)
		draw_colored_polygon(PackedVector2Array([tip2, tip2 + Vector2(-22, 34), tip2 + Vector2(22, 34)]), col)
