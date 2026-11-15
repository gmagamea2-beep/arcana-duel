extends SceneTree
## 온라인 대전 점검: 방장/손님 두 연결을 실제 공개 서버로 이어서
## AI끼리 한 판을 두고, 매 행동마다 두 기기의 게임 상태가 같은지 확인한다.
## 실행: godot --headless --path . -s res://tests/online_test.gd

const NetMatch = preload("res://net/net_match.gd")
const Game = preload("res://core/game.gd")
const AI = preload("res://ai/simple_ai.gd")

var host: NetMatch
var guest: NetMatch
var g: Array = [null, null]  # g[0] = 방장 기기의 게임, g[1] = 손님 기기의 게임
var inbox: Array = [[], []]  # 각 기기가 받은 행동
var mull_in: Array = [null, null]


func _initialize() -> void:
	_run()


func _wait_until(cond: Callable, sec: float) -> bool:
	var t0 := Time.get_ticks_msec()
	while not cond.call():
		if Time.get_ticks_msec() - t0 > sec * 1000.0:
			return false
		await process_frame
	return true


func _done(ok: bool, msg: String) -> void:
	print(("온라인 점검: 성공 - " if ok else "온라인 점검: 실패 - ") + msg)
	if host != null:
		host.leave()
	if guest != null:
		guest.leave()
	quit(0 if ok else 1)


func _run() -> void:
	host = NetMatch.new()
	guest = NetMatch.new()
	root.add_child(host)
	root.add_child(guest)
	host.status_changed.connect(func(t): print("[방장] ", t))
	guest.status_changed.connect(func(t): print("[손님] ", t))
	host.action_received.connect(func(a, h): inbox[0].append([a, h]))
	guest.action_received.connect(func(a, h): inbox[1].append([a, h]))
	host.mulligan_received.connect(func(idx): mull_in[0] = idx)
	guest.mulligan_received.connect(func(idx): mull_in[1] = idx)

	host.host_room("fire")
	if not await _wait_until(func(): return host.mqtt.is_ready(), 40.0):
		_done(false, "방장이 서버에 연결하지 못함")
		return
	print("방 코드: ", host.room)
	guest.join_room(host.room, "steel")
	if not await _wait_until(func(): return host.is_matched and guest.is_matched, 30.0):
		_done(false, "방 참가(짝짓기) 실패")
		return
	if host.seed_value != guest.seed_value:
		_done(false, "시드가 다름")
		return

	for i in 2:
		g[i] = Game.new()
		g[i].start(host.heroes[0], host.heroes[1], host.seed_value, ["방장", "손님"])
	# 시작 손패 교체: 방장은 0번 카드 교체, 손님은 교체 안 함
	host.send_mulligan([0])
	guest.send_mulligan([])
	if not await _wait_until(func(): return mull_in[0] != null and mull_in[1] != null, 20.0):
		_done(false, "시작 손패 교체 메시지를 못 받음")
		return
	for i in 2:
		g[i].mulligan(0, [0])
		g[i].mulligan(1, [])
	if g[0].state_hash() != g[1].state_hash():
		_done(false, "시작 손패 교체 후 상태가 다름")
		return

	var ai := AI.new()
	var nets := [host, guest]
	var actions := 0
	while g[0].phase == "play" and actions < 400:
		var p: int = g[0].current
		var other := 1 - p
		var a: Dictionary = ai.choose_action(g[p], p)
		if a.is_empty():
			a = {"type": "end"}
		if not g[p].apply_action(p, a):
			a = {"type": "end"}
			g[p].apply_action(p, a)
		nets[p].send_action(a, g[p].state_hash())
		if not await _wait_until(func(): return not inbox[other].is_empty(), 20.0):
			_done(false, "행동 %d개째에서 상대가 메시지를 못 받음" % actions)
			return
		var got: Array = inbox[other].pop_front()
		var ok: bool = g[other].apply_action(p, got[0])
		if not ok or g[other].state_hash() != int(got[1]):
			_done(false, "행동 %d개째에서 상태가 달라짐 (%s)" % [actions, str(got[0])])
			return
		actions += 1
	_done(true, "행동 %d개, 두 기기 상태 일치, 승자 %d, 방 %s" % [actions, g[0].winner, host.room])
