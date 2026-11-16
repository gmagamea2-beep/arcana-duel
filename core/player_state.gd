extends RefCounted
## 플레이어 한 명의 상태.

var idx := 0
var name := ""
var hero_id := ""
var hero_name := ""
var faction := ""
var power_id := ""
var is_emperor := false

var hp := 25
var max_hp := 25
var armor := 0
var mana := 0
var max_mana := 0
## 최대 마나 한도 (보통 10, 카드로 15까지)
var mana_cap := 10
var gold := 0

var deck: Array = []
var hand: Array = []
var discard: Array = []
var board: Array = []
var traps: Array = []
var exiled: Array = []

var turn_count := 0
var power_used := false
var refreshed := false
var cleaned := false
var buy_discount := 0
var factions_played := {}
var mulligan_done := false
## 결성된 조합 {조합 id: true}, 이번 턴에 쓴 조합 스킬
var combos := {}
var combo_used := {}


func total_cards() -> int:
	return deck.size() + hand.size() + discard.size() + board.size() + traps.size()
