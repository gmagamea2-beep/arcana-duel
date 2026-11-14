extends RefCounted
## 규칙 기반 AI. choose_action() 을 부를 때마다 "지금 할 행동 하나"를 돌려준다.
## 순서: 금화 → 마무리 공격 → 카드 사용 → 영웅 능력 → 공격 → 정리 → 버리기 → 구매 → 턴 종료

const CardDB = preload("res://core/card_db.gd")
const CardInst = preload("res://core/card_inst.gd")
const PlayerState = preload("res://core/player_state.gd")

const CLEAN_COST := 2
const RARITY_VALUE := {"common": 1.0, "rare": 2.0, "epic": 3.0, "legendary": 4.5, "mythic": 6.0, "ultimate": 8.0}

## 0 = 쉬움 (가끔 실수), 1 = 보통
var level := 1
var rng := RandomNumberGenerator.new()


func _init() -> void:
	rng.randomize()


func choose_action(g, pi: int) -> Dictionary:
	if g.phase != "play" or g.current != pi:
		return {}
	var a: Dictionary
	for step in [_lethal, _best_play, _power, _best_attack, _clean, _pitch, _buy, _refresh]:
		a = step.call(g, pi)
		if not a.is_empty():
			return a
	return {"type": "end"}


# ── 평가 함수 ──

func unit_value(u: CardInst) -> float:
	var v := u.attack * 1.5 + u.health
	if u.has_kw("taunt"):
		v += 1.5
	if u.has_kw("poison"):
		v += 2.0
	if u.has_kw("shield"):
		v += 1.5
	if u.has_kw("lifesteal"):
		v += 1.0
	return v


func _kills(dmg: int, u: CardInst) -> bool:
	return dmg >= u.health and not u.has_kw("shield")


func _ready_units(p: PlayerState) -> Array:
	var res: Array = []
	for i in p.board.size():
		var u: CardInst = p.board[i]
		if (not u.summoned_turn or u.has_kw("charge")) and not u.attacked and not u.sleeping and u.attack > 0:
			res.append(i)
	return res


# ── 1. 마무리 공격 ──

func _lethal(g, pi: int) -> Dictionary:
	var p: PlayerState = g.players[pi]
	var op: PlayerState = g.players[1 - pi]
	for u in op.board:
		if u.has_kw("taunt"):
			return {}
	var ready := _ready_units(p)
	var total := 0
	for i in ready:
		total += p.board[i].attack
	if ready.size() > 0 and total >= op.hp + op.armor:
		return {"type": "attack", "unit": ready[0], "target": {"side": 1 - pi, "slot": -1}}
	return {}


# ── 2. 카드 사용 ──

func _best_play(g, pi: int) -> Dictionary:
	var p: PlayerState = g.players[pi]
	var best_s := 0.0
	var best: Dictionary = {}
	for i in p.hand.size():
		if g.play_error(pi, i) != "":
			continue
		var r := _score_card(g, pi, p.hand[i])
		var s: float = r[0]
		if level == 0:
			s += rng.randf_range(-2.0, 2.0)
		if s > best_s:
			best_s = s
			best = {"type": "play", "hand": i, "target": r[1]}
	return best


## [점수, 대상]
func _score_card(g, pi: int, c: CardInst) -> Array:
	var p: PlayerState = g.players[pi]
	var op: PlayerState = g.players[1 - pi]
	var d := c.data
	var s := 0.0
	var tgt: Dictionary = {}
	match d["type"]:
		"unit":
			s = 3.0 + c.cost() * 1.5
		"trap":
			s = 4.0 + c.cost()
		"field":
			if g.field != null and g.field_owner == pi:
				return [-1.0, {}]
			s = 9.0 + c.cost()
		"hero":
			if p.is_emperor:
				return [-1.0, {}]
			s = 25.0
		"spell":
			s = 1.0
	var ally: bool = CardDB.FACTIONS.has(d["faction"]) and p.factions_played.has(d["faction"])
	for e in d.get("effects", []):
		if e.get("when", "") != "play":
			continue
		if e.has("ally") and bool(e["ally"]) != ally:
			continue
		var amt := int(e.get("amount", 0))
		var spec: String = e.get("target", "")
		match e["do"]:
			"gold":
				s += 40.0 if d["type"] == "spell" else amt * 1.5
			"draw":
				s += 2.5 * amt
			"armor":
				s += amt * 0.7
			"summon":
				s += 3.0 * int(e.get("count", 1))
			"ramp":
				s += 6.0 if p.max_mana < 8 else -10.0
			"steal_gold":
				s += 1.5 * mini(amt, op.gold) + 0.5
			"buy_discount":
				s += 1.0
			"destroy_enemy_traps":
				s += 2.0 * op.traps.size()
			"become_hero":
				pass
			"damage":
				if spec == "chosen":
					var r := _best_damage_target(g, pi, d["target"], amt)
					s += r[0]
					tgt = r[1]
				elif spec == "all_enemy_units":
					var net := -2.0
					for u in op.board:
						net += unit_value(u) if _kills(amt, u) else amt * 0.4
					s += net
				elif spec == "all_other_units":
					var net2 := 0.0
					for u in op.board:
						if _kills(amt, u):
							net2 += unit_value(u)
					for u in p.board:
						if _kills(amt, u):
							net2 -= unit_value(u)
					s += net2
				else:
					s += amt * 1.0
			"heal":
				if spec == "chosen":
					var r2 := _best_heal_target(g, pi, d["target"], amt)
					s += r2[0]
					tgt = r2[1]
				else:
					s += 1.0
			"buff":
				if spec == "chosen":
					var best_u := -1
					var best_v := -1.0
					for i in p.board.size():
						var v := unit_value(p.board[i])
						if v > best_v:
							best_v = v
							best_u = i
					if best_u < 0:
						return [-1.0, {}]
					tgt = {"side": pi, "slot": best_u}
					s += 5.0
				else:
					s += 1.5 * p.board.size()
			"destroy":
				var net3 := 0.0
				for u in op.board:
					net3 += unit_value(u)
				for u in p.board:
					net3 -= unit_value(u)
				s += net3 - 4.0
	if d.has("target") and tgt.is_empty():
		return [-1.0, {}]
	return [s, tgt]


func _best_damage_target(g, pi: int, spec: String, amt: int) -> Array:
	var op: PlayerState = g.players[1 - pi]
	var best_v := -100.0
	var best: Dictionary = {}
	for t in g.valid_targets(pi, spec):
		if int(t["side"]) == pi:
			continue
		var v := 0.0
		if int(t["slot"]) < 0:
			v = amt * 0.8
			if amt >= op.hp + op.armor:
				v += 100.0
		else:
			var u: CardInst = op.board[int(t["slot"])]
			if _kills(amt, u):
				v = unit_value(u) + 2.0
			else:
				v = amt * 0.4
		if v > best_v:
			best_v = v
			best = t
	return [best_v if not best.is_empty() else -100.0, best]


func _best_heal_target(g, pi: int, spec: String, amt: int) -> Array:
	var p: PlayerState = g.players[pi]
	var best_v := 1.5
	var best: Dictionary = {}
	for t in g.valid_targets(pi, spec):
		if int(t["side"]) != pi:
			continue
		var v := 0.0
		if int(t["slot"]) < 0:
			v = mini(amt, p.max_hp - p.hp) * 0.8
		else:
			var u: CardInst = p.board[int(t["slot"])]
			v = mini(amt, u.max_health - u.health) * 0.6
		if v > best_v:
			best_v = v
			best = t
	return [best_v, best]


# ── 3. 영웅 능력 ──

func _power(g, pi: int) -> Dictionary:
	if g.power_error(pi) != "":
		return {}
	var pd: Dictionary = g.power_def(pi)
	if pd.has("target"):
		var amt := 1
		for e in pd["effects"]:
			amt = int(e.get("amount", 1))
		var r := _best_damage_target(g, pi, pd["target"], amt)
		if r[1].is_empty():
			return {}
		return {"type": "power", "target": r[1]}
	return {"type": "power"}


# ── 4. 공격 ──

func _best_attack(g, pi: int) -> Dictionary:
	var p: PlayerState = g.players[pi]
	var op: PlayerState = g.players[1 - pi]
	for i in _ready_units(p):
		var u: CardInst = p.board[i]
		var targets: Array = g.attack_targets(pi)
		var best_v := -1000.0
		var best: Dictionary = {}
		for t in targets:
			var v := 0.0
			if int(t["slot"]) < 0:
				v = u.attack * (1.0 + (25.0 - op.hp) / 25.0)
			else:
				var e: CardInst = op.board[int(t["slot"])]
				var kills := _kills(u.attack, e) or (u.has_kw("poison") and not e.has_kw("shield"))
				var dies := (e.attack >= u.health or e.has_kw("poison")) and not u.has_kw("shield")
				if kills and not dies:
					v = unit_value(e) + 3.0
				elif kills:
					v = unit_value(e) - unit_value(u) + 1.0
				else:
					v = -2.0 + (0.0 if dies else 0.5)
				if e.has_kw("taunt"):
					v += 1.0
			if level == 0:
				v += rng.randf_range(-1.5, 1.5)
			if v > best_v:
				best_v = v
				best = t
		if not best.is_empty():
			return {"type": "attack", "unit": i, "target": best}
	return {}


# ── 5. 정리 (약한 스타터 카드 제거) ──

func _clean(g, pi: int) -> Dictionary:
	var p: PlayerState = g.players[pi]
	if p.cleaned or p.gold < CLEAN_COST + 2 or p.turn_count < 3:
		return {}
	for want in ["B1", "B3"]:
		for i in p.hand.size():
			if p.hand[i].id == want:
				return {"type": "clean", "hand": i}
	return {}


# ── 6. 버리기 (골드 얻기) ──

func _pitch(g, pi: int) -> Dictionary:
	var p: PlayerState = g.players[pi]
	if p.hand.is_empty():
		return {}
	# 다음 턴에 쓸 좋은 카드 1장은 남긴다
	var keep := -1
	var keep_v := 0.0
	var next_mana := mini(10, p.max_mana + 1)
	for i in p.hand.size():
		var c: CardInst = p.hand[i]
		if c.cost() > next_mana:
			continue
		var r: String = c.data["rarity"]
		var v := 0.0
		if CardDB.rarity_index(r) >= 2 or c.type() in ["field", "hero"]:
			v = c.cost() + RARITY_VALUE.get(r, 0.0)
		if v > keep_v:
			keep_v = v
			keep = i
	for i in p.hand.size():
		if i != keep:
			return {"type": "pitch", "hand": i}
	return {}


# ── 7. 구매 ──

func _card_buy_value(g, pi: int, id: String) -> float:
	var p: PlayerState = g.players[pi]
	var d: Dictionary = CardDB.cards[id]
	var v: float = RARITY_VALUE[d["rarity"]]
	if d["faction"] == p.faction:
		v += 0.7
	if d["type"] == "field" and g.field != null and g.field_owner == pi and g.field.id == id:
		v -= 3.0
	return v


func _buy(g, pi: int) -> Dictionary:
	var p: PlayerState = g.players[pi]
	if p.gold <= 0:
		return {}
	# 비싼 카드가 곧 살 수 있으면 아껴 둔다
	var top_v := -1.0
	var top_i := -1
	for i in g.market.size():
		if g.market[i] == "":
			continue
		var v := _card_buy_value(g, pi, g.market[i])
		if v > top_v:
			top_v = v
			top_i = i
	if top_i >= 0:
		var pr: int = g.price(pi, g.market[top_i])
		var r: String = CardDB.cards[g.market[top_i]]["rarity"]
		if pr > p.gold and pr - p.gold <= 3 and CardDB.rarity_index(r) >= 4:
			return {}
	var big_deck := p.total_cards() >= 28
	var best_v := 0.0
	var best := -1
	for i in g.market.size():
		if g.buy_error(pi, i) != "":
			continue
		var id: String = g.market[i]
		var v := _card_buy_value(g, pi, id)
		if big_deck and CardDB.rarity_index(CardDB.cards[id]["rarity"]) < 2:
			continue
		if v > best_v:
			best_v = v
			best = i
	if best >= 0:
		return {"type": "buy", "market": best}
	return {}


func _refresh(g, pi: int) -> Dictionary:
	var p: PlayerState = g.players[pi]
	if p.gold >= 8 and g.refresh_error(pi) == "":
		return {"type": "refresh"}
	return {}
