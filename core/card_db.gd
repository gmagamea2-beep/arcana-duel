extends RefCounted
## 카드·영웅 데이터 로더와 공용 상수.
## data/cards.json, data/heroes.json 을 읽어 static 변수에 보관한다.

const RARITY_ORDER := ["common", "rare", "epic", "legendary", "mythic", "ultimate"]
const UNIQUE_RARITIES := ["legendary", "mythic", "ultimate"]
const RARITY_NAMES := {
	"basic": "기본", "token": "토큰", "common": "일반", "rare": "레어",
	"epic": "에픽", "legendary": "레전더리", "mythic": "미스틱", "ultimate": "얼티밋",
}
## 시장 등장 가중치(%)
const RARITY_WEIGHT := {"common": 40, "rare": 27, "epic": 16, "legendary": 10, "mythic": 5, "ultimate": 2}
## 시장 구매 가격(골드)
const RARITY_PRICE := {"common": 2, "rare": 3, "epic": 4, "legendary": 5, "mythic": 7, "ultimate": 9}
const FACTIONS := ["fire", "steel", "shadow", "forest"]
const FACTION_NAMES := {
	"fire": "불꽃", "steel": "강철", "shadow": "그림자", "forest": "숲",
	"neutral": "중립", "starter": "기본",
}
const TYPE_NAMES := {"unit": "유닛", "spell": "주문", "trap": "함정", "field": "필드", "hero": "영웅"}
const KEYWORD_NAMES := {"taunt": "도발", "charge": "돌진", "shield": "보호막", "poison": "독", "lifesteal": "흡혈"}
const KEYWORD_DESC := {
	"taunt": "적은 이 유닛부터 공격해야 합니다.",
	"charge": "낸 턴에 바로 공격할 수 있습니다.",
	"shield": "처음 받는 피해 1회를 무효로 합니다.",
	"poison": "이 유닛에게 피해를 받은 유닛은 즉시 죽습니다.",
	"lifesteal": "이 유닛이 준 피해만큼 내 영웅이 회복합니다.",
}
const TEXT_KEYWORD_DESC := {
	"등장": "손패에서 낼 때 발동합니다.",
	"유언": "죽을 때 발동합니다.",
	"동맹": "이번 턴에 같은 진영 카드를 먼저 사용했다면 추가 효과가 있습니다.",
	"함정": "뒷면으로 놓았다가 상대 턴에 조건이 맞으면 자동으로 발동합니다.",
}

const _INT_KEYS := ["cost", "attack", "health", "count", "trap_slots_bonus", "min_cost", "amount", "atk", "hp", "armor"]

static var cards := {}
static var starter: Array = []
static var market_ids: Array = []
static var heroes := {}
static var hero_order: Array = []
static var powers := {}
static var _loaded := false


static func load_all() -> void:
	if _loaded:
		return
	var c: Dictionary = _read_json("res://data/cards.json")
	for sec in ["starter", "tokens", "market"]:
		for d in c[sec]:
			_norm(d)
			cards[d["id"]] = d
			if sec == "starter":
				starter.append(d)
			elif sec == "market":
				market_ids.append(d["id"])
	var h: Dictionary = _read_json("res://data/heroes.json")
	for hd in h["heroes"]:
		heroes[hd["id"]] = hd
		hero_order.append(hd["id"])
	powers = h["powers"]
	for k in powers:
		_norm(powers[k])
	_loaded = true


static func get_card(id: String) -> Dictionary:
	return cards[id]


static func rarity_index(r: String) -> int:
	return RARITY_ORDER.find(r)


static func _read_json(path: String) -> Variant:
	var txt := FileAccess.get_file_as_string(path)
	var data: Variant = JSON.parse_string(txt)
	if data == null:
		push_error("JSON 읽기 실패: " + path)
		return {}
	return data


## JSON 숫자는 float 로 들어오므로 정수로 바꿔 둔다.
static func _norm(d: Dictionary) -> void:
	for k in _INT_KEYS:
		if d.has(k):
			d[k] = int(d[k])
	if d.has("effects"):
		for e in d["effects"]:
			for k in _INT_KEYS:
				if e.has(k):
					e[k] = int(e[k])
