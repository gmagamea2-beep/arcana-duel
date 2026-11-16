extends Node
## 온라인 대전 연결 (방 코드). 1:1, 1:1:1, 2:2.
## 모두 같은 시드로 같은 게임을 돌리고 '행동'만 주고받는다 (lockstep).
## 방의 모든 사람이 한 주제(topic)로 보내고 받는다.
## - 메시지마다 보낸 사람별 번호(n)를 붙이고, 다른 모든 사람이 받았다고 할 때까지 다시 보낸다.
## - 행동에는 전체 순번(step)을 붙여 모두가 같은 순서로 적용한다.
## - 빈 자리와 나간 사람 자리는 방장 기기의 AI가 맡고, 방장이 그 행동을 보낸다.

signal status_changed(text: String)
signal lobby_changed
signal matched
signal mulligan_received(seat: int, idx: Array)
signal action_received(step: int, seat: int, a: Dictionary, state_hash: int)
## 나간 사람 자리를 방장 AI가 맡게 됨 (다인전)
signal seat_ai_changed(seat: int)
## 1:1 에서 상대가 나감 / 방장이 나감
signal opponent_left(reason: String)
signal link_changed(ok: bool)

const MQTT = preload("res://net/mqtt.gd")
const PROTO := 2
## 공개 MQTT 중계 서버 (방 코드 첫 글자로 구분)
const BROKERS := {
	"A": "wss://broker.emqx.io:8084/mqtt",
	"B": "wss://broker.hivemq.com:8884/mqtt",
	"C": "wss://test.mosquitto.org:8081/mqtt",
}
const BROKER_ORDER := ["A", "B", "C"]
const CODE_CHARS := "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
const MODES := {
	"1v1": {"cap": 2, "teams": [0, 1], "name": "1 : 1"},
	"ffa3": {"cap": 3, "teams": [0, 1, 2], "name": "1 : 1 : 1"},
	"2v2": {"cap": 4, "teams": [0, 1, 0, 1], "name": "2 : 2"},
}
const SILENT_LIMIT := 25000

var mqtt: MQTT
var is_host := false
var room := ""
var mode := "1v1"
var my_seat := 0
var my_hero := ""
var game_build := 0
var seed_value := 0
## 자리별 영웅 / 팀 / 기기 토큰("" = AI) / AI가 맡는지
var heroes: Array = []
var teams: Array = []
var seat_tok: Array = []
var seat_ai: Array = []
## 대기실 사람들 [{"tok", "hero"}] (방장 먼저)
var members: Array = []
var is_matched := false
var closed := false

var _token := ""
var _host_tok := ""
var _out_seq := 0
var _outbox := {}
var _acked := {}
var _peers: Array = []
var _in_seq := {}
var _pending := {}
var _last_rx := {}
var _last_resend := 0
var _last_ping := 0
var _broker_try := 0
var _link_ok := true
var _connected_once := false


## 1:1 예전 이름 호환
var my_index: int:
	get:
		return my_seat


func _init() -> void:
	# 트리에 들어가기 전에도 바로 쓸 수 있게 생성자에서 만든다
	mqtt = MQTT.new()
	add_child(mqtt)
	mqtt.connected.connect(_on_connected)
	mqtt.disconnected.connect(_on_disconnected)
	mqtt.message.connect(_on_message)
	_token = "%x" % (randi() & 0xFFFFFF)


func capacity() -> int:
	return int(MODES[mode]["cap"])


# ── 방 만들기 / 참가 ──

func host_room(hero: String, p_mode: String = "1v1") -> void:
	is_host = true
	mode = p_mode if MODES.has(p_mode) else "1v1"
	my_seat = 0
	my_hero = hero
	_host_tok = _token
	members = [{"tok": _token, "hero": hero}]
	_broker_try = 0
	_try_host_broker()


func _try_host_broker() -> void:
	var letter: String = BROKER_ORDER[_broker_try]
	room = letter
	for i in 4:
		room += CODE_CHARS[randi() % CODE_CHARS.length()]
	mqtt.subs.clear()
	mqtt.subscribe(_topic())
	status_changed.emit("서버에 연결하는 중... (%s)" % letter)
	mqtt.connect_to(BROKERS[letter])


func join_room(code: String, hero: String) -> bool:
	code = code.strip_edges().to_upper()
	if code.length() != 5 or not BROKERS.has(code[0]):
		status_changed.emit("방 코드가 올바르지 않아요 (5글자)")
		return false
	is_host = false
	my_hero = hero
	room = code
	mqtt.subs.clear()
	mqtt.subscribe(_topic())
	status_changed.emit("서버에 연결하는 중...")
	mqtt.connect_to(BROKERS[code[0]])
	return true


## 방장: 빈 자리를 AI로 채우고 바로 시작
func host_start() -> void:
	if not is_host or is_matched:
		return
	seed_value = randi()
	var cap := capacity()
	heroes = []
	seat_tok = []
	seat_ai = []
	teams = (MODES[mode]["teams"] as Array).duplicate()
	var pool: Array = preload("res://core/card_db.gd").hero_order.duplicate()
	for m in members:
		pool.erase(m["hero"])
	pool.shuffle()
	for i in cap:
		if i < members.size():
			heroes.append(members[i]["hero"])
			seat_tok.append(members[i]["tok"])
			seat_ai.append(false)
		else:
			heroes.append(pool[i % pool.size()])
			seat_tok.append("")
			seat_ai.append(true)
	var base := {}
	for m in members:
		if m["tok"] != _token:
			base[m["tok"]] = int(_in_seq.get(m["tok"], 0))
	_peers = _human_peers()
	is_matched = true
	_send_reliable({"t": "start", "seed": seed_value, "mode": mode, "heroes": heroes, "teams": teams, "toks": seat_tok, "base": base})
	status_changed.emit("대전 시작!")
	matched.emit()


func leave() -> void:
	if closed:
		return
	_publish_raw({"t": "bye", "tok": _token})
	closed = true
	mqtt.close()


func _topic() -> String:
	return "arcanaduel/v%d/%s/all" % [PROTO, room]


func _human_peers() -> Array:
	var res: Array = []
	if is_matched:
		for i in seat_tok.size():
			if seat_tok[i] != "" and seat_tok[i] != _token and not seat_ai[i]:
				res.append(seat_tok[i])
	elif is_host:
		for m in members:
			if m["tok"] != _token:
				res.append(m["tok"])
	elif _host_tok != "":
		res.append(_host_tok)
	return res


# ── 보내기 ──

func send_mulligan(seat: int, idx: Array) -> void:
	_send_reliable({"t": "mull", "seat": seat, "idx": idx})


func send_action(step: int, seat: int, a: Dictionary, state_hash: int) -> void:
	_send_reliable({"t": "act", "step": step, "seat": seat, "a": a, "h": state_hash})


func _send_reliable(msg: Dictionary) -> void:
	_out_seq += 1
	msg["n"] = _out_seq
	msg["tok"] = _token
	_outbox[_out_seq] = msg
	_publish_raw(msg)


func _publish_raw(msg: Dictionary) -> void:
	if not msg.has("tok"):
		msg["tok"] = _token
	mqtt.publish(_topic(), JSON.stringify(msg))


func _all_acked(n: int) -> bool:
	if _peers.is_empty():
		return false
	for t in _peers:
		if int(_acked.get(t, 0)) < n:
			return false
	return true


# ── 받기 ──

func _on_connected() -> void:
	_connected_once = true
	var now := Time.get_ticks_msec()
	for t in _last_rx:
		_last_rx[t] = now
	if is_host and not is_matched:
		status_changed.emit("방을 만들었어요! 친구에게 코드를 알려 주세요")
		_send_lobby()
	elif not is_host and not is_matched:
		status_changed.emit("방에 들어가는 중...")
		if _outbox.is_empty():
			_send_reliable({"t": "hello", "hero": my_hero, "proto": PROTO, "build": game_build})
	for n in _outbox:
		_publish_raw(_outbox[n])


func _on_disconnected() -> void:
	if closed:
		return
	if is_host and not is_matched and _broker_try < BROKER_ORDER.size() - 1 and mqtt.state == "idle" and not _connected_once:
		# 이 서버가 안 되면 다음 공개 서버로
		_broker_try += 1
		_try_host_broker()
		return
	if not is_host and not is_matched and not _connected_once:
		status_changed.emit("서버에 연결하지 못했어요. 잠시 후 다시 시도해 주세요")
		return
	_set_link(false)
	# 잠시 후 다시 연결
	await get_tree().create_timer(2.0).timeout
	if not closed and mqtt.state == "idle":
		mqtt.connect_to(mqtt.url)


func _known(tok: String) -> bool:
	if is_matched:
		return seat_tok.has(tok)
	if is_host:
		return true
	return _host_tok == "" or tok == _host_tok


func _on_message(_topic_name: String, payload: String) -> void:
	var msg: Variant = JSON.parse_string(payload)
	if not (msg is Dictionary):
		return
	var tok: String = str(msg.get("tok", ""))
	if tok == "" or tok == _token:
		return  # 내가 보낸 것 (서버가 되돌려 줌)
	var t: String = str(msg.get("t", ""))
	if t == "ack":
		if str(msg.get("to", "")) == _token:
			_acked[tok] = maxi(int(_acked.get(tok, 0)), int(msg.get("n", 0)))
			for n in _outbox.keys():
				if _all_acked(int(n)):
					_outbox.erase(n)
		_touch(tok)
		return
	if not _known(tok):
		return
	_touch(tok)
	if t == "ping":
		return
	if t == "bye":
		_peer_gone(tok, "left")
		return
	if t == "reject":
		if str(msg.get("to", "")) == _token and not is_matched:
			status_changed.emit(str(msg.get("why", "들어갈 수 없는 방이에요")))
			_outbox.clear()
		return
	if not msg.has("n"):
		return
	var n2 := int(msg["n"])
	if not _in_seq.has(tok):
		_in_seq[tok] = n2 - 1
		_pending[tok] = {}
	if n2 == int(_in_seq[tok]) + 1:
		_in_seq[tok] = n2
		_deliver(tok, msg)
		var pend: Dictionary = _pending[tok]
		while pend.has(int(_in_seq[tok]) + 1):
			_in_seq[tok] = int(_in_seq[tok]) + 1
			var m2: Dictionary = pend[int(_in_seq[tok])]
			pend.erase(int(_in_seq[tok]))
			_deliver(tok, m2)
	elif n2 > int(_in_seq[tok]) + 1:
		(_pending[tok] as Dictionary)[n2] = msg
	_publish_raw({"t": "ack", "to": tok, "n": int(_in_seq.get(tok, 0))})


func _touch(tok: String) -> void:
	_last_rx[tok] = Time.get_ticks_msec()


func _deliver(tok: String, msg: Dictionary) -> void:
	match str(msg.get("t", "")):
		"hello":
			if not is_host or is_matched:
				return
			if int(msg.get("proto", 0)) != PROTO or int(msg.get("build", 0)) != game_build:
				_publish_raw({"t": "reject", "to": tok, "why": "방장과 게임 버전이 달라요 (방장: 빌드 %d). 둘 다 최신으로 업데이트해 주세요" % game_build})
				status_changed.emit("버전이 다른 사람이 들어오려고 했어요 (상대 빌드 %d)" % int(msg.get("build", 0)))
				return
			for m in members:
				if m["tok"] == tok:
					return
			if members.size() >= capacity():
				_publish_raw({"t": "reject", "to": tok, "why": "방이 가득 찼어요"})
				return
			members.append({"tok": tok, "hero": str(msg.get("hero", "fire"))})
			_peers = _human_peers()
			status_changed.emit("%d / %d명 모였어요" % [members.size(), capacity()])
			lobby_changed.emit()
			if members.size() >= capacity():
				host_start()
			else:
				_send_lobby()
		"lobby":
			if is_host or is_matched:
				return
			_host_tok = tok
			mode = str(msg.get("mode", "1v1"))
			members = msg.get("members", [])
			_peers = _human_peers()
			status_changed.emit("대기실: %d / %d명 · 방장이 시작하기를 기다리는 중" % [members.size(), capacity()])
			lobby_changed.emit()
		"start":
			if is_host or is_matched:
				return
			_host_tok = tok
			seed_value = int(msg.get("seed", 0))
			mode = str(msg.get("mode", "1v1"))
			heroes = msg.get("heroes", [])
			teams = []
			for x in msg.get("teams", []):
				teams.append(int(x))
			seat_tok = msg.get("toks", [])
			seat_ai = []
			my_seat = -1
			for i in seat_tok.size():
				seat_ai.append(seat_tok[i] == "")
				if seat_tok[i] == _token:
					my_seat = i
			if my_seat < 0:
				status_changed.emit("방이 이미 시작됐어요")
				return
			# 다른 손님의 메시지 번호 시작점
			var base: Dictionary = msg.get("base", {})
			for bt in base:
				if bt != _token and not _in_seq.has(bt):
					_in_seq[bt] = int(base[bt])
					_pending[bt] = {}
			is_matched = true
			_peers = _human_peers()
			var now := Time.get_ticks_msec()
			for st in seat_tok:
				if st != "":
					_last_rx[st] = now
			status_changed.emit("대전 시작!")
			matched.emit()
		"mull":
			mulligan_received.emit(int(msg.get("seat", 0)), msg.get("idx", []))
		"act":
			var seat := int(msg.get("seat", -1))
			# 그 자리 주인이거나, AI 자리는 방장만 보낼 수 있다
			if seat < 0 or seat >= seat_tok.size():
				return
			if seat_tok[seat] != tok and not (seat_ai[seat] and tok == _host_tok):
				return
			action_received.emit(int(msg.get("step", 0)), seat, msg.get("a", {}), int(msg.get("h", 0)))
		"ai":
			var s2 := int(msg.get("seat", -1))
			if s2 >= 0 and s2 < seat_ai.size() and tok == _host_tok:
				seat_ai[s2] = true
				_peers = _human_peers()
				seat_ai_changed.emit(s2)


func _send_lobby() -> void:
	_send_reliable({"t": "lobby", "mode": mode, "members": members})


## 누군가 나감 (bye 또는 오래 조용함)
func _peer_gone(tok: String, reason: String) -> void:
	if not is_matched:
		if is_host:
			for i in range(members.size() - 1, -1, -1):
				if members[i]["tok"] == tok:
					members.remove_at(i)
			_peers = _human_peers()
			lobby_changed.emit()
			_send_lobby()
		elif tok == _host_tok:
			status_changed.emit("방장이 방을 나갔어요")
		return
	if tok == _host_tok and not is_host:
		closed = true
		opponent_left.emit("host_" + reason)
		return
	var seat := seat_tok.find(tok)
	if seat < 0 or seat_ai[seat]:
		return
	if mode == "1v1":
		closed = true
		opponent_left.emit(reason)
		return
	if is_host:
		seat_ai[seat] = true
		_peers = _human_peers()
		_send_reliable({"t": "ai", "seat": seat})
		seat_ai_changed.emit(seat)


func _set_link(ok: bool) -> void:
	if ok != _link_ok:
		_link_ok = ok
		link_changed.emit(ok)


func _process(_delta: float) -> void:
	if closed or mqtt == null:
		return
	var now := Time.get_ticks_msec()
	# 모두가 받았다고 하기 전까지 2초마다 다시 보내기
	if not _outbox.is_empty() and now - _last_resend > 2000 and mqtt.is_ready():
		_last_resend = now
		for n in _outbox:
			_publish_raw(_outbox[n])
	if mqtt.is_ready() and now - _last_ping > 5000 and (is_matched or members.size() > 1 or _host_tok != ""):
		_last_ping = now
		_publish_raw({"t": "ping"})
	if not is_matched and not is_host:
		return
	var worst := 0
	for tok in _human_peers():
		var last := int(_last_rx.get(tok, now))
		if not _last_rx.has(tok):
			_last_rx[tok] = now
		worst = maxi(worst, now - last)
		if now - last > SILENT_LIMIT:
			_peer_gone(tok, "timeout")
			return
	_set_link(worst < 12000)
