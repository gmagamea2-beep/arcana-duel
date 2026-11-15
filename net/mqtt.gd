extends Node
## 아주 작은 MQTT 3.1.1 클라이언트 (WebSocket 위, QoS 0).
## 공개 MQTT 중계 서버를 통해 메시지를 주고받는 데만 쓴다.

signal connected
signal disconnected
signal message(topic: String, payload: String)

var ws := WebSocketPeer.new()
var url := ""
var client_id := ""
var subs: Array = []
## idle / connecting / ws_open / ready
var state := "idle"
var _buf := PackedByteArray()
var _pid := 1
var _last_ping := 0
var _connect_started := 0


func connect_to(p_url: String) -> void:
	url = p_url
	if client_id == "":
		client_id = "ad-%d-%d" % [Time.get_ticks_usec() % 1000000, randi() % 100000]
	ws = WebSocketPeer.new()
	ws.supported_protocols = PackedStringArray(["mqtt"])
	_buf = PackedByteArray()
	var err := ws.connect_to_url(url, TLSOptions.client())
	state = "connecting" if err == OK else "idle"
	_connect_started = Time.get_ticks_msec()
	if err != OK:
		disconnected.emit()


func close() -> void:
	if state == "ready":
		_send(PackedByteArray([0xE0, 0x00]))
	ws.close()
	state = "idle"


func is_ready() -> bool:
	return state == "ready"


func subscribe(topic: String) -> void:
	if not subs.has(topic):
		subs.append(topic)
	if state == "ready":
		_send_subscribe(topic)


func publish(topic: String, payload: String) -> void:
	if state != "ready":
		return
	var body := PackedByteArray()
	body.append_array(_str(topic))
	body.append_array(payload.to_utf8_buffer())
	_send(_packet(0x30, body))


func _process(_delta: float) -> void:
	if state == "idle":
		return
	ws.poll()
	var st := ws.get_ready_state()
	if st == WebSocketPeer.STATE_OPEN:
		if state == "connecting":
			state = "ws_open"
			_send_connect()
		while ws.get_available_packet_count() > 0:
			_buf.append_array(ws.get_packet())
		_parse()
		if state == "ready" and Time.get_ticks_msec() - _last_ping > 20000:
			_send(PackedByteArray([0xC0, 0x00]))
			_last_ping = Time.get_ticks_msec()
	elif st == WebSocketPeer.STATE_CLOSED:
		state = "idle"
		disconnected.emit()
	elif state == "connecting" and Time.get_ticks_msec() - _connect_started > 10000:
		ws.close()
		state = "idle"
		disconnected.emit()


# ── 패킷 만들기 ──

func _str(s: String) -> PackedByteArray:
	var b := s.to_utf8_buffer()
	var out := PackedByteArray([(b.size() >> 8) & 0xFF, b.size() & 0xFF])
	out.append_array(b)
	return out


func _packet(header: int, body: PackedByteArray) -> PackedByteArray:
	var out := PackedByteArray([header])
	var n := body.size()
	while true:
		var byte := n % 128
		n = n / 128
		if n > 0:
			byte |= 0x80
		out.append(byte)
		if n == 0:
			break
	out.append_array(body)
	return out


func _send(bytes: PackedByteArray) -> void:
	ws.send(bytes, WebSocketPeer.WRITE_MODE_BINARY)


func _send_connect() -> void:
	var body := PackedByteArray()
	body.append_array(_str("MQTT"))
	body.append(4)  # 프로토콜 레벨 3.1.1
	body.append(0x02)  # clean session
	body.append_array(PackedByteArray([0, 60]))  # keep alive 60초
	body.append_array(_str(client_id))
	_send(_packet(0x10, body))


func _send_subscribe(topic: String) -> void:
	_pid = (_pid % 60000) + 1
	var body := PackedByteArray([(_pid >> 8) & 0xFF, _pid & 0xFF])
	body.append_array(_str(topic))
	body.append(0)  # QoS 0
	_send(_packet(0x82, body))


# ── 패킷 읽기 ──

func _parse() -> void:
	while _buf.size() >= 2:
		# 남은 길이 (가변 길이 정수)
		var mult := 1
		var length := 0
		var i := 1
		var complete := false
		while i < _buf.size() and i <= 4:
			var b := _buf[i]
			length += (b & 0x7F) * mult
			mult *= 128
			i += 1
			if (b & 0x80) == 0:
				complete = true
				break
		if not complete or _buf.size() < i + length:
			return
		var header := _buf[0]
		var body := _buf.slice(i, i + length)
		_buf = _buf.slice(i + length)
		_handle(header, body)


func _handle(header: int, body: PackedByteArray) -> void:
	var kind := header >> 4
	match kind:
		2:  # CONNACK
			if body.size() >= 2 and body[1] == 0:
				state = "ready"
				_last_ping = Time.get_ticks_msec()
				for t in subs:
					_send_subscribe(t)
				connected.emit()
			else:
				close()
				disconnected.emit()
		3:  # PUBLISH
			var qos := (header >> 1) & 0x03
			if body.size() < 2:
				return
			var tlen := (body[0] << 8) | body[1]
			var topic := body.slice(2, 2 + tlen).get_string_from_utf8()
			var pos := 2 + tlen
			if qos > 0:
				var pid_hi := body[pos]
				var pid_lo := body[pos + 1]
				pos += 2
				if qos == 1:
					_send(PackedByteArray([0x40, 0x02, pid_hi, pid_lo]))
			message.emit(topic, body.slice(pos).get_string_from_utf8())
		_:
			pass  # SUBACK, PINGRESP 등은 무시
