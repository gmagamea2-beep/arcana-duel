extends SceneTree
## 규칙 단위 테스트. 실패하면 "규칙 테스트 실패:" 를 출력한다 (빌드에서 검사).
## 실행: godot --headless --path . -s res://tests/rules_test.gd

const Game = preload("res://core/game.gd")
const Tutorial = preload("res://ui/tutorial.gd")

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
