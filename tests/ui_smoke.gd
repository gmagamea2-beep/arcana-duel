extends SceneTree
## 화면 자동 점검: 메뉴 → 대전 시작 → 내 쪽도 AI가 대신 두며 화면 코드를 그대로 거쳐 한 판 진행.
## 화면이 있는 환경(xvfb 등)에서는 SHOT_DIR 폴더에 스크린샷을 저장한다.
## 실행: godot --path . --resolution 1920x1080 -s res://tests/ui_smoke.gd

const AI = preload("res://ai/simple_ai.gd")

var _out := ""
var _frames_total := 0


func _initialize() -> void:
	_out = OS.get_environment("SHOT_DIR")
	_run()


func _frames(n: int) -> void:
	for i in n:
		_frames_total += 1
		await process_frame


func _shot(name: String) -> void:
	if _out == "" or DisplayServer.get_name() == "headless":
		return
	await _frames(3)
	var img := root.get_texture().get_image()
	if img != null:
		img.save_png(_out.path_join(name + ".png"))
		print("스크린샷: ", name)


func _run() -> void:
	var main = load("res://ui/main.tscn").instantiate()
	root.add_child(main)
	await _frames(10)
	await _shot("1_menu")

	main._start_battle()
	await _frames(10)
	var battle = main.screen
	battle.fast = true
	await _shot("2_mulligan")
	battle._on_mull_confirm()

	var helper := AI.new()
	var game = battle.game
	var my_turns := 0
	var shots := {3: "3_turn3", 6: "4_turn6", 9: "5_turn9"}
	while game.phase == "play" and my_turns < 40 and _frames_total < 30000:
		if game.current == 0 and not battle.busy and not battle.overlay.visible:
			var t: int = game.players[0].turn_count
			if shots.has(t):
				if game.players[0].hand.size() > 0:
					battle.sel = {"kind": "hand", "index": 0}
				battle._refresh()
				await _frames(40)
				await _shot(shots[t])
				battle.sel = {}
			if t == 2 or t == 3:
				await _drag_checks(battle, t)
			var steps := 0
			while game.phase == "play" and game.current == 0 and steps < 120:
				var a: Dictionary = helper.choose_action(game, 0)
				if a.get("type", "end") == "end":
					break
				if a.has("hand"):
					battle.sel = {"kind": "hand", "index": int(a["hand"])}
					battle._refresh()
				elif a.has("market"):
					battle.sel = {"kind": "market", "index": int(a["market"])}
					battle._refresh()
				if not battle._do(a):
					print("UI 행동 실패: ", a)
					break
				steps += 1
				await _frames(1)
			if game.phase != "play":
				break
			battle._on_end_pressed()
			my_turns += 1
		await _frames(2)
	await _frames(120)
	await _shot("6_result")
	print("UI 대전 점검: 내 턴 %d번, 승자 %d, 오버레이 %s" % [my_turns, game.winner, str(battle.overlay.visible)])
	await _run_tutorial(main)
	print("UI 점검 완료")
	quit()


## 튜토리얼을 화면 그대로 따라가며 끝까지 진행
func _run_tutorial(main) -> void:
	main._start_tutorial()
	await _frames(10)
	var battle = main.screen
	battle.fast = true
	var tut = battle.tutorial
	var game = battle.game
	var shots := {0: "7_tutorial_start", 3: "8_tutorial_coin", 10: "9_tutorial_attack", 14: "10_tutorial_taunt"}
	var taken := {}
	var guard := 0
	while tut.active and game.phase == "play" and guard < 400:
		guard += 1
		if game.current != 0 or battle.busy:
			await _frames(2)
			continue
		var idx: int = tut.index
		if shots.has(idx) and not taken.has(idx):
			taken[idx] = true
			await _frames(30)
			await _shot(shots[idx])
		var a: Dictionary = tut.auto_action(game)
		if a.get("next", false):
			if not battle.coach.visible or not battle.coach_btn.visible:
				print("UI 행동 실패: 튜토리얼 [다음] 버튼이 안 보임 (단계 %d)" % (idx + 1))
				break
			battle._on_coach_next()
		elif a.get("type", "") == "end":
			battle._on_end_pressed()
		elif not a.is_empty():
			if not battle._do(a):
				print("UI 행동 실패: 튜토리얼 단계 %d 행동 %s" % [idx + 1, str(a)])
				break
		else:
			print("UI 행동 실패: 튜토리얼 단계 %d에서 멈춤" % (idx + 1))
			break
		await _frames(3)
	print("UI 튜토리얼 점검: 끝까지 진행 %s, 상대 체력 %d" % [str(not tut.active), game.players[1].hp])
	if tut.active:
		print("UI 행동 실패: 튜토리얼이 끝나지 않음")


## 끌어다 놓기 점검: 버리기 / 유닛 내기 / 구매 / 공격
func _drag(battle, view: Control, kind: String, index: int, to: Vector2, shot_name: String = "") -> void:
	var from := view.global_position + view.size / 2.0
	battle._on_drag_start(view, from, kind, index)
	battle._on_drag_move(view, (from + to) / 2.0)
	battle._on_drag_move(view, to)
	await _frames(2)
	if shot_name != "":
		await _shot(shot_name)
	battle._on_drag_end(view, to)
	await _frames(3)


func _center_of(c: Control) -> Vector2:
	return c.global_position + c.size / 2.0


func _drag_checks(battle, turn: int) -> void:
	var game = battle.game
	var me = game.players[0]
	if turn == 2:
		# 1) 버린 더미로 끌어 버리기
		var n: int = me.hand.size()
		var disc: int = me.discard.size()
		if n > 0:
			await _drag(battle, battle.hand_area.get_child(n - 1), "hand", n - 1, _center_of(battle.discard_pile))
			if me.hand.size() != n - 1 or me.discard.size() != disc + 1:
				print("UI 행동 실패: 드래그로 버리기 안 됨")
			else:
				print("드래그 점검: 버리기 OK")
		# 2) 유닛을 전장으로 끌어 내기
		for i in me.hand.size():
			if me.hand[i].type() == "unit" and game.play_error(0, i) == "":
				var b: int = me.board.size()
				await _drag(battle, battle.hand_area.get_child(i), "hand", i, _center_of(battle.me_board), "11_drag_play")
				if me.board.size() != b + 1:
					print("UI 행동 실패: 드래그로 유닛 내기 안 됨")
				else:
					print("드래그 점검: 유닛 내기 OK")
				break
		# 3) 시장 카드를 전장으로 끌어 구매
		for mi in game.market.size():
			if game.buy_error(0, mi) == "":
				var d: int = me.discard.size()
				await _drag(battle, battle.market_box.get_child(mi), "market", mi, _center_of(battle.left_area))
				if me.discard.size() != d + 1:
					print("UI 행동 실패: 드래그로 구매 안 됨")
				else:
					print("드래그 점검: 구매 OK")
				break
	else:
		# 4) 유닛을 끌어 공격 (화살표)
		for i in me.board.size():
			if game.attack_error(0, i) == "":
				var targets: Array = game.attack_targets(0)
				var t: Dictionary = targets[0]
				var to: Vector2 = _center_of(battle._view_for_target(t))
				await _drag(battle, battle.me_board.get_child(i), "unit", i, to, "12_drag_attack")
				if me.board.size() > i and not me.board[i].attacked and game.phase == "play":
					print("UI 행동 실패: 드래그로 공격 안 됨")
				else:
					print("드래그 점검: 공격 OK")
				break
	await _shot("drag_turn%d" % turn)
