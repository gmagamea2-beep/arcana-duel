extends RefCounted
## 플레이어 한 명의 상태.

var idx := 0
## 팀 번호 (같은 번호끼리 같은 편), 다인전에서 쓰러지면 alive = false (탈락)
var team := 0
var alive := true
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
## AI 난이도 보너스: 매 턴 추가로 뽑는 카드 수, 매 턴 받는 골드
var extra_draw := 0
var gold_per_turn := 0


func total_cards() -> int:
	return deck.size() + hand.size() + discard.size() + board.size() + traps.size()
