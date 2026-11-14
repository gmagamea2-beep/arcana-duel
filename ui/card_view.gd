extends Control
## 카드 한 장을 직접 그리는 컨트롤.
## mode: "hand"(세로 카드), "detail"(큰 세로 카드), "board"(필드 위 유닛), "market"(시장 가로줄),
##       "trap_back"(상대 함정 뒷면), "trap_own"(내 함정), "field"(공용 필드), "back"(카드 뒷면)
## 누르면 pressed, draggable 이면 끌기 시작/이동/놓기 신호를 보낸다.

signal pressed(view: Control)
signal drag_started(view: Control, pos: Vector2)
signal drag_moved(view: Control, pos: Vector2)
signal drag_ended(view: Control, pos: Vector2)

const Art = preload("res://ui/art.gd")
const CardDB = preload("res://core/card_db.gd")
const DRAG_THRESHOLD := 14.0

const SIZES := {
	"hand": Vector2(190, 266),
	"detail": Vector2(220, 308),
	"board": Vector2(150, 180),
	"field": Vector2(230, 110),
	"market": Vector2(300, 92),
	"trap_back": Vector2(70, 92),
	"trap_own": Vector2(70, 92),
	"back": Vector2(190, 266),
}

var data: Dictionary = {}
var inst = null
var mode := "hand"
## "", "ok"(사용/공격 가능), "sel"(선택됨), "target"(대상 가능), "mark"(교체 표시)
var highlight := ""
var price := -1
var dim := false
var caption := ""
var meta_info: Dictionary = {}
var draggable := false
var _t := 0.0
var _pressing := false
var _dragging := false
var _press_pos := Vector2.ZERO


func setup(p_data: Dictionary, p_inst = null, p_mode: String = "hand"):
	data = p_data
	inst = p_inst
	mode = p_mode
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = SIZES.get(mode, Vector2(190, 266))
	size = custom_minimum_size
	pivot_offset = size / 2.0
	set_process(data.get("rarity", "") == "ultimate" or highlight != "")
	return self


func set_mode(m: String) -> void:
	mode = m
	queue_redraw()


func set_highlight(h: String) -> void:
	highlight = h
	set_process(h != "" or data.get("rarity", "") == "ultimate")
	queue_redraw()


func _gui_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
		if ev.pressed:
			_pressing = true
			_dragging = false
			_press_pos = ev.global_position
		else:
			if _dragging:
				drag_ended.emit(self, ev.global_position)
			elif _pressing:
				pressed.emit(self)
			_pressing = false
			_dragging = false
		accept_event()
	elif ev is InputEventMouseMotion and _pressing:
		if not _dragging and draggable and ev.global_position.distance_to(_press_pos) > DRAG_THRESHOLD:
			_dragging = true
			drag_started.emit(self, _press_pos)
		if _dragging:
			drag_moved.emit(self, ev.global_position)
		accept_event()


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _draw() -> void:
	match mode:
		"hand", "detail":
			_draw_portrait()
		"board":
			_draw_board()
		"field":
			_draw_field()
		"market":
			_draw_market()
		"trap_back":
			_draw_trap(false)
		"trap_own":
			_draw_trap(true)
		"back":
			_draw_back()


# ── 공통 ──

func _rarity() -> String:
	return data.get("rarity", "common")


func _border_color() -> Color:
	if _rarity() == "ultimate":
		return Color.from_hsv(fmod(_t * 0.25, 1.0), 0.75, 1.0)
	return Art.rarity_color(_rarity())


func _draw_glow(rect: Rect2, radius: int) -> void:
	if highlight == "":
		return
	var col := Art.COL_OK
	match highlight:
		"sel":
			col = Art.COL_SEL
		"target":
			col = Art.COL_TARGET
		"mark":
			col = Art.COL_TARGET
	var pulse := 0.65 + 0.35 * sin(_t * 6.0)
	col.a = pulse
	var sb := Art.panel_style(Color(0, 0, 0, 0), col, 5, radius + 4)
	draw_style_box(sb, rect.grow(6))


func _frame(rect: Rect2, border_w: int, radius: int, border_col: Color = Color(0, 0, 0, 0)) -> void:
	var bc := border_col if border_col.a > 0 else _border_color()
	var sb := Art.panel_style(Art.faction_color(data.get("faction", "neutral")), bc, border_w, radius)
	draw_style_box(sb, rect)


func _draw_icon(rect: Rect2, alpha: float = 1.0) -> void:
	var tex := Art.icon(data.get("icon", ""))
	if tex == null:
		return
	var s := minf(rect.size.x, rect.size.y)
	var r := Rect2(rect.position + (rect.size - Vector2(s, s)) / 2.0, Vector2(s, s))
	var col: Color = Art.FACTION_ACCENT.get(data.get("faction", "neutral"), Color.WHITE)
	col = col.lerp(Color.WHITE, 0.35)
	col.a = alpha
	draw_texture_rect(tex, r, false, col)


func _cur_attack() -> int:
	return inst.attack if inst != null else int(data.get("attack", 0))


func _cur_health() -> int:
	return inst.health if inst != null else int(data.get("health", 0))


func _health_color() -> Color:
	if inst == null:
		return Color.WHITE
	if inst.health < inst.max_health:
		return Color("#fecaca")
	if inst.max_health > int(data.get("health", 0)):
		return Color("#bbf7d0")
	return Color.WHITE


func _attack_color() -> Color:
	if inst != null and inst.attack > int(data.get("attack", 0)):
		return Color("#14532d")
	return Color.BLACK


## 키워드 + 효과 문구
func rules_text() -> String:
	var parts: Array = []
	var kws: Array = inst.keywords if inst != null else data.get("keywords", [])
	var kw_names: Array = []
	for k in kws:
		kw_names.append(CardDB.KEYWORD_NAMES.get(k, k))
	if not kw_names.is_empty():
		parts.append(", ".join(PackedStringArray(kw_names)))
	var tx: String = data.get("text", "")
	if tx != "" and tx != "토큰":
		parts.append(tx)
	return "\n".join(PackedStringArray(parts))


func type_line() -> String:
	var t: String = CardDB.TYPE_NAMES.get(data.get("type", ""), "")
	var r: String = CardDB.RARITY_NAMES.get(_rarity(), "")
	var f: String = CardDB.FACTION_NAMES.get(data.get("faction", ""), "")
	return "%s · %s · %s" % [t, f, r]


# ── 세로 카드 (손패 / 상세) ──

func _draw_portrait() -> void:
	var w := size.x
	var h := size.y
	var k := w / 200.0
	var rect := Rect2(Vector2.ZERO, size)
	_draw_glow(rect, int(12 * k))
	_frame(rect, int(maxf(3.0, 5.0 * k)), int(12 * k))
	# 그림 영역
	var art_rect := Rect2(14 * k, 46 * k, w - 28 * k, 94 * k)
	draw_style_box(Art.panel_style(Color(0, 0, 0, 0.35), Color(0, 0, 0, 0), 0, int(8 * k)), art_rect)
	_draw_icon(art_rect.grow(-6 * k))
	# 이름
	var name_w := w - 52 * k - (38 * k if price >= 0 else 0.0)
	Art.draw_text(self, data.get("name", ""), Rect2(46 * k, 4 * k, name_w, 38 * k), int(23 * k), Art.COL_TEXT, HORIZONTAL_ALIGNMENT_CENTER, true, 3)
	# 비용
	Art.draw_badge(self, Vector2(24 * k, 24 * k), 20 * k, Art.COL_MANA, str(int(data.get("cost", 0))))
	# 종류 줄
	Art.draw_text(self, type_line(), Rect2(6 * k, 142 * k, w - 12 * k, 24 * k), int(15 * k), _border_color().lightened(0.3))
	# 효과 문구
	var bottom_pad := 46.0 * k if data.get("type", "") == "unit" else 10.0 * k
	Art.draw_multiline(self, rules_text(), Rect2(9 * k, 168 * k, w - 18 * k, h - 168 * k - bottom_pad), int(20 * k), Color.WHITE)
	# 공격력 / 체력
	if data.get("type", "") == "unit":
		Art.draw_badge(self, Vector2(26 * k, h - 26 * k), 22 * k, Art.COL_ATK, str(_cur_attack()), _attack_color())
		Art.draw_badge(self, Vector2(w - 26 * k, h - 26 * k), 22 * k, Art.COL_HP, str(_cur_health()), _health_color())
	# 시장 가격
	if price >= 0:
		Art.draw_badge(self, Vector2(w - 22 * k, 22 * k), 19 * k, Art.COL_GOLD, str(price), Color.BLACK)
	if caption != "":
		Art.draw_text(self, caption, Rect2(0, h - 30 * k, w, 26 * k), int(16 * k), Art.COL_SEL, HORIZONTAL_ALIGNMENT_CENTER, true)
	if highlight == "mark":
		draw_rect(rect, Color(0, 0, 0, 0.45))
		Art.draw_text(self, "교체", rect, int(40 * k), Art.COL_TARGET, HORIZONTAL_ALIGNMENT_CENTER, true)
	elif dim:
		draw_style_box(Art.panel_style(Color(0, 0, 0, 0.42), Color(0, 0, 0, 0), 0, int(12 * k)), rect)


# ── 필드 위 유닛 ──

func _draw_board() -> void:
	var w := size.x
	var h := size.y
	var k := w / 150.0
	var rect := Rect2(Vector2.ZERO, size)
	_draw_glow(rect, int(14 * k))
	var taunt: bool = inst != null and inst.has_kw("taunt")
	if taunt:
		_frame(rect, int(7 * k), int(14 * k), Color("#cbd5e1"))
	else:
		_frame(rect, int(3 * k), int(14 * k))
	_draw_icon(Rect2(26 * k, 30 * k, w - 52 * k, 78 * k), 0.95)
	Art.draw_text(self, data.get("name", ""), Rect2(6 * k, 3 * k, w - 12 * k, 28 * k), int(18 * k), Art.COL_TEXT, HORIZONTAL_ALIGNMENT_CENTER, true, 3)
	# 키워드 배지
	var tags: Array = []
	if inst != null:
		for kw in ["charge", "poison", "lifesteal"]:
			if inst.has_kw(kw):
				tags.append(CardDB.KEYWORD_NAMES[kw])
		var tx: String = data.get("text", "")
		if tx.begins_with("유언"):
			tags.append("유언")
		elif tx.begins_with("내 턴 종료"):
			tags.append("성장")
	if not tags.is_empty():
		Art.draw_text(self, " ".join(PackedStringArray(tags)), Rect2(4 * k, 108 * k, w - 8 * k, 24 * k), int(16 * k), Art.COL_SEL, HORIZONTAL_ALIGNMENT_CENTER, true, 2)
	if taunt:
		Art.draw_text(self, "도발", Rect2(0, h - 50 * k, w, 22 * k), int(16 * k), Color("#e2e8f0"), HORIZONTAL_ALIGNMENT_CENTER, true, 2)
	Art.draw_badge(self, Vector2(23 * k, h - 23 * k), 20 * k, Art.COL_ATK, str(_cur_attack()), _attack_color())
	Art.draw_badge(self, Vector2(w - 23 * k, h - 23 * k), 20 * k, Art.COL_HP, str(_cur_health()), _health_color())
	if inst != null and inst.has_kw("shield"):
		var sb := Art.panel_style(Color(1, 0.85, 0.2, 0.12), Color("#fde047"), int(3 * k), int(18 * k))
		draw_style_box(sb, rect.grow(-2))
	if inst != null and meta_info.get("show_sleep", true):
		if inst.sleeping:
			Art.draw_text(self, "묶임", Rect2(w - 50 * k, 30 * k, 44 * k, 22 * k), int(16 * k), Color("#86efac"), HORIZONTAL_ALIGNMENT_CENTER, true, 2)
		elif inst.summoned_turn and not inst.has_kw("charge"):
			Art.draw_text(self, "Zz", Rect2(w - 44 * k, 30 * k, 38 * k, 22 * k), int(18 * k), Art.COL_SUB, HORIZONTAL_ALIGNMENT_CENTER, true, 2)
	if dim:
		draw_style_box(Art.panel_style(Color(0, 0, 0, 0.35), Color(0, 0, 0, 0), 0, int(14 * k)), rect)


# ── 공용 필드 ──

func _draw_field() -> void:
	var w := size.x
	var h := size.y
	var rect := Rect2(Vector2.ZERO, size)
	_draw_glow(rect, 12)
	_frame(rect, 4, 12)
	_draw_icon(Rect2(8, 28, 58, 58))
	Art.draw_text(self, data.get("name", ""), Rect2(6, 2, w - 12, 26), 18, Art.COL_TEXT, HORIZONTAL_ALIGNMENT_CENTER, true, 2)
	Art.draw_text(self, caption, Rect2(70, 32, w - 76, 24), 17, Art.COL_SEL, HORIZONTAL_ALIGNMENT_LEFT, true)
	Art.draw_text(self, "공용 필드", Rect2(70, 58, w - 76, 22), 15, Art.COL_SUB, HORIZONTAL_ALIGNMENT_LEFT)
	Art.draw_text(self, "눌러서 보기", Rect2(0, h - 24, w, 20), 14, Art.COL_SUB)


# ── 시장 가로줄 ──

func _draw_market() -> void:
	var w := size.x
	var h := size.y
	var rect := Rect2(Vector2.ZERO, size)
	_draw_glow(rect, 10)
	_frame(rect, 3, 10)
	var icon_rect := Rect2(8, 8, h - 16, h - 16)
	draw_style_box(Art.panel_style(Color(0, 0, 0, 0.35), Color(0, 0, 0, 0), 0, 8), icon_rect)
	_draw_icon(icon_rect.grow(-6))
	Art.draw_badge(self, Vector2(19, 19), 15, Art.COL_MANA, str(int(data.get("cost", 0))))
	var x := h + 2.0
	var text_w := w - x - 66
	Art.draw_text(self, data.get("name", ""), Rect2(x, 1, text_w, 30), 23, Art.COL_TEXT, HORIZONTAL_ALIGNMENT_LEFT, true, 2)
	var stats := ""
	if data.get("type", "") == "unit":
		stats = "  %d/%d" % [int(data.get("attack", 0)), int(data.get("health", 0))]
	Art.draw_text(self, type_line() + stats, Rect2(x, 30, text_w, 20), 15, _border_color().lightened(0.3), HORIZONTAL_ALIGNMENT_LEFT)
	var rt := rules_text().replace("\n", " · ")
	if rt != "":
		var f := Art.font()
		var fs := int(round(17 * Art.ts()))
		while fs > 12 and f.get_multiline_string_size(rt, HORIZONTAL_ALIGNMENT_LEFT, text_w, fs).y > h - 52.0:
			fs -= 1
		var y := 51.0 + f.get_ascent(fs)
		draw_multiline_string(f, Vector2(x, y), rt, HORIZONTAL_ALIGNMENT_LEFT, text_w, fs, 2, Color("#dfe3ea"))
	if price >= 0:
		Art.draw_badge(self, Vector2(w - 36, h / 2.0), 26, Art.COL_GOLD, str(price), Color.BLACK)
	if dim:
		draw_style_box(Art.panel_style(Color(0, 0, 0, 0.45), Color(0, 0, 0, 0), 0, 10), rect)


# ── 함정 ──

func _draw_trap(own: bool) -> void:
	var rect := Rect2(Vector2.ZERO, size)
	var sb := Art.panel_style(Color("#3b2f52") if not own else Art.faction_color(data.get("faction", "neutral")), Color("#a78bfa"), 3, 8)
	draw_style_box(sb, rect)
	if own:
		_draw_icon(Rect2(10, 8, size.x - 20, 44), 0.9)
		Art.draw_text(self, data.get("name", ""), Rect2(2, 54, size.x - 4, 32), 14, Art.COL_TEXT, HORIZONTAL_ALIGNMENT_CENTER, true, 2)
	else:
		Art.draw_text(self, "?", rect, 44, Color("#ddd6fe"), HORIZONTAL_ALIGNMENT_CENTER, true)


# ── 카드 뒷면 ──

func _draw_back() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	var k := size.x / 190.0
	draw_style_box(Art.panel_style(Color("#2a1f4a"), Color("#f5b301"), int(maxf(2.0, 5.0 * k)), int(14 * k)), rect)
	draw_style_box(Art.panel_style(Color("#3b2a6b"), Color("#6d5bd0"), int(maxf(1.0, 2.0 * k)), int(10 * k)), rect.grow(-10 * k))
	var tex := Art.icon("crossed-swords")
	if tex != null:
		var s := minf(size.x, size.y) * 0.55
		draw_texture_rect(tex, Rect2((size - Vector2(s, s)) / 2.0, Vector2(s, s)), false, Color(1, 0.85, 0.4, 0.9))
