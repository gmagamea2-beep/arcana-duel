extends SceneTree
## AI끼리 자동 대전 → 밸런스 통계.
## 실행: godot --headless -s res://tests/sim.gd -- [판 수]

const Game = preload("res://core/game.gd")
const AI = preload("res://ai/simple_ai.gd")
const CardDB = preload("res://core/card_db.gd")

var combo_formed := {}
var combo_skills := 0


func _on_sim_event(kind: String, info: Dictionary) -> void:
	if kind == "combo":
		combo_formed[info["combo"]] = int(combo_formed.get(info["combo"], 0)) + 1
	elif kind == "combo_skill":
		combo_skills += 1



func _init() -> void:
	var n := 500
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		n = int(args[0])
	var ai := AI.new()
	ai.rng.seed = 7
	var pick := RandomNumberGenerator.new()
	pick.seed = 12345

	var first_wins := 0
	var decided := 0
	var draws := 0
	var timeouts := 0
	var errors := 0
	var turn_sum := 0
	var hero_games := {}
	var hero_wins := {}
	var bought := {}
	var buyer_wins := {}
	var collapse_games := 0
	var max_turns := 0
	var t0 := Time.get_ticks_msec()
	CardDB.load_all()
	var HEROES: Array = CardDB.hero_order

	for gi in n:
		var g := Game.new()
		var h0: String = HEROES[pick.randi() % HEROES.size()]
		var h1: String = HEROES[pick.randi() % HEROES.size()]
		g.game_event.connect(_on_sim_event)
		g.start(h0, h1, gi + 1)
		g.mulligan(0, [])
		g.mulligan(1, [])
		var steps := 0
		var per_turn := 0
		var last_turn := -1
		var bought_by := [{}, {}]
		while g.phase == "play" and steps < 20000:
			var pi: int = g.current
			if g.total_turns != last_turn:
				last_turn = g.total_turns
				per_turn = 0
			per_turn += 1
			var a: Dictionary = ai.choose_action(g, pi)
			if per_turn > 150:
				a = {"type": "end"}
			if a.get("type", "") == "buy":
				var bid: String = g.market[int(a["market"])]
				bought_by[pi][bid] = true
			var ok: bool = g.apply_action(pi, a)
			if not ok:
				errors += 1
				if errors <= 5:
					print("행동 실패: ", a, " / ", g.play_error(pi, int(a.get("hand", 0))))
				g.apply_action(pi, {"type": "end"})
			steps += 1
		if g.phase != "over":
			timeouts += 1
			continue
		var turns: int = int(ceil(g.total_turns / 2.0))
		turn_sum += turns
		max_turns = maxi(max_turns, turns)
		if g.total_turns >= (Game.COLLAPSE_TURN * 2 - 1):
			collapse_games += 1
		if g.winner == 2:
			draws += 1
			continue
		decided += 1
		if g.winner == g.first:
			first_wins += 1
		if h0 != h1:
			for i in 2:
				var h: String = [h0, h1][i]
				hero_games[h] = hero_games.get(h, 0) + 1
				if g.winner == i:
					hero_wins[h] = hero_wins.get(h, 0) + 1
		for i in 2:
			for id in bought_by[i]:
				bought[id] = bought.get(id, 0) + 1
				if g.winner == i:
					buyer_wins[id] = buyer_wins.get(id, 0) + 1

	var played := n - timeouts
	print("=== 시뮬레이션 %d판 (%.1f초) ===" % [n, (Time.get_ticks_msec() - t0) / 1000.0])
	print("완료 %d / 시간초과 %d / 행동 실패 %d / 무승부 %d" % [played, timeouts, errors, draws])
	if decided > 0:
		print("선공 승률: %.1f%%" % (100.0 * first_wins / decided))
	if played > 0:
		print("평균 게임 길이: 한 사람당 %.1f턴 (최장 %d턴), 붕괴까지 간 판 %.1f%%" % [float(turn_sum) / played, max_turns, 100.0 * collapse_games / played])
	print("영웅별 승률 (같은 영웅끼리 제외):")
	for h in HEROES:
		var gcount: int = hero_games.get(h, 0)
		if gcount > 0:
			print("  %s: %.1f%% (%d판)" % [h, 100.0 * hero_wins.get(h, 0) / gcount, gcount])
	print("조합 결성 횟수 (조합 스킬 사용 %d회):" % combo_skills)
	for k in CardDB.combos:
		print("  %s: %d회" % [k["name"], int(combo_formed.get(k["id"], 0))])
	print("카드별 '구매한 쪽 승률' (구매 20회 이상):")
	var ids: Array = bought.keys()
	ids.sort_custom(func(a, b): return float(buyer_wins.get(a, 0)) / bought[a] > float(buyer_wins.get(b, 0)) / bought[b])
	for id in ids:
		if bought[id] >= 20:
			print("  %s %s: %.0f%% (%d회)" % [id, CardDB.cards[id]["name"], 100.0 * buyer_wins.get(id, 0) / bought[id], bought[id]])
	quit()
