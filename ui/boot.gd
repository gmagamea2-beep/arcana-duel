extends Control
## 시작 화면 (자동 업데이트).
## 1) 전에 받아 둔 패치(.pck)가 있으면 적용
## 2) GitHub 최신 릴리스의 version.json 을 확인해서 더 새 빌드면 패치를 받아 바로 적용
## 3) 메인 메뉴로 이동
## 주의: 이 스크립트는 다른 게임 스크립트를 미리 불러오면 안 된다 (패치보다 먼저 올라가 버림).

const REPO := "gmagamea2-beep/arcana-duel"
const LATEST := "https://github.com/" + REPO + "/releases/latest/download/"
const PATCH_INFO := "user://patch.json"
const MAIN := "res://ui/main.tscn"

var status: Label
var bar: ProgressBar
var _req: HTTPRequest = null


func _ready() -> void:
	_build_ui()
	var st := {"state": "offline", "app_build": 0, "current": 0}
	var app := _read_json(FileAccess.get_file_as_string("res://data/version.json"))
	var app_build := int(app.get("build", 0))
	# 빌드 점검용: 옛날 앱인 척해서 실제로 패치를 받아 적용해 본다
	if OS.get_environment("ARCANA_UPDATE_TEST") == "1" and app_build > 0:
		app_build = 1
	st["app_build"] = app_build
	var current := app_build

	# 1) 받아 둔 패치 적용
	var info := _read_json(FileAccess.get_file_as_string(PATCH_INFO))
	var patch_build := int(info.get("build", 0))
	var patch_file: String = info.get("file", "")
	if patch_build > app_build and str(info.get("engine", "")) == _engine() and patch_file != "" and FileAccess.file_exists(patch_file):
		if ProjectSettings.load_resource_pack(patch_file, true):
			current = patch_build
	_cleanup(patch_file if current == patch_build and current > app_build else "")
	st["current"] = current

	# 2) 새 버전 확인 (에디터에서 실행했거나 직접 만든 빌드면 건너뜀)
	if app_build <= 0 or OS.has_feature("editor"):
		st["state"] = "dev"
	else:
		status.text = "업데이트 확인 중..."
		var remote: Variant = await _get_json(LATEST + "version.json")
		if remote is Dictionary:
			var rb := int(remote.get("build", 0))
			st["remote"] = rb
			if rb <= current:
				st["state"] = "latest"
			elif str(remote.get("engine", "")) != _engine() or int(remote.get("min_app_build", 0)) > app_build:
				st["state"] = "need_install"
				st["url"] = LATEST + ("ArcanaDuel.apk" if OS.has_feature("android") else "ArcanaDuel.exe")
			else:
				status.text = "새 업데이트 받는 중... (빌드 %d)" % rb
				var path := "user://patch_%d.pck" % rb
				var ok: bool = await _download(LATEST + _pack_name(), path)
				if ok and ProjectSettings.load_resource_pack(path, true):
					_save_info({"build": rb, "engine": _engine(), "file": path})
					_cleanup(path)
					st["current"] = rb
					st["state"] = "updated"
					status.text = "업데이트 완료! (빌드 %d)" % rb
					await get_tree().create_timer(0.6).timeout
				else:
					st["state"] = "failed"
	Engine.set_meta("update_status", st)
	print("부트 상태: ", st)
	get_tree().change_scene_to_file.call_deferred(MAIN)


func _process(_delta: float) -> void:
	if _req != null and is_instance_valid(_req):
		var total := _req.get_body_size()
		if total > 0:
			bar.visible = true
			bar.max_value = total
			bar.value = _req.get_downloaded_bytes()


func _engine() -> String:
	var v := Engine.get_version_info()
	return "%d.%d.%d" % [v["major"], v["minor"], v["patch"]]


func _pack_name() -> String:
	return "patch_android.pck" if OS.has_feature("android") else "patch_windows.pck"


func _read_json(txt: String) -> Dictionary:
	if txt == "":
		return {}
	var d: Variant = JSON.parse_string(txt)
	return d if d is Dictionary else {}


func _save_info(d: Dictionary) -> void:
	var f := FileAccess.open(PATCH_INFO, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(d))


## 지금 쓰는 패치 말고 남은 옛 패치 파일 지우기
func _cleanup(keep: String) -> void:
	var dir := DirAccess.open("user://")
	if dir == null:
		return
	for fn in dir.get_files():
		if fn.begins_with("patch_") and fn.ends_with(".pck") and "user://" + fn != keep:
			dir.remove(fn)


func _get_json(url: String) -> Variant:
	var req := HTTPRequest.new()
	req.timeout = 6.0
	add_child(req)
	if req.request(url) != OK:
		req.queue_free()
		return null
	var res: Array = await req.request_completed
	req.queue_free()
	if int(res[0]) != HTTPRequest.RESULT_SUCCESS or int(res[1]) != 200:
		return null
	return JSON.parse_string((res[3] as PackedByteArray).get_string_from_utf8())


func _download(url: String, path: String) -> bool:
	var req := HTTPRequest.new()
	req.timeout = 120.0
	req.download_file = path
	add_child(req)
	_req = req
	if req.request(url) != OK:
		req.queue_free()
		_req = null
		return false
	var res: Array = await req.request_completed
	_req = null
	req.queue_free()
	var ok := int(res[0]) == HTTPRequest.RESULT_SUCCESS and int(res[1]) == 200 and FileAccess.file_exists(path)
	if not ok and FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	return ok


func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color("#12141a")
	add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 24)
	center.add_child(v)
	var title := Label.new()
	title.text = "아르카나 듀얼"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 80)
	v.add_child(title)
	status = Label.new()
	status.text = "불러오는 중..."
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status.add_theme_font_size_override("font_size", 30)
	status.add_theme_color_override("font_color", Color("#b9bfcb"))
	v.add_child(status)
	bar = ProgressBar.new()
	bar.custom_minimum_size = Vector2(600, 28)
	bar.visible = false
	v.add_child(bar)
