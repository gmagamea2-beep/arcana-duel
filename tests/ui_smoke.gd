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
			var t: int = game.players[0].turn_count
			if shots.has(t):
				if game.players[0].hand.size() > 0:
					battle.sel = {"kind": "hand", "index": 0}
				battle._refresh()
				await _shot(shots[t])
				battle.sel = {}
			battle._on_end_pressed()
			my_turns += 1
		await _frames(2)
	await _frames(120)
	await _shot("6_result")
	print("UI 점검 완료: 내 턴 %d번, 승자 %d, 오버레이 %s" % [my_turns, game.winner, str(battle.overlay.visible)])
	quit()
