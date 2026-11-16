extends Control
## 대전 화면 (나 = 0번, AI = 1번).
## 조작은 탭/클릭: 카드를 누르면 오른쪽 아래에 자세히 보기 + 행동 버튼이 나온다.

signal exit_to_menu
signal restart_requested

const Art = preload("res://ui/art.gd")
const CardDB = preload("res://core/card_db.gd")
const Game = preload("res://core/game.gd")
const AI = preload("res://ai/simple_ai.gd")
const CardView = preload("res://ui/card_view.gd")
const HeroView = preload("res://ui/hero_view.gd")
const PlayerState = preload("res://core/player_state.gd")
const CardInst = preload("res://core/card_inst.gd")
const Tutorial = preload("res://ui/tutorial.gd")
const Settings = preload("res://ui/settings.gd")
const FocusFrame = preload("res://ui/focus_frame.gd")
const PileView = preload("res://ui/pile_view.gd")
const DragArrow = preload("res://ui/drag_arrow.gd")
const Profile = preload("res://ui/profile.gd")

## 나 / 상대의 플레이어 번호 (온라인에서 내가 손님이면 1 / 0)
var ME := 0
var OP := 1
const TURN_TIME := 90
const RIGHT_W := 480
const AI_DELAY := 0.7

var my_hero := "fire"
var op_hero := "steel"
var ai_level := 1
## 메뉴에서 "튜토리얼"로 시작했는지
var tutorial_mode := false
## 온라인 대전 연결 (NetMatch). null 이면 AI 대전
var net = null
var _mull_local = null
var _mull_remote = null
var _turn_deadline := 0
var link_label: Label
var tutorial: Tutorial = null

var game: Game
var ai: AI

var op_hero_view: HeroView
var me_hero_view: HeroView
var op_info: Label
var me_info: Label
var op_traps_box: HBoxContainer
var me_traps_box: HBoxContainer
var op_board: HBoxContainer
var me_board: HBoxContainer
var field_slot: HBoxContainer
var turn_label: Label
var hand_area: Control
var power_btn: Button
## 조합 스킬 버튼 (결성된 조합마다 1개)
var combo_box: GridContainer
var _combo_panel: Control = null
var end_btn: Button
var refresh_btn: Button
var market_box: VBoxContainer
var detail_holder: CenterContainer
var detail_actions: VBoxContainer
var log_label: RichTextLabel
var fx_layer: Control
var overlay: Control
var hint_label: Label
var left_area: VBoxContainer
var coach: PanelContainer
var coach_title: Label
var coach_text: Label
var coach_btn: Button
var coach_skip: Button
var focus_frame: FocusFrame
var deck_pile: PileView
var discard_pile: PileView
var hand_row: HBoxContainer
var drag_arrow: DragArrow
var drag_ghost: Control = null
var drop_zone: PanelContainer
var drop_zone_label: Label

var busy := false
var sel: Dictionary = {}
var targeting: Dictionary = {}
var mull_marks: Dictionary = {}
var _run_id := 0
var _pending_fx: Array = []
var _pos_cache: Dictionary = {}
var _hint_id := 0
var _over_shown := false
var _banner_label: Label = null
var _reveal_view: Control = null
## 자동 점검용: 대기 시간을 거의 0으로
var fast := false
var _detail_btns: Dictionary = {}
## 끌기 중인 정보 {"kind", "index", "view", "targets", "arrow"}
var _drag: Dictionary = {}
## 드로우 연출이 끝날 때까지 손패에서 숨겨 둘 카드 uid
var _anim_hidden: Dictionary = {}
## 도움말 팁 대기열 [[key, text], ...]
var _tips: Array = []


## 조합 연출: 유닛들을 잇는 빛줄기 + 퍼지는 고리 + 줄을 따라 도는 불꽃
class ComboLines extends Control:
	var pts: PackedVector2Array = PackedVector2Array()
	var col := Color.WHITE
	var t := 0.0
	var life := 1.9

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_process(true)

	func _process(d: float) -> void:
		t += d
		if t >= life:
			queue_free()
			return
		queue_redraw()

	func _draw() -> void:
		var a := minf(1.0, t / 0.15) * minf(1.0, (life - t) / 0.45)
		var glow := col
		glow.a = 0.35 * a
		var core := col.lerp(Color.WHITE, 0.6)
		core.a = a
		if pts.size() >= 2:
			draw_polyline(pts, glow, 18.0, true)
			draw_polyline(pts, core, 5.0, true)
			for i in pts.size() - 1:
				for k in 2:
					var f := fmod(t * 1.3 + k * 0.5, 1.0)
					var sp := pts[i].lerp(pts[i + 1], f)
					draw_circle(sp, 9.0, Color(1, 1, 0.9, a))
		for p in pts:
			for k in 2:
				var rt := fmod(t * 1.1 + k * 0.45, 1.0)
				var rc := col
				rc.a = a * (1.0 - rt)
				draw_arc(p, 50.0 + rt * 70.0, 0.0, TAU, 48, rc, 6.0 * (1.0 - rt) + 1.0, true)
			draw_circle(p, 14.0, Color(col.r, col.g, col.b, 0.8 * a))
var _tips_queued: Dictionary = {}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	if net != null:
		ME = net.my_index
		OP = 1 - ME
		net.mulligan_received.connect(_on_net_mulligan)
		net.action_received.connect(_on_net_action)
		net.opponent_left.connect(_on_net_left)
		net.link_changed.connect(_on_net_link)
	_build()
	_start_game()


func _process(_delta: float) -> void:
	if focus_frame != null:
		focus_frame.set_target(_focus_rect(_focus_key()))
	if net != null and game != null and game.phase == "play" and game.current == ME and _turn_deadline > 0:
		var left := int(ceil((_turn_deadline - Time.get_ticks_msec()) / 1000.0))
		var want := "내 턴 (%d) · %d초" % [game.players[ME].turn_count, maxi(0, left)]
		if turn_label.text != want:
			turn_label.text = want
			turn_label.add_theme_color_override("font_color", Art.COL_TARGET if left <= 15 else Art.COL_OK)
		if left <= 0 and not busy and not overlay.visible:
			_turn_deadline = 0
			if not _drag.is_empty():
				var v = _drag.get("view", null)
				_drag = {}
				_end_drag_visuals(v)
			targeting = {}
			sel = {}
			_show_hint("시간이 다 돼서 턴이 자동으로 끝났어요")
			_on_end_pressed()


# ─────────────────────────────── 화면 구성 ───────────────────────────────

func _build() -> void:
	var bg := ColorRect.new()
	bg.color = Art.COL_BG
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 12)
	margin.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var root := HBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	root.mouse_filter = Control.MOUSE_FILTER_PASS
	margin.add_child(root)

	# ── 왼쪽: 전장 ──
	left_area = VBoxContainer.new()
	left_area.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_area.add_theme_constant_override("separation", 6)
	left_area.mouse_filter = Control.MOUSE_FILTER_PASS
	root.add_child(left_area)

	var op_bar := _bar()
	left_area.add_child(op_bar)
	op_hero_view = HeroView.new()
	op_hero_view.pressed.connect(_on_hero_pressed.bind(OP))
	op_bar.add_child(op_hero_view)
	op_info = _label("", 22, Art.COL_SUB)
	op_bar.add_child(op_info)
	op_bar.add_child(_spacer())
	op_bar.add_child(_label("함정", 18, Art.COL_SUB))
	op_traps_box = HBoxContainer.new()
	op_traps_box.add_theme_constant_override("separation", 6)
	op_bar.add_child(op_traps_box)

	op_board = _board_row()
	left_area.add_child(op_board)

	var mid := HBoxContainer.new()
	mid.alignment = BoxContainer.ALIGNMENT_CENTER
	mid.custom_minimum_size = Vector2(0, 112)
	mid.add_theme_constant_override("separation", 40)
	mid.mouse_filter = Control.MOUSE_FILTER_PASS
	left_area.add_child(mid)
	turn_label = _label("", 30, Art.COL_TEXT, true)
	turn_label.custom_minimum_size = Vector2(260, 0)
	turn_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mid.add_child(turn_label)
	field_slot = HBoxContainer.new()
	field_slot.alignment = BoxContainer.ALIGNMENT_CENTER
	field_slot.custom_minimum_size = Vector2(220, 110)
	mid.add_child(field_slot)
	combo_box = GridContainer.new()
	combo_box.columns = 1
	combo_box.add_theme_constant_override("h_separation", 8)
	combo_box.add_theme_constant_override("v_separation", 6)
	mid.add_child(combo_box)

	me_board = _board_row()
	left_area.add_child(me_board)

	var me_bar := _bar()
	left_area.add_child(me_bar)
	me_hero_view = HeroView.new()
	me_hero_view.pressed.connect(_on_hero_pressed.bind(ME))
	me_bar.add_child(me_hero_view)
	power_btn = Button.new()
	power_btn.custom_minimum_size = Vector2(300, 100)
	power_btn.add_theme_font_size_override("font_size", int(19 * Art.ts()))
	power_btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	power_btn.pressed.connect(_on_power_pressed)
	me_bar.add_child(power_btn)
	me_info = _label("", 24, Art.COL_TEXT, true)
	me_bar.add_child(me_info)
	me_bar.add_child(_spacer())
	me_bar.add_child(_label("함정", 18, Art.COL_SUB))
	me_traps_box = HBoxContainer.new()
	me_traps_box.add_theme_constant_override("separation", 6)
	me_bar.add_child(me_traps_box)

	# 손패 줄: [덱] [손패] [버린 더미]
	hand_row = HBoxContainer.new()
	hand_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hand_row.add_theme_constant_override("separation", 8)
	hand_row.mouse_filter = Control.MOUSE_FILTER_PASS
	left_area.add_child(hand_row)
	deck_pile = PileView.new().setup("deck")
	deck_pile.pressed.connect(_on_pile_pressed.bind("deck"))
	hand_row.add_child(deck_pile)
	hand_area = Control.new()
	hand_area.custom_minimum_size = Vector2(0, 282)
	hand_area.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hand_area.mouse_filter = Control.MOUSE_FILTER_PASS
	hand_area.resized.connect(_layout_hand)
	hand_row.add_child(hand_area)
	discard_pile = PileView.new().setup("discard")
	discard_pile.pressed.connect(_on_pile_pressed.bind("discard"))
	hand_row.add_child(discard_pile)

	# ── 오른쪽: 시장 + 자세히 보기 + 기록 ──
	var right := PanelContainer.new()
	right.custom_minimum_size = Vector2(RIGHT_W, 0)
	var rsb := Art.panel_style(Art.COL_PANEL, Color("#2c313d"), 2, 14)
	rsb.content_margin_left = 12
	rsb.content_margin_right = 12
	rsb.content_margin_top = 10
	rsb.content_margin_bottom = 10
	right.add_theme_stylebox_override("panel", rsb)
	root.add_child(right)
	var rv := VBoxContainer.new()
	rv.add_theme_constant_override("separation", 8)
	right.add_child(rv)

	var head := HBoxContainer.new()
	rv.add_child(head)
	head.add_child(_label("시장", 28, Art.COL_TEXT, true))
	var sub := _label("  산 카드는 내 버린 더미로", 17, Art.COL_SUB)
	sub.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sub)
	var exit_btn := Button.new()
	exit_btn.text = "나가기"
	exit_btn.add_theme_font_size_override("font_size", 18)
	exit_btn.pressed.connect(func(): exit_to_menu.emit())
	head.add_child(exit_btn)

	market_box = VBoxContainer.new()
	market_box.add_theme_constant_override("separation", 6)
	rv.add_child(market_box)

	var btns := HBoxContainer.new()
	btns.add_theme_constant_override("separation", 8)
	rv.add_child(btns)
	refresh_btn = Button.new()
	refresh_btn.text = "시장 갱신 (1골드)"
	refresh_btn.add_theme_font_size_override("font_size", int(20 * Art.ts()))
	refresh_btn.custom_minimum_size = Vector2(0, 56)
	refresh_btn.pressed.connect(_on_refresh_pressed)
	btns.add_child(refresh_btn)
	end_btn = Button.new()
	end_btn.text = "턴 종료"
	end_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	end_btn.custom_minimum_size = Vector2(0, 56)
	end_btn.add_theme_font_size_override("font_size", int(28 * Art.ts()))
	Art.accent_button(end_btn, Color("#16a34a"))
	end_btn.pressed.connect(_on_end_pressed)
	btns.add_child(end_btn)

	var detail := PanelContainer.new()
	var dsb := Art.panel_style(Art.COL_PANEL_2, Color("#353b49"), 2, 12)
	dsb.content_margin_left = 8
	dsb.content_margin_right = 8
	dsb.content_margin_top = 8
	dsb.content_margin_bottom = 8
	detail.add_theme_stylebox_override("panel", dsb)
	detail.custom_minimum_size = Vector2(0, 326)
	rv.add_child(detail)
	var dh := HBoxContainer.new()
	dh.add_theme_constant_override("separation", 10)
	detail.add_child(dh)
	detail_holder = CenterContainer.new()
	detail_holder.custom_minimum_size = Vector2(220, 308)
	dh.add_child(detail_holder)
	detail_actions = VBoxContainer.new()
	detail_actions.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_actions.add_theme_constant_override("separation", 8)
	dh.add_child(detail_actions)

	log_label = RichTextLabel.new()
	log_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	log_label.scroll_following = true
	log_label.bbcode_enabled = true
	log_label.add_theme_font_size_override("normal_font_size", int(18 * Art.ts()))
	log_label.add_theme_font_size_override("bold_font_size", int(18 * Art.ts()))
	log_label.custom_minimum_size = Vector2(0, 60)
	rv.add_child(log_label)

	# ── 연출 / 팝업 층 ──
	fx_layer = Control.new()
	fx_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(fx_layer)
	fx_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hint_label = _label("", 26, Art.COL_SEL, true)
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint_label.add_theme_color_override("font_outline_color", Color.BLACK)
	hint_label.add_theme_constant_override("outline_size", 8)
	fx_layer.add_child(hint_label)

	drop_zone = PanelContainer.new()
	drop_zone.add_theme_stylebox_override("panel", Art.panel_style(Color(0.2, 0.8, 0.4, 0.10), Color(0.3, 0.9, 0.5, 0.8), 4, 18))
	drop_zone.mouse_filter = Control.MOUSE_FILTER_IGNORE
	drop_zone.visible = false
	fx_layer.add_child(drop_zone)
	drop_zone_label = _label("", 30, Color("#bbf7d0"), true)
	drop_zone_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	drop_zone_label.add_theme_color_override("font_outline_color", Color.BLACK)
	drop_zone_label.add_theme_constant_override("outline_size", 8)
	drop_zone.add_child(drop_zone_label)
	drag_arrow = DragArrow.new()
	fx_layer.add_child(drag_arrow)

	focus_frame = FocusFrame.new()
	fx_layer.add_child(focus_frame)
	link_label = _label("", 24, Color("#fca5a5"), true)
	link_label.add_theme_color_override("font_outline_color", Color.BLACK)
	link_label.add_theme_constant_override("outline_size", 8)
	link_label.position = Vector2(20, 1040)
	link_label.visible = false
	fx_layer.add_child(link_label)

	coach = PanelContainer.new()
	var csb := Art.panel_style(Color(0.06, 0.07, 0.1, 0.94), Color("#facc15"), 3, 14)
	csb.content_margin_left = 18
	csb.content_margin_right = 18
	csb.content_margin_top = 12
	csb.content_margin_bottom = 12
	coach.add_theme_stylebox_override("panel", csb)
	coach.custom_minimum_size = Vector2(600, 0)
	coach.visible = false
	fx_layer.add_child(coach)
	var cv := VBoxContainer.new()
	cv.add_theme_constant_override("separation", 8)
	coach.add_child(cv)
	var ch := HBoxContainer.new()
	cv.add_child(ch)
	coach_title = _label("", 18, Art.COL_SEL, true)
	coach_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ch.add_child(coach_title)
	coach_skip = Button.new()
	coach_skip.text = "튜토리얼 건너뛰기"
	coach_skip.add_theme_font_size_override("font_size", 16)
	coach_skip.pressed.connect(_on_coach_skip)
	ch.add_child(coach_skip)
	coach_text = _label("", 23, Art.COL_TEXT)
	coach_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	coach_text.custom_minimum_size = Vector2(564, 0)
	cv.add_child(coach_text)
	var cb := HBoxContainer.new()
	cb.alignment = BoxContainer.ALIGNMENT_END
	cv.add_child(cb)
	coach_btn = Button.new()
	coach_btn.text = "다음"
	coach_btn.custom_minimum_size = Vector2(160, 48)
	coach_btn.add_theme_font_size_override("font_size", 22)
	Art.accent_button(coach_btn, Color("#ca8a04"))
	coach_btn.pressed.connect(_on_coach_next)
	cb.add_child(coach_btn)

	overlay = Control.new()
	overlay.visible = false
	add_child(overlay)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _bar() -> HBoxContainer:
	var b := HBoxContainer.new()
	b.add_theme_constant_override("separation", 14)
	b.custom_minimum_size = Vector2(0, 104)
	b.mouse_filter = Control.MOUSE_FILTER_PASS
	return b


func _board_row() -> HBoxContainer:
	var b := HBoxContainer.new()
	b.alignment = BoxContainer.ALIGNMENT_CENTER
	b.custom_minimum_size = Vector2(0, 190)
	b.add_theme_constant_override("separation", 12)
	b.mouse_filter = Control.MOUSE_FILTER_PASS
	return b


func _label(text: String, fsize: int, color: Color, use_bold: bool = false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", int(round(fsize * Art.ts())))
	l.add_theme_color_override("font_color", color)
	if use_bold:
		l.add_theme_font_override("font", Art.bold())
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _spacer() -> Control:
	var c := Control.new()
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


func _clear(node: Node) -> void:
	for c in node.get_children():
		node.remove_child(c)
		c.queue_free()


# ─────────────────────────────── 게임 진행 ───────────────────────────────

func _start_game() -> void:
	game = Game.new()
	if net != null:
		var names := ["상대", "상대"]
		names[ME] = "나"
		my_hero = net.heroes[ME]
		op_hero = net.heroes[OP]
		game.start(net.heroes[0], net.heroes[1], net.seed_value, names)
	else:
		game.start(my_hero, op_hero, -1, ["나", "상대"])
	game.logged.connect(_on_log)
	game.game_event.connect(_on_game_event)
	ai = AI.new()
	ai.level = ai_level
	if tutorial_mode:
		tutorial = Tutorial.new()
		ai.level = 0
		tutorial.setup(game)
	elif net == null:
		game.mulligan(OP, [])
	log_label.clear()
	for l in game.log_lines:
		_on_log(l)
	op_hero_view.setup(game.players[OP])
	me_hero_view.setup(game.players[ME])
	_refresh()
	if tutorial_mode:
		_banner("튜토리얼", Art.COL_SEL)
		_update_coach()
	else:
		_show_mulligan()


func _idle() -> bool:
	return game != null and game.phase == "play" and game.current == ME and not busy and not overlay.visible


func _do(a: Dictionary) -> bool:
	if tutorial != null and tutorial.active:
		var msg := tutorial.allows(a, game)
		if msg != "":
			_show_hint(msg)
			_refresh()
			return false
	_snapshot_positions()
	var ok := game.apply_action(ME, a)
	if not ok:
		_show_hint("지금은 할 수 없는 행동입니다")
	elif net != null:
		net.send_action(a, game.state_hash())
	if tutorial != null:
		var was_active := tutorial.active
		tutorial.after_action(a, ok)
		if was_active and not tutorial.active:
			_banner("튜토리얼 완료!", Art.COL_OK)
	_refresh()
	_flush_fx()
	_update_coach()
	_check_over()
	return ok


func _check_over() -> void:
	if game.phase == "over" and not _over_shown:
		_over_shown = true
		busy = true
		await _wait(1.0)
		if is_inside_tree():
			_show_game_over()


func _run_ai() -> void:
	busy = true
	_run_id += 1
	var my_id := _run_id
	_refresh()
	_banner("상대 턴", Art.COL_TARGET)
	await _wait(0.9)
	var guard := 0
	while my_id == _run_id and game.phase == "play" and game.current == OP and guard < 200:
		guard += 1
		var a: Dictionary = {}
		if tutorial != null:
			a = tutorial.op_action(game)
		if a.is_empty():
			a = ai.choose_action(game, OP)
		if a.is_empty():
			break
		_snapshot_positions()
		var ok: bool = game.apply_action(OP, a)
		if not ok:
			game.apply_action(OP, {"type": "end"})
		_refresh()
		_flush_fx()
		if a["type"] == "end" or not ok:
			break
		var delay := AI_DELAY if a["type"] in ["play", "attack", "power", "buy"] else 0.3
		await _wait(delay)
	if my_id != _run_id:
		return
	if game.phase == "play" and game.current == OP:
		game.apply_action(OP, {"type": "end"})
	busy = false
	_refresh()
	_flush_fx()
	if game.phase == "over":
		_check_over()
	else:
		_banner("내 턴", Art.COL_OK)
		_on_my_turn_start()
	_update_coach()


func _wait(sec: float) -> void:
	var t := Timer.new()
	t.one_shot = true
	t.wait_time = 0.02 if fast else sec
	add_child(t)
	t.start()
	await t.timeout
	t.queue_free()


# ─────────────────────────────── 화면 갱신 ───────────────────────────────

func _refresh() -> void:
	if game == null:
		return
	var me: PlayerState = game.players[ME]
	var op: PlayerState = game.players[OP]
	op_hero_view.set_highlight(_target_hl(OP, -1))
	me_hero_view.set_highlight(_target_hl(ME, -1))
	op_hero_view.queue_redraw()
	me_hero_view.queue_redraw()
	op_info.text = "손패 %d장\n덱 %d · 버린 더미 %d\n마나 %d/%d · 골드 %d" % [op.hand.size(), op.deck.size(), op.discard.size(), op.mana, op.max_mana, op.gold]
	var op_combos: Array = []
	for cid in game.active_combos(OP):
		op_combos.append(CardDB.combo_by_id[cid]["name"])
	if not op_combos.is_empty():
		op_info.text += "\n조합: " + ", ".join(PackedStringArray(op_combos))
	me_info.text = "마나  %d / %d\n골드  %d" % [me.mana, me.max_mana, me.gold]
	if me.mana_cap > Game.MAX_MANA:
		me_info.text += "\n마나 한도 %d" % me.mana_cap
	deck_pile.set_state(me.deck.size())
	discard_pile.set_state(me.discard.size(), me.discard.back().data if not me.discard.is_empty() else {})
	_fill_traps(op_traps_box, op, false)
	_fill_traps(me_traps_box, me, true)
	_fill_board(op_board, op, OP)
	_fill_board(me_board, me, ME)
	_fill_field()
	_fill_hand()
	_fill_market()
	_update_buttons()
	_update_detail()
	if game.phase == "over":
		turn_label.text = "게임 종료"
	elif game.phase == "mulligan":
		turn_label.text = "준비 중"
	elif game.current == ME:
		turn_label.text = "내 턴 (%d)" % me.turn_count
		if net != null and _turn_deadline > 0:
			turn_label.text += " · %d초" % maxi(0, int(ceil((_turn_deadline - Time.get_ticks_msec()) / 1000.0)))
		turn_label.add_theme_color_override("font_color", Art.COL_OK)
	else:
		turn_label.text = "상대 턴" + (" (생각 중...)" if net != null else "")
		turn_label.add_theme_color_override("font_color", Art.COL_TARGET)


func _target_hl(side: int, slot: int) -> String:
	if targeting.is_empty():
		return ""
	if Game.target_in(targeting["targets"], {"side": side, "slot": slot}):
		return "target"
	return ""


func _fill_traps(box: HBoxContainer, p: PlayerState, own: bool) -> void:
	_clear(box)
	for i in p.traps.size():
		var t: CardInst = p.traps[i]
		var v: CardView = CardView.new().setup(t.data, t, "trap_own" if own else "trap_back")
		if own:
			v.pressed.connect(_on_trap_pressed.bind(i))
		box.add_child(v)
	for k in range(p.traps.size(), game.trap_slots(p.idx)):
		var empty := Panel.new()
		empty.custom_minimum_size = Vector2(70, 92)
		empty.add_theme_stylebox_override("panel", Art.panel_style(Color(1, 1, 1, 0.03), Color("#3a4050"), 2, 8))
		empty.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(empty)


func _fill_board(box: HBoxContainer, p: PlayerState, side: int) -> void:
	_clear(box)
	var combo_col := {}
	for cid in game.active_combos(side):
		for cu in game.combo_units(side, cid):
			if not combo_col.has(cu.uid):
				combo_col[cu.uid] = Color(CardDB.combo_by_id[cid]["color"])
	for i in p.board.size():
		var u: CardInst = p.board[i]
		var v: CardView = CardView.new().setup(u.data, u, "board")
		if combo_col.has(u.uid):
			v.meta_info["combo_col"] = combo_col[u.uid]
			v.set_process(true)
		v.pressed.connect(_on_unit_pressed.bind(side, i))
		v.set_meta("side", side)
		v.set_meta("slot", i)
		v.meta_info["show_sleep"] = side == game.current
		if side == ME and _idle() and game.attack_error(ME, i) == "":
			v.draggable = true
			v.drag_started.connect(_on_drag_start.bind("unit", i))
			v.drag_moved.connect(_on_drag_move)
			v.drag_ended.connect(_on_drag_end)
		var hl := _target_hl(side, i)
		if hl == "" and sel.get("kind", "") == "unit" and int(sel.get("side", -1)) == side and int(sel.get("index", -1)) == i:
			hl = "sel"
		elif hl == "" and targeting.is_empty() and side == ME and _idle() and game.attack_error(ME, i) == "":
			hl = "ok"
		v.set_highlight(hl)
		box.add_child(v)
	if p.board.is_empty():
		box.add_child(_label("유닛 없음", 20, Color("#4b5263")))


func _fill_field() -> void:
	_clear(field_slot)
	if game.field == null:
		field_slot.add_child(_label("공용 필드 없음", 18, Color("#4b5263")))
		return
	var v: CardView = CardView.new().setup(game.field.data, game.field, "field")
	v.custom_minimum_size = Vector2(230, 104)
	v.caption = "주인: " + ("나" if game.field_owner == ME else "상대")
	v.pressed.connect(_on_field_pressed)
	if sel.get("kind", "") == "field":
		v.set_highlight("sel")
	field_slot.add_child(v)


func _fill_hand() -> void:
	_clear(hand_area)
	var me: PlayerState = game.players[ME]
	for i in me.hand.size():
		var c: CardInst = me.hand[i]
		var v: CardView = CardView.new().setup(c.data, c, "hand")
		v.pressed.connect(_on_hand_pressed.bind(i))
		if _idle():
			v.draggable = true
			v.drag_started.connect(_on_drag_start.bind("hand", i))
			v.drag_moved.connect(_on_drag_move)
			v.drag_ended.connect(_on_drag_end)
		if _anim_hidden.has(c.uid):
			# 연출이 끝나면 다시 보임 (혹시 연출이 안 돌면 2.5초 뒤 자동으로 보임)
			if Time.get_ticks_msec() - int(_anim_hidden[c.uid]) < 2500:
				v.modulate.a = 0.0
			else:
				_anim_hidden.erase(c.uid)
		var selected: bool = sel.get("kind", "") == "hand" and int(sel.get("index", -1)) == i
		if selected:
			v.set_highlight("sel")
		elif targeting.is_empty() and _idle() and game.play_error(ME, i) == "":
			v.set_highlight("ok")
		v.set_meta("selected", selected)
		hand_area.add_child(v)
	_layout_hand()


func _layout_hand() -> void:
	var cards := hand_area.get_children()
	var n := cards.size()
	if n == 0:
		return
	var cw := 190.0
	var w := hand_area.size.x
	var step := cw + 12.0
	if n > 1 and step * (n - 1) + cw > w:
		step = (w - cw) / float(n - 1)
	var total := step * (n - 1) + cw
	var x0 := (w - total) / 2.0
	for i in n:
		var c: Control = cards[i]
		var y := 4.0 if c.get_meta("selected", false) else 16.0
		c.position = Vector2(x0 + i * step, y)


func _fill_market() -> void:
	_clear(market_box)
	var me: PlayerState = game.players[ME]
	for i in game.market.size():
		var id: String = game.market[i]
		if id == "":
			continue
		var v: CardView = CardView.new().setup(CardDB.cards[id], null, "market")
		v.price = game.price(ME, id)
		v.dim = v.price > me.gold
		if sel.get("kind", "") == "market" and int(sel.get("index", -1)) == i:
			v.set_highlight("sel")
		v.pressed.connect(_on_market_pressed.bind(i))
		if _idle():
			v.draggable = true
			v.drag_started.connect(_on_drag_start.bind("market", i))
			v.drag_moved.connect(_on_drag_move)
			v.drag_ended.connect(_on_drag_end)
		market_box.add_child(v)


func _update_buttons() -> void:
	var pd: Dictionary = game.power_def(ME)
	power_btn.text = "영웅 능력 · %s (%d마나)\n%s" % [pd["name"], int(pd["cost"]), pd["text"]]
	power_btn.disabled = not _idle() or game.power_error(ME) != ""
	end_btn.disabled = not _idle()
	refresh_btn.disabled = not _idle() or game.refresh_error(ME) != ""
	_fill_combo_buttons()


func _fill_combo_buttons() -> void:
	_clear(combo_box)
	var ids: Array = game.active_combos(ME)
	combo_box.columns = maxi(1, int(ceil(ids.size() / 2.0)))
	for cid in ids:
		var k: Dictionary = CardDB.combo_by_id[cid]
		var sk: Dictionary = k["skill"]
		var b := Button.new()
		var err: String = game.combo_error(ME, cid)
		if ids.size() == 1:
			b.text = "조합 스킬 · %s (%d마나)\n%s" % [sk["name"], int(sk["cost"]), sk["text"]]
			b.custom_minimum_size = Vector2(270, 104)
			b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		else:
			b.text = "%s (%d마나)" % [sk["name"], int(sk["cost"])]
			b.custom_minimum_size = Vector2(220, 50)
		b.tooltip_text = "[%s] %s\n%s" % [k["name"], k["cond"], sk["text"]]
		b.add_theme_font_size_override("font_size", int(17 * Art.ts()))
		b.disabled = not _idle() or err != ""
		Art.accent_button(b, Color(k["color"]).darkened(0.2))
		b.pressed.connect(_on_combo_pressed.bind(cid))
		combo_box.add_child(b)


# ── 자세히 보기 + 행동 버튼 ──

func _update_detail() -> void:
	_clear(detail_holder)
	_clear(detail_actions)
	_detail_btns.clear()
	detail_holder.visible = sel.get("kind", "") != "pile"
	var me: PlayerState = game.players[ME]
	var kind: String = sel.get("kind", "")
	var data: Dictionary = {}
	var inst = null
	var price := -1
	match kind:
		"pile":
			_info_label(_pile_text(str(sel.get("which", "deck"))))
			return
		"hand":
			var i := int(sel["index"])
			if i < me.hand.size():
				inst = me.hand[i]
				data = inst.data
				_detail_hand_buttons(i)
		"market":
			var mi := int(sel["index"])
			if mi < game.market.size() and game.market[mi] != "":
				data = CardDB.cards[game.market[mi]]
				price = game.price(ME, game.market[mi])
				var err: String = game.buy_error(ME, mi)
				_action_button("구매하기 (%d골드)" % price if err == "" else "구매 불가: " + err, err == "", _on_buy_pressed, Color("#d97706"), "buy")
		"unit":
			var side := int(sel["side"])
			var ui := int(sel["index"])
			var p: PlayerState = game.players[side]
			if ui < p.board.size():
				inst = p.board[ui]
				data = inst.data
				if side == ME and _idle():
					var aerr: String = game.attack_error(ME, ui)
					_action_button("공격하기" if aerr == "" else aerr, aerr == "", _on_attack_btn, Color("#dc2626"), "attack")
		"field":
			if game.field != null:
				inst = game.field
				data = inst.data
				_info_label("주인: " + ("나" if game.field_owner == ME else "상대") + "\n필드는 전장에 1장만 있을 수 있습니다. 새 필드를 내면 교체됩니다.")
		"trap":
			var ti := int(sel["index"])
			if ti < me.traps.size():
				inst = me.traps[ti]
				data = inst.data
				_info_label("내가 놓은 함정입니다. 상대 턴에 조건이 맞으면 자동으로 발동합니다.")
		"hero":
			var hp: PlayerState = game.players[int(sel["side"])]
			var pd: Dictionary = CardDB.powers[hp.power_id]
			_info_label("%s · %s\n체력 %d / %d, 방어도 %d\n영웅 능력: %s (%d마나)\n%s" % [hp.name, hp.hero_name, hp.hp, hp.max_hp, hp.armor, pd["name"], int(pd["cost"]), pd["text"]])
	if data.is_empty():
		if kind != "hero":
			_info_label(_tips_text())
		return
	var v: CardView = CardView.new().setup(data, inst, "detail")
	v.price = price
	detail_holder.add_child(v)
	_keyword_help(data, inst)
	var close := Button.new()
	close.text = "닫기"
	close.add_theme_font_size_override("font_size", 18)
	close.pressed.connect(func():
		sel = {}
		targeting = {}
		_refresh())
	detail_actions.add_child(close)


func _detail_hand_buttons(i: int) -> void:
	var err: String = game.play_error(ME, i)
	_action_button("사용하기" if err == "" else "사용 불가: " + err, err == "", _on_use_pressed, Color("#2563eb"), "use")
	var perr: String = game.pitch_error(ME, i)
	_action_button("버리기 → 골드 +1", perr == "", _on_pitch_pressed, Color("#b45309"), "pitch")
	var cerr: String = game.clean_error(ME, i)
	_action_button("정리 (2골드, 영구 제거)" if cerr == "" else "정리 불가: " + cerr, cerr == "", _on_clean_pressed, Color("#475569"), "clean")


func _action_button(text: String, enabled: bool, cb: Callable, col: Color, key: String = "") -> void:
	var b := Button.new()
	if key != "":
		_detail_btns[key] = b
	b.text = text
	b.disabled = not enabled
	b.custom_minimum_size = Vector2(0, 52)
	b.add_theme_font_size_override("font_size", 19)
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if enabled:
		Art.accent_button(b, col)
	b.pressed.connect(cb)
	detail_actions.add_child(b)


func _info_label(text: String) -> void:
	var l := _label(text, 17, Art.COL_SUB)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.custom_minimum_size = Vector2(220, 0)
	detail_actions.add_child(l)


func _keyword_help(data: Dictionary, inst) -> void:
	var lines: Array = []
	var kws: Array = inst.keywords if inst != null and inst is CardInst else data.get("keywords", [])
	for k in kws:
		lines.append("[b]%s[/b]: %s" % [CardDB.KEYWORD_NAMES.get(k, k), CardDB.KEYWORD_DESC.get(k, "")])
	var tx: String = data.get("text", "")
	for word in CardDB.TEXT_KEYWORD_DESC:
		if tx.contains(word):
			lines.append("[b]%s[/b]: %s" % [word, CardDB.TEXT_KEYWORD_DESC[word]])
	if data.has("upgrade_of") and CardDB.cards.has(data["upgrade_of"]):
		lines.append("[b]상위 호환[/b]: 일반 카드 '%s'보다 강한 레어 카드" % CardDB.cards[data["upgrade_of"]]["name"])
	if not data.get("tags", []).is_empty():
		lines.append("[b]시리즈[/b]: %s (같은 시리즈를 모으면 조합 결성)" % CardDB.tag_line(data))
	var shown := 0
	for k in CardDB.combos:
		if shown < 3 and _card_in_combo(data, k):
			shown += 1
			lines.append("[color=%s][b]조합 %s[/b][/color]: %s → %s, 스킬 '%s'" % [k["color"], k["name"], k["cond"], k["form_text"], k["skill"]["name"]])
	if lines.is_empty():
		return
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = true
	r.scroll_active = false
	r.add_theme_font_size_override("normal_font_size", 15)
	r.add_theme_font_size_override("bold_font_size", 15)
	r.add_theme_color_override("default_color", Art.COL_SUB)
	r.text = "\n".join(PackedStringArray(lines))
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	detail_actions.add_child(r)


func _card_in_combo(data: Dictionary, k: Dictionary) -> bool:
	if data.get("type", "") != "unit":
		return false
	for n in k["need"]:
		if n.has("tag") and data.get("tags", []).has(n["tag"]):
			return true
		if n.has("kw") and data.get("keywords", []).has(n["kw"]):
			return true
		if n.has("faction") and data.get("faction", "") == n["faction"]:
			return true
		if n.has("all_ids") and (n["all_ids"] as Array).has(data.get("id", "")):
			return true
		if n.has("any_ids") and (n["any_ids"] as Array).has(data.get("id", "")):
			return true
	return false


func _tips_text() -> String:
	if game.phase == "play" and game.current == ME:
		return "카드를 누르면 여기서 자세히 보고 행동을 고를 수 있어요.\n\n· 마나: 카드 사용\n· 골드: 손패를 버려서 얻고, 시장에서 카드 구매\n· 초록 테두리: 지금 쓸 수 있는 카드·공격 가능한 유닛"
	return "상대 차례입니다. 카드를 눌러 자세히 볼 수 있어요."


# ─────────────────────────────── 입력 ───────────────────────────────

func _gui_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.pressed:
		if not targeting.is_empty():
			targeting = {}
			_show_hint("취소했습니다")
			_refresh()
		elif not sel.is_empty():
			sel = {}
			_refresh()


func _begin_targeting(action: Dictionary, targets: Array, hint: String) -> void:
	if targets.is_empty():
		_show_hint("고를 수 있는 대상이 없습니다")
		return
	targeting = action.duplicate()
	targeting["targets"] = targets
	_show_hint(hint + "  (빈 곳을 누르면 취소)")
	_refresh()


func _try_target(t: Dictionary) -> void:
	if not Game.target_in(targeting["targets"], t):
		if targeting.get("type", "") == "attack" and int(t["side"]) == OP and int(t["slot"]) < 0:
			_show_hint("도발 유닛이 있어서 영웅을 공격할 수 없어요. 도발 유닛부터 공격하세요!")
			_queue_tip("taunt", "도발: 상대 필드에 '도발' 유닛(두꺼운 회색 테두리)이 있으면, 유닛으로는 그 도발 유닛만 공격할 수 있어요.\n도발을 먼저 처치하거나, 주문·영웅 능력으로 처리하세요. (주문은 도발과 상관없이 영웅을 노릴 수 있어요)")
		else:
			_show_hint("그 대상은 고를 수 없습니다")
		return
	var a := targeting.duplicate()
	a.erase("targets")
	a["target"] = t
	targeting = {}
	sel = {}
	_do(a)


func _on_hand_pressed(_v: Control, i: int) -> void:
	if not targeting.is_empty():
		targeting = {}
	sel = {"kind": "hand", "index": i}
	_refresh()


func _on_unit_pressed(_v: Control, side: int, i: int) -> void:
	if not targeting.is_empty():
		_try_target({"side": side, "slot": i})
		return
	sel = {"kind": "unit", "side": side, "index": i}
	if side == ME and _idle():
		var err: String = game.attack_error(ME, i)
		if err == "":
			_begin_targeting({"type": "attack", "unit": i}, game.attack_targets(ME), "공격할 대상을 고르세요")
			return
		_show_hint(err)
		if err.begins_with("이번 턴에 낸"):
			_queue_tip("sleep", "유닛은 낸 다음 턴부터 공격할 수 있어요. ('Zz' 표시)\n바로 공격하는 '돌진' 키워드 유닛은 예외예요.")
	_refresh()


func _on_hero_pressed(_v: Control, side: int) -> void:
	if not targeting.is_empty():
		_try_target({"side": side, "slot": -1})
		return
	sel = {"kind": "hero", "side": side}
	_refresh()


func _on_market_pressed(_v: Control, i: int) -> void:
	targeting = {}
	sel = {"kind": "market", "index": i}
	_refresh()


func _on_field_pressed(_v: Control) -> void:
	if not targeting.is_empty():
		return
	sel = {"kind": "field"}
	_refresh()


func _on_trap_pressed(_v: Control, i: int) -> void:
	if not targeting.is_empty():
		return
	sel = {"kind": "trap", "index": i}
	_refresh()


func _on_power_pressed() -> void:
	if not _idle():
		return
	var err: String = game.power_error(ME)
	if err != "":
		_show_hint(err)
		return
	var pd: Dictionary = game.power_def(ME)
	if pd.has("target"):
		sel = {}
		_begin_targeting({"type": "power"}, game.valid_targets(ME, pd["target"]), "영웅 능력의 대상을 고르세요")
	else:
		_do({"type": "power"})


func _on_combo_pressed(cid: String) -> void:
	if not _idle():
		return
	var err: String = game.combo_error(ME, cid)
	if err != "":
		_show_hint(err)
		return
	var sk: Dictionary = CardDB.combo_by_id[cid]["skill"]
	if sk.has("target"):
		sel = {}
		_begin_targeting({"type": "combo", "combo": cid}, game.valid_targets(ME, sk["target"]), "'%s'의 대상을 고르세요" % sk["name"])
	else:
		_do({"type": "combo", "combo": cid})


func _on_use_pressed() -> void:
	if not _idle() or sel.get("kind", "") != "hand":
		return
	var i := int(sel["index"])
	var me: PlayerState = game.players[ME]
	var err: String = game.play_error(ME, i)
	if err != "":
		_show_hint(err)
		return
	var c: CardInst = me.hand[i]
	if c.data.has("target"):
		_begin_targeting({"type": "play", "hand": i}, game.valid_targets(ME, c.data["target"]), "'%s'의 대상을 고르세요" % c.display_name())
	else:
		sel = {}
		_do({"type": "play", "hand": i})


func _on_pitch_pressed() -> void:
	if not _idle() or sel.get("kind", "") != "hand":
		return
	var i := int(sel["index"])
	sel = {}
	_do({"type": "pitch", "hand": i})


func _on_clean_pressed() -> void:
	if not _idle() or sel.get("kind", "") != "hand":
		return
	var i := int(sel["index"])
	sel = {}
	_do({"type": "clean", "hand": i})


func _on_buy_pressed() -> void:
	if not _idle() or sel.get("kind", "") != "market":
		return
	var i := int(sel["index"])
	sel = {}
	_do({"type": "buy", "market": i})


func _on_attack_btn() -> void:
	if sel.get("kind", "") != "unit":
		return
	var i := int(sel["index"])
	_begin_targeting({"type": "attack", "unit": i}, game.attack_targets(ME), "공격할 대상을 고르세요")


func _on_refresh_pressed() -> void:
	if _idle():
		sel = {}
		_do({"type": "refresh"})


func _on_end_pressed() -> void:
	if not _idle():
		return
	sel = {}
	targeting = {}
	if _do({"type": "end"}) and game.phase == "play" and game.current == OP:
		if net != null:
			_begin_remote_turn()
		else:
			_run_ai()


# ─────────────────────────────── 기록 / 연출 ───────────────────────────────

func _on_log(text: String) -> void:
	if log_label == null:
		return
	var t := text
	if text.begins_with("──"):
		t = "[color=#facc15]%s[/color]" % text
	elif text.begins_with("나:"):
		t = "[color=#93c5fd]%s[/color]" % text
	elif text.begins_with("상대:"):
		t = "[color=#fca5a5]%s[/color]" % text
	log_label.append_text(t + "\n")


func _key_of(obj) -> String:
	if obj is PlayerState:
		return "h%d" % obj.idx
	if obj is CardInst:
		return "u%d" % obj.uid
	return ""


func _snapshot_positions() -> void:
	_pos_cache.clear()
	for box in [op_board, me_board]:
		for v in box.get_children():
			if v is CardView and v.inst != null:
				_pos_cache["u%d" % v.inst.uid] = v.global_position + v.size / 2.0
	for v in hand_area.get_children():
		if v is CardView and v.inst != null:
			_pos_cache["c%d" % v.inst.uid] = v.global_position + v.size / 2.0
	for i in market_box.get_child_count():
		var mv = market_box.get_child(i)
		_pos_cache["m%d" % i] = mv.global_position + mv.size / 2.0
	_pos_cache["h%d" % ME] = me_hero_view.global_position + me_hero_view.size / 2.0
	_pos_cache["h%d" % OP] = op_hero_view.global_position + op_hero_view.size / 2.0


func _on_game_event(kind: String, info: Dictionary) -> void:
	match kind:
		"damage", "heal":
			_pending_fx.append({"kind": kind, "key": _key_of(info["obj"]), "amount": int(info["amount"]), "armor": int(info.get("armor", 0))})
		"trap":
			_pending_fx.append({"kind": "trap", "name": info["card"].display_name(), "player": int(info["player"])})
			if int(info["player"]) == OP:
				_queue_tip("trap", "상대의 함정이 발동했어요! 함정은 뒷면으로 놓였다가, 내 턴에 조건이 맞으면 자동으로 발동해요.\n상대 함정 칸의 '?' 카드를 조심하세요. (그림자 군주는 상대 함정을 모두 파괴해요)")
		"play":
			if int(info["player"]) == OP:
				_pending_fx.append({"kind": "reveal", "card": info["card"]})
		"buy":
			if int(info["player"]) == OP:
				_pending_fx.append({"kind": "opbuy", "name": info["card"].display_name()})
			_pending_fx.append({"kind": "buyfly", "player": int(info["player"]), "data": info["card"].data, "slot": int(info.get("slot", 0))})
		"draw":
			var c: CardInst = info["card"]
			if int(info["player"]) == ME and not info.get("burn", false) and not fast:
				_anim_hidden[c.uid] = Time.get_ticks_msec()
			_pending_fx.append({"kind": "draw", "player": int(info["player"]), "uid": c.uid, "data": c.data, "burn": bool(info.get("burn", false))})
		"shuffle":
			_pending_fx.append({"kind": "shuffle", "player": int(info["player"])})
		"pitch":
			var pc: CardInst = info["card"]
			_pending_fx.append({"kind": "pitch", "player": int(info["player"]), "uid": pc.uid, "data": pc.data})
		"buff":
			_pending_fx.append({"kind": "buff", "key": _key_of(info["obj"]), "atk": int(info["atk"]), "hp": int(info["hp"]), "keyword": str(info.get("keyword", ""))})
		"gold":
			_pending_fx.append({"kind": "gold", "key": "h%d" % int(info["player"]), "amount": int(info["amount"])})
		"combo", "combo_skill":
			var uids: Array = []
			for u in info["units"]:
				uids.append(u.uid)
			_pending_fx.append({"kind": kind, "player": int(info["player"]), "combo": str(info["combo"]), "uids": uids})
			if kind == "combo" and int(info["player"]) == ME:
				_queue_tip("combo", "조합이 결성됐어요! 같은 시리즈나 조건에 맞는 유닛이 모이면 효과가 터지고,\n가운데 [조합 스킬] 버튼이 생겨요. 턴마다 1번 쓸 수 있어요. (조합 유닛은 색 테두리로 빛나요)")


func _flush_fx() -> void:
	if _pending_fx.is_empty():
		return
	await get_tree().process_frame
	if not is_inside_tree():
		return
	# 살아 있는 유닛은 새 위치, 죽은 유닛은 직전 위치
	for box in [op_board, me_board]:
		for v in box.get_children():
			if v is CardView and v.inst != null:
				_pos_cache["u%d" % v.inst.uid] = v.global_position + v.size / 2.0
	var fxs := _pending_fx.duplicate()
	_pending_fx.clear()
	var offset := 0
	var draw_n := 0
	var base_delay := 0.0
	for fx in fxs:
		match fx["kind"]:
			"draw":
				_fx_draw(fx, base_delay + draw_n * 0.14)
				draw_n += 1
			"shuffle":
				if int(fx["player"]) == ME:
					_fx_shuffle()
					base_delay += 0.45
			"pitch":
				_fx_pitch(fx)
			"buyfly":
				_fx_buy(fx)
			"damage":
				if _pos_cache.has(fx["key"]):
					var pos: Vector2 = _pos_cache[fx["key"]] + Vector2(0, offset % 3 * 8)
					var amount := int(fx["amount"])
					var armor := int(fx.get("armor", 0))
					if amount == 0:
						_float_text(pos, "막힘", Color("#fde047"))
					elif armor > 0:
						_float_text(pos + Vector2(-70, 0), "방어도 -%d" % armor, Color("#cbd5e1"))
						if amount > armor:
							_float_text(pos + Vector2(60, 0), "-%d" % (amount - armor), Color("#ff4d4d"))
						if fx["key"] == "h%d" % OP:
							_queue_tip("armor", "상대 영웅의 '방어도'(체력 옆 회색 방패 숫자)가 피해를 먼저 막았어요.\n방어도가 0이 되어야 체력이 줄어들어요. 강철 영웅 로완은 영웅 능력으로 방어도를 쌓아요.")
					else:
						_float_text(pos, "-%d" % amount, Color("#ff4d4d"))
					if fx["key"] == "h%d" % ME and amount > armor:
						me_hero_view.flash()
					elif fx["key"] == "h%d" % OP and amount > armor:
						op_hero_view.flash()
			"heal":
				if _pos_cache.has(fx["key"]):
					_float_text(_pos_cache[fx["key"]], "+%d" % int(fx["amount"]), Color("#4ade80"))
			"buff":
				if _pos_cache.has(fx["key"]):
					var bt := ""
					if int(fx["atk"]) != 0 or int(fx["hp"]) != 0:
						bt = "+%d/+%d" % [int(fx["atk"]), int(fx["hp"])]
					if fx["keyword"] != "":
						bt += (" " if bt != "" else "") + str(CardDB.KEYWORD_NAMES.get(fx["keyword"], fx["keyword"]))
					if bt != "":
						_float_text(_pos_cache[fx["key"]] + Vector2(0, -30 + offset % 3 * 10), bt, Color("#86efac"))
			"gold":
				if _pos_cache.has(fx["key"]):
					_float_text(_pos_cache[fx["key"]] + Vector2(90, 0), "골드 +%d" % int(fx["amount"]), Art.COL_GOLD)
			"combo", "combo_skill":
				_fx_combo(fx)
			"trap":
				_banner("함정 발동! " + fx["name"], Color("#c084fc"))
			"reveal":
				_reveal(fx["card"])
			"opbuy":
				_show_hint("상대가 %s 구매" % fx["name"])
		offset += 1


func _fx_combo(fx: Dictionary) -> void:
	var k: Dictionary = CardDB.combo_by_id.get(fx["combo"], {})
	if k.is_empty():
		return
	var col := Color(k["color"])
	var pts := PackedVector2Array()
	for uid in fx["uids"]:
		var key := "u%d" % int(uid)
		if _pos_cache.has(key):
			pts.append(_pos_cache[key] - fx_layer.global_position)
	var lines := ComboLines.new()
	lines.pts = pts
	lines.col = col
	fx_layer.add_child(lines)
	lines.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# 가운데 큰 알림판
	if is_instance_valid(_combo_panel):
		_combo_panel.queue_free()
	var mine := int(fx["player"]) == ME
	var skill: bool = fx["kind"] == "combo_skill"
	var panel := PanelContainer.new()
	var sb := Art.panel_style(Color(0.05, 0.06, 0.09, 0.92), col, 4, 18)
	sb.content_margin_left = 34
	sb.content_margin_right = 34
	sb.content_margin_top = 14
	sb.content_margin_bottom = 16
	sb.shadow_color = Color(col.r, col.g, col.b, 0.45)
	sb.shadow_size = 24
	panel.add_theme_stylebox_override("panel", sb)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	panel.add_child(v)
	var head := ("조합 스킬!" if skill else "조합 결성!") + ("" if mine else "  (상대)")
	v.add_child(_label(head, 26, Art.COL_SUB if mine else Art.COL_TARGET, true))
	var title := _label(k["skill"]["name"] if skill else k["name"], 58, col.lerp(Color.WHITE, 0.25), true)
	title.add_theme_color_override("font_outline_color", Color.BLACK)
	title.add_theme_constant_override("outline_size", 10)
	v.add_child(title)
	v.add_child(_label(k["skill"]["text"] if skill else "%s → %s" % [k["cond"], k["form_text"]], 24, Art.COL_TEXT))
	for c in v.get_children():
		(c as Label).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	fx_layer.add_child(panel)
	_combo_panel = panel
	panel.reset_size()
	var area := left_area.get_global_rect()
	panel.position = Vector2(area.position.x + (area.size.x - panel.size.x) / 2.0, area.position.y + area.size.y * 0.26) - fx_layer.global_position
	panel.pivot_offset = panel.size / 2.0
	panel.scale = Vector2(0.4, 0.4)
	panel.modulate.a = 0.0
	var tw := panel.create_tween()
	tw.set_parallel(true)
	tw.tween_property(panel, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(panel, "modulate:a", 1.0, 0.15)
	tw.chain().tween_interval(0.15 if fast else 1.3)
	tw.chain().tween_property(panel, "modulate:a", 0.0, 0.35)
	tw.chain().tween_callback(panel.queue_free)
	# 조합 유닛이 통통 튀기
	for box in [op_board, me_board]:
		for cv in box.get_children():
			if cv is CardView and cv.inst != null and (fx["uids"] as Array).has(cv.inst.uid):
				var bt := cv.create_tween()
				bt.tween_property(cv, "scale", Vector2(1.15, 1.15), 0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
				bt.tween_property(cv, "scale", Vector2.ONE, 0.25)


func _float_text(pos: Vector2, text: String, col: Color) -> void:
	var l := _label(text, 44, col, true)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 10)
	fx_layer.add_child(l)
	l.reset_size()
	l.position = pos - l.size / 2.0 - fx_layer.global_position
	var tw := l.create_tween()
	tw.set_parallel(true)
	tw.tween_property(l, "position:y", l.position.y - 70, 1.0)
	tw.tween_property(l, "modulate:a", 0.0, 1.0).set_delay(0.35)
	tw.chain().tween_callback(l.queue_free)


func _banner(text: String, col: Color) -> void:
	if is_instance_valid(_banner_label):
		_banner_label.queue_free()
	var l := _label(text, 64, col, true)
	_banner_label = l
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 14)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	fx_layer.add_child(l)
	l.reset_size()
	var area := left_area.get_global_rect()
	l.position = Vector2(area.position.x + (area.size.x - l.size.x) / 2.0, area.position.y + area.size.y * 0.38) - fx_layer.global_position
	l.modulate.a = 0.0
	var tw := l.create_tween()
	tw.tween_property(l, "modulate:a", 1.0, 0.15)
	tw.tween_interval(0.8)
	tw.tween_property(l, "modulate:a", 0.0, 0.35)
	tw.tween_callback(l.queue_free)


func _reveal(c: CardInst) -> void:
	if is_instance_valid(_reveal_view):
		_reveal_view.queue_free()
	var v: CardView = CardView.new().setup(c.data, null, "detail")
	_reveal_view = v
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fx_layer.add_child(v)
	var area := left_area.get_global_rect()
	v.position = Vector2(area.position.x + area.size.x - 230, area.position.y + 120) - fx_layer.global_position
	v.modulate.a = 0.0
	var tw := v.create_tween()
	tw.tween_property(v, "modulate:a", 1.0, 0.15)
	tw.tween_interval(1.1)
	tw.tween_property(v, "modulate:a", 0.0, 0.3)
	tw.tween_callback(v.queue_free)


func _show_hint(text: String) -> void:
	_hint_id += 1
	var my := _hint_id
	hint_label.text = text
	hint_label.reset_size()
	var area := left_area.get_global_rect()
	hint_label.position = Vector2(area.position.x + (area.size.x - hint_label.size.x) / 2.0, area.position.y + area.size.y * 0.30) - fx_layer.global_position
	hint_label.visible = true
	await _wait(2.4)
	if my == _hint_id and is_inside_tree():
		hint_label.visible = false


# ─────────────────────────────── 팝업 ───────────────────────────────

func _modal() -> VBoxContainer:
	_clear(overlay)
	overlay.visible = true
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.78)
	overlay.add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	overlay.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 18)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(v)
	return v


func _show_mulligan() -> void:
	var me: PlayerState = game.players[ME]
	var v := _modal()
	var title := _label("시작 손패", 48, Art.COL_TEXT, true)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)
	var who := "내가 선공입니다 (손패 4장)" if game.first == ME else "상대가 선공입니다 (나는 손패 5장 + 골드 2)"
	var sub := _label("바꾸고 싶은 카드를 누르세요 (한 번만 교체)\n" + who, 22, Art.COL_SUB)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(sub)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 16)
	v.add_child(row)
	mull_marks = {}
	for i in me.hand.size():
		var c: CardInst = me.hand[i]
		var cv: CardView = CardView.new().setup(c.data, c, "detail")
		cv.pressed.connect(_on_mull_card.bind(i))
		row.add_child(cv)
	var ok := Button.new()
	ok.text = "확정"
	ok.custom_minimum_size = Vector2(260, 64)
	ok.add_theme_font_size_override("font_size", 28)
	Art.accent_button(ok, Color("#16a34a"))
	ok.pressed.connect(_on_mull_confirm)
	var okc := CenterContainer.new()
	okc.add_child(ok)
	v.add_child(okc)


func _on_mull_card(view, i: int) -> void:
	if mull_marks.has(i):
		mull_marks.erase(i)
		view.set_highlight("")
	else:
		mull_marks[i] = true
		view.set_highlight("mark")


func _on_mull_confirm() -> void:
	if net != null:
		_mull_local = mull_marks.keys()
		net.send_mulligan(_mull_local)
		overlay.visible = false
		_clear(overlay)
		_show_hint("상대가 시작 손패를 고르는 중...")
		_try_apply_mulligans()
		return
	game.mulligan(ME, mull_marks.keys())
	overlay.visible = false
	_clear(overlay)
	_refresh()
	if game.phase == "play" and game.current == OP:
		_run_ai()
	else:
		_banner("내 턴", Art.COL_OK)
		_on_my_turn_start()


func _show_game_over() -> void:
	coach.visible = false
	var me: PlayerState = game.players[ME]
	var op: PlayerState = game.players[OP]
	var v := _modal()
	var text := "무승부"
	var col := Art.COL_SEL
	if game.winner == ME:
		text = "승리!"
		col = Art.COL_OK
	elif game.winner == OP:
		text = "패배..."
		col = Art.COL_TARGET
	var title := _label(text, 96, col, true)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)
	var sub := _label("내 턴 %d번 · 내 체력 %d · 상대 체력 %d" % [me.turn_count, me.hp, op.hp], 24, Art.COL_SUB)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(sub)
	if net == null and not tutorial_mode and game.winner == ME:
		var reward := Profile.win_reward(ai_level)
		var total := Profile.add_crystals(reward)
		var rl := _label("마석 +%d 획득! (보유 %d)\n메인 메뉴의 [영웅 뽑기]에서 마석 %d으로 새 영웅을 뽑을 수 있어요" % [reward, total, Profile.pull_cost()], 26, Color("#67e8f9"), true)
		rl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(rl)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 20)
	v.add_child(row)
	var again := Button.new()
	again.text = "다시 하기"
	again.custom_minimum_size = Vector2(240, 64)
	again.add_theme_font_size_override("font_size", 26)
	Art.accent_button(again, Color("#16a34a"))
	again.pressed.connect(func(): restart_requested.emit())
	if net == null:
		row.add_child(again)
	var menu := Button.new()
	menu.text = "메인 메뉴"
	menu.custom_minimum_size = Vector2(240, 64)
	menu.add_theme_font_size_override("font_size", 26)
	menu.pressed.connect(func(): exit_to_menu.emit())
	row.add_child(menu)


# ─────────────────────────────── 튜토리얼 / 도움말 ───────────────────────────────

func _on_my_turn_start() -> void:
	var me: PlayerState = game.players[ME]
	if me.turn_count == 1:
		_queue_tip("basics", "카드를 누르면 오른쪽 아래에서 [사용하기] / [버리기]를 고를 수 있어요.\n초록 테두리 = 지금 쓸 수 있는 카드, 공격할 수 있는 유닛이에요.\n유닛으로 공격하려면: 내 유닛 → 상대 영웅(또는 유닛) 순서로 누르세요.")
	elif me.turn_count == 2:
		_queue_tip("pitch", "남는 카드는 [버리기]로 골드 1로 바꾸세요. 손패는 매 턴 5장까지 다시 채워져요.\n골드로 시장에서 좋은 카드를 사면 덱이 강해져요. 내 영웅과 같은 진영 카드는 1골드 할인!")
	elif me.turn_count == 12:
		_queue_tip("collapse", "다음 턴부터 '붕괴'가 시작돼요. 13번째 턴부터 매 턴 시작할 때 영웅이 1, 2, 3… 피해를 받아요.\n게임이 너무 길어지지 않게 하는 규칙이에요. 체력이 많은 쪽이 유리해요!")


func _queue_tip(key: String, text: String) -> void:
	if tutorial != null and tutorial.active:
		return
	if fast or not Settings.tips_on():
		return
	if Settings.tip_seen(key) or _tips_queued.has(key):
		return
	_tips_queued[key] = true
	_tips.append([key, text])
	_update_coach()


func _mark_basic_tips() -> void:
	for k in ["basics", "pitch", "taunt", "sleep"]:
		Settings.mark_tip(k)


func _update_coach() -> void:
	if coach == null or game == null:
		return
	var want := false
	if tutorial != null and tutorial.active:
		var st := tutorial.current()
		if not st.is_empty() and game.phase == "play" and game.current == ME and not busy:
			want = true
			coach_title.text = tutorial.step_label()
			coach_text.text = st["text"]
			coach_btn.visible = st.get("next", false)
			coach_btn.text = "다음"
			coach_skip.visible = true
	elif not _tips.is_empty() and game.phase == "play" and not overlay.visible:
		want = true
		coach_title.text = "도움말"
		coach_text.text = _tips[0][1]
		coach_btn.visible = true
		coach_btn.text = "알겠어요"
		coach_skip.visible = false
	coach.visible = want
	if want:
		_place_coach.call_deferred()


func _place_coach() -> void:
	coach.reset_size()
	var area := left_area.get_global_rect()
	var avoid := _focus_rect(_focus_key())
	# 후보 위치: 가운데 줄(가운데/왼쪽/오른쪽) → 위 → 아래. 눌러야 할 곳을 가리지 않는 첫 자리.
	var mid_y := area.position.y + area.size.y * 0.36 - coach.size.y / 2.0
	var cx := area.position.x + (area.size.x - coach.size.x) / 2.0
	var cands := [
		Vector2(cx, mid_y),
		Vector2(area.position.x + 4.0, mid_y),
		Vector2(area.end.x - coach.size.x - 4.0, mid_y),
		Vector2(cx, area.position.y + 112.0),
		Vector2(cx, area.end.y - coach.size.y - 8.0),
	]
	var pos: Vector2 = cands[0]
	if avoid.size != Vector2.ZERO:
		for cand in cands:
			var p: Vector2 = cand
			if not Rect2(p, coach.size).intersects(avoid.grow(8)):
				pos = p
				break
	coach.position = pos - fx_layer.global_position


func _on_coach_next() -> void:
	if tutorial != null and tutorial.active and tutorial.current().get("next", false):
		tutorial.advance()
		if not tutorial.active:
			_banner("튜토리얼 완료!", Art.COL_OK)
			_mark_basic_tips()
	elif not _tips.is_empty():
		var t: Array = _tips.pop_front()
		Settings.mark_tip(t[0])
	_refresh()
	_update_coach()


func _on_coach_skip() -> void:
	if tutorial != null and tutorial.active:
		tutorial.finish()
		_mark_basic_tips()
		_show_hint("튜토리얼을 건너뛰었어요. 이제 자유롭게 플레이하세요!")
	_refresh()
	_update_coach()


## 튜토리얼에서 지금 눌러야 할 곳
func _focus_key() -> String:
	if tutorial == null or not tutorial.active or game == null:
		return ""
	if game.phase != "play" or game.current != ME or busy:
		return ""
	var st := tutorial.current()
	if st.is_empty():
		return ""
	if st.get("next", false) or st.get("free", false):
		return st.get("focus", "")
	var ex: Dictionary = st["expect"]
	var me: PlayerState = game.players[ME]
	match ex["type"]:
		"play", "pitch":
			if not targeting.is_empty():
				return "op_units" if ex.get("target", "") == "op_unit" else "op_hero"
			var i := int(sel.get("index", -1))
			if sel.get("kind", "") == "hand" and i >= 0 and i < me.hand.size() and me.hand[i].id == ex["card"]:
				return "btn:use" if ex["type"] == "play" else "btn:pitch"
			return "hand_card:" + ex["card"]
		"buy":
			var mi := int(sel.get("index", -1))
			if sel.get("kind", "") == "market" and mi >= 0 and mi < game.market.size() and game.market[mi] == ex["card"]:
				return "btn:buy"
			return "market:" + ex["card"]
		"attack":
			return "op_hero" if not targeting.is_empty() else "my_unit"
		"power":
			return "op_units" if not targeting.is_empty() else "power"
		"end":
			return "end"
	return ""


func _focus_rect(key: String) -> Rect2:
	match key:
		"":
			return Rect2()
		"op_hero":
			return op_hero_view.get_global_rect()
		"me_info":
			return me_info.get_global_rect()
		"hand":
			return hand_area.get_global_rect()
		"end":
			return end_btn.get_global_rect()
		"power":
			return power_btn.get_global_rect()
		"my_unit", "op_units":
			var box := me_board if key == "my_unit" else op_board
			var r := Rect2()
			for c in box.get_children():
				if c is CardView:
					r = c.get_global_rect() if r.size == Vector2.ZERO else r.merge(c.get_global_rect())
					if key == "my_unit":
						break
			return r
	if key.begins_with("hand_card:"):
		var id := key.substr(10)
		for c in hand_area.get_children():
			if c is CardView and c.inst != null and c.inst.id == id:
				return c.get_global_rect()
	elif key.begins_with("market:"):
		var mid := key.substr(7)
		for c in market_box.get_children():
			if c is CardView and c.data.get("id", "") == mid:
				return c.get_global_rect()
	elif key.begins_with("btn:"):
		var b = _detail_btns.get(key.substr(4), null)
		if b != null and is_instance_valid(b):
			return b.get_global_rect()
	return Rect2()


# ─────────────────────────────── 카드 이동 연출 ───────────────────────────────

func _center(c: Control) -> Vector2:
	return c.global_position + c.size / 2.0


func _hand_view_by_uid(uid: int) -> CardView:
	for v in hand_area.get_children():
		if v is CardView and v.inst != null and v.inst.uid == uid:
			return v
	return null


## 카드 한 장이 a → b 로 날아가는 연출. flip 이면 도착하면서 뒷면 → 앞면.
func _fly(data: Dictionary, mode: String, a: Vector2, b: Vector2, s0: float, s1: float,
		delay: float, dur: float, flip: bool, done: Callable = Callable()) -> void:
	var g: CardView = CardView.new().setup(data, null, mode)
	g.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fx_layer.add_child(g)
	g.position = a - g.size / 2.0 - fx_layer.global_position
	g.scale = Vector2(s0, s0)
	g.modulate.a = 0.0
	var tw := g.create_tween()
	tw.tween_interval(delay)
	tw.tween_property(g, "modulate:a", 1.0, 0.04)
	tw.tween_property(g, "position", b - g.size / 2.0 - fx_layer.global_position, dur).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(g, "scale", Vector2(s1, s1), dur)
	if flip:
		tw.tween_property(g, "scale:x", 0.0, 0.09)
		tw.tween_callback(g.set_mode.bind("hand"))
		tw.tween_property(g, "scale:x", s1, 0.09)
	tw.tween_callback(_fly_done.bind(g, done))


func _fly_done(g: Control, done: Callable) -> void:
	if done.is_valid():
		done.call()
	g.queue_free()


func _reveal_drawn(uid: int) -> void:
	_anim_hidden.erase(uid)
	var real := _hand_view_by_uid(uid)
	if real != null:
		real.modulate.a = 1.0


func _fx_draw(fx: Dictionary, delay: float) -> void:
	var uid := int(fx["uid"])
	if fast:
		_anim_hidden.erase(uid)
		return
	if int(fx["player"]) == OP:
		var r := op_info.get_global_rect()
		_fly(fx["data"], "back", r.position + Vector2(20, r.size.y / 2.0), r.position + Vector2(140, 10), 0.25, 0.25, delay, 0.3, false)
		return
	var from := _center(deck_pile)
	if fx["burn"]:
		_fly(fx["data"], "back", from, _center(discard_pile), 0.5, 0.45, delay, 0.45, true)
		_show_hint("손패가 가득 차서 '%s'이(가) 버려졌어요 (최대 10장)" % fx["data"].get("name", ""))
		return
	var v := _hand_view_by_uid(uid)
	var to := _center(v) if v != null else _center(hand_area)
	_fly(fx["data"], "back", from, to, 0.55, 1.0, delay, 0.32, true, _reveal_drawn.bind(uid))


func _fx_shuffle() -> void:
	if fast:
		return
	_show_hint("덱이 비어서 버린 더미를 섞어 새 덱을 만들어요!")
	for i in 4:
		_fly({}, "back", _center(discard_pile), _center(deck_pile), 0.45, 0.45, i * 0.07, 0.3, false)


func _fx_pitch(fx: Dictionary) -> void:
	if fast:
		return
	if int(fx["player"]) == ME:
		var from: Vector2 = _pos_cache.get("c%d" % int(fx["uid"]), _center(hand_area))
		_fly(fx["data"], "hand", from, _center(discard_pile), 1.0, 0.45, 0.0, 0.3, false)
		_float_text(_center(me_info) + Vector2(0, -10), "+1 골드", Art.COL_GOLD)
	else:
		var r := op_info.get_global_rect()
		_fly(fx["data"], "hand", r.position + Vector2(140, 20), r.position + Vector2(200, 60), 0.3, 0.2, 0.0, 0.3, false)


func _fx_buy(fx: Dictionary) -> void:
	if fast:
		return
	var from: Vector2 = _pos_cache.get("m%d" % int(fx["slot"]), _center(market_box))
	var to := _center(discard_pile) if int(fx["player"]) == ME else op_info.get_global_rect().get_center()
	_fly(fx["data"], "hand", from, to, 0.6, 0.4, 0.0, 0.45, false)


# ─────────────────────────────── 덱 / 버린 더미 목록 ───────────────────────────────

func _on_pile_pressed(_v: Control, which: String) -> void:
	if not _drag.is_empty():
		return
	targeting = {}
	sel = {"kind": "pile", "which": which}
	_refresh()


func _pile_text(which: String) -> String:
	var me: PlayerState = game.players[ME]
	var cards: Array = me.deck if which == "deck" else me.discard
	var counts := {}
	for c in cards:
		counts[c.display_name()] = counts.get(c.display_name(), 0) + 1
	var names: Array = counts.keys()
	names.sort()
	var lines: Array = []
	for n in names:
		lines.append("· %s × %d" % [n, counts[n]])
	var head := "내 덱 %d장 (뽑는 순서는 비밀)" % cards.size() if which == "deck" else "내 버린 더미 %d장\n(덱이 떨어지면 섞여서 덱이 돼요)" % cards.size()
	if lines.is_empty():
		lines.append("(비어 있음)")
	return head + "\n\n" + "\n".join(PackedStringArray(lines))


# ─────────────────────────────── 끌어다 놓기 ───────────────────────────────

func _on_drag_start(view: Control, pos: Vector2, kind: String, index: int) -> void:
	if not _idle():
		return
	targeting = {}
	var d := {"kind": kind, "index": index, "view": view, "targets": [], "arrow": false}
	match kind:
		"hand":
			var c: CardInst = game.players[ME].hand[index]
			if c.data.has("target"):
				d["targets"] = game.valid_targets(ME, c.data["target"])
				d["arrow"] = true
		"unit":
			d["targets"] = game.attack_targets(ME)
			d["arrow"] = true
	_drag = d
	if d["arrow"]:
		view.set_highlight("sel")
	else:
		view.modulate.a = 0.35
		var data: Dictionary = view.data
		drag_ghost = CardView.new().setup(data, view.inst, "hand")
		drag_ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
		drag_ghost.scale = Vector2(0.85, 0.85)
		drag_ghost.modulate.a = 0.92
		fx_layer.add_child(drag_ghost)
	# 놓을 수 있는 곳 표시
	for t in d["targets"]:
		var tv := _view_for_target(t)
		if tv != null:
			tv.set_highlight("target")
	if kind == "hand":
		discard_pile.set_highlight("sel")
		if not d["arrow"]:
			_show_drop_zone("여기에 놓으면 사용")
	elif kind == "market":
		_show_drop_zone("여기에 놓으면 구매")
	var hints := {
		"hand": "위쪽에 놓으면 사용 · 오른쪽 '버린 더미'에 놓으면 골드 +1",
		"unit": "공격할 대상 위에 놓으세요",
		"market": "왼쪽 전장으로 끌어오면 구매",
	}
	if d["arrow"] and kind == "hand":
		_show_hint("대상 위에 놓으면 사용 · '버린 더미'에 놓으면 골드 +1")
	else:
		_show_hint(hints[kind])
	_on_drag_move(view, pos)


func _on_drag_move(view: Control, pos: Vector2) -> void:
	if _drag.is_empty():
		return
	if drag_ghost != null:
		drag_ghost.position = pos - drag_ghost.size / 2.0 - fx_layer.global_position
	if _drag["arrow"]:
		var col := Color("#f43f5e") if _drag["kind"] == "unit" else Color("#facc15")
		drag_arrow.show_arrow(_center(view), pos, col)


func _on_drag_end(view: Control, pos: Vector2) -> void:
	if _drag.is_empty():
		return
	var d := _drag
	_drag = {}
	_end_drag_visuals(view)
	var kind: String = d["kind"]
	var index: int = d["index"]
	var action := {}
	match kind:
		"hand":
			if _over_discard(pos):
				action = {"type": "pitch", "hand": index}
			elif d["arrow"]:
				var t := _target_at(pos)
				if not t.is_empty() and Game.target_in(d["targets"], t):
					action = {"type": "play", "hand": index, "target": t}
				elif _in_play_zone(pos):
					_show_hint("그 대상에는 쓸 수 없어요. 빛나는 대상 위에 놓으세요")
			elif _in_play_zone(pos):
				action = {"type": "play", "hand": index}
		"unit":
			var t2 := _target_at(pos)
			if not t2.is_empty() and Game.target_in(d["targets"], t2):
				action = {"type": "attack", "unit": index, "target": t2}
			elif not t2.is_empty() and int(t2["side"]) == OP and int(t2["slot"]) < 0:
				_show_hint("도발 유닛이 있어서 영웅을 공격할 수 없어요. 도발 유닛부터 공격하세요!")
			elif not t2.is_empty():
				_show_hint("그 대상은 공격할 수 없어요")
		"market":
			if left_area.get_global_rect().has_point(pos):
				action = {"type": "buy", "market": index}
	if action.is_empty():
		_refresh()
		return
	var err := ""
	match action["type"]:
		"play":
			err = game.play_error(ME, index)
		"buy":
			err = game.buy_error(ME, index)
	if err != "":
		_show_hint(err)
		_refresh()
		return
	sel = {}
	_do(action)


func _end_drag_visuals(view: Control) -> void:
	if drag_ghost != null:
		drag_ghost.queue_free()
		drag_ghost = null
	drag_arrow.hide_arrow()
	drop_zone.visible = false
	discard_pile.set_highlight("")
	if is_instance_valid(view):
		view.modulate.a = 1.0


func _show_drop_zone(text: String) -> void:
	var r := Rect2(op_board.global_position, Vector2(left_area.size.x, me_board.get_global_rect().end.y - op_board.global_position.y))
	drop_zone.position = r.position - fx_layer.global_position
	drop_zone.size = r.size
	drop_zone_label.text = text
	drop_zone.visible = true


func _over_discard(pos: Vector2) -> bool:
	return discard_pile.get_global_rect().grow(24).has_point(pos)


func _in_play_zone(pos: Vector2) -> bool:
	var la := left_area.get_global_rect()
	return la.has_point(pos) and pos.y < hand_row.global_position.y


## 화면 좌표에 있는 영웅/유닛 → 대상 {"side","slot"}
func _target_at(pos: Vector2) -> Dictionary:
	if op_hero_view.get_global_rect().has_point(pos):
		return {"side": OP, "slot": -1}
	if me_hero_view.get_global_rect().has_point(pos):
		return {"side": ME, "slot": -1}
	for box in [op_board, me_board]:
		for v in box.get_children():
			if v is CardView and v.has_meta("slot") and v.get_global_rect().grow(6).has_point(pos):
				return {"side": int(v.get_meta("side")), "slot": int(v.get_meta("slot"))}
	return {}


func _view_for_target(t: Dictionary) -> Control:
	if int(t["slot"]) < 0:
		return op_hero_view if int(t["side"]) == OP else me_hero_view
	var box := op_board if int(t["side"]) == OP else me_board
	for v in box.get_children():
		if v is CardView and v.has_meta("slot") and int(v.get_meta("slot")) == int(t["slot"]):
			return v
	return null


# ─────────────────────────────── 온라인 대전 ───────────────────────────────

func _ints(a: Array) -> Array:
	var out: Array = []
	for x in a:
		out.append(int(x))
	return out


func _on_net_mulligan(idx: Array) -> void:
	_mull_remote = _ints(idx)
	_try_apply_mulligans()


## 두 사람 시작 손패 교체를 같은 순서(방장 → 손님)로 적용해야 두 기기의 게임이 똑같이 흘러간다
func _try_apply_mulligans() -> void:
	if _mull_local == null or _mull_remote == null or game.phase != "mulligan":
		return
	for pi in [0, 1]:
		var idx: Array = _mull_local if pi == ME else _mull_remote
		game.mulligan(pi, _ints(idx))
	_refresh()
	_flush_fx()
	if game.phase == "play" and game.current == ME:
		_banner("내 턴", Art.COL_OK)
		_start_turn_timer()
		_on_my_turn_start()
	else:
		_begin_remote_turn()


func _start_turn_timer() -> void:
	if net != null:
		_turn_deadline = Time.get_ticks_msec() + TURN_TIME * 1000


func _begin_remote_turn() -> void:
	busy = true
	_turn_deadline = 0
	_refresh()
	_banner("상대 턴", Art.COL_TARGET)
	_update_coach()


func _on_net_action(a: Dictionary, state_hash: int) -> void:
	if game == null or game.phase != "play" or _over_shown:
		return
	if game.current != OP:
		_desync("상대 차례가 아닌데 행동이 왔어요")
		return
	_snapshot_positions()
	var ok := game.apply_action(OP, a)
	if not ok or (state_hash != 0 and game.state_hash() != state_hash):
		_desync("상대의 행동을 적용한 결과가 달라요")
		return
	_refresh()
	_flush_fx()
	if game.phase == "over":
		busy = false
		_check_over()
	elif game.current == ME:
		busy = false
		_refresh()
		_banner("내 턴", Art.COL_OK)
		_start_turn_timer()
		_on_my_turn_start()
		_update_coach()


func _on_net_left(reason: String) -> void:
	if _over_shown:
		return
	_over_shown = true
	busy = true
	var v := _modal()
	var text := "상대가 게임을 나갔어요" if reason == "left" else "상대와 연결이 끊겼어요"
	var title := _label(text, 56, Art.COL_SEL, true)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)
	var sub := _label("이번 판은 내 승리로 처리돼요", 26, Art.COL_SUB)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(sub)
	_menu_button(v)


func _on_net_link(ok: bool) -> void:
	link_label.text = "" if ok else "연결이 불안정해요... 다시 연결하는 중"
	link_label.visible = not ok


func _desync(why: String) -> void:
	if _over_shown:
		return
	_over_shown = true
	busy = true
	print("DESYNC: ", why)
	var v := _modal()
	var title := _label("동기화 오류", 56, Art.COL_TARGET, true)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)
	var sub := _label("두 기기의 게임 화면이 서로 달라졌어요. 이번 판은 여기서 끝낼게요.\n(" + why + ")", 24, Art.COL_SUB)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(sub)
	_menu_button(v)


func _menu_button(v: VBoxContainer) -> void:
	var menu := Button.new()
	menu.text = "메인 메뉴"
	menu.custom_minimum_size = Vector2(260, 64)
	menu.add_theme_font_size_override("font_size", 26)
	menu.pressed.connect(func(): exit_to_menu.emit())
	var c := CenterContainer.new()
	c.add_child(menu)
	v.add_child(c)
