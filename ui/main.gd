extends Control
## 앱 진입점: 테마 설정, 메인 메뉴, 대전 화면 전환.

const Art = preload("res://ui/art.gd")
const CardDB = preload("res://core/card_db.gd")
const Battle = preload("res://ui/battle.gd")
const Settings = preload("res://ui/settings.gd")
const NetMatch = preload("res://net/net_match.gd")
const HeroCard = preload("res://ui/hero_card.gd")
const Profile = preload("res://ui/profile.gd")
const Gacha = preload("res://ui/gacha.gd")
const AI = preload("res://ai/simple_ai.gd")

const VERSION := "알파 v0.1"

var selected_hero := "fire"
var ai_level := 1
var screen: Control = null
## 온라인 대전 연결 (로비 → 대전까지 유지)
var net: NetMatch = null
var _lobby_status: Label = null
var _lobby_code: Label = null
var _lobby_code_box: VBoxContainer = null
var _lobby_members: Label = null
var _lobby_start: Button = null
var _lobby_mode_btns := {}
var _hero_cards := {}
var _hero_detail: HBoxContainer = null
var _start_btn: Button = null
var _online_btn: Button = null
var _level_btns: Array = []
var _level_desc: Label = null
## 대전 방식: "1v1", "ffa3" (1:1:1), "2v2"
var mode := "1v1"
var _mode_btns := {}
const MODES := [["1v1", "1 : 1"], ["ffa3", "1 : 1 : 1"], ["2v2", "2 : 2 (팀)"]]


func _ready() -> void:
	CardDB.load_all()
	selected_hero = str(Settings.get_value("selected_hero", "fire"))
	ai_level = clampi(int(Settings.get_value("ai_level", 1)), 0, AI.DIFFICULTIES.size() - 1)
	mode = str(Settings.get_value("mode", "1v1"))
	if not CardDB.heroes.has(selected_hero) or not Profile.is_owned(selected_hero):
		selected_hero = "fire"
	theme = Art.make_theme()
	get_tree().set_quit_on_go_back(false)
	_show_menu()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		if screen is Battle or net != null:
			_leave_online()
			_show_menu()
		else:
			get_tree().quit()


func _set_screen(c: Control) -> void:
	if screen != null:
		screen.queue_free()
	screen = c
	add_child(c)
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


# ─────────────────────────────── 메인 메뉴 ───────────────────────────────

func _show_menu() -> void:
	var root := Control.new()
	_set_screen(root)
	var bg := ColorRect.new()
	bg.color = Art.COL_BG
	root.add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	root.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	center.add_child(v)

	var title := _label("아르카나 듀얼", 80, Art.COL_TEXT, true)
	v.add_child(title)
	var st: Dictionary = Engine.get_meta("update_status", {})
	var build := int(st.get("current", 0))
	v.add_child(_label("%s%s · 1:1 덱빌딩 결투" % [VERSION, (" · 빌드 %d" % build) if build > 0 else ""], 26, Art.COL_SUB))
	var own := Profile.owned()
	v.add_child(_label("영웅을 고르세요  (%d / %d명 보유 · 잠긴 영웅은 [영웅 뽑기]로 얻어요)" % [own.size(), CardDB.hero_order.size()], 26, Art.COL_TEXT, true))

	var heroes := HBoxContainer.new()
	heroes.alignment = BoxContainer.ALIGNMENT_CENTER
	heroes.add_theme_constant_override("separation", 10)
	v.add_child(heroes)
	_hero_cards.clear()
	for hid in CardDB.hero_order:
		var hc: HeroCard = HeroCard.new().setup(hid, Vector2(132, 172), not own.has(hid))
		hc.pressed.connect(_on_hero_card.bind(hid))
		heroes.add_child(hc)
		_hero_cards[hid] = hc
	var dp := PanelContainer.new()
	dp.custom_minimum_size = Vector2(1300, 150)
	var dpc := CenterContainer.new()
	dpc.add_child(dp)
	v.add_child(dpc)
	_hero_detail = HBoxContainer.new()
	_hero_detail.add_theme_constant_override("separation", 24)
	dp.add_child(_hero_detail)

	var lv := HBoxContainer.new()
	lv.alignment = BoxContainer.ALIGNMENT_CENTER
	lv.add_theme_constant_override("separation", 12)
	v.add_child(lv)
	lv.add_child(_label("상대 난이도", 24, Art.COL_SUB))
	_level_btns.clear()
	for i in AI.DIFFICULTIES.size():
		var b := Button.new()
		b.text = AI.DIFFICULTIES[i]["name"]
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(110, 52)
		b.add_theme_font_size_override("font_size", int(21 * Art.ts()))
		if i >= 4:
			b.add_theme_color_override("font_color", Color("#fca5a5"))
		b.pressed.connect(_on_level.bind(i))
		lv.add_child(b)
		_level_btns.append(b)
	_level_desc = _label("", 19, Art.COL_SUB)
	v.add_child(_level_desc)
	_on_level(ai_level)

	var mr := HBoxContainer.new()
	mr.alignment = BoxContainer.ALIGNMENT_CENTER
	mr.add_theme_constant_override("separation", 12)
	v.add_child(mr)
	mr.add_child(_label("대전 방식", 24, Art.COL_SUB))
	_mode_btns.clear()
	for pair in MODES:
		var mb := Button.new()
		mb.text = pair[1]
		mb.toggle_mode = true
		mb.custom_minimum_size = Vector2(170, 52)
		mb.pressed.connect(_on_mode.bind(pair[0]))
		mr.add_child(mb)
		_mode_btns[pair[0]] = mb
	mr.add_child(_label("  (1:1:1 = 셋이 각자, 2:2 = 나 + 팀원 vs 둘)", 18, Art.COL_SUB))
	_on_mode(mode)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 18)
	v.add_child(row)
	var tut := Button.new()
	tut.text = "튜토리얼"
	tut.custom_minimum_size = Vector2(240, 76)
	tut.add_theme_font_size_override("font_size", 28)
	Art.accent_button(tut, Color("#ca8a04"))
	tut.pressed.connect(_start_tutorial)
	row.add_child(tut)
	var start := Button.new()
	start.text = "게임 시작"
	start.custom_minimum_size = Vector2(280, 76)
	start.add_theme_font_size_override("font_size", 32)
	Art.accent_button(start, Color("#16a34a"))
	start.pressed.connect(_start_battle)
	row.add_child(start)
	_start_btn = start
	var online := Button.new()
	online.text = "온라인 대전"
	online.custom_minimum_size = Vector2(240, 76)
	online.add_theme_font_size_override("font_size", 28)
	Art.accent_button(online, Color("#2563eb"))
	online.pressed.connect(_show_online_lobby)
	row.add_child(online)
	_online_btn = online
	var gacha := Button.new()
	gacha.text = "영웅 뽑기\n마석 %d" % Profile.crystals()
	gacha.custom_minimum_size = Vector2(220, 76)
	gacha.add_theme_font_size_override("font_size", 22)
	Art.accent_button(gacha, Color("#7c3aed"))
	gacha.pressed.connect(_show_gacha)
	row.add_child(gacha)
	var rules := Button.new()
	rules.text = "게임 방법"
	rules.custom_minimum_size = Vector2(200, 76)
	rules.add_theme_font_size_override("font_size", 26)
	rules.pressed.connect(_show_rules)
	row.add_child(rules)
	if not OS.has_feature("mobile") and not OS.has_feature("web"):
		var quit := Button.new()
		quit.text = "종료"
		quit.custom_minimum_size = Vector2(140, 76)
		quit.add_theme_font_size_override("font_size", 26)
		quit.pressed.connect(func(): get_tree().quit())
		row.add_child(quit)

	var opt := HBoxContainer.new()
	opt.alignment = BoxContainer.ALIGNMENT_CENTER
	opt.add_theme_constant_override("separation", 16)
	v.add_child(opt)
	var tips := CheckButton.new()
	tips.text = "게임 중 도움말 팁"
	tips.add_theme_font_size_override("font_size", 20)
	tips.button_pressed = Settings.tips_on()
	tips.toggled.connect(func(on: bool): Settings.set_value("tips_on", on))
	opt.add_child(tips)
	var reset := Button.new()
	reset.text = "팁 다시 보기"
	reset.add_theme_font_size_override("font_size", 18)
	reset.pressed.connect(func():
		Settings.reset_tips()
		reset.text = "팁을 처음부터 다시 보여 줄게요")
	opt.add_child(reset)
	opt.add_child(_label("   글자 크기", 20, Art.COL_SUB))
	for pair in [["보통", 1.0], ["크게", 1.15], ["아주 크게", 1.3]]:
		var tb := Button.new()
		tb.text = pair[0]
		tb.toggle_mode = true
		tb.button_pressed = absf(Art.ts() - float(pair[1])) < 0.01
		tb.add_theme_font_size_override("font_size", 18)
		tb.pressed.connect(_on_text_scale.bind(float(pair[1])))
		opt.add_child(tb)
	if not bool(Settings.get_value("tutorial_done", false)):
		v.add_child(_label("처음이라면 [튜토리얼]부터 해 보세요! (5분)", 22, Art.COL_SEL, true))
	_add_update_row(v, st)
	v.add_child(_label("아이콘: game-icons.net (CC BY 3.0) · 글꼴: Pretendard (OFL 1.1)", 15, Color("#5b6272")))
	_update_hero_panels()


## 자동 업데이트 상태 표시 (boot.gd 가 넘겨준 정보)
func _add_update_row(v: VBoxContainer, st: Dictionary) -> void:
	var state: String = st.get("state", "")
	var text := ""
	var col := Art.COL_SUB
	match state:
		"latest":
			text = "최신 버전이에요 (자동 업데이트 켜짐)"
		"updated":
			text = "새 업데이트를 받아 적용했어요! (빌드 %d)" % int(st.get("current", 0))
			col = Art.COL_OK
		"offline":
			text = "인터넷에 연결되지 않아 업데이트를 확인하지 못했어요"
		"failed":
			text = "업데이트를 받지 못했어요. 다음에 켤 때 다시 시도해요"
			col = Art.COL_TARGET
	if state == "need_install":
		var row := HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_theme_constant_override("separation", 14)
		row.add_child(_label("새 버전(빌드 %d)은 앱을 새로 설치해야 해요" % int(st.get("remote", 0)), 20, Art.COL_SEL, true))
		var b := Button.new()
		b.text = "새 버전 받기"
		b.add_theme_font_size_override("font_size", 20)
		Art.accent_button(b, Color("#ca8a04"))
		var url: String = st.get("url", "")
		b.pressed.connect(func(): OS.shell_open(url))
		row.add_child(b)
		v.add_child(row)
	elif text != "":
		v.add_child(_label(text, 18, col))


func _update_hero_panels() -> void:
	for hid in _hero_cards:
		_hero_cards[hid].selected = hid == selected_hero
	if _hero_detail == null or not is_instance_valid(_hero_detail):
		return
	for c in _hero_detail.get_children():
		c.queue_free()
	var hd: Dictionary = CardDB.heroes[selected_hero]
	var pd: Dictionary = CardDB.powers[hd["power"]]
	var locked := not Profile.is_owned(selected_hero)
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(440, 0)
	_hero_detail.add_child(left)
	var nm := _label("%s · %s" % [hd["name"], hd["title"]], 32, Art.COL_TEXT, true)
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	left.add_child(nm)
	var sub := _label("%s 진영 · %s" % [CardDB.FACTION_NAMES[hd["faction"]], HeroCard.RARITY_LABEL.get(hd.get("rarity", "basic"), "")], 20, Art.FACTION_ACCENT[hd["faction"]])
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	left.add_child(sub)
	var desc := _label(hd["desc"], 19, Art.COL_SUB)
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	left.add_child(desc)
	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(760, 0)
	_hero_detail.add_child(right)
	var pw := _label("영웅 능력 · %s (%d마나): %s" % [pd["name"], int(pd["cost"]), pd["text"]], 22, Art.COL_TEXT, true)
	pw.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	pw.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right.add_child(pw)
	var bonus: Array = []
	for bid in hd.get("bonus_cards", []):
		bonus.append(CardDB.cards[bid]["name"])
	var extra := "시작 덱: 기본 10장" + ((" + 전용 카드 '%s'" % ", ".join(PackedStringArray(bonus))) if not bonus.is_empty() else "")
	var bl := _label(extra, 19, Art.COL_SUB)
	bl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	right.add_child(bl)
	if locked:
		var lk := _label("잠긴 영웅이에요. [영웅 뽑기]에서 얻을 수 있어요. (지금은 AI 상대로만 만나요)", 20, Art.COL_SEL, true)
		lk.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		right.add_child(lk)
	if _start_btn != null and is_instance_valid(_start_btn):
		_start_btn.disabled = locked
		_online_btn.disabled = locked


func _on_hero_card(_v: Control, hid: String) -> void:
	selected_hero = hid
	if Profile.is_owned(hid):
		Settings.set_value("selected_hero", hid)
	_update_hero_panels()


func _show_gacha() -> void:
	var g := Gacha.new()
	g.closed.connect(_show_menu)
	_set_screen(g)


func _on_text_scale(v: float) -> void:
	Art.text_scale = v
	Settings.set_value("text_scale", v)
	theme = Art.make_theme()
	_show_menu()


func _on_mode(m: String) -> void:
	mode = m
	Settings.set_value("mode", m)
	for k in _mode_btns:
		if is_instance_valid(_mode_btns[k]):
			_mode_btns[k].button_pressed = k == m


## 자리별 영웅·팀 (나는 0번 자리). 다른 자리 영웅은 겹치지 않게 무작위
func seat_setup(m: String, me_hero: String) -> Array:
	var pool: Array = CardDB.hero_order.duplicate()
	pool.erase(me_hero)
	pool.shuffle()
	match m:
		"ffa3":
			return [[me_hero, pool[0], pool[1]], [0, 1, 2]]
		"2v2":
			# 차례: 나 → 상대 1 → 팀원 → 상대 2
			return [[me_hero, pool[0], pool[1], pool[2]], [0, 1, 0, 1]]
	return [[me_hero, pool[0]], [0, 1]]


func _on_level(i: int) -> void:
	ai_level = i
	Settings.set_value("ai_level", i)
	for k in _level_btns.size():
		if is_instance_valid(_level_btns[k]):
			_level_btns[k].button_pressed = k == i
	if _level_desc != null and is_instance_valid(_level_desc):
		_level_desc.text = AI.difficulty_text(i)


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


# ─────────────────────────────── 대전 ───────────────────────────────

func _start_tutorial() -> void:
	var b := Battle.new()
	b.my_hero = "fire"
	b.op_hero = "forest"
	b.tutorial_mode = true
	b.exit_to_menu.connect(_show_menu)
	b.restart_requested.connect(_start_battle)
	_set_screen(b)


func _start_battle() -> void:
	if not Profile.is_owned(selected_hero):
		selected_hero = "fire"
	var b := Battle.new()
	b.my_hero = selected_hero
	var setup := seat_setup(mode, selected_hero)
	b.op_hero = setup[0][1]
	if mode != "1v1":
		b.seat_heroes = setup[0]
		b.seat_teams = setup[1]
	b.ai_level = ai_level
	b.exit_to_menu.connect(_show_menu)
	b.restart_requested.connect(_start_battle)
	_set_screen(b)


# ─────────────────────────────── 게임 방법 ───────────────────────────────

func _show_rules() -> void:
	var layer := Control.new()
	add_child(layer)
	layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.8)
	layer.add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	layer.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(1100, 800)
	center.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	panel.add_child(v)
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.size_flags_vertical = Control.SIZE_EXPAND_FILL
	r.add_theme_font_size_override("normal_font_size", 22)
	r.add_theme_font_size_override("bold_font_size", 24)
	r.text = RULES_TEXT + "\n" + combo_list_text()
	v.add_child(r)
	var close := Button.new()
	close.text = "닫기"
	close.custom_minimum_size = Vector2(0, 60)
	close.pressed.connect(layer.queue_free)
	v.add_child(close)


const RULES_TEXT := """[b]목표[/b]
상대 영웅의 체력 25를 0으로 만들면 승리합니다.

[b]두 가지 자원[/b]
· [color=#60a5fa]마나[/color]: 매 턴 1씩 늘어납니다 (최대 10). 카드를 낼 때 씁니다.
· [color=#fbbf24]골드[/color]: 손패를 1장 버릴 때마다 +1. 시장에서 카드를 살 때 씁니다. 다음 턴으로 넘어갑니다 (최대 10).

[b]덱 키우기[/b]
· 모두 같은 스타터 덱 10장으로 시작합니다.
· 시장에서 산 카드는 내 버린 더미로 갑니다. 덱이 떨어지면 버린 더미를 섞어 다시 씁니다.
· 매 턴 손패를 5장까지 채웁니다. 그래서 남는 카드는 버려서 골드로 바꾸는 게 좋습니다.
· 내 영웅과 같은 진영 카드는 1골드 싸게 삽니다.
· [b]정리[/b] (2골드): 약한 카드를 게임에서 영구 제거합니다.

[b]전투[/b]
· 유닛은 낸 다음 턴부터 공격합니다 (돌진은 바로).
· 공격할 유닛을 누르고 대상을 누르세요. 도발 유닛이 있으면 그것부터 공격해야 합니다.
· 함정은 뒷면으로 놓았다가 상대 턴에 자동으로 발동합니다.
· 필드는 전장에 1장만 있고, 새 필드가 나오면 바뀝니다.

[b]붕괴[/b]
· 내 13번째 턴부터 매 턴 영웅이 1, 2, 3… 피해를 받습니다.

[b]시리즈와 조합[/b]
· 드래곤, 군주, 늑대 같은 [color=#facc15]시리즈[/color] 카드가 있습니다 (카드 종류 줄에 표시).
· 내 필드에 조건에 맞는 유닛이 모이면 [color=#facc15]조합[/color]이 결성됩니다. 결성될 때 효과가 1번 발동하고 (체력 증가 등),
  결성되어 있는 동안 영웅 능력 옆에 [b]조합 스킬[/b] 버튼이 생겨 턴마다 1번 쓸 수 있습니다.
· 조합에 든 유닛이 죽어 조건이 깨지면 조합도 풀립니다. 다시 모이면 다시 결성됩니다.

[b]마나와 골드 더 얻기[/b]
· 최대 마나 카드: 최대 마나를 올립니다. '최대 마나 한도'를 올리는 카드는 10을 넘어 15까지 키웁니다.
· '이번 턴에만 마나' 카드는 그 턴에만 마나를 더 줍니다.
· [b]약탈[/b] 유닛은 공격할 때마다 골드 +1. 금광 광부, 황금 군주처럼 턴마다 골드를 주는 카드도 있습니다.
· 레어 카드 중에는 일반 카드의 [b]상위 호환[/b]이 있습니다 (같은 비용에 더 강함).

[b]영웅 뽑기[/b]
· AI 대전에서 이기면 마석을 얻습니다 (쉬움 +30 ~ 얼티밋 +500). 마석 100으로 새 영웅을 뽑습니다.

[b]난이도[/b]
· 쉬움 · 보통 · 어려움 · 매우 어려움 · 헬 · 마스터 · 갓 · 얼티밋
· 어려움부터는 AI가 행동을 미리 해 보고 가장 좋은 수를 고릅니다.
· 매우 어려움부터는 AI에게 보너스가 붙습니다 (체력 30~50, 매 턴 골드·카드 추가, 시작 마나 추가).
· 이미 가진 영웅은 나오지 않습니다. 새 영웅은 시작 덱에 전용 카드 1장이 들어 있습니다."""


## 게임 방법 아래에 붙는 조합 목록
static func combo_list_text() -> String:
	var lines: Array = ["", "[b]조합 목록[/b]"]
	for k in CardDB.combos:
		var sk: Dictionary = k["skill"]
		lines.append("· [color=%s][b]%s[/b][/color] — %s → 결성: %s / 스킬 '%s'(%d마나): %s" % [k["color"], k["name"], k["cond"], k["form_text"], sk["name"], int(sk["cost"]), sk["text"]])
	return "\n".join(PackedStringArray(lines))


# ─────────────────────────────── 온라인 대전 로비 ───────────────────────────────

func _game_build() -> int:
	var st: Dictionary = Engine.get_meta("update_status", {})
	var b := int(st.get("current", 0))
	if b > 0:
		return b
	var v: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/version.json"))
	return int(v.get("build", 0)) if v is Dictionary else 0


func _leave_online() -> void:
	if net != null:
		net.leave()
		net.queue_free()
		net = null


func _new_net() -> void:
	_leave_online()
	net = NetMatch.new()
	net.game_build = _game_build()
	add_child(net)
	net.status_changed.connect(_on_net_status)
	net.lobby_changed.connect(_on_lobby_changed)
	net.matched.connect(_start_online_battle, CONNECT_DEFERRED)


func _on_net_status(t: String) -> void:
	if _lobby_status != null and is_instance_valid(_lobby_status):
		_lobby_status.text = t
	if _lobby_code != null and is_instance_valid(_lobby_code) and net != null and net.is_host and net.room != "":
		_lobby_code.text = net.room


func _copy_code() -> void:
	if net != null:
		DisplayServer.clipboard_set(net.room)


func _show_online_lobby() -> void:
	_leave_online()
	if not Profile.is_owned(selected_hero):
		selected_hero = "fire"
	var root := Control.new()
	_set_screen(root)
	var bg := ColorRect.new()
	bg.color = Art.COL_BG
	root.add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	root.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 22)
	center.add_child(v)
	v.add_child(_label("온라인 대전", 64, Art.COL_TEXT, true))
	var mr := HBoxContainer.new()
	mr.alignment = BoxContainer.ALIGNMENT_CENTER
	mr.add_theme_constant_override("separation", 12)
	v.add_child(mr)
	mr.add_child(_label("방 만들 때 대전 방식", 22, Art.COL_SUB))
	_lobby_mode_btns.clear()
	for pair in MODES:
		var mb := Button.new()
		mb.text = pair[1]
		mb.toggle_mode = true
		mb.custom_minimum_size = Vector2(170, 52)
		mb.pressed.connect(_on_lobby_mode.bind(pair[0]))
		mr.add_child(mb)
		_lobby_mode_btns[pair[0]] = mb
	_on_lobby_mode(mode)
	var hd: Dictionary = CardDB.heroes[selected_hero]
	v.add_child(_label("내 영웅: %s · %s  (메인 메뉴에서 바꿀 수 있어요)" % [hd["name"], hd["title"]], 24, Art.FACTION_ACCENT[hd["faction"]]))
	v.add_child(_label("무료 공개 서버로 연결해요. 가끔 느리거나 끊길 수 있어요. 모두 같은 빌드(최신 버전)여야 해요.\n한 턴 제한 시간은 90초. 다인전은 빈 자리를 AI가 채우고, 중간에 나간 사람 자리도 AI가 이어서 둬요.", 20, Art.COL_SUB))

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 30)
	v.add_child(row)
	var host_btn := Button.new()
	host_btn.text = "방 만들기"
	host_btn.custom_minimum_size = Vector2(260, 76)
	host_btn.add_theme_font_size_override("font_size", 28)
	Art.accent_button(host_btn, Color("#16a34a"))
	host_btn.pressed.connect(_on_host_pressed)
	row.add_child(host_btn)
	var join_box := HBoxContainer.new()
	join_box.add_theme_constant_override("separation", 10)
	row.add_child(join_box)
	var code_edit := LineEdit.new()
	code_edit.placeholder_text = "방 코드 5글자"
	code_edit.max_length = 5
	code_edit.custom_minimum_size = Vector2(240, 76)
	code_edit.add_theme_font_size_override("font_size", 30)
	code_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	join_box.add_child(code_edit)
	var join_btn := Button.new()
	join_btn.text = "참가"
	join_btn.custom_minimum_size = Vector2(150, 76)
	join_btn.add_theme_font_size_override("font_size", 28)
	Art.accent_button(join_btn, Color("#2563eb"))
	join_btn.pressed.connect(func(): _on_join_pressed(code_edit.text))
	code_edit.text_submitted.connect(func(t: String): _on_join_pressed(t))
	join_box.add_child(join_btn)

	_lobby_code_box = VBoxContainer.new()
	_lobby_code_box.visible = false
	v.add_child(_lobby_code_box)
	_lobby_code_box.add_child(_label("방 코드", 22, Art.COL_SUB))
	_lobby_code = _label("·····", 96, Art.COL_SEL, true)
	_lobby_code_box.add_child(_lobby_code)
	var copy := Button.new()
	copy.text = "코드 복사"
	copy.add_theme_font_size_override("font_size", 20)
	copy.pressed.connect(_copy_code)
	var cc := CenterContainer.new()
	cc.add_child(copy)
	_lobby_code_box.add_child(cc)
	_lobby_code_box.add_child(_label("친구에게 이 코드를 알려 주세요. 자리가 다 차면 바로 시작해요.", 22, Art.COL_TEXT))
	_lobby_start = Button.new()
	_lobby_start.text = "빈 자리는 AI로 채우고 지금 시작"
	_lobby_start.custom_minimum_size = Vector2(0, 60)
	_lobby_start.add_theme_font_size_override("font_size", 24)
	Art.accent_button(_lobby_start, Color("#16a34a"))
	_lobby_start.pressed.connect(func():
		if net != null:
			net.host_start())
	var sc := CenterContainer.new()
	sc.add_child(_lobby_start)
	_lobby_code_box.add_child(sc)

	_lobby_members = _label("", 22, Art.COL_TEXT)
	v.add_child(_lobby_members)

	_lobby_status = _label("", 24, Art.COL_SUB)
	v.add_child(_lobby_status)
	var back := Button.new()
	back.text = "뒤로"
	back.custom_minimum_size = Vector2(200, 60)
	back.add_theme_font_size_override("font_size", 24)
	back.pressed.connect(func():
		_leave_online()
		_show_menu())
	var bc := CenterContainer.new()
	bc.add_child(back)
	v.add_child(bc)


func _on_lobby_mode(m: String) -> void:
	_on_mode(m)
	for k in _lobby_mode_btns:
		if is_instance_valid(_lobby_mode_btns[k]):
			_lobby_mode_btns[k].button_pressed = k == m


func _on_lobby_changed() -> void:
	if net == null or _lobby_members == null or not is_instance_valid(_lobby_members):
		return
	var lines: Array = ["대전 방식: %s · %d / %d명" % [NetMatch.MODES[net.mode]["name"], net.members.size(), net.capacity()]]
	for i in net.capacity():
		if i < net.members.size():
			var hd: Dictionary = CardDB.heroes.get(str(net.members[i]["hero"]), CardDB.heroes["fire"])
			lines.append("%d번 자리: %s%s" % [i + 1, hd["name"], " (방장)" if i == 0 else ""])
		else:
			lines.append("%d번 자리: 비어 있음 (시작하면 AI)" % (i + 1))
	if net.mode == "2v2":
		lines.append("팀: 1·3번 자리 vs 2·4번 자리")
	_lobby_members.text = "\n".join(PackedStringArray(lines))
	if _lobby_start != null and is_instance_valid(_lobby_start):
		_lobby_start.visible = net.is_host and net.mode != "1v1"


func _on_host_pressed() -> void:
	_new_net()
	_lobby_code_box.visible = true
	_lobby_code.text = "·····"
	net.host_room(selected_hero, mode)
	_on_lobby_changed()


func _on_join_pressed(code: String) -> void:
	_new_net()
	_lobby_code_box.visible = false
	if not net.join_room(code, selected_hero):
		_lobby_status.text = "방 코드가 올바르지 않아요 (5글자)"


func _start_online_battle() -> void:
	if net == null or not net.is_matched:
		return
	_lobby_status = null
	_lobby_code = null
	_lobby_code_box = null
	_lobby_members = null
	_lobby_start = null
	var b := Battle.new()
	b.net = net
	b.exit_to_menu.connect(func():
		_leave_online()
		_show_menu())
	b.restart_requested.connect(_show_online_lobby)
	_set_screen(b)
