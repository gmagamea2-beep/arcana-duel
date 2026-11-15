extends Node
## 온라인 1:1 대전 연결 (방 코드).
## 두 기기가 같은 시드로 같은 게임을 돌리고, 서로 '행동'만 주고받는다 (lockstep).
## 메시지는 번호를 붙여 보내고, 상대가 받았다고 할 때까지 다시 보낸다 (잠깐 끊겨도 복구).

signal status_changed(text: String)
signal matched
signal mulligan_received(idx: Array)
signal action_received(a: Dictionary, state_hash: int)
signal opponent_left(reason: String)
signal link_changed(ok: bool)

const MQTT = preload("res://net/mqtt.gd")
const PROTO := 1
## 공개 MQTT 중계 서버 (방 코드 첫 글자로 구분)
const BROKERS := {
	"A": "wss://broker.emqx.io:8084/mqtt",
	"B": "wss://broker.hivemq.com:8884/mqtt",
	"C": "wss://test.mosquitto.org:8081/mqtt",
}
const BROKER_ORDER := ["A", "B", "C"]
const CODE_CHARS := "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"

var mqtt: MQTT
var is_host := false
var room := ""
var my_index := 0
var my_hero := ""
var game_build := 0
var seed_value := 0
var heroes: Array = ["", ""]
var is_matched := false
var closed := false

var _token := ""
var _peer_token := ""
var _out_seq := 0
var _outbox := {}
var _in_seq := 0
var _pending := {}
var _last_rx := 0
var _last_resend := 0
var _last_ping := 0
var _broker_try := 0
var _link_ok := true


func _ready() -> void:
	mqtt = MQTT.new()
	add_child(mqtt)
	mqtt.connected.connect(_on_connected)
	mqtt.disconnected.connect(_on_disconnected)
	mqtt.message.connect(_on_message)
	_token = "%x" % (randi() & 0xFFFFFF)


# ── 방 만들기 / 참가 ──

func host_room(hero: String) -> void:
	is_host = true
	my_index = 0
	my_hero = hero
	_broker_try = 0
	_try_host_broker()


func _try_host_broker() -> void:
	var letter: String = BROKER_ORDER[_broker_try]
	room = letter
	for i in 4:
		room += CODE_CHARS[randi() % CODE_CHARS.length()]
	mqtt.subs.clear()
	mqtt.subscribe(_topic("g2h"))
	status_changed.emit("서버에 연결하는 중... (%s)" % letter)
	mqtt.connect_to(BROKERS[letter])


func join_room(code: String, hero: String) -> bool:
	code = code.strip_edges().to_upper()
	if code.length() != 5 or not BROKERS.has(code[0]):
		status_changed.emit("방 코드가 올바르지 않아요 (5글자)")
		return false
	is_host = false
	my_index = 1
	my_hero = hero
	room = code
	mqtt.subs.clear()
	mqtt.subscribe(_topic("h2g"))
	status_changed.emit("서버에 연결하는 중...")
	mqtt.connect_to(BROKERS[code[0]])
	return true


func leave() -> void:
	if closed:
		return
	if is_matched:
		_publish_raw({"t": "bye", "tok": _token})
	closed = true
	mqtt.close()


func _topic(dir: String) -> String:
	return "arcanaduel/v%d/%s/%s" % [PROTO, room, dir]


func _out_topic() -> String:
	return _topic("h2g") if is_host else _topic("g2h")


# ── 보내기 ──

func send_mulligan(idx: Array) -> void:
	_send_reliable({"t": "mull", "idx": idx})


func send_action(a: Dictionary, state_hash: int) -> void:
	_send_reliable({"t": "act", "a": a, "h": state_hash})


func _send_reliable(msg: Dictionary) -> void:
	_out_seq += 1
	msg["n"] = _out_seq
	msg["tok"] = _token
	_outbox[_out_seq] = msg
	_publish_raw(msg)


func _publish_raw(msg: Dictionary) -> void:
	mqtt.publish(_out_topic(), JSON.stringify(msg))


# ── 받기 ──

func _on_connected() -> void:
	_last_rx = Time.get_ticks_msec()
	if is_host and not is_matched:
		status_changed.emit("방을 만들었어요! 상대에게 코드를 알려 주세요")
	elif not is_host and not is_matched:
		status_changed.emit("방에 들어가는 중...")
		_send_reliable({"t": "hello", "hero": my_hero, "proto": PROTO, "build": game_build})
	# 다시 연결됐으면 못 받은 메시지 다시 보내기
	for n in _outbox:
		_publish_raw(_outbox[n])


func _on_disconnected() -> void:
	if closed:
		return
	if is_host and not is_matched and _broker_try < BROKER_ORDER.size() - 1 and mqtt.state == "idle" and _last_rx == 0:
		# 이 서버가 안 되면 다음 공개 서버로
		_broker_try += 1
		_try_host_broker()
		return
	if not is_host and not is_matched and _last_rx == 0:
		status_changed.emit("서버에 연결하지 못했어요. 잠시 후 다시 시도해 주세요")
		return
	_set_link(false)
	# 잠시 후 다시 연결
	await get_tree().create_timer(2.0).timeout
	if not closed and mqtt.state == "idle":
		mqtt.connect_to(mqtt.url)


func _on_message(_topic_name: String, payload: String) -> void:
	var msg: Variant = JSON.parse_string(payload)
	if not (msg is Dictionary):
		return
	var tok: String = str(msg.get("tok", ""))
	if is_matched and tok != _peer_token:
		return  # 다른 사람이 같은 방 코드를 쓴 경우 무시
	_last_rx = Time.get_ticks_msec()
	_set_link(true)
	var t: String = str(msg.get("t", ""))
	if t == "ack":
		var upto := int(msg.get("n", 0))
		for n in _outbox.keys():
			if int(n) <= upto:
				_outbox.erase(n)
		return
	if t == "ping":
		return
	if t == "bye":
		opponent_left.emit("left")
		return
	if not msg.has("n"):
		return
	var n2 := int(msg["n"])
	if n2 == _in_seq + 1:
		_in_seq = n2
		_deliver(msg)
		while _pending.has(_in_seq + 1):
			_in_seq += 1
			_deliver(_pending[_in_seq])
			_pending.erase(_in_seq)
	elif n2 > _in_seq + 1:
		_pending[n2] = msg
	_publish_raw({"t": "ack", "n": _in_seq, "tok": _token})


func _deliver(msg: Dictionary) -> void:
	match str(msg.get("t", "")):
		"hello":
			if not is_host or is_matched:
				return
			if int(msg.get("proto", 0)) != PROTO or int(msg.get("build", 0)) != game_build:
				_publish_raw({"t": "reject", "tok": _token, "build": game_build})
				status_changed.emit("상대와 게임 버전이 달라요 (나: 빌드 %d, 상대: 빌드 %d). 둘 다 최신으로 업데이트해 주세요" % [game_build, int(msg.get("build", 0))])
				return
			_peer_token = str(msg.get("tok", ""))
			seed_value = randi()
			heroes = [my_hero, str(msg.get("hero", "fire"))]
			is_matched = true
			_send_reliable({"t": "start", "seed": seed_value, "heroes": heroes})
			status_changed.emit("상대가 들어왔어요!")
			matched.emit()
		"start":
			if is_host or is_matched:
				return
			_peer_token = str(msg.get("tok", ""))
			seed_value = int(msg.get("seed", 0))
			heroes = msg.get("heroes", ["fire", "fire"])
			is_matched = true
			status_changed.emit("대전 시작!")
			matched.emit()
		"mull":
			mulligan_received.emit(msg.get("idx", []))
		"act":
			action_received.emit(msg.get("a", {}), int(msg.get("h", 0)))


func _set_link(ok: bool) -> void:
	if ok != _link_ok:
		_link_ok = ok
		link_changed.emit(ok)


func _process(_delta: float) -> void:
	if closed or mqtt == null:
		return
	var now := Time.get_ticks_msec()
	# 상대가 받았다고 하기 전까지 2초마다 다시 보내기
	if not _outbox.is_empty() and now - _last_resend > 2000 and mqtt.is_ready():
		_last_resend = now
		for n in _outbox:
			_publish_raw(_outbox[n])
	if is_matched and mqtt.is_ready() and now - _last_ping > 5000:
		_last_ping = now
		_publish_raw({"t": "ping", "tok": _token})
	if is_matched and _last_rx > 0:
		if now - _last_rx > 15000:
			_set_link(false)
		if now - _last_rx > 90000:
			closed = true
			opponent_left.emit("timeout")
