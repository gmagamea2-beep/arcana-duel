extends RefCounted
## 아르카나 듀얼 규칙 엔진.
## 화면(UI)과 분리되어 있어서 AI 시뮬레이션, 나중의 온라인 대전에도 그대로 쓴다.
## 모든 행동은 apply_action() 또는 개별 함수로 하고, 성공하면 true 를 돌려준다.

signal changed
signal logged(text: String)
## UI 연출용 이벤트 (kind: "damage", "heal", "trap", "death", "summon", "play", "buy", "turn",
## "buff", "gold", "combo", "combo_skill")
signal game_event(kind: String, info: Dictionary)

const CardDB = preload("res://core/card_db.gd")
const CardInst = preload("res://core/card_inst.gd")
const PlayerState = preload("res://core/player_state.gd")

const START_HP := 25
const MAX_MANA := 10
const MANA_CAP_LIMIT := 15
const MAX_GOLD := 10
const HAND_LIMIT := 10
const HAND_REFILL := 5
const BOARD_SIZE := 6
const BASE_TRAP_SLOTS := 2
const MARKET_SIZE := 5
const COLLAPSE_TURN := 13
const REFRESH_COST := 1
const CLEAN_COST := 2
const FIRST_HAND := 4
const SECOND_HAND := 5
const SECOND_GOLD := 2

var players: Array = []
var current := 0
var first := 0
var phase := "mulligan"  # mulligan / play / over
## 이긴 팀 번호 (1:1 이면 팀 = 자리 번호). 무승부면 DRAW
var winner := -1
const DRAW := 9
## 자리별 팀 번호. 1:1 = [0, 1], 1:1:1 = [0, 1, 2], 2:2 = [0, 1, 0, 1]
var teams: Array = [0, 1]
var market: Array = []
var field: CardInst = null
var field_owner := -1
var unique_seen := {}
var rng := RandomNumberGenerator.new()
var log_lines: Array = []
var total_turns := 0
var _uid := 0


# ─────────────────────────────── 시작 ───────────────────────────────

func start(hero0: String, hero1: String, seed_value: int = -1, names: Array = ["플레이어 1", "플레이어 2"]) -> void:
	start_multi([hero0, hero1], [0, 1], seed_value, names)


## 여러 명 게임. heroes[i] = i번 자리 영웅, team_ids[i] = 팀 번호 (같은 번호끼리 같은 편)
func start_multi(hero_ids: Array, team_ids: Array, seed_value: int = -1, names: Array = []) -> void:
	CardDB.load_all()
	if seed_value >= 0:
		rng.seed = seed_value
	else:
		rng.randomize()
	players.clear()
	teams = team_ids.duplicate()
	var n := hero_ids.size()
	for i in n:
		var p := PlayerState.new()
		p.idx = i
		p.team = int(teams[i])
		p.name = names[i] if i < names.size() else "플레이어 %d" % (i + 1)
		var hd: Dictionary = CardDB.heroes[hero_ids[i]]
		p.hero_id = hero_ids[i]
		p.hero_name = hd["name"]
		p.faction = hd["faction"]
		p.power_id = hd["power"]
		p.hp = START_HP
		p.max_hp = START_HP
		for sd in CardDB.starter:
			for k in int(sd["count"]):
				p.deck.append(_make(sd["id"], i))
		# 영웅마다 시작 덱에 들어가는 전용 카드
		for bid in hd.get("bonus_cards", []):
			p.deck.append(_make(bid, i))
		_shuffle(p.deck)
		players.append(p)
	first = rng.randi_range(0, n - 1)
	current = first
	market.clear()
	for i in MARKET_SIZE:
		market.append("")
	for i in MARKET_SIZE:
		market[i] = _roll_market_card()
	_draw(players[first], FIRST_HAND, true)
	for pi in turn_order(first):
		if pi != first:
			_draw(players[pi], SECOND_HAND, true)
			players[pi].gold = SECOND_GOLD
	phase = "mulligan"
	_log("게임 시작! 선공: %s" % players[first].name)
	changed.emit()


## AI 난이도 보너스 (게임 시작 직후, 첫 턴 전에 부른다)
## {"hp": 시작 체력, "draw": 매 턴 추가 카드, "gold": 매 턴 골드, "mana": 시작 최대 마나 보너스}
func apply_handicap(pi: int, h: Dictionary) -> void:
	var p: PlayerState = players[pi]
	if int(h.get("hp", 0)) > 0:
		p.hp = int(h["hp"])
		p.max_hp = p.hp
	p.extra_draw = int(h.get("draw", 0))
	p.gold_per_turn = int(h.get("gold", 0))
	p.max_mana = mini(p.mana_cap - 1, int(h.get("mana", 0)))


## 시작 손패에서 고른 카드(인덱스 목록)를 덱에 돌려보내고 같은 수만큼 다시 뽑는다.
func mulligan(pi: int, idxs: Array) -> bool:
	if phase != "mulligan":
		return false
	var p: PlayerState = players[pi]
	if p.mulligan_done:
		return false
	var sorted := idxs.duplicate()
	sorted.sort()
	sorted.reverse()
	var back: Array = []
	for i in sorted:
		if i >= 0 and i < p.hand.size():
			back.append(p.hand[i])
			p.hand.remove_at(i)
	p.deck.append_array(back)
	_shuffle(p.deck)
	_draw(p, back.size(), true)
	p.mulligan_done = true
	if back.size() > 0:
		_log("%s: 시작 손패 %d장 교체" % [p.name, back.size()])
	var all_done := true
	for q in players:
		if not q.mulligan_done:
			all_done = false
	if all_done:
		phase = "play"
		_start_turn(first)
	changed.emit()
	return true


# ─────────────────────────────── 조회 ───────────────────────────────

func opponent(pi: int) -> PlayerState:
	var es := enemies(pi)
	return players[es[0]] if not es.is_empty() else players[(pi + 1) % players.size()]


func is_multi() -> bool:
	return players.size() > 2


func is_enemy(a: int, b: int) -> bool:
	return int(teams[a]) != int(teams[b])


## from 다음 자리부터 한 바퀴 (from 포함, 맨 앞) — 죽은 자리도 포함
func turn_order(from: int) -> Array:
	var res: Array = []
	for k in players.size():
		res.append((from + k) % players.size())
	return res


## 살아 있는 적 자리 (pi 다음 차례부터)
func enemies(pi: int) -> Array:
	var res: Array = []
	for q in turn_order(pi):
		if q != pi and players[q].alive and is_enemy(pi, q):
			res.append(q)
	return res


## 살아 있는 같은 편 (자기 자신 제외)
func allies(pi: int) -> Array:
	var res: Array = []
	for q in turn_order(pi):
		if q != pi and players[q].alive and not is_enemy(pi, q):
			res.append(q)
	return res


func next_alive(pi: int) -> int:
	for k in range(1, players.size() + 1):
		var q := (pi + k) % players.size()
		if players[q].alive:
			return q
	return pi


func trap_slots(pi: int) -> int:
	var n := BASE_TRAP_SLOTS
	if field != null and field_owner == pi:
		n += int(field.data.get("trap_slots_bonus", 0))
	return n


func price(pi: int, card_id: String) -> int:
	var d: Dictionary = CardDB.cards[card_id]
	var pr: int = CardDB.RARITY_PRICE[d["rarity"]]
	if d["faction"] == players[pi].faction:
		pr -= 1
	pr -= players[pi].buy_discount
	return maxi(0, pr)


func power_def(pi: int) -> Dictionary:
	return CardDB.powers[players[pi].power_id]


## 대상 목록. 대상은 {"side": 플레이어 번호, "slot": 유닛 칸 번호 (-1 = 영웅)} 형식.
func valid_targets(pi: int, spec: String) -> Array:
	var res: Array = []
	var me := pi
	var ens := enemies(pi)
	var friends: Array = [me]
	friends.append_array(allies(pi))
	match spec:
		"any":
			var everyone: Array = friends + ens
			for q in everyone:
				res.append_array(_unit_targets(q))
			for q in everyone:
				res.append({"side": q, "slot": -1})
		"enemy":
			for q in ens:
				res.append_array(_unit_targets(q))
			for q in ens:
				res.append({"side": q, "slot": -1})
		"enemy_unit":
			for q in ens:
				res.append_array(_unit_targets(q))
		"friendly":
			for q in friends:
				res.append_array(_unit_targets(q))
			for q in friends:
				res.append({"side": q, "slot": -1})
		"friendly_unit":
			for q in friends:
				res.append_array(_unit_targets(q))
	return res


func _unit_targets(side: int) -> Array:
	var res: Array = []
	for i in players[side].board.size():
		res.append({"side": side, "slot": i})
	return res


static func target_in(list: Array, t: Dictionary) -> bool:
	if t.is_empty():
		return false
	for x in list:
		if int(x["side"]) == int(t["side"]) and int(x["slot"]) == int(t["slot"]):
			return true
	return false


func target_obj(t: Dictionary) -> Variant:
	if t.is_empty():
		return null
	var p: PlayerState = players[int(t["side"])]
	var slot := int(t["slot"])
	if slot < 0:
		return p
	if slot < p.board.size():
		return p.board[slot]
	return null


func can_unit_attack(u: CardInst) -> bool:
	return (not u.summoned_turn or u.has_kw("charge")) and not u.attacked and not u.sleeping and u.attack > 0


## 공격할 수 있는 대상. 도발은 그 주인만 지켜 준다 (다인전에서 다른 적은 그대로 공격 가능).
func attack_targets(pi: int) -> Array:
	var res: Array = []
	for q in enemies(pi):
		var op: PlayerState = players[q]
		var taunts: Array = []
		for i in op.board.size():
			if op.board[i].has_kw("taunt"):
				taunts.append({"side": q, "slot": i})
		if not taunts.is_empty():
			res.append_array(taunts)
			continue
		res.append({"side": q, "slot": -1})
		res.append_array(_unit_targets(q))
	return res


# ─────────────────────────── 행동 가능 여부 ───────────────────────────
## 빈 문자열이면 가능, 아니면 불가능한 이유.

func _turn_error(pi: int) -> String:
	if phase != "play":
		return "지금은 할 수 없습니다"
	if pi != current:
		return "내 턴이 아닙니다"
	return ""


func play_error(pi: int, hi: int) -> String:
	var e := _turn_error(pi)
	if e != "":
		return e
	var p: PlayerState = players[pi]
	if hi < 0 or hi >= p.hand.size():
		return "잘못된 카드"
	var c: CardInst = p.hand[hi]
	var d := c.data
	if c.cost() > p.mana:
		return "마나가 부족합니다"
	match d["type"]:
		"unit":
			if p.board.size() >= BOARD_SIZE:
				return "유닛 칸이 가득 찼습니다"
		"trap":
			if p.traps.size() >= trap_slots(pi):
				return "함정 칸이 가득 찼습니다"
			for t in p.traps:
				if t.id == c.id:
					return "같은 함정은 하나만 놓을 수 있습니다"
	if d.has("target") and valid_targets(pi, d["target"]).is_empty():
		return "대상이 없습니다"
	return ""


func pitch_error(pi: int, hi: int) -> String:
	var e := _turn_error(pi)
	if e != "":
		return e
	if hi < 0 or hi >= players[pi].hand.size():
		return "잘못된 카드"
	return ""


func clean_error(pi: int, hi: int) -> String:
	var e := _turn_error(pi)
	if e != "":
		return e
	var p: PlayerState = players[pi]
	if hi < 0 or hi >= p.hand.size():
		return "잘못된 카드"
	if p.cleaned:
		return "정리는 턴당 1회입니다"
	if p.gold < CLEAN_COST:
		return "골드가 부족합니다"
	return ""


func buy_error(pi: int, mi: int) -> String:
	var e := _turn_error(pi)
	if e != "":
		return e
	if mi < 0 or mi >= market.size() or market[mi] == "":
		return "잘못된 카드"
	if price(pi, market[mi]) > players[pi].gold:
		return "골드가 부족합니다"
	return ""


func refresh_error(pi: int) -> String:
	var e := _turn_error(pi)
	if e != "":
		return e
	var p: PlayerState = players[pi]
	if p.refreshed:
		return "갱신은 턴당 1회입니다"
	if p.gold < REFRESH_COST:
		return "골드가 부족합니다"
	return ""


func power_error(pi: int) -> String:
	var e := _turn_error(pi)
	if e != "":
		return e
	var p: PlayerState = players[pi]
	var pd := power_def(pi)
	if p.power_used:
		return "영웅 능력은 턴당 1회입니다"
	if p.mana < int(pd["cost"]):
		return "마나가 부족합니다"
	if pd.has("target") and valid_targets(pi, pd["target"]).is_empty():
		return "대상이 없습니다"
	for ef in pd["effects"]:
		if ef["do"] == "summon" and p.board.size() >= BOARD_SIZE:
			return "유닛 칸이 가득 찼습니다"
	return ""


func attack_error(pi: int, ui: int) -> String:
	var e := _turn_error(pi)
	if e != "":
		return e
	var p: PlayerState = players[pi]
	if ui < 0 or ui >= p.board.size():
		return "잘못된 유닛"
	var u: CardInst = p.board[ui]
	if u.attacked:
		return "이번 턴에 이미 공격했습니다"
	if u.sleeping:
		return "덩굴에 묶여 공격할 수 없습니다"
	if u.summoned_turn and not u.has_kw("charge"):
		return "이번 턴에 낸 유닛은 공격할 수 없습니다"
	if u.attack <= 0:
		return "공격력이 0입니다"
	return ""


# ─────────────────────────────── 행동 ───────────────────────────────

## UI 와 AI 가 공통으로 쓰는 진입점.
## {"type": "play"|"pitch"|"clean"|"buy"|"refresh"|"power"|"attack"|"combo"|"end", "hand", "market", "unit", "target", "combo"}
func apply_action(pi: int, a: Dictionary) -> bool:
	match a.get("type", ""):
		"play":
			return play_card(pi, int(a["hand"]), a.get("target", {}))
		"pitch":
			return pitch(pi, int(a["hand"]))
		"clean":
			return clean(pi, int(a["hand"]))
		"buy":
			return buy(pi, int(a["market"]))
		"refresh":
			return refresh_market(pi)
		"power":
			return use_power(pi, a.get("target", {}))
		"attack":
			return attack(pi, int(a["unit"]), a.get("target", {}))
		"combo":
			return use_combo(pi, str(a.get("combo", "")), a.get("target", {}))
		"end":
			return end_turn(pi)
	return false


func play_card(pi: int, hi: int, target: Dictionary = {}) -> bool:
	if play_error(pi, hi) != "":
		return false
	var p: PlayerState = players[pi]
	var c: CardInst = p.hand[hi]
	var d := c.data
	var chosen: Dictionary = {}
	if d.has("target"):
		if not target_in(valid_targets(pi, d["target"]), target):
			return false
		chosen = target
	p.hand.remove_at(hi)
	p.mana -= c.cost()
	var faction: String = d["faction"]
	var ally: bool = CardDB.FACTIONS.has(faction) and p.factions_played.has(faction)
	p.factions_played[faction] = true
	var ctx := {"chosen": chosen, "ally": ally, "self": c}
	match d["type"]:
		"unit":
			_log("%s: %s 소환" % [p.name, c.display_name()])
			c.summoned_turn = true
			p.board.append(c)
			game_event.emit("play", {"card": c, "player": pi})
			_run_effects(c, "play", pi, ctx)
			_resolve_deaths()
			if phase == "play" and p.board.has(c) and not c.is_dead():
				_fire_enemy_traps(pi, "enemy_unit_played", {"trigger_unit": c})
		"spell":
			_log("%s: %s 사용" % [p.name, c.display_name()])
			game_event.emit("play", {"card": c, "player": pi})
			var tctx := {"countered": false, "cost": c.cost()}
			_fire_enemy_traps(pi, "enemy_spell", tctx)
			if tctx["countered"]:
				_log("  → %s 무효화됨!" % c.display_name())
			else:
				_run_effects(c, "play", pi, ctx)
			c.reset()
			p.discard.append(c)
		"trap":
			_log("%s: 함정을 놓았습니다" % p.name)
			p.traps.append(c)
		"field":
			_log("%s: 필드 %s 전개" % [p.name, c.display_name()])
			if field != null:
				players[field_owner].discard.append(field)
			field = c
			field_owner = pi
			game_event.emit("play", {"card": c, "player": pi})
		"hero":
			_log("%s: 영웅 카드 %s 사용!" % [p.name, c.display_name()])
			game_event.emit("play", {"card": c, "player": pi})
			_run_effects(c, "play", pi, ctx)
			p.exiled.append(c)
	_after_action()
	return true


func pitch(pi: int, hi: int) -> bool:
	if pitch_error(pi, hi) != "":
		return false
	var p: PlayerState = players[pi]
	var c: CardInst = p.hand[hi]
	p.hand.remove_at(hi)
	p.discard.append(c)
	p.gold = mini(MAX_GOLD, p.gold + 1)
	_log("%s: %s 버림 → 골드 +1" % [p.name, c.display_name()])
	game_event.emit("pitch", {"player": pi, "card": c})
	changed.emit()
	return true


func clean(pi: int, hi: int) -> bool:
	if clean_error(pi, hi) != "":
		return false
	var p: PlayerState = players[pi]
	var c: CardInst = p.hand[hi]
	p.hand.remove_at(hi)
	p.exiled.append(c)
	p.gold -= CLEAN_COST
	p.cleaned = true
	_log("%s: %s 정리 (게임에서 제거)" % [p.name, c.display_name()])
	changed.emit()
	return true


func buy(pi: int, mi: int) -> bool:
	if buy_error(pi, mi) != "":
		return false
	var p: PlayerState = players[pi]
	var id: String = market[mi]
	var pr := price(pi, id)
	p.gold -= pr
	p.buy_discount = 0
	var c := _make(id, pi)
	p.discard.append(c)
	market[mi] = ""
	market[mi] = _roll_market_card()
	_log("%s: %s 구매 (%d골드)" % [p.name, c.display_name(), pr])
	game_event.emit("buy", {"card": c, "player": pi, "slot": mi})
	_fire_enemy_traps(pi, "enemy_buy", {})
	_after_action()
	return true


func refresh_market(pi: int) -> bool:
	if refresh_error(pi) != "":
		return false
	var p: PlayerState = players[pi]
	p.gold -= REFRESH_COST
	p.refreshed = true
	for i in MARKET_SIZE:
		market[i] = ""
	for i in MARKET_SIZE:
		market[i] = _roll_market_card()
	_log("%s: 시장 갱신" % p.name)
	changed.emit()
	return true


func use_power(pi: int, target: Dictionary = {}) -> bool:
	if power_error(pi) != "":
		return false
	var p: PlayerState = players[pi]
	var pd := power_def(pi)
	if pd.has("target") and not target_in(valid_targets(pi, pd["target"]), target):
		return false
	p.mana -= int(pd["cost"])
	p.power_used = true
	_log("%s: 영웅 능력 [%s]" % [p.name, pd["name"]])
	_run_effects(null, "", pi, {"chosen": target}, pd["effects"])
	_after_action()
	return true


func attack(pi: int, ui: int, target: Dictionary) -> bool:
	if attack_error(pi, ui) != "":
		return false
	if not target_in(attack_targets(pi), target):
		return false
	var p: PlayerState = players[pi]
	var u: CardInst = p.board[ui]
	var tobj: Variant = target_obj(target)
	u.attacked = true
	var ctx := {"trigger_unit": u, "cancel": false}
	var defender := int(target["side"])
	if tobj is PlayerState:
		_fire_traps(defender, "enemy_attack_hero", ctx)
	if not u.is_dead() and not ctx["cancel"]:
		_fire_traps(defender, "enemy_attack", ctx)
	if u.is_dead() or ctx["cancel"]:
		_after_action()
		return true
	if tobj is PlayerState:
		_log("%s: %s → %s 영웅 공격" % [p.name, u.display_name(), tobj.name])
		_damage(tobj, u.attack, u)
	else:
		var e: CardInst = tobj
		_log("%s: %s → %s 공격" % [p.name, u.display_name(), e.display_name()])
		var a_dmg := u.attack
		var d_dmg := e.attack
		_damage(e, a_dmg, u)
		_damage(u, d_dmg, e)
	if u.has_kw("plunder"):
		_gain_gold(pi, 1, "약탈")
	_after_action()
	return true


func end_turn(pi: int) -> bool:
	if _turn_error(pi) != "":
		return false
	var p: PlayerState = players[pi]
	for u in p.board.duplicate():
		_run_effects(u, "turn_end", pi, {"self": u})
	if field != null and field_owner == pi:
		_run_effects(field, "field_turn_end", pi, {})
	_resolve_deaths()
	_update_combos()
	_check_win()
	if phase == "over":
		changed.emit()
		return true
	p.buy_discount = 0
	p.factions_played.clear()
	_advance_turn()
	changed.emit()
	return true


## 다음 살아 있는 사람에게 턴을 넘긴다 (붕괴 등으로 그 사람이 바로 탈락하면 또 넘김)
func _advance_turn() -> void:
	for guard in players.size() + 1:
		if phase != "play":
			return
		current = next_alive(current)
		_start_turn(current)
		if phase != "play" or players[current].alive:
			return


# ─────────────────────────────── 내부 처리 ───────────────────────────────

func _start_turn(pi: int) -> void:
	var p: PlayerState = players[pi]
	p.turn_count += 1
	total_turns += 1
	p.max_mana = mini(p.mana_cap, p.max_mana + 1)
	p.mana = p.max_mana
	p.power_used = false
	p.combo_used.clear()
	p.refreshed = false
	p.cleaned = false
	p.buy_discount = 0
	p.factions_played.clear()
	for u in p.board:
		u.summoned_turn = false
		u.attacked = false
		u.sleeping = u.frozen
		u.frozen = false
	_log("── %s의 %d번째 턴 ──" % [p.name, p.turn_count])
	game_event.emit("turn", {"player": pi})
	if p.turn_count >= COLLAPSE_TURN:
		var dmg := p.turn_count - (COLLAPSE_TURN - 1)
		p.hp -= dmg
		_log("  붕괴! %s 영웅이 %d 피해" % [p.name, dmg])
		game_event.emit("damage", {"obj": p, "amount": dmg})
		_check_win()
		if phase == "over" or not p.alive:
			return
	if field != null and field_owner == pi:
		_run_effects(field, "field_turn_start", pi, {})
	for u in p.board.duplicate():
		_run_effects(u, "turn_start", pi, {"self": u})
	_resolve_deaths()
	_update_combos()
	_check_win()
	if phase == "over" or not p.alive:
		return
	if not (pi == first and p.turn_count == 1):
		_draw(p, maxi(1, HAND_REFILL - p.hand.size()) + p.extra_draw)
	if p.gold_per_turn > 0:
		_gain_gold(pi, p.gold_per_turn, "난이도 보너스")


func _after_action() -> void:
	_resolve_deaths()
	_update_combos()
	_check_win()
	if phase == "play" and not players[current].alive:
		_advance_turn()
	changed.emit()


func _check_win() -> void:
	if phase == "over":
		return
	var dead_now: Array = []
	for p in players:
		if p.alive and p.hp <= 0:
			dead_now.append(p)
	if dead_now.is_empty():
		return
	for p in dead_now:
		p.alive = false
	var alive_teams := {}
	for p in players:
		if p.alive:
			alive_teams[p.team] = true
	if alive_teams.size() <= 1:
		phase = "over"
		if alive_teams.is_empty():
			winner = DRAW
			_log("무승부!")
		else:
			winner = int(alive_teams.keys()[0])
			var names: Array = []
			for p in players:
				if p.team == winner:
					names.append(p.name)
			_log("%s 승리!" % ", ".join(PackedStringArray(names)))
		return
	# 다인전: 쓰러진 사람은 탈락. 유닛·함정은 사라지고, 가진 필드도 사라진다
	for p in dead_now:
		_log("%s 탈락!" % p.name)
		p.board.clear()
		p.traps.clear()
		if field != null and field_owner == p.idx:
			field = null
			field_owner = -1
		p.combos.clear()
		game_event.emit("eliminated", {"player": p.idx})


func _make(id: String, owner: int) -> CardInst:
	_uid += 1
	var c := CardInst.new()
	c.setup(_uid, CardDB.cards[id], owner)
	return c


func _shuffle(arr: Array) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp


func _draw(p: PlayerState, n: int, silent: bool = false) -> void:
	for k in n:
		if p.deck.is_empty():
			if p.discard.is_empty():
				return
			p.deck = p.discard
			p.discard = []
			_shuffle(p.deck)
			if not silent:
				_log("  %s: 버린 더미를 섞어 새 덱을 만듭니다" % p.name)
				game_event.emit("shuffle", {"player": p.idx, "count": p.deck.size()})
		var c: CardInst = p.deck.pop_back()
		if p.hand.size() >= HAND_LIMIT:
			p.discard.append(c)
			if not silent:
				_log("  %s: 손패가 가득 차 %s 버려짐" % [p.name, c.display_name()])
				game_event.emit("draw", {"player": p.idx, "card": c, "burn": true})
		else:
			p.hand.append(c)
			if not silent:
				game_event.emit("draw", {"player": p.idx, "card": c, "burn": false})


func _roll_market_card() -> String:
	var avail := {}
	for id in CardDB.market_ids:
		var r: String = CardDB.cards[id]["rarity"]
		if CardDB.UNIQUE_RARITIES.has(r) and (unique_seen.has(id) or market.has(id)):
			continue
		if not avail.has(r):
			avail[r] = []
		avail[r].append(id)
	var total := 0
	for r in avail:
		total += int(CardDB.RARITY_WEIGHT[r])
	if total <= 0:
		return ""
	var roll := rng.randi_range(1, total)
	var pick_r := ""
	for r in CardDB.RARITY_ORDER:
		if not avail.has(r):
			continue
		roll -= int(CardDB.RARITY_WEIGHT[r])
		if roll <= 0:
			pick_r = r
			break
	var list: Array = avail[pick_r]
	var id: String = list[rng.randi_range(0, list.size() - 1)]
	if CardDB.UNIQUE_RARITIES.has(pick_r):
		unique_seen[id] = true
	return id


## actor 의 적들이 차례대로 함정을 발동 (무효화·취소되면 멈춤)
func _fire_enemy_traps(actor: int, trigger: String, ctx: Dictionary) -> void:
	for q in enemies(actor):
		if ctx.get("cancel", false) or ctx.get("countered", false):
			return
		var tu = ctx.get("trigger_unit", null)
		if tu != null and tu.is_dead():
			return
		_fire_traps(q, trigger, ctx)


func _fire_traps(owner_pi: int, trigger: String, ctx: Dictionary) -> void:
	var o: PlayerState = players[owner_pi]
	for t in o.traps.duplicate():
		if t.data.get("trigger", "") != trigger:
			continue
		if int(t.data.get("min_cost", 0)) > int(ctx.get("cost", 99)):
			continue
		if ctx.get("cancel", false) or ctx.get("countered", false):
			break
		var tu = ctx.get("trigger_unit", null)
		if tu != null and tu.is_dead():
			break
		o.traps.erase(t)
		_log("  %s의 함정 발동: %s" % [o.name, t.display_name()])
		game_event.emit("trap", {"card": t, "player": owner_pi})
		_run_effects(t, "trap", owner_pi, ctx)
		o.discard.append(t)
		if field != null and field_owner == owner_pi:
			_run_effects(field, "field_trap_fired", owner_pi, {})


func _run_effects(src: CardInst, when: String, pi: int, ctx: Dictionary, effects: Variant = null) -> void:
	var effs: Array = effects if effects != null else src.data.get("effects", [])
	for e in effs:
		if e.get("when", "") != when:
			continue
		if e.has("ally") and bool(e["ally"]) != bool(ctx.get("ally", false)):
			continue
		if e.has("if_tag") and tag_count(pi, e["if_tag"], src) < 1:
			continue
		if e.has("if_no_tag") and tag_count(pi, e["if_no_tag"], src) > 0:
			continue
		_apply(e, pi, src, ctx)


## 내 필드에서 이 시리즈(tag)인 유닛 수 (except 는 빼고 센다)
func tag_count(pi: int, tag: String, except: CardInst = null) -> int:
	var n := 0
	for u in players[pi].board:
		if u != except and not u.is_dead() and u.data.get("tags", []).has(tag):
			n += 1
	return n


func _resolve_targets(spec: String, pi: int, src: CardInst, ctx: Dictionary, e: Dictionary = {}) -> Array:
	var me: PlayerState = players[pi]
	var ens: Array = []
	for q in enemies(pi):
		ens.append(players[q])
	match spec:
		"chosen":
			var o = target_obj(ctx.get("chosen", {}))
			return [] if o == null else [o]
		"self":
			return [] if src == null else [src]
		"enemy_hero":
			return ens
		"my_hero":
			return [me]
		"all_enemy_units":
			var ru: Array = []
			for ep in ens:
				ru.append_array(ep.board)
			return ru
		"all_enemies":
			var r: Array = ens.duplicate()
			for ep in ens:
				r.append_array(ep.board)
			return r
		"my_units":
			return me.board.duplicate()
		"my_other_units":
			var r2: Array = me.board.duplicate()
			r2.erase(src)
			return r2
		"all_other_units":
			var r3: Array = []
			for q in turn_order(pi):
				if players[q].alive:
					r3.append_array(players[q].board)
			r3.erase(src)
			return r3
		"trigger_unit":
			var tu = ctx.get("trigger_unit", null)
			return [] if tu == null else [tu]
		"my_tag_units":
			var r4: Array = []
			for u in me.board:
				if u != src and u.data.get("tags", []).has(str(e.get("tag", ""))):
					r4.append(u)
			return r4
		"combo_units":
			var r5: Array = []
			for u in ctx.get("combo_units", []):
				if me.board.has(u):
					r5.append(u)
			return r5
	return []


func _apply(e: Dictionary, pi: int, src: CardInst, ctx: Dictionary) -> void:
	var me: PlayerState = players[pi]
	# 골드 빼앗기 등은 가장 골드가 많은 적에게서
	var op: PlayerState = opponent(pi)
	for q in enemies(pi):
		if players[q].gold > op.gold:
			op = players[q]
	var amt := int(e.get("amount", 0))
	if e.has("per_tag"):
		amt *= tag_count(pi, e["per_tag"], src)
	match e["do"]:
		"damage":
			if e.get("target", "") == "random_enemy":
				# 무작위 적(영웅 또는 유닛)에게 여러 번. 게임 난수를 써서 온라인에서도 모두 같은 결과
				for k in int(e.get("times", 1)):
					var pool: Array = []
					for q in enemies(pi):
						pool.append(players[q])
						for u in players[q].board:
							if not u.is_dead():
								pool.append(u)
					if pool.is_empty():
						break
					_damage(pool[rng.randi_range(0, pool.size() - 1)], amt, null)
			else:
				for t in _resolve_targets(e.get("target", "chosen"), pi, src, ctx, e):
					_damage(t, amt, null)
		"heal":
			for t in _resolve_targets(e.get("target", "chosen"), pi, src, ctx, e):
				_heal(t, amt)
		"gold":
			_gain_gold(pi, amt)
		"mana":
			me.mana += amt
			_log("  %s: 이번 턴 마나 +%d" % [me.name, amt])
		"cap_up":
			var before := me.mana_cap
			me.mana_cap = mini(MANA_CAP_LIMIT, me.mana_cap + amt)
			me.max_mana = mini(me.mana_cap, me.max_mana + amt)
			_log("  %s: 최대 마나 한도 %d → %d, 최대 마나 %d" % [me.name, before, me.mana_cap, me.max_mana])
		"draw":
			_draw(me, amt)
		"armor":
			me.armor += amt
			_log("  %s: 방어도 +%d" % [me.name, amt])
		"summon":
			for k in int(e.get("count", 1)):
				_summon(pi, e["token"])
		"buff":
			for t in _resolve_targets(e.get("target", "chosen"), pi, src, ctx, e):
				if t is CardInst:
					t.attack += int(e.get("atk", 0))
					t.health += int(e.get("hp", 0))
					t.max_health += int(e.get("hp", 0))
					if e.has("keyword") and not t.has_kw(e["keyword"]):
						t.keywords.append(e["keyword"])
					game_event.emit("buff", {"obj": t, "atk": int(e.get("atk", 0)), "hp": int(e.get("hp", 0)), "keyword": str(e.get("keyword", ""))})
		"ramp":
			me.max_mana = mini(me.mana_cap, me.max_mana + amt)
			_log("  %s: 최대 마나 +%d" % [me.name, amt])
		"steal_gold":
			var s := mini(amt, op.gold)
			op.gold -= s
			me.gold = mini(MAX_GOLD, me.gold + s)
			_log("  %s: 골드 %d 빼앗음" % [me.name, s])
		"destroy_enemy_traps":
			for q in enemies(pi):
				var ep: PlayerState = players[q]
				if not ep.traps.is_empty():
					_log("  %s의 함정 %d개 파괴" % [ep.name, ep.traps.size()])
				for t in ep.traps:
					ep.discard.append(t)
				ep.traps.clear()
		"destroy":
			for t in _resolve_targets(e.get("target", "chosen"), pi, src, ctx, e):
				if t is CardInst:
					t.destroyed = true
		"buy_discount":
			me.buy_discount += amt
		"become_hero":
			me.power_id = e["power"]
			me.armor += int(e.get("armor", 0))
			me.hero_name = src.display_name() if src != null else me.hero_name
			me.is_emperor = true
			me.power_used = false
		"counter":
			ctx["countered"] = true
		"cancel_attack_freeze":
			ctx["cancel"] = true
			var tu = ctx.get("trigger_unit", null)
			if tu != null:
				tu.frozen = true
				_log("  %s의 공격이 취소되고 묶였습니다" % tu.display_name())


## 피해를 주고 실제로 들어간 양을 돌려준다. source 가 유닛이면 독·흡혈 적용.
func _damage(obj: Variant, amount: int, source: CardInst) -> int:
	if amount <= 0 or obj == null:
		return 0
	var dealt := 0
	var absorbed := 0
	if obj is PlayerState:
		absorbed = mini(obj.armor, amount)
		obj.armor -= absorbed
		obj.hp -= amount - absorbed
		dealt = amount
		if absorbed > 0:
			_log("  %s 영웅: %d 피해 → 방어도가 %d 막음, 체력 -%d (남은 체력 %d)" % [obj.name, amount, absorbed, amount - absorbed, obj.hp])
		else:
			_log("  %s 영웅: %d 피해 (남은 체력 %d)" % [obj.name, amount, obj.hp])
	else:
		var u: CardInst = obj
		if u.is_dead():
			return 0
		if u.has_kw("shield"):
			u.keywords.erase("shield")
			_log("  %s의 보호막이 피해를 막음" % u.display_name())
			game_event.emit("damage", {"obj": u, "amount": 0})
			return 0
		u.health -= amount
		dealt = amount
		if source != null and source.has_kw("poison"):
			u.destroyed = true
	game_event.emit("damage", {"obj": obj, "amount": dealt, "armor": absorbed})
	if source != null and source.has_kw("lifesteal") and dealt > 0:
		_heal(players[source.owner], dealt)
	return dealt


func _heal(obj: Variant, amount: int) -> void:
	if obj == null or amount <= 0:
		return
	if obj is PlayerState:
		var before: int = obj.hp
		obj.hp = mini(obj.max_hp, obj.hp + amount)
		if obj.hp > before:
			_log("  %s 영웅: 체력 %d 회복" % [obj.name, obj.hp - before])
			game_event.emit("heal", {"obj": obj, "amount": obj.hp - before})
	else:
		var u: CardInst = obj
		var b := u.health
		u.health = mini(u.max_health, u.health + amount)
		if u.health > b:
			game_event.emit("heal", {"obj": u, "amount": u.health - b})


func _summon(pi: int, token_id: String) -> void:
	var p: PlayerState = players[pi]
	if p.board.size() >= BOARD_SIZE:
		return
	var c := _make(token_id, pi)
	c.summoned_turn = true
	p.board.append(c)
	_log("  %s: %s 소환" % [p.name, c.display_name()])
	game_event.emit("summon", {"card": c, "player": pi})


func _resolve_deaths() -> void:
	for guard in 30:
		var dead: Array = []
		for pi in turn_order(current):
			var p: PlayerState = players[pi]
			for u in p.board.duplicate():
				if u.is_dead():
					p.board.erase(u)
					dead.append(u)
		if dead.is_empty():
			return
		for u in dead:
			_log("  %s 파괴" % u.display_name())
			game_event.emit("death", {"card": u})
			if not u.is_token:
				u.reset()
				players[u.owner].discard.append(u)
			_run_effects(u, "death", u.owner, {"self": u})


func _log(text: String) -> void:
	log_lines.append(text)
	if log_lines.size() > 300:
		log_lines.pop_front()
	logged.emit(text)


# ─────────────────────────────── 골드 / 조합 ───────────────────────────────

func _gain_gold(pi: int, amt: int, why: String = "") -> void:
	var me: PlayerState = players[pi]
	var before := me.gold
	me.gold = mini(MAX_GOLD, me.gold + amt)
	_log("  %s: 골드 +%d%s" % [me.name, amt, (" (%s)" % why) if why != "" else ""])
	if me.gold > before:
		game_event.emit("gold", {"player": pi, "amount": me.gold - before})


## 조합 조건을 만족하는 유닛들 (만족하지 않으면 빈 배열)
func combo_match(pi: int, k: Dictionary) -> Array:
	var board: Array = players[pi].board
	var picked: Array = []
	for n in k["need"]:
		var matched: Array = []
		if n.has("all_ids"):
			for id in n["all_ids"]:
				var found = null
				for u in board:
					if u.id == id and not u.is_dead():
						found = u
						break
				if found == null:
					return []
				matched.append(found)
		else:
			for u in board:
				if not u.is_dead() and _need_ok(n, u):
					matched.append(u)
			if matched.size() < int(n.get("count", 1)):
				return []
		for u in matched:
			if not picked.has(u):
				picked.append(u)
	return picked


func _need_ok(n: Dictionary, u: CardInst) -> bool:
	if n.has("tag"):
		return u.data.get("tags", []).has(n["tag"])
	if n.has("kw"):
		return u.has_kw(n["kw"])
	if n.has("faction"):
		return u.data.get("faction", "") == n["faction"]
	if n.has("any_ids"):
		return (n["any_ids"] as Array).has(u.id)
	return false


## 결성된 조합 id 목록 (조합 정의 순서)
func active_combos(pi: int) -> Array:
	var res: Array = []
	for k in CardDB.combos:
		if players[pi].combos.has(k["id"]):
			res.append(k["id"])
	return res


func combo_units(pi: int, cid: String) -> Array:
	if not CardDB.combo_by_id.has(cid):
		return []
	return combo_match(pi, CardDB.combo_by_id[cid])


## 필드가 바뀔 때마다 조합이 새로 결성됐는지 / 깨졌는지 확인한다.
func _update_combos() -> void:
	if players.size() < 2 or phase == "over":
		return
	for guard in 6:
		var formed := false
		for pi in turn_order(current):
			var p: PlayerState = players[pi]
			if not p.alive:
				continue
			for k in CardDB.combos:
				var cid: String = k["id"]
				var units := combo_match(pi, k)
				if units.is_empty():
					p.combos.erase(cid)
				elif not p.combos.has(cid):
					p.combos[cid] = true
					formed = true
					_log("  %s: 조합 결성! [%s] %s" % [p.name, k["name"], k["form_text"]])
					game_event.emit("combo", {"player": pi, "combo": cid, "units": units})
					_run_effects(null, "", pi, {"combo_units": units}, k["on_form"])
		_resolve_deaths()
		if not formed:
			return


func combo_error(pi: int, cid: String) -> String:
	var e := _turn_error(pi)
	if e != "":
		return e
	var p: PlayerState = players[pi]
	if not CardDB.combo_by_id.has(cid) or not p.combos.has(cid):
		return "조합이 결성되어 있지 않습니다"
	if p.combo_used.has(cid):
		return "조합 스킬은 턴당 1회입니다"
	var sk: Dictionary = CardDB.combo_by_id[cid]["skill"]
	if p.mana < int(sk["cost"]):
		return "마나가 부족합니다"
	if sk.has("target") and valid_targets(pi, sk["target"]).is_empty():
		return "대상이 없습니다"
	return ""


func use_combo(pi: int, cid: String, target: Dictionary = {}) -> bool:
	if combo_error(pi, cid) != "":
		return false
	var k: Dictionary = CardDB.combo_by_id[cid]
	var sk: Dictionary = k["skill"]
	if sk.has("target") and not target_in(valid_targets(pi, sk["target"]), target):
		return false
	var p: PlayerState = players[pi]
	p.mana -= int(sk["cost"])
	p.combo_used[cid] = true
	var units := combo_units(pi, cid)
	_log("%s: 조합 스킬 [%s]" % [p.name, sk["name"]])
	game_event.emit("combo_skill", {"player": pi, "combo": cid, "units": units})
	_run_effects(null, "", pi, {"chosen": target, "combo_units": units}, sk["effects"])
	_after_action()
	return true


# ─────────────────────────────── 복제 (AI가 미리 해 보기용) ───────────────────────────────

## 게임 상태를 통째로 복사한다. 복사본에서 행동을 해 봐도 원래 게임은 바뀌지 않는다.
func clone():
	var g = get_script().new()
	g.current = current
	g.first = first
	g.phase = phase
	g.winner = winner
	g.teams = teams.duplicate()
	g.market = market.duplicate()
	g.field_owner = field_owner
	g.unique_seen = unique_seen.duplicate()
	g.total_turns = total_turns
	g._uid = _uid
	g.rng.seed = rng.seed
	g.rng.state = rng.state
	g.field = _clone_card(field) if field != null else null
	for p in players:
		g.players.append(_clone_player(p))
	return g


static func _clone_card(c: CardInst) -> CardInst:
	var n := CardInst.new()
	n.uid = c.uid
	n.id = c.id
	n.data = c.data
	n.owner = c.owner
	n.attack = c.attack
	n.health = c.health
	n.max_health = c.max_health
	n.keywords = c.keywords.duplicate()
	n.is_token = c.is_token
	n.summoned_turn = c.summoned_turn
	n.attacked = c.attacked
	n.frozen = c.frozen
	n.sleeping = c.sleeping
	n.destroyed = c.destroyed
	return n


static func _clone_cards(arr: Array) -> Array:
	var res: Array = []
	for c in arr:
		res.append(_clone_card(c))
	return res


static func _clone_player(p: PlayerState) -> PlayerState:
	var n := PlayerState.new()
	for k in ["idx", "name", "hero_id", "hero_name", "faction", "power_id", "is_emperor", "hp", "max_hp", "armor",
			"mana", "max_mana", "mana_cap", "gold", "turn_count", "power_used", "refreshed", "cleaned",
			"buy_discount", "mulligan_done", "extra_draw", "gold_per_turn", "team", "alive"]:
		n.set(k, p.get(k))
	n.factions_played = p.factions_played.duplicate()
	n.combos = p.combos.duplicate()
	n.combo_used = p.combo_used.duplicate()
	n.deck = _clone_cards(p.deck)
	n.hand = _clone_cards(p.hand)
	n.discard = _clone_cards(p.discard)
	n.board = _clone_cards(p.board)
	n.traps = _clone_cards(p.traps)
	n.exiled = _clone_cards(p.exiled)
	return n


## 온라인 대전용: 두 기기의 게임 상태가 같은지 비교하는 지문
func state_hash() -> int:
	var parts: Array = [phase, current, winner, total_turns, market, field.id if field != null else "", field_owner]
	for p in players:
		parts.append([p.hp, p.armor, p.mana, p.max_mana, p.mana_cap, p.gold, p.turn_count, p.deck.size(), p.discard.size(), p.exiled.size(), p.alive])
		parts.append([active_combos(p.idx), p.combo_used.keys()])
		var hand_ids: Array = []
		for c in p.hand:
			hand_ids.append(c.id)
		parts.append(hand_ids)
		var units: Array = []
		for u in p.board:
			units.append([u.id, u.attack, u.health, u.keywords])
		parts.append(units)
		var trap_ids: Array = []
		for t in p.traps:
			trap_ids.append(t.id)
		parts.append(trap_ids)
	return str(parts).hash()
