extends RefCounted
## 규칙 기반 AI. choose_action() 을 부를 때마다 "지금 할 행동 하나"를 돌려준다.
## 순서: 마무리 공격 → 카드 사용 → 영웅 능력 → 조합 스킬 → 공격 → 정리 → 버리기 → 구매 → 턴 종료

const CardDB = preload("res://core/card_db.gd")
const CardInst = preload("res://core/card_inst.gd")
const PlayerState = preload("res://core/player_state.gd")

const CLEAN_COST := 2
const RARITY_VALUE := {"common": 1.0, "rare": 2.0, "epic": 3.0, "legendary": 4.5, "mythic": 6.0, "ultimate": 8.0}

## 난이도. 0 쉬움(가끔 실수), 1 보통(규칙대로), 2 이상은 행동을 하나씩 미리 해 보고 가장 좋은 수를 고른다.
## 3 이상은 AI 쪽에 보너스(체력, 매 턴 골드·카드, 시작 마나)가 붙는다.
const DIFFICULTIES := [
	{"name": "쉬움", "reward": 30},
	{"name": "보통", "reward": 50},
	{"name": "어려움", "reward": 80},
	{"name": "매우 어려움", "reward": 120, "hp": 30, "gold": 1},
	{"name": "헬", "reward": 180, "hp": 35, "gold": 1, "draw": 1},
	{"name": "마스터", "reward": 250, "hp": 40, "gold": 2, "draw": 1, "mana": 1},
	{"name": "갓", "reward": 350, "hp": 45, "gold": 2, "draw": 1, "mana": 2},
	{"name": "얼티밋", "reward": 500, "hp": 50, "gold": 3, "draw": 2, "mana": 2},
]

var level := 1


## 화면에 보여 줄 난이도 설명
static func difficulty_text(lv: int) -> String:
	var d: Dictionary = DIFFICULTIES[clampi(lv, 0, DIFFICULTIES.size() - 1)]
	var parts: Array = []
	if lv == 0:
		parts.append("AI가 가끔 실수해요")
	elif lv == 1:
		parts.append("AI가 규칙대로 둬요")
	else:
		parts.append("AI가 수를 미리 읽어요")
	if d.has("hp"):
		parts.append("AI 체력 %d" % int(d["hp"]))
	if d.has("gold"):
		parts.append("매 턴 골드 +%d" % int(d["gold"]))
	if d.has("draw"):
		parts.append("매 턴 카드 +%d" % int(d["draw"]))
	if d.has("mana"):
		parts.append("시작 마나 +%d" % int(d["mana"]))
	parts.append("승리 보상 마석 %d" % int(d["reward"]))
	return " · ".join(PackedStringArray(parts))
var rng := RandomNumberGenerator.new()


func _init() -> void:
	rng.randomize()


func choose_action(g, pi: int) -> Dictionary:
	if g.phase != "play" or g.current != pi:
		return {}
	var a: Dictionary
	if level >= 2:
		for step in [_lethal, _search, _clean, _pitch, _buy, _refresh]:
			a = step.call(g, pi)
			if not a.is_empty():
				return a
		return {"type": "end"}
	for step in [_lethal, _best_play, _power, _combo_skill, _best_attack, _clean, _pitch, _buy, _refresh]:
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
	if u.has_kw("plunder"):
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
		# 낼 수 없는 카드(대상 없음 등)는 실수로도 고르지 않는다
		if s < 0.0 or (p.hand[i].data.has("target") and (r[1] as Dictionary).is_empty()):
			continue
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
	if d["type"] == "unit":
		s += _combo_bonus(g, pi, c)
	for e in d.get("effects", []):
		if e.get("when", "") != "play":
			continue
		if e.has("ally") and bool(e["ally"]) != ally:
			continue
		if e.has("if_tag") and g.tag_count(pi, e["if_tag"]) < 1:
			continue
		if e.has("if_no_tag") and g.tag_count(pi, e["if_no_tag"]) > 0:
			continue
		var amt := int(e.get("amount", 0))
		if e.has("per_tag"):
			amt *= g.tag_count(pi, e["per_tag"])
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
				s += 6.0 if p.max_mana < mini(8, p.mana_cap) else -10.0
			"cap_up":
				s += 5.0 + amt * 2.0
			"mana":
				s += _extra_mana_value(p, c, amt)
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
				elif spec == "my_tag_units":
					s += 1.5 * g.tag_count(pi, str(e.get("tag", "")))
				elif spec == "self":
					s += 1.5 * (int(e.get("atk", 0)) + int(e.get("hp", 0)))
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


## 이 유닛을 내면 새 조합이 결성되는지
func _combo_bonus(g, pi: int, c: CardInst) -> float:
	var p: PlayerState = g.players[pi]
	if p.board.size() >= 6:
		return 0.0
	var bonus := 0.0
	p.board.append(c)
	for k in CardDB.combos:
		if not p.combos.has(k["id"]) and not g.combo_match(pi, k).is_empty():
			bonus += 6.0
	p.board.erase(c)
	return bonus


## 이번 턴 마나를 더 얻으면 손패에서 더 낼 수 있는지
func _extra_mana_value(p: PlayerState, c: CardInst, amt: int) -> float:
	var left := p.mana - c.cost()
	for o in p.hand:
		if o != c and o.cost() > left and o.cost() <= left + amt:
			return 6.0
	return -1.0


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
	if not _worth_using(g, pi, pd["effects"]):
		return {}
	if pd.has("target"):
		var r := _pick_target(g, pi, pd["target"], pd["effects"])
		if not r[0]:
			return {}
		return {"type": "power", "target": r[1]}
	return {"type": "power"}


# ── 3-2. 조합 스킬 ──

func _combo_skill(g, pi: int) -> Dictionary:
	for cid in g.active_combos(pi):
		if g.combo_error(pi, cid) != "":
			continue
		var sk: Dictionary = CardDB.combo_by_id[cid]["skill"]
		if not _worth_using(g, pi, sk["effects"]):
			continue
		if sk.has("target"):
			var r := _pick_target(g, pi, sk["target"], sk["effects"])
			if not r[0]:
				continue
			return {"type": "combo", "combo": cid, "target": r[1]}
		return {"type": "combo", "combo": cid}
	return {}


## 쓸모없는 상황이면 아끼기 (최대 마나가 이미 끝, 상대 유닛이 없는 광역 피해 등)
func _worth_using(g, pi: int, effects: Array) -> bool:
	var p: PlayerState = g.players[pi]
	var op: PlayerState = g.players[1 - pi]
	for e in effects:
		match e.get("do", ""):
			"ramp":
				if p.max_mana >= p.mana_cap:
					return false
			"damage":
				if e.get("target", "") == "all_enemy_units" and op.board.is_empty():
					return false
			"heal":
				if e.get("target", "") in ["my_units", "my_hero"]:
					var hurt := p.hp < p.max_hp
					for u in p.board:
						if u.health < u.max_health:
							hurt = true
					if not hurt:
						return false
	return true


## [고를 수 있는지, 대상] — 효과 종류에 맞게 대상을 고른다
func _pick_target(g, pi: int, spec: String, effects: Array) -> Array:
	var kind := ""
	var amt := 1
	for e in effects:
		if e.get("target", "") == "chosen":
			kind = e["do"]
			amt = int(e.get("amount", 1))
			break
	match kind:
		"damage":
			var r := _best_damage_target(g, pi, spec, amt)
			return [not r[1].is_empty(), r[1]]
		"heal":
			var r2 := _best_heal_target(g, pi, spec, amt)
			return [not r2[1].is_empty(), r2[1]]
		"buff":
			var p: PlayerState = g.players[pi]
			var best_u := -1
			var best_v := -1.0
			for i in p.board.size():
				var v := unit_value(p.board[i])
				if v > best_v:
					best_v = v
					best_u = i
			if best_u < 0:
				return [false, {}]
			return [true, {"side": pi, "slot": best_u}]
	return [false, {}]


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
	# 같은 시리즈(드래곤, 군주 등)를 모으면 조합이 잘 생긴다
	for t in d.get("tags", []):
		var n := 0
		for pile in [p.deck, p.hand, p.discard, p.board]:
			for c in pile:
				if c.data.get("tags", []).has(t):
					n += 1
		v += 0.4 * mini(n, 4)
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


# ── 어려움 이상: 미리 해 보기 ──
## 카드 사용·영웅 능력·조합 스킬·공격 후보를 게임 복사본에서 하나씩 해 보고,
## 상황 점수가 가장 많이 오르는 행동을 고른다. (경제 행동은 위의 규칙을 그대로 씀)

func _search(g, pi: int) -> Dictionary:
	var base := evaluate(g, pi)
	# 규칙 AI 가 고를 행동에 약간 가산점 (점수가 비슷하면 검증된 규칙을 따른다)
	var rule := _rule_choice(g, pi)
	var best_d := 0.4
	var best: Dictionary = {}
	for a in _candidates(g, pi):
		var c = g.clone()
		if not c.apply_action(pi, a):
			continue
		var d := evaluate(c, pi) - base
		if not rule.is_empty() and _same_action(a, rule):
			d += RULE_BONUS
		if d > best_d:
			best_d = d
			best = a
	return best


const RULE_BONUS := 1.0


func _rule_choice(g, pi: int) -> Dictionary:
	for step in [_best_play, _power, _combo_skill, _best_attack]:
		var a: Dictionary = step.call(g, pi)
		if not a.is_empty():
			return a
	return {}


func _same_action(a: Dictionary, b: Dictionary) -> bool:
	if a.get("type", "") != b.get("type", ""):
		return false
	for k in ["hand", "unit", "combo"]:
		if str(a.get(k, "")) != str(b.get(k, "")):
			return false
	var ta: Dictionary = a.get("target", {})
	var tb: Dictionary = b.get("target", {})
	if ta.is_empty() != tb.is_empty():
		return false
	return ta.is_empty() or (int(ta["side"]) == int(tb["side"]) and int(ta["slot"]) == int(tb["slot"]))


func _candidates(g, pi: int) -> Array:
	var p: PlayerState = g.players[pi]
	var res: Array = []
	for i in p.hand.size():
		if g.play_error(pi, i) != "":
			continue
		var d: Dictionary = p.hand[i].data
		if d.has("target"):
			for t in g.valid_targets(pi, d["target"]):
				res.append({"type": "play", "hand": i, "target": t})
		else:
			res.append({"type": "play", "hand": i})
	if g.power_error(pi) == "":
		var pd: Dictionary = g.power_def(pi)
		if pd.has("target"):
			for t in g.valid_targets(pi, pd["target"]):
				res.append({"type": "power", "target": t})
		else:
			res.append({"type": "power"})
	for cid in g.active_combos(pi):
		if g.combo_error(pi, cid) != "":
			continue
		var sk: Dictionary = CardDB.combo_by_id[cid]["skill"]
		if sk.has("target"):
			for t in g.valid_targets(pi, sk["target"]):
				res.append({"type": "combo", "combo": cid, "target": t})
		else:
			res.append({"type": "combo", "combo": cid})
	for ui in p.board.size():
		if g.attack_error(pi, ui) != "":
			continue
		for t in g.attack_targets(pi):
			res.append({"type": "attack", "unit": ui, "target": t})
	return res


## 상황 점수 (pi 쪽에서 볼 때 높을수록 좋음)
## 체력·필드·손패·자원에 더해, 다음 상대 턴에 맞을 피해와 내 다음 턴 마무리 가능성을 본다.
func evaluate(g, pi: int) -> float:
	if g.phase == "over":
		if g.winner == pi:
			return 100000.0
		return -100000.0 if g.winner == 1 - pi else -50000.0
	var me: PlayerState = g.players[pi]
	var op: PlayerState = g.players[1 - pi]
	var s := 0.0
	var my_life := me.hp + 0.8 * me.armor
	var op_life := op.hp + 0.8 * op.armor
	s += 1.0 * my_life - 1.2 * op_life
	if op_life < 12:
		s += (12.0 - op_life) * 1.2
	var my_taunt_hp := 0
	var my_atk := 0
	for u in me.board:
		s += unit_value(u) * 1.2
		if u.has_kw("taunt"):
			my_taunt_hp += u.health
		if not u.frozen:
			my_atk += u.attack
	var op_taunt := false
	var op_atk := 0
	for u in op.board:
		s -= unit_value(u) * 1.35
		if u.has_kw("taunt"):
			op_taunt = true
		op_atk += u.attack
	# 다음 상대 턴 위협: 내 도발 유닛이 일부를 막아 준다고 본다
	var threat := maxf(0.0, op_atk - my_taunt_hp * 0.7)
	s -= 0.45 * threat
	if threat >= my_life:
		s -= 40.0
	# 내 다음 턴 마무리 가능성
	if not op_taunt and my_atk >= op_life:
		s += 12.0
	s += 0.8 * me.hand.size()
	s += 0.5 * me.gold - 0.25 * op.gold
	s += 1.5 * me.max_mana + 0.8 * me.mana_cap
	for t in me.traps:
		s += 2.0 + t.cost()
	if g.field != null:
		s += (4.0 + g.field.cost()) * (1.0 if g.field_owner == pi else -1.0)
	s += 3.0 * me.combos.size() - 3.0 * op.combos.size()
	return s
