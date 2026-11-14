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


func total_cards() -> int:
	return deck.size() + hand.size() + discard.size() + board.size() + traps.size()
