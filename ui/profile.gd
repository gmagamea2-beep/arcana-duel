extends RefCounted
## 내 기록: 마석(뽑기 재화)과 가진 영웅. user://settings.cfg 의 "profile" 칸에 저장한다.
## 마석은 AI 대전에서 이기면 얻고, 영웅 뽑기에 쓴다.

const CardDB = preload("res://core/card_db.gd")
const Settings = preload("res://ui/settings.gd")
const AI = preload("res://ai/simple_ai.gd")

const RARITY_ORDER := ["rare", "epic", "legendary"]


static func _init_profile() -> void:
	CardDB.load_all()
	if bool(Settings.get_value("profile_ready", false)):
		return
	Settings.set_value("crystals", int(CardDB.gacha.get("start_crystals", 100)))
	Settings.set_value("owned_heroes", CardDB.starter_heroes())
	Settings.set_value("profile_ready", true)


static func crystals() -> int:
	_init_profile()
	return int(Settings.get_value("crystals", 0))


static func add_crystals(n: int) -> int:
	_init_profile()
	var c := maxi(0, crystals() + n)
	Settings.set_value("crystals", c)
	return c


static func owned() -> Array:
	_init_profile()
	var res: Array = []
	for hid in Settings.get_value("owned_heroes", []):
		if CardDB.heroes.has(hid) and not res.has(hid):
			res.append(hid)
	for hid in CardDB.starter_heroes():
		if not res.has(hid):
			res.append(hid)
	return res


static func is_owned(hid: String) -> bool:
	return owned().has(hid)


static func pull_cost() -> int:
	CardDB.load_all()
	return int(CardDB.gacha.get("cost", 100))


static func win_reward(ai_level: int) -> int:
	return int(AI.DIFFICULTIES[clampi(ai_level, 0, AI.DIFFICULTIES.size() - 1)]["reward"])


## 아직 없는 영웅 (뽑기 후보)
static func locked() -> Array:
	var own := owned()
	var res: Array = []
	for hid in CardDB.hero_order:
		if not own.has(hid):
			res.append(hid)
	return res


static func pull_error() -> String:
	if locked().is_empty():
		return "모든 영웅을 모았어요!"
	if crystals() < pull_cost():
		return "마석이 부족해요 (AI 대전에서 이기면 얻어요)"
	return ""


## 후보 중에서 하나 고르기. roll 은 0~1 사이 난수. (중복 없음: 없는 영웅만 나옴)
## 희귀도별 확률을 따르되, 그 희귀도에 남은 영웅이 없으면 남은 희귀도끼리 나눈다.
static func pick_hero(candidates: Array, roll: float) -> String:
	if candidates.is_empty():
		return ""
	var weights: Dictionary = CardDB.gacha.get("weights", {"rare": 55, "epic": 30, "legendary": 15})
	var by_r := {}
	for hid in candidates:
		var r: String = CardDB.heroes[hid].get("rarity", "rare")
		if not by_r.has(r):
			by_r[r] = []
		by_r[r].append(hid)
	var total := 0.0
	for r in by_r:
		total += float(weights.get(r, 10))
	var x := roll * total
	var pick_r := ""
	for r in RARITY_ORDER + by_r.keys():
		if not by_r.has(r):
			continue
		pick_r = r
		x -= float(weights.get(r, 10))
		if x < 0.0:
			break
	var list: Array = by_r[pick_r]
	# 같은 희귀도 안에서는 roll 의 남은 부분으로 고른다
	var idx := int(floor(fmod(roll * 1000.0, 1.0) * list.size()))
	return list[clampi(idx, 0, list.size() - 1)]


## 뽑기 1회. 성공하면 얻은 영웅 id, 실패하면 "".
static func pull(rng: RandomNumberGenerator) -> String:
	if pull_error() != "":
		return ""
	var hid := pick_hero(locked(), rng.randf())
	if hid == "":
		return ""
	add_crystals(-pull_cost())
	var own := owned()
	own.append(hid)
	Settings.set_value("owned_heroes", own)
	return hid
