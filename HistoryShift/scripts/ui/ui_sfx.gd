class_name UISfx
extends RefCounted
## UI 効果音。UISfx.play("hover"|"click"|"confirm"|"back"|"open"|"close"|"mark"|"error"|"success"|"history"|"warp"|"tick"|"page"|"toggle"|"select")
## 音は assets/audio/ui（Kenney Interface/UI Audio, CC0）とジングル。Audio（Master→SFX/Music バス）で鳴らす。

const KEYS := {
	"hover": "ui_hover", "click": "ui_click", "confirm": "ui_confirm", "back": "ui_back", "open": "ui_open",
	"close": "ui_close", "mark": "ui_mark", "error": "ui_error", "tick": "ui_tick", "toggle": "ui_toggle",
	"select": "ui_select", "toast": "ui_toast", "page": "book_page", "warp": "time_warp",
	"success": "stinger_success", "fail": "stinger_fail", "history": "stinger_history", "rin": "rin",
}
static var enabled := true


static func play(kind: String, volume_db := 0.0) -> void:
	if not enabled:
		return
	Audio.play(String(KEYS.get(kind, "ui_click")), volume_db)
