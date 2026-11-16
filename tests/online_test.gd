extends SceneTree
## 온라인 대전 점검: 여러 연결을 실제 공개 서버로 이어서 AI끼리 한 판씩 두고,
## 매 행동마다 모든 기기의 게임 상태가 같은지 확인한다.
## 1) 1:1 (방장 + 손님)  2) 2:2 (방장 + 손님 2명 + 방장이 맡는 AI 1자리)
## 실행: godot --headless --path . -s res://tests/online_test.gd

const NetMatch = preload("res://net/net_match.gd")
const Game = preload("res://core/game.gd")
const AI = preload("res://ai/simple_ai.gd")
const CardDB = preload("res://core/card_db.gd")

var nets: Array = []
var games: Array = []
var steps: Array = []
var bufs: Array = []
var mulls: Array = []
var ai := AI.new()


func _initialize() -> void:
	_run()


func _wait_until(cond: Callable, sec: float) -> bool:
	var t0 := Time.get_ticks_msec()
	while not cond.call():
		if Time.get_ticks_msec() - t0 > sec * 1000.0:
			return false
		await process_frame
	return true


func _on_act(step: int, seat: int, a: Dictionary, h: int, ci: int) -> void:
	bufs[ci][step] = [seat, a, h]


func _on_mull(seat: int, idx: Array, ci: int) -> void:
	mulls[ci][seat] = idx


func _cleanup() -> void:
	for n in nets:
		n.leave()
		n.queue_free()
	nets.clear()
	games.clear()
	steps.clear()
	bufs.clear()
	mulls.clear()


func _run() -> void:
	CardDB.load_all()
	var r1: String = await _match("1v1", ["fire", "steel"])
	print("온라인 점검 1:1: " + r1)
	_cleanup()
	await process_frame
	var r2: String = await _match("2v2", ["shadow", "forest", "dragon"])
	print("온라인 점검 2:2: " + r2)
	_cleanup()
	var ok := r1.begins_with("성공") and r2.begins_with("성공")
	print(("온라인 점검: 성공 - " if ok else "온라인 점검: 실패 - ") + "1:1 %s / 2:2 %s" % [r1, r2])
	quit(0 if ok else 1)


## heroes[0] = 방장, 나머지 = 손님들
func _match(mode: String, heroes: Array) -> String:
	for i in heroes.size():
		var n := NetMatch.new()
		root.add_child(n)
		n.status_changed.connect(func(t): print("[%d] %s" % [i, t]))
		n.action_received.connect(_on_act.bind(i))
		n.mulligan_received.connect(_on_mull.bind(i))
		nets.append(n)
		bufs.append({})
		mulls.append({})
		steps.append(0)
	await process_frame
	var host: NetMatch = nets[0]
	host.host_room(heroes[0], mode)
	if not await _wait_until(func(): return host.mqtt.is_ready(), 40.0):
		return "실패 - 방장이 서버에 연결하지 못함"
	print("방 코드: ", host.room)
	for i in range(1, heroes.size()):
		nets[i].join_room(host.room, heroes[i])
		var want := i + 1
		if not await _wait_until(func(): return host.members.size() >= want or host.is_matched, 30.0):
			return "실패 - %d번 손님이 방에 못 들어옴" % i
	if not host.is_matched:
		host.host_start()
	if not await _wait_until(func(): return nets.all(func(n): return n.is_matched), 30.0):
		return "실패 - 시작 메시지를 다 못 받음"
	for n in nets:
		if n.seed_value != host.seed_value:
			return "실패 - 시드가 다름"
	# 각자 게임 시작
	for i in nets.size():
		var g := Game.new()
		g.start_multi(nets[i].heroes, nets[i].teams, nets[i].seed_value)
		games.append(g)
	var seats: int = host.heroes.size()
	# 시작 손패 교체: 각자 자기 자리, 방장은 AI 자리도
	for i in nets.size():
		var idx: Array = [0] if i == 0 else []
		mulls[i][nets[i].my_seat] = idx
		nets[i].send_mulligan(nets[i].my_seat, idx)
	for q in seats:
		if host.seat_ai[q]:
			mulls[0][q] = []
			host.send_mulligan(q, [])
	if not await _wait_until(func(): return mulls.all(func(m): return m.size() == seats), 30.0):
		return "실패 - 시작 손패 교체 메시지를 다 못 받음"
	for i in nets.size():
		for q in seats:
			games[i].mulligan(q, mulls[i][q])
	for i in nets.size():
		if games[i].state_hash() != games[0].state_hash():
			return "실패 - 시작 손패 교체 후 상태가 다름"
	# 차례대로: 그 자리 주인(또는 AI 자리면 방장)이 두고 보냄 → 나머지가 받아서 적용
	var actions := 0
	while games[0].phase == "play" and actions < 900:
		var seat: int = games[0].current
		var ci := -1
		for i in nets.size():
			if nets[i].my_seat == seat:
				ci = i
		if ci < 0:
			ci = 0
		var g: Game = games[ci]
		var a: Dictionary = ai.choose_action(g, seat)
		if a.is_empty() or (a.get("type", "") != "end" and actions % 40 == 39):
			a = {"type": "end"}
		if not g.apply_action(seat, a):
			a = {"type": "end"}
			g.apply_action(seat, a)
		var st: int = steps[ci]
		nets[ci].send_action(st, seat, a, g.state_hash())
		steps[ci] = st + 1
		for i in nets.size():
			if i == ci:
				continue
			if not await _wait_until(func(): return bufs[i].has(st), 25.0):
				return "실패 - 행동 %d개째를 %d번 기기가 못 받음" % [actions, i]
			var item: Array = bufs[i][st]
			bufs[i].erase(st)
			if games[i].current != int(item[0]) or not games[i].apply_action(int(item[0]), item[1]) or games[i].state_hash() != int(item[2]):
				return "실패 - 행동 %d개째에서 %d번 기기 상태가 달라짐 (%s)" % [actions, i, str(item[1])]
			steps[i] = st + 1
		actions += 1
	if games[0].phase != "over":
		return "실패 - %d개 행동 안에 끝나지 않음" % actions
	return "성공 - 행동 %d개, %d대 모두 상태 일치, 이긴 팀 %d, 방 %s" % [actions, nets.size(), games[0].winner, host.room]
