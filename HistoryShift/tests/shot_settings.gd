extends Node

const SettingsScreen := preload("res://scripts/ui/settings_screen.gd")
## 設定画面と FPS 表示を撮る: xvfb-run -a godot --rendering-driver vulkan --path . res://tests/shot_settings.tscn -- <out.png>

func _ready() -> void:
	var out := "user://settings.png"
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out = args[0]
	get_window().size = Vector2i(1920, 1080)
	var ui := Control.new()
	ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(ui)
	var bg := ColorRect.new()
	bg.color = Color(0.25, 0.35, 0.3)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui.add_child(bg)
	FpsOverlay.set_visible_on(self, true)
	SettingsScreen.open(ui)
	for i in 60:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(out)
	get_tree().quit()
