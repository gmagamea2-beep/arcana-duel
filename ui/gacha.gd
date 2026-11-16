extends Control
## 영웅 뽑기 화면. 마석 100으로 아직 없는 영웅 1명을 뽑는다 (중복 없음).
## 연출: 카드 흔들림 → 희귀도 색 빛 → 뒤집기 → 조각이 터지며 등장.

signal closed

const Art = preload("res://ui/art.gd")
const CardDB = preload("res://core/card_db.gd")
const HeroCard = preload("res://ui/hero_card.gd")
const Profile = preload("res://ui/profile.gd")

const STAGE := Vector2(300, 400)

## 테스트용: 연출을 빠르게
var fast := false
var busy := false
var rng := RandomNumberGenerator.new()
var last_pulled := ""

var stage: Control
var stage_card: HeroCard
var crystal_label: Label
var msg_label: Label
var pull_btn: Button
var close_btn: Button
var collection: HBoxContainer
## 카드 뒤 (빛줄기) / 카드 앞 (조각)
var fx_back: Control
var fx: Control


class Rays extends Control:
	var col := Color.WHITE
	var t := 0.0

	func _process(d: float) -> void:
		t += d
		queue_redraw()

	func _draw() -> void:
		var c := size / 2.0
		var r := maxf(size.x, size.y) * 0.75
		for i in 18:
			var a0 := t * 0.7 + i * TAU / 18.0
			var pts := PackedVector2Array([c, c + Vector2(cos(a0 - 0.07), sin(a0 - 0.07)) * r, c + Vector2(cos(a0 + 0.07), sin(a0 + 0.07)) * r])
			var cc := col
			cc.a = 0.28
			draw_colored_polygon(pts, cc)
		var glow := col
		glow.a = 0.25
		draw_circle(c, r * 0.35, glow)


func _ready() -> void:
	rng.randomize()
	CardDB.load_all()
	_build()
	_refresh()


func _label(text: String, fsize: int, color: Color, use_bold: bool = false) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", int(round(fsize * Art.ts())))
	l.add_theme_color_override("font_color", color)
	if use_bold:
		l.add_theme_font_override("font", Art.bold())
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _build() -> void:
	var bg := ColorRect.new()
	bg.color = Color("#0e0c18")
	add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	center.add_child(v)
	v.add_child(_label("영웅 뽑기", 64, Art.COL_TEXT, true))

	var cr := HBoxContainer.new()
	cr.alignment = BoxContainer.ALIGNMENT_CENTER
	cr.add_theme_constant_override("separation", 10)
	v.add_child(cr)
	var ci := TextureRect.new()
	ci.texture = Art.icon("floating-crystal")
	ci.custom_minimum_size = Vector2(44, 44)
	ci.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ci.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	ci.modulate = Color("#67e8f9")
	cr.add_child(ci)
	crystal_label = _label("", 34, Color("#a5f3fc"), true)
	cr.add_child(crystal_label)

	var w: Dictionary = CardDB.gacha.get("weights", {})
	var rw: Array = CardDB.gacha.get("win_reward", [30, 50])
	v.add_child(_label("1회 마석 %d · 레어 %d%% · 에픽 %d%% · 레전더리 %d%% · 이미 가진 영웅은 나오지 않아요\nAI 대전에서 이기면 마석을 얻어요 (쉬움 +%d, 보통 +%d)" % [
		Profile.pull_cost(), int(w.get("rare", 0)), int(w.get("epic", 0)), int(w.get("legendary", 0)), int(rw[0]), int(rw[1])], 19, Art.COL_SUB))

	stage = Control.new()
	stage.custom_minimum_size = Vector2(760, STAGE.y + 40)
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(stage)
	stage_card = HeroCard.new().setup(CardDB.hero_order[0], STAGE)
	stage_card.back = true
	stage_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fx_back = Control.new()
	fx_back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(fx_back)
	fx_back.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stage.add_child(stage_card)
	stage_card.position = Vector2((stage.custom_minimum_size.x - STAGE.x) / 2.0, 20)
	fx = Control.new()
	fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(fx)
	fx.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	msg_label = _label("카드를 뽑아 새 영웅을 만나 보세요!", 28, Art.COL_TEXT, true)
	msg_label.custom_minimum_size = Vector2(0, 44)
	v.add_child(msg_label)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 20)
	v.add_child(row)
	pull_btn = Button.new()
	pull_btn.custom_minimum_size = Vector2(320, 76)
	pull_btn.add_theme_font_size_override("font_size", 30)
	Art.accent_button(pull_btn, Color("#7c3aed"))
	pull_btn.pressed.connect(_on_pull)
	row.add_child(pull_btn)
	close_btn = Button.new()
	close_btn.text = "닫기"
	close_btn.custom_minimum_size = Vector2(200, 76)
	close_btn.add_theme_font_size_override("font_size", 28)
	close_btn.pressed.connect(func():
		if not busy:
			closed.emit())
	row.add_child(close_btn)

	v.add_child(_label("영웅 도감", 22, Art.COL_SUB, true))
	collection = HBoxContainer.new()
	collection.alignment = BoxContainer.ALIGNMENT_CENTER
	collection.add_theme_constant_override("separation", 8)
	v.add_child(collection)


func _refresh() -> void:
	crystal_label.text = "마석 %d" % Profile.crystals()
	var err := Profile.pull_error()
	pull_btn.text = "뽑기! (마석 %d)" % Profile.pull_cost()
	pull_btn.disabled = busy or err != ""
	if err != "" and not busy and last_pulled == "":
		msg_label.text = err
	for c in collection.get_children():
		c.queue_free()
	var own := Profile.owned()
	for hid in CardDB.hero_order:
		var hc: HeroCard = HeroCard.new().setup(hid, Vector2(104, 136), not own.has(hid))
		hc.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hc.selected = hid == last_pulled
		collection.add_child(hc)


func _wait(sec: float) -> void:
	await get_tree().create_timer(0.01 if fast else sec).timeout


func _on_pull() -> void:
	if busy:
		return
	var err := Profile.pull_error()
	if err != "":
		msg_label.text = err
		return
	busy = true
	pull_btn.disabled = true
	var hid := Profile.pull(rng)
	if hid == "":
		busy = false
		_refresh()
		return
	last_pulled = hid
	var hd: Dictionary = CardDB.heroes[hid]
	var r: String = hd.get("rarity", "rare")
	var rcol := Art.rarity_color(r)
	crystal_label.text = "마석 %d" % Profile.crystals()
	msg_label.text = "두근두근..."
	msg_label.add_theme_color_override("font_color", Art.COL_TEXT)
	for c in fx.get_children():
		c.queue_free()
	for c in fx_back.get_children():
		c.queue_free()
	stage_card.back = true
	stage_card.hid = hid
	stage_card.rotation = 0.0
	stage_card.scale = Vector2.ONE
	stage_card.glow_color = Color(1, 1, 1, 0)

	# 1) 흔들림 + 빛이 차오름 (희귀도가 높을수록 오래, 강하게)
	var steps: int = {"rare": 4, "epic": 6, "legendary": 9}.get(r, 4)
	var tw := stage_card.create_tween()
	for i in steps:
		var amp := 0.03 + 0.012 * i
		tw.tween_property(stage_card, "rotation", amp if i % 2 == 0 else -amp, 0.01 if fast else 0.07)
	tw.tween_property(stage_card, "rotation", 0.0, 0.01 if fast else 0.06)
	var tg := stage_card.create_tween()
	tg.tween_property(stage_card, "glow_color", Color(rcol.r, rcol.g, rcol.b, 1.0), 0.01 if fast else steps * 0.07)
	await tw.finished

	# 2) 뒤로 퍼지는 빛줄기
	var rays := Rays.new()
	rays.col = rcol.lerp(Color.WHITE, 0.2)
	rays.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fx_back.add_child(rays)
	rays.size = Vector2(760, STAGE.y + 40)
	rays.pivot_offset = rays.size / 2.0
	rays.scale = Vector2(0.2, 0.2)
	rays.create_tween().tween_property(rays, "scale", Vector2.ONE, 0.01 if fast else 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	# 3) 뒤집기
	var tf := stage_card.create_tween()
	tf.tween_property(stage_card, "scale:x", 0.0, 0.01 if fast else 0.16)
	await tf.finished
	stage_card.back = false
	stage_card.selected = true
	var tf2 := stage_card.create_tween()
	tf2.tween_property(stage_card, "scale", Vector2(1.08, 1.08), 0.01 if fast else 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tf2.tween_property(stage_card, "scale", Vector2.ONE, 0.01 if fast else 0.15)

	# 4) 조각이 터짐 + 레전더리는 화면 번쩍
	_burst(rcol, 22 if r == "rare" else (32 if r == "epic" else 48))
	if r == "legendary":
		var flash := ColorRect.new()
		flash.color = Color(1, 0.95, 0.8, 0.75)
		flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(flash)
		flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		var tfl := flash.create_tween()
		tfl.tween_property(flash, "color:a", 0.0, 0.01 if fast else 0.6)
		tfl.tween_callback(flash.queue_free)

	msg_label.text = "새 영웅 획득!  [%s] %s · %s" % [HeroCard.RARITY_LABEL.get(r, ""), hd["name"], hd["title"]]
	msg_label.add_theme_color_override("font_color", rcol.lerp(Color.WHITE, 0.3))
	await _wait(0.5)
	busy = false
	_refresh()


func _burst(col: Color, n: int) -> void:
	var c := stage_card.position + STAGE / 2.0
	for i in n:
		var p := ColorRect.new()
		var s := rng.randf_range(8.0, 18.0)
		p.size = Vector2(s, s)
		p.pivot_offset = p.size / 2.0
		p.rotation = PI / 4.0
		p.color = col.lerp(Color.WHITE, rng.randf_range(0.0, 0.6))
		p.mouse_filter = Control.MOUSE_FILTER_IGNORE
		fx.add_child(p)
		p.position = c - p.size / 2.0
		var ang := rng.randf() * TAU
		var dist := rng.randf_range(180.0, 380.0)
		var t := p.create_tween()
		t.set_parallel(true)
		t.tween_property(p, "position", p.position + Vector2(cos(ang), sin(ang)) * dist, 0.01 if fast else rng.randf_range(0.6, 1.0)).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		t.tween_property(p, "modulate:a", 0.0, 0.01 if fast else 0.9).set_delay(0.0 if fast else 0.3)
		t.chain().tween_callback(p.queue_free)
