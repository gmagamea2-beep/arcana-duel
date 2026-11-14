extends RefCounted
## 색상, 폰트, 아이콘(SVG → 텍스처) 공용 도우미.

const RARITY_COLORS := {
	"basic": Color("#8b919a"),
	"token": Color("#6b7280"),
	"common": Color("#a8b0ba"),
	"rare": Color("#3b82f6"),
	"epic": Color("#a855f7"),
	"legendary": Color("#f59e0b"),
	"mythic": Color("#14b8a6"),
	"ultimate": Color("#ef4444"),
}
const FACTION_COLORS := {
	"fire": Color("#5a2219"),
	"steel": Color("#22344d"),
	"shadow": Color("#2f2346"),
	"forest": Color("#1f4229"),
	"neutral": Color("#3a3630"),
	"starter": Color("#2e3138"),
}
const FACTION_ACCENT := {
	"fire": Color("#f97316"),
	"steel": Color("#93c5fd"),
	"shadow": Color("#c084fc"),
	"forest": Color("#4ade80"),
	"neutral": Color("#d6d3d1"),
	"starter": Color("#9ca3af"),
}
const COL_BG := Color("#12141a")
const COL_PANEL := Color("#1c1f27")
const COL_PANEL_2 := Color("#262a35")
const COL_TEXT := Color("#eef0f4")
const COL_SUB := Color("#b9bfcb")
const COL_MANA := Color("#2563eb")
const COL_GOLD := Color("#f5b301")
const COL_ATK := Color("#eab308")
const COL_HP := Color("#dc2626")
const COL_ARMOR := Color("#94a3b8")
const COL_OK := Color("#22c55e")
const COL_SEL := Color("#facc15")
const COL_TARGET := Color("#f43f5e")

static var _icons := {}
static var _tex := {}
static var _font_r: Font = null
static var _font_b: Font = null
## 글자 크기 배율 (설정: 보통 1.0 / 크게 1.15 / 아주 크게 1.3)
static var text_scale := -1.0


static func ts() -> float:
	if text_scale < 0.0:
		text_scale = float(preload("res://ui/settings.gd").get_value("text_scale", 1.0))
	return text_scale


static func font() -> Font:
	if _font_r == null:
		_font_r = load("res://assets/fonts/Pretendard-Regular.otf")
	return _font_r


static func bold() -> Font:
	if _font_b == null:
		_font_b = load("res://assets/fonts/Pretendard-Bold.otf")
	return _font_b


static func icon(name: String) -> Texture2D:
	if _tex.has(name):
		return _tex[name]
	if _icons.is_empty():
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/icons.json"))
		if data is Dictionary:
			_icons = data.get("icons", {})
	var svg: String = _icons.get(name, "")
	if svg == "":
		_tex[name] = null
		return null
	var img := Image.new()
	if img.load_svg_from_string(svg, 0.375) != OK:
		_tex[name] = null
		return null
	var t := ImageTexture.create_from_image(img)
	_tex[name] = t
	return t


static func rarity_color(r: String) -> Color:
	return RARITY_COLORS.get(r, Color.GRAY)


static func faction_color(f: String) -> Color:
	return FACTION_COLORS.get(f, Color("#333333"))


## 사각형 안에 텍스트를 세로 가운데로 그린다.
static func draw_text(ci: CanvasItem, text: String, rect: Rect2, size: int, color: Color,
		align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_CENTER, use_bold: bool = false, outline: int = 0) -> void:
	var f := bold() if use_bold else font()
	var s := int(round(size * ts()))
	# 칸을 넘지 않을 때까지 줄인다 (높이와 너비 모두)
	while s > 8 and (f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, s).x > rect.size.x or f.get_height(s) > rect.size.y + 6):
		s -= 1
	var y := rect.position.y + (rect.size.y + f.get_ascent(s) - f.get_descent(s)) / 2.0
	if outline > 0:
		ci.draw_string_outline(f, Vector2(rect.position.x, y), text, align, rect.size.x, s, outline, Color(0, 0, 0, 0.85))
	ci.draw_string(f, Vector2(rect.position.x, y), text, align, rect.size.x, s, color)


static func draw_multiline(ci: CanvasItem, text: String, rect: Rect2, size: int, color: Color) -> void:
	var f := font()
	var s := int(round(size * ts()))
	# 칸에 들어갈 때까지 글자 크기를 줄인다
	while s > 10:
		var h := f.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, s).y
		if h <= rect.size.y:
			break
		s -= 1
	var total := f.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, s).y
	var y := rect.position.y + maxf(0.0, (rect.size.y - total) / 2.0) + f.get_ascent(s)
	ci.draw_multiline_string(f, Vector2(rect.position.x, y), text, HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, s, -1, color)


static func draw_badge(ci: CanvasItem, center: Vector2, radius: float, fill: Color, text: String,
		text_color: Color = Color.WHITE) -> void:
	ci.draw_circle(center, radius + 2.0, Color(0, 0, 0, 0.6))
	ci.draw_circle(center, radius, fill)
	draw_text(ci, text, Rect2(center - Vector2(radius, radius), Vector2(radius * 2, radius * 2)),
		int(radius * 1.3), text_color, HORIZONTAL_ALIGNMENT_CENTER, true)


static func panel_style(bg: Color, border: Color = Color(0, 0, 0, 0), border_w: int = 0, radius: int = 10) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(border_w)
	sb.set_corner_radius_all(radius)
	return sb


static func make_theme() -> Theme:
	var t := Theme.new()
	t.default_font = font()
	t.default_font_size = int(round(24 * ts()))
	var normal := panel_style(Color("#2b3140"), Color("#46506a"), 2, 10)
	normal.content_margin_left = 16
	normal.content_margin_right = 16
	normal.content_margin_top = 8
	normal.content_margin_bottom = 8
	var hover: StyleBoxFlat = normal.duplicate()
	hover.bg_color = Color("#36405a")
	var pressed: StyleBoxFlat = normal.duplicate()
	pressed.bg_color = Color("#3d4a68")
	pressed.border_color = Color("#facc15")
	pressed.set_border_width_all(3)
	var disabled: StyleBoxFlat = normal.duplicate()
	disabled.bg_color = Color("#22262f")
	disabled.border_color = Color("#2e333f")
	t.set_stylebox("normal", "Button", normal)
	t.set_stylebox("hover", "Button", hover)
	t.set_stylebox("pressed", "Button", pressed)
	t.set_stylebox("hover_pressed", "Button", pressed)
	t.set_color("font_pressed_color", "Button", Color("#fde68a"))
	t.set_stylebox("disabled", "Button", disabled)
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_color("font_color", "Button", COL_TEXT)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_disabled_color", "Button", Color("#6b7280"))
	t.set_color("font_color", "Label", COL_TEXT)
	t.set_stylebox("panel", "PanelContainer", panel_style(COL_PANEL, Color("#2c313d"), 2, 12))
	t.set_stylebox("panel", "Panel", panel_style(COL_PANEL, Color("#2c313d"), 2, 12))
	t.set_color("default_color", "RichTextLabel", COL_TEXT)
	t.set_font("bold_font", "RichTextLabel", bold())
	return t


static func accent_button(b: Button, col: Color) -> void:
	var sb := panel_style(col.darkened(0.25), col, 2, 10)
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	var h: StyleBoxFlat = sb.duplicate()
	h.bg_color = col.darkened(0.1)
	b.add_theme_stylebox_override("normal", sb)
	b.add_theme_stylebox_override("hover", h)
	b.add_theme_stylebox_override("pressed", sb)
	b.add_theme_font_override("font", bold())
