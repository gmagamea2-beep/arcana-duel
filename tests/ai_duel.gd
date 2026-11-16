extends SceneTree
## 난이도 AI끼리 대결 (보너스 없이, 자리를 번갈아 가며).
## 실행: godot --headless --path . -s res://tests/ai_duel.gd -- [A 레벨] [B 레벨] [판 수]

const Game = preload("res://core/game.gd")
const AI = preload("res://ai/simple_ai.gd")
const CardDB = preload("res://core/card_db.gd")


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var la := int(args[0]) if args.size() > 0 else 2
	var lb := int(args[1]) if args.size() > 1 else 1
	var n := int(args[2]) if args.size() > 2 else 40
	print("AI 대결: 레벨 %d vs 레벨 %d, %d판 → A 승률 %.0f%%" % [la, lb, n, 100.0 * duel(la, lb, n)])
	quit()


## A 레벨 AI 의 승률 (0~1)
static func duel(la: int, lb: int, n: int, seed_base: int = 9000) -> float:
	CardDB.load_all()
	var a := AI.new()
	a.level = la
	a.rng.seed = 3
	var b := AI.new()
	b.level = lb
	b.rng.seed = 4
	var wins := 0.0
	var done := 0
	for gi in n:
		var g := Game.new()
		var heroes: Array = CardDB.hero_order
		g.start(heroes[gi % heroes.size()], heroes[(gi * 7 + 3) % heroes.size()], seed_base + gi)
		g.mulligan(0, [])
		g.mulligan(1, [])
		var a_seat := gi % 2
		var steps := 0
		var per_turn := 0
		var last_turn := -1
		while g.phase == "play" and steps < 6000:
			var pi: int = g.current
			if g.total_turns != last_turn:
				last_turn = g.total_turns
				per_turn = 0
			per_turn += 1
			var act: Dictionary = (a if pi == a_seat else b).choose_action(g, pi)
			if per_turn > 150 or act.is_empty():
				act = {"type": "end"}
			if not g.apply_action(pi, act):
				print("행동 실패: (AI 대결) ", act)
				g.apply_action(pi, {"type": "end"})
			steps += 1
		if g.phase == "over":
			done += 1
			if g.winner == a_seat:
				wins += 1.0
			elif g.winner == 2:
				wins += 0.5
	return wins / maxf(1.0, done)
