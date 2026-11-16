extends SceneTree
## 규칙 단위 테스트. 실패하면 "규칙 테스트 실패:" 를 출력한다 (빌드에서 검사).
## 실행: godot --headless --path . -s res://tests/rules_test.gd

const Game = preload("res://core/game.gd")
const Tutorial = preload("res://ui/tutorial.gd")
const CardDB = preload("res://core/card_db.gd")
const Profile = preload("res://ui/profile.gd")

var fails := 0
var checks := 0


func _initialize() -> void:
	test_attack_hero()
	test_armor()
	test_taunt()
	test_spell_to_hero()
	test_trap_vine()
	test_collapse()
	test_tutorial_flow()
	test_data_valid()
	test_hero_bonus()
	test_dragon_combo()
	test_combo_break_reform()
	test_lord_cards()
	test_mana_cards()
	test_plunder()
	test_gacha_pick()
	test_clone()
	test_handicap()
	test_search_ai()
	test_ffa()
	test_teams()
	test_multi_effects()
	print("규칙 테스트: %d개 검사, 실패 %d개" % [checks, fails])
	quit(1 if fails > 0 else 0)


func check(cond: bool, what: String) -> void:
	checks += 1
	if not cond:
		fails += 1
		print("규칙 테스트 실패: ", what)


## 바로 내 턴인 게임 (손패/필드는 비움)
func new_game() -> Game:
	var g := Game.new()
	g.start("fire", "steel", 1)
	g.first = 0
	g.current = 0
	g.mulligan(1, [])
	g.mulligan(0, [])
	for p in g.players:
		p.hand.clear()
		p.board.clear()
		p.traps.clear()
	g.players[0].mana = 10
	g.players[0].max_mana = 10
	return g


func put_unit(g: Game, pi: int, id: String, ready: bool = true):
	var c = g._make(id, pi)
	c.summoned_turn = not ready
	g.players[pi].board.append(c)
	return c


func put_hand(g: Game, pi: int, id: String) -> int:
	g.players[pi].hand.append(g._make(id, pi))
	return g.players[pi].hand.size() - 1


func test_attack_hero() -> void:
	var g := new_game()
	put_unit(g, 0, "C1")  # 떠돌이 용병 3/4
	var ok := g.attack(0, 0, {"side": 1, "slot": -1})
	check(ok, "유닛이 상대 영웅을 공격할 수 있어야 함")
	check(g.players[1].hp == 22, "공격 후 상대 체력 25 → 22 (실제 %d)" % g.players[1].hp)
	check(not g.attack(0, 0, {"side": 1, "slot": -1}), "같은 유닛은 한 턴에 두 번 공격 불가")
	var fresh = put_unit(g, 0, "C1", false)
	check(g.attack_error(0, 1) != "", "이번 턴에 낸 유닛은 공격 불가")
	fresh.summoned_turn = false


func test_armor() -> void:
	var g := new_game()
	g.players[1].armor = 3
	put_unit(g, 0, "B1")  # 1/2
	put_unit(g, 0, "C1")  # 3/4
	g.attack(0, 0, {"side": 1, "slot": -1})
	check(g.players[1].hp == 25 and g.players[1].armor == 2, "방어도가 먼저 피해를 막음 (체력 %d, 방어도 %d)" % [g.players[1].hp, g.players[1].armor])
	g.attack(0, 1, {"side": 1, "slot": -1})
	check(g.players[1].hp == 24 and g.players[1].armor == 0, "방어도를 넘는 피해는 체력으로 (체력 %d, 방어도 %d)" % [g.players[1].hp, g.players[1].armor])


func test_taunt() -> void:
	var g := new_game()
	put_unit(g, 0, "C1")
	put_unit(g, 1, "B4")  # 방패병 1/3 도발
	var targets: Array = g.attack_targets(0)
	check(not Game.target_in(targets, {"side": 1, "slot": -1}), "도발이 있으면 영웅은 공격 대상이 아님")
	check(not g.attack(0, 0, {"side": 1, "slot": -1}), "도발이 있을 때 영웅 공격은 실패")
	check(g.attack(0, 0, {"side": 1, "slot": 0}), "도발 유닛은 공격 가능")
	check(g.players[1].board.is_empty(), "3 피해로 방패병(체력 3) 처치")


func test_spell_to_hero() -> void:
	var g := new_game()
	put_unit(g, 1, "B4")
	var hi := put_hand(g, 0, "B3")  # 화살: 대상 하나에 2 피해
	check(g.play_card(0, hi, {"side": 1, "slot": -1}), "주문은 도발과 상관없이 영웅을 노릴 수 있음")
	check(g.players[1].hp == 23, "화살로 상대 체력 25 → 23 (실제 %d)" % g.players[1].hp)


func test_trap_vine() -> void:
	var g := new_game()
	put_unit(g, 0, "C1")
	g.players[1].traps.append(g._make("N6", 1))  # 덩굴 올가미
	g.attack(0, 0, {"side": 1, "slot": -1})
	check(g.players[1].hp == 25, "덩굴 올가미가 공격을 취소함")
	check(g.players[1].traps.is_empty(), "발동한 함정은 사라짐")


func test_collapse() -> void:
	var g := new_game()
	g.players[1].turn_count = 12
	var before: int = g.players[1].hp
	g.end_turn(0)
	check(g.players[1].hp == before - 1, "13번째 턴 시작에 붕괴 1 피해 (실제 %d → %d)" % [before, g.players[1].hp])


## 튜토리얼 대본대로 끝까지 진행되는지 (화면 없이)
func test_tutorial_flow() -> void:
	var g := Game.new()
	g.start("fire", "forest", 3)
	var t := Tutorial.new()
	t.setup(g)
	check(g.phase == "play" and g.current == 0, "튜토리얼은 내 선공으로 시작")
	var guard := 0
	while t.active and g.phase == "play" and guard < 300:
		guard += 1
		if g.current == 1:
			var oa: Dictionary = t.op_action(g)
			if oa.is_empty():
				oa = {"type": "end"}
			g.apply_action(1, oa)
			continue
		var a: Dictionary = t.auto_action(g)
		if a.get("next", false):
			t.advance()
			continue
		if a.is_empty():
			check(false, "튜토리얼 단계 %d에서 할 행동이 없음" % (t.index + 1))
			break
		var msg := t.allows(a, g)
		check(msg == "", "튜토리얼 단계 %d: 자동 행동이 막힘 (%s)" % [t.index + 1, msg])
		var ok := g.apply_action(0, a)
		check(ok, "튜토리얼 단계 %d: 행동 실패 %s" % [t.index + 1, str(a)])
		t.after_action(a, ok)
		if not ok:
			break
	check(not t.active, "튜토리얼이 끝까지 진행됨 (멈춘 단계 %d)" % (t.index + 1))
	check(g.players[1].hp == 24, "튜토리얼 공격 후 상대 체력 24 (실제 %d)" % g.players[1].hp)


## 데이터 검사: 아이콘, 토큰, 조합 카드, 영웅 능력/전용 카드가 모두 있는지
func test_data_valid() -> void:
	CardDB.load_all()
	var icons: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/icons.json"))["icons"]
	for id in CardDB.cards:
		var d: Dictionary = CardDB.cards[id]
		check(icons.has(d.get("icon", "")), "아이콘 없음: %s %s" % [id, d.get("icon", "")])
		for e in d.get("effects", []):
			if e.has("token"):
				check(CardDB.cards.has(e["token"]), "토큰 없음: %s" % id)
		if d.has("upgrade_of"):
			var base: Dictionary = CardDB.cards[d["upgrade_of"]]
			check(int(d.get("cost", 0)) <= int(base.get("cost", 0)), "상위 호환인데 더 비쌈: %s" % id)
			check(int(d.get("attack", 0)) >= int(base.get("attack", 0)) and int(d.get("health", 0)) >= int(base.get("health", 0)), "상위 호환인데 능력치가 낮음: %s" % id)
	for k in CardDB.combos:
		for n in k["need"]:
			for id in n.get("all_ids", []) + n.get("any_ids", []):
				check(CardDB.cards.has(id), "조합 %s 카드 없음: %s" % [k["id"], id])
	for hid in CardDB.hero_order:
		var hd: Dictionary = CardDB.heroes[hid]
		check(CardDB.powers.has(hd["power"]), "영웅 능력 없음: %s" % hid)
		check(icons.has(hd["icon"]), "영웅 아이콘 없음: %s" % hid)
		for bid in hd.get("bonus_cards", []):
			check(CardDB.cards.has(bid), "전용 카드 없음: %s" % hid)


func test_hero_bonus() -> void:
	var g := Game.new()
	g.start("dragon", "fire", 3)
	var has_egg := false
	for c in g.players[0].deck + g.players[0].hand:
		if c.id == "DR1":
			has_egg = true
	check(has_egg, "드라코 시작 덱에 용의 알")
	check(g.players[0].total_cards() == 11 and g.players[1].total_cards() == 10, "전용 카드 1장 추가")


func test_dragon_combo() -> void:
	var g := new_game()
	var me = g.players[0]
	var op = g.players[1]
	var whelp = put_unit(g, 0, "T_WHELP")
	var golem = put_unit(g, 1, "S3")
	var hi := put_hand(g, 0, "DR2")
	check(g.play_card(0, hi), "새끼 화룡 내기")
	check(op.hp == 23, "다른 드래곤이 있으면 적 영웅 2 피해 (%d)" % op.hp)
	check(me.combos.has("dragon2"), "쌍룡 결속 결성")
	check(whelp.attack == 3 and whelp.health == 4, "결성 효과 +1/+2 (%d/%d)" % [whelp.attack, whelp.health])
	var mana_before: int = me.mana
	check(g.apply_action(0, {"type": "combo", "combo": "dragon2"}), "조합 스킬 사용")
	check(me.mana == mana_before - 3, "조합 스킬 마나 3")
	check(golem.health == 4, "쌍룡의 숨결: 적 유닛 2 피해")
	check(not g.use_combo(0, "dragon2"), "조합 스킬은 턴당 1번")
	check(not g.use_combo(0, "lord2"), "결성 안 된 조합 스킬은 못 씀")


func test_combo_break_reform() -> void:
	var g := new_game()
	var me = g.players[0]
	var a = put_unit(g, 0, "T_WHELP")
	put_unit(g, 0, "T_WHELP")
	g._after_action()
	check(me.combos.has("dragon2"), "드래곤 2마리면 결성")
	a.destroyed = true
	g._after_action()
	check(not me.combos.has("dragon2"), "한 마리가 죽으면 조합 풀림")
	var c = put_unit(g, 0, "T_WHELP")
	g._after_action()
	check(me.combos.has("dragon2") and c.health == 4, "다시 모이면 다시 결성")


func test_lord_cards() -> void:
	var g := new_game()
	var me = g.players[0]
	var op = g.players[1]
	put_unit(g, 0, "F7")
	var hi := put_hand(g, 0, "LD1")
	check(g.play_card(0, hi), "몰락한 군주 내기")
	var ld1 = me.board[1]
	check(me.combos.has("lord2"), "군주 회합 결성")
	check(ld1.attack == 6 and ld1.health == 7, "군주 조건 +2/+2, 결성 +2/+2 (%d/%d)" % [ld1.attack, ld1.health])
	var hp_before: int = op.hp
	me.mana = 10
	var hi2 := put_hand(g, 0, "LD7")
	check(g.play_card(0, hi2), "만왕의 군주 내기")
	check(op.hp == hp_before - 6, "다른 군주 2명 → 적 영웅 6 피해 (%d)" % (hp_before - op.hp))


func test_mana_cards() -> void:
	var g := new_game()
	var me = g.players[0]
	var hi := put_hand(g, 0, "MN3")
	check(g.play_card(0, hi), "비전 결정체 내기")
	check(me.mana_cap == 11 and me.max_mana == 11, "최대 마나 한도 11 (%d/%d)" % [me.max_mana, me.mana_cap])
	var m: int = me.mana
	var hi2 := put_hand(g, 0, "MN1")
	check(g.play_card(0, hi2), "마나 결정 내기")
	check(me.mana == m + 2, "이번 턴 마나 +2")
	g.end_turn(0)
	g.end_turn(1)
	check(me.max_mana == 11 and me.mana == 11, "다음 턴 마나 11까지 (%d)" % me.max_mana)


func test_plunder() -> void:
	var g := new_game()
	var me = g.players[0]
	put_unit(g, 0, "GD2")
	var gold: int = me.gold
	check(g.attack(0, 0, {"side": 1, "slot": -1}), "약탈자 공격")
	check(me.gold == gold + 1, "약탈: 공격하면 골드 +1")


func test_gacha_pick() -> void:
	CardDB.load_all()
	check(Profile.pick_hero(["dragon", "star"], 0.0) == "star", "뽑기: 낮은 수 → 레어")
	check(Profile.pick_hero(["dragon", "star"], 0.99) == "dragon", "뽑기: 높은 수 → 레전더리")
	check(Profile.pick_hero(["dragon"], 0.1) == "dragon", "뽑기: 남은 희귀도끼리")
	check(Profile.pick_hero([], 0.5) == "", "뽑기: 후보 없음")


func test_clone() -> void:
	var g := new_game()
	put_unit(g, 0, "C1")
	put_unit(g, 1, "S1")
	put_hand(g, 0, "F3")
	var c = g.clone()
	check(c.state_hash() == g.state_hash(), "복사본은 같은 상태")
	check(c.apply_action(0, {"type": "play", "hand": 0, "target": {"side": 1, "slot": -1}}), "복사본에서 행동")
	check(c.players[1].hp == 21 and g.players[1].hp == 25, "복사본에서 한 행동은 원래 게임에 영향 없음")
	check(g.players[0].hand.size() == 1 and c.players[0].hand.is_empty(), "손패도 따로")
	c.players[0].board[0].attack = 99
	check(g.players[0].board[0].attack == 3, "유닛도 따로")


func test_handicap() -> void:
	var AI = load("res://ai/simple_ai.gd")
	var g := Game.new()
	g.start("fire", "steel", 5)
	g.apply_handicap(1, AI.DIFFICULTIES[7])
	var op = g.players[1]
	check(op.hp == 50 and op.max_hp == 50, "얼티밋: AI 체력 50")
	g.first = 1
	g.current = 1
	g.mulligan(0, [])
	g.mulligan(1, [])
	check(op.max_mana == 3, "얼티밋: 시작 마나 +2 (첫 턴 최대 마나 %d)" % op.max_mana)
	g.end_turn(1)
	g.end_turn(0)
	check(op.hand.size() >= 6, "얼티밋: 매 턴 카드 +2 (손패 %d)" % op.hand.size())
	check(op.gold >= 6, "얼티밋: 매 턴 골드 +3 (골드 %d)" % op.gold)


func test_search_ai() -> void:
	var AI = load("res://ai/simple_ai.gd")
	var ai = AI.new()
	ai.level = 2
	var g := new_game()
	put_unit(g, 0, "C1")
	put_unit(g, 1, "F1")
	g.players[1].hp = 3
	var a: Dictionary = ai.choose_action(g, 0)
	check(a.get("type", "") == "attack" and int(a["target"]["slot"]) == -1, "어려움 AI: 이길 수 있으면 영웅 공격 (%s)" % str(a))
	var g2 := new_game()
	put_unit(g2, 1, "C1")
	var hi := put_hand(g2, 0, "F3")
	var a2: Dictionary = ai.choose_action(g2, 0)
	check(a2.get("type", "") == "play" and int(a2.get("hand", -1)) == hi, "어려움 AI: 화염구 사용 (%s)" % str(a2))



## 다인전: 바로 0번 자리 턴인 게임
func new_multi(heroes: Array, teams: Array) -> Game:
	var g := Game.new()
	g.start_multi(heroes, teams, 11)
	g.first = 0
	g.current = 0
	for i in heroes.size():
		g.mulligan(i, [])
	for p in g.players:
		p.hand.clear()
		p.board.clear()
		p.traps.clear()
	g.players[0].mana = 10
	g.players[0].max_mana = 10
	return g


func test_ffa() -> void:
	var g := new_multi(["fire", "steel", "shadow"], [0, 1, 2])
	check(g.phase == "play" and g.current == 0, "1:1:1 시작")
	check(g.enemies(0) == [1, 2], "1:1:1 적은 둘 (%s)" % str(g.enemies(0)))
	put_unit(g, 1, "S1")
	put_unit(g, 2, "C1")
	var at: Array = g.attack_targets(0)
	var sides := {}
	for t in at:
		sides[int(t["side"])] = true
	check(sides.has(1) and sides.has(2), "두 적 모두 공격 가능")
	check(not Game.target_in(at, {"side": 1, "slot": -1}) and Game.target_in(at, {"side": 2, "slot": -1}), "도발은 그 주인만 지킴")
	g.players[1].hp = 0
	g._after_action()
	check(g.phase == "play" and not g.players[1].alive and g.players[1].board.is_empty(), "한 명 탈락해도 게임 계속, 유닛 사라짐")
	check(g.end_turn(0) and g.current == 2, "탈락한 자리는 차례 건너뜀 (%d)" % g.current)
	g.players[2].hp = 0
	g._after_action()
	check(g.phase == "over" and g.winner == 0, "마지막 생존자 승리 (승자 %d)" % g.winner)


func test_teams() -> void:
	var g := new_multi(["fire", "steel", "shadow", "forest"], [0, 1, 0, 1])
	check(g.enemies(0) == [1, 3] and g.allies(0) == [2], "2:2 적·아군")
	check(Game.target_in(g.valid_targets(0, "friendly"), {"side": 2, "slot": -1}), "아군 영웅 치료 가능")
	check(not Game.target_in(g.attack_targets(0), {"side": 2, "slot": -1}), "아군은 공격 불가")
	check(not Game.target_in(g.valid_targets(0, "enemy"), {"side": 2, "slot": -1}), "아군은 적 대상 아님")
	g.players[2].hp = 0
	g._after_action()
	check(g.phase == "play", "같은 편 한 명이 쓰러져도 계속")
	g.players[1].hp = 0
	g.players[3].hp = 0
	g._after_action()
	check(g.phase == "over" and g.winner == 0, "상대 팀 둘 다 쓰러지면 팀 승리")
	var g2 := new_multi(["fire", "steel", "shadow", "forest"], [0, 1, 0, 1])
	for i in 4:
		g2.players[i].hp = 0
	g2._after_action()
	check(g2.phase == "over" and g2.winner == Game.DRAW, "모두 쓰러지면 무승부")


func test_multi_effects() -> void:
	var g := new_multi(["fire", "steel", "shadow"], [0, 1, 2])
	var a = put_unit(g, 1, "C1")
	var b = put_unit(g, 2, "C1")
	var hi := put_hand(g, 0, "F7")
	check(g.play_card(0, hi), "화염의 군주 내기")
	check(g.players[1].hp == 22 and g.players[2].hp == 22, "적 영웅 피해는 모든 적에게")
	g.players[0].mana = 10
	var hi2 := put_hand(g, 0, "F5")
	check(g.play_card(0, hi2), "불꽃 폭풍")
	check(a.health == 2 and b.health == 2, "모든 적 유닛 피해")
	var c = g.clone()
	check(c.state_hash() == g.state_hash() and c.players.size() == 3, "다인전 복사")
	var g2 := new_multi(["fire", "steel", "shadow", "forest"], [0, 1, 0, 1])
	var ally = put_unit(g2, 2, "C1")
	put_hand(g2, 0, "F5")
	check(g2.play_card(0, 0) and ally.health == 4, "아군 유닛은 광역 피해를 안 받음")
