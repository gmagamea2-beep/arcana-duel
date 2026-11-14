extends RefCounted
## 튜토리얼: 정해진 손패·덱·시장으로 시작해서 단계별 안내를 따라 한 판을 배운다.
## 단계 종류
##  - "next": 설명만 보여 주고 [다음] 버튼으로 넘어감 (이때는 게임 행동 막음)
##  - "expect": 정해진 행동을 하면 넘어감 (다른 행동은 막음)
##  - "free": 아무 행동이나 가능, 턴을 끝내면 넘어감

const Settings = preload("res://ui/settings.gd")

const ME := 0
const OP := 1

const STEPS := [
	{"next": true, "focus": "op_hero",
		"text": "아르카나 듀얼에 오신 걸 환영해요!\n목표는 상대 영웅(왼쪽 위)의 체력 25를 0으로 만드는 거예요."},
	{"next": true, "focus": "hand",
		"text": "아래쪽 카드들이 내 손패예요. 오른쪽은 두 사람이 함께 쓰는 시장이에요.\n시장에서 카드를 사서 내 덱을 점점 강하게 만드는 게임이에요."},
	{"next": true, "focus": "me_info",
		"text": "자원은 두 가지예요.\n· 마나: 카드를 낼 때 써요. 매 턴 1씩 늘어나요 (최대 10).\n· 골드: 시장에서 카드를 살 때 써요. 손패를 1장 버릴 때마다 1골드."},
	{"expect": {"type": "play", "card": "B2"}, "short": "금화를 눌러 [사용하기]를 눌러 주세요",
		"text": "먼저 '금화'를 누르고, 오른쪽 아래의 [사용하기]를 눌러 보세요.\n금화는 0마나로 골드 +2를 줘요."},
	{"expect": {"type": "play", "card": "B1"}, "short": "견습 병사를 내 주세요",
		"text": "좋아요! 이번엔 '견습 병사'를 내 보세요. 비용은 1마나예요.\n(카드 왼쪽 위 파란 숫자가 마나 비용)"},
	{"expect": {"type": "pitch", "card": "B4"}, "short": "방패병을 눌러 [버리기]를 눌러 주세요",
		"text": "'방패병'은 2마나라서 지금은 낼 수 없어요.\n이런 카드는 [버리기]로 골드 1로 바꿀 수 있어요. 방패병을 버려 보세요."},
	{"expect": {"type": "buy", "card": "F2"}, "short": "시장의 돌격 기사를 사 주세요",
		"text": "골드가 3이 됐어요. 시장에서 '돌격 기사'를 누르고 [구매하기]를 눌러 보세요.\n내 영웅(이그나)과 같은 불꽃 진영 카드는 1골드 싸요!"},
	{"next": true, "focus": "me_info",
		"text": "산 카드는 '버린 더미'로 가요.\n덱이 떨어지면 버린 더미를 섞어서 다시 쓰기 때문에, 산 카드가 곧 손에 들어와요."},
	{"expect": {"type": "end"}, "short": "[턴 종료]를 눌러 주세요",
		"text": "'화살'은 다음 턴에 쓸 거라 남겨 둘게요.\n[턴 종료]를 눌러 상대에게 차례를 넘기세요."},
	{"next": true, "focus": "my_unit",
		"text": "상대가 견습 병사를 냈어요.\n지난 턴에 낸 내 견습 병사는 이제 공격할 수 있어요 (초록 테두리).\n(유닛은 낸 다음 턴부터 공격해요. 'Zz'는 아직 못 움직인다는 뜻)"},
	{"expect": {"type": "attack", "target": "op_hero"}, "short": "내 견습 병사 → 상대 영웅을 눌러 주세요",
		"text": "내 '견습 병사'를 누른 다음, 상대 영웅을 눌러 공격하세요!"},
	{"next": true, "focus": "op_hero",
		"text": "상대 영웅의 체력이 25 → 24로 줄었어요!\n이렇게 체력을 0으로 만들면 이겨요."},
	{"expect": {"type": "play", "card": "B3", "target": "op_unit"}, "short": "화살 → [사용하기] → 상대 견습 병사",
		"text": "'화살'로 상대 견습 병사를 처치해 보세요.\n화살 → [사용하기] → 상대 병사를 누르면 돼요."},
	{"free": true, "focus": "end",
		"text": "잘했어요! 이제 남은 카드로 자유롭게 해 보세요.\n금화는 쓰고, 남는 카드는 버려서 골드로 바꾸고, 시장에서 사세요.\n다 했으면 [턴 종료]."},
	{"next": true, "focus": "op_units",
		"text": "상대가 '도발' 유닛을 냈어요! 두꺼운 회색 테두리가 도발이에요.\n도발 유닛이 있으면 영웅을 공격할 수 없어요. 도발부터 처리해야 해요."},
	{"expect": {"type": "power"}, "short": "[영웅 능력] 버튼을 눌러 주세요",
		"text": "영웅 능력을 써 보세요. 아래 [영웅 능력] 버튼을 누르고 대상을 고르면 돼요.\n이그나의 능력: 2마나로 적 하나에 1 피해 (턴마다 1번)."},
	{"next": true, "focus": "",
		"text": "알아 두면 좋은 것:\n· 방어도(회색 방패 숫자): 체력보다 먼저 피해를 막아요.\n· 함정(뒷면 카드): 상대 턴에 조건이 맞으면 자동으로 발동해요."},
	{"next": true, "focus": "",
		"text": "· 필드: 전장에 1장만 있고, 새 필드를 내면 바뀌어요.\n· 정리(2골드): 약한 카드를 게임에서 영구 제거해요.\n· 붕괴: 13번째 턴부터 매 턴 영웅이 1, 2, 3… 피해를 받아요."},
	{"next": true, "focus": "op_hero",
		"text": "이제 자유롭게 싸워 보세요!\n상대 체력을 0으로 만들면 승리예요. 막히면 카드를 눌러 설명을 읽어 보세요."},
]

var index := 0
var active := true
var _matched := false
var _op_done_turn := -1


func current() -> Dictionary:
	if not active or index >= STEPS.size():
		return {}
	return STEPS[index]


func step_label() -> String:
	return "튜토리얼 %d / %d" % [index + 1, STEPS.size()]


# ── 시작 상태 만들기 ──

func setup(g) -> void:
	g.first = ME
	g.current = ME
	var me = g.players[ME]
	var op = g.players[OP]
	me.gold = 0
	op.gold = 2
	_arrange(me, ["B2", "B1", "B4", "B3"], ["B2", "B1", "B2", "B4"])
	_arrange(op, ["B1", "B4", "B2", "B3", "B2"], [])
	g.market = ["F2", "F3", "C1", "S1", "C3"]
	g.log_lines.append("튜토리얼: 내가 선공입니다")
	g.mulligan(OP, [])
	g.mulligan(ME, [])


## 손패를 정해진 카드로, 덱 맨 위를 정해진 순서로 만든다 (덱은 뒤에서부터 뽑힘).
func _arrange(p, hand_ids: Array, top_ids: Array) -> void:
	var pool: Array = []
	pool.append_array(p.deck)
	pool.append_array(p.hand)
	var hand: Array = []
	for id in hand_ids:
		hand.append(_take(pool, id))
	var top: Array = []
	for id in top_ids:
		top.append(_take(pool, id))
	top.reverse()
	pool.append_array(top)
	p.hand = hand
	p.deck = pool


func _take(pool: Array, id: String):
	for i in pool.size():
		if pool[i].id == id:
			var c = pool[i]
			pool.remove_at(i)
			return c
	return null


# ── 행동 제한 / 진행 ──

## 빈 문자열이면 허용, 아니면 막고 안내할 문구.
func allows(a: Dictionary, g) -> String:
	_matched = false
	var st := current()
	if st.is_empty():
		return ""
	if st.get("next", false):
		return "튜토리얼: 설명을 읽고 [다음]을 눌러 주세요"
	if st.get("free", false):
		return ""
	if _match(st["expect"], a, g):
		_matched = true
		return ""
	return "튜토리얼: " + st.get("short", "안내에 따라 해 주세요")


func after_action(a: Dictionary, ok: bool) -> void:
	var st := current()
	if st.is_empty() or not ok:
		_matched = false
		return
	if _matched or (st.get("free", false) and a.get("type", "") == "end"):
		advance()
	_matched = false


func advance() -> void:
	index += 1
	if index >= STEPS.size():
		finish()


func finish() -> void:
	active = false
	Settings.set_value("tutorial_done", true)


func _match(want: Dictionary, a: Dictionary, g) -> bool:
	var t: String = a.get("type", "")
	if t != want["type"]:
		return false
	var me = g.players[ME]
	match t:
		"play", "pitch":
			var hi := int(a.get("hand", -1))
			if hi < 0 or hi >= me.hand.size() or me.hand[hi].id != want["card"]:
				return false
			if want.has("target"):
				return _target_kind(a.get("target", {})) == want["target"]
			return true
		"buy":
			var mi := int(a.get("market", -1))
			return mi >= 0 and mi < g.market.size() and g.market[mi] == want["card"]
		"attack":
			return _target_kind(a.get("target", {})) == want.get("target", "")
	return true


func _target_kind(t: Dictionary) -> String:
	if t.is_empty():
		return ""
	var side := "op" if int(t["side"]) == OP else "my"
	return side + ("_hero" if int(t["slot"]) < 0 else "_unit")


# ── 상대(AI) 대본: 처음 두 턴은 정해진 카드만 낸다 ──

func op_action(g) -> Dictionary:
	if not active:
		return {}
	var op = g.players[OP]
	var want := ""
	if op.turn_count == 1:
		want = "B1"
	elif op.turn_count == 2:
		want = "B4"
	else:
		return {}
	if _op_done_turn != op.turn_count:
		_op_done_turn = op.turn_count
		for i in op.hand.size():
			if op.hand[i].id == want:
				return {"type": "play", "hand": i}
	return {"type": "end"}


# ── 자동 점검용: 지금 단계를 통과하는 행동 ──

func auto_action(g) -> Dictionary:
	var st := current()
	if st.is_empty():
		return {}
	if st.get("next", false):
		return {"next": true}
	if st.get("free", false):
		return {"type": "end"}
	var ex: Dictionary = st["expect"]
	var me = g.players[ME]
	match ex["type"]:
		"play", "pitch":
			for i in me.hand.size():
				if me.hand[i].id == ex["card"]:
					var a := {"type": ex["type"], "hand": i}
					if ex.get("target", "") == "op_unit":
						a["target"] = {"side": OP, "slot": 0}
					elif ex.get("target", "") == "op_hero":
						a["target"] = {"side": OP, "slot": -1}
					return a
		"buy":
			return {"type": "buy", "market": g.market.find(ex["card"])}
		"attack":
			for i in me.board.size():
				if g.attack_error(ME, i) == "":
					return {"type": "attack", "unit": i, "target": {"side": OP, "slot": -1}}
		"power":
			var pd: Dictionary = g.power_def(ME)
			if pd.has("target"):
				var ts: Array = g.valid_targets(ME, pd["target"])
				return {"type": "power", "target": ts[0] if not ts.is_empty() else {}}
			return {"type": "power"}
		"end":
			return {"type": "end"}
	return {}
