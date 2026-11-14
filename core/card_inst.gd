extends RefCounted
## 게임 안의 카드 한 장 (덱, 손패, 필드 어디에 있든 같은 객체).

var uid := 0
var id := ""
var data: Dictionary = {}
var owner := 0
var attack := 0
var health := 0
var max_health := 0
var keywords: Array = []
var is_token := false

## 이번 턴에 냈는지 (돌진이 없으면 공격 불가)
var summoned_turn := false
var attacked := false
## 덩굴 올가미: 다음 내 턴에 공격 불가
var frozen := false
var sleeping := false
var destroyed := false


func setup(p_uid: int, p_data: Dictionary, p_owner: int) -> void:
	uid = p_uid
	data = p_data
	id = p_data["id"]
	owner = p_owner
	is_token = p_data.get("rarity", "") == "token"
	reset()


## 버린 더미로 갈 때 원래 상태로 되돌린다.
func reset() -> void:
	attack = int(data.get("attack", 0))
	health = int(data.get("health", 0))
	max_health = health
	keywords = (data.get("keywords", []) as Array).duplicate()
	summoned_turn = false
	attacked = false
	frozen = false
	sleeping = false
	destroyed = false


func has_kw(k: String) -> bool:
	return keywords.has(k)


func type() -> String:
	return data["type"]


func is_dead() -> bool:
	return destroyed or health <= 0


func cost() -> int:
	return int(data.get("cost", 0))


func display_name() -> String:
	return data["name"]
