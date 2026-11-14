extends RefCounted
## 간단한 설정 저장 (user://settings.cfg).
## 도움말 팁 켜기/끄기, 이미 본 팁, 튜토리얼 완료 여부 등.

const PATH := "user://settings.cfg"

static var _cfg: ConfigFile = null


static func _load() -> void:
	if _cfg != null:
		return
	_cfg = ConfigFile.new()
	_cfg.load(PATH)


static func get_value(key: String, default: Variant) -> Variant:
	_load()
	return _cfg.get_value("main", key, default)


static func set_value(key: String, value: Variant) -> void:
	_load()
	_cfg.set_value("main", key, value)
	_cfg.save(PATH)


static func tips_on() -> bool:
	return bool(get_value("tips_on", true))


static func tip_seen(key: String) -> bool:
	_load()
	return bool(_cfg.get_value("tips_seen", key, false))


static func mark_tip(key: String) -> void:
	_load()
	_cfg.set_value("tips_seen", key, true)
	_cfg.save(PATH)


static func reset_tips() -> void:
	_load()
	if _cfg.has_section("tips_seen"):
		_cfg.erase_section("tips_seen")
	_cfg.save(PATH)
