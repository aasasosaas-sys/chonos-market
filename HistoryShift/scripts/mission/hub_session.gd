class_name HubSession
extends Node3D
## 2026年のハブを歩く（PresentWorld＋Player＋CameraRig＋小さな案内表示）。Flow.show_hub が作る。
## 研究所の操作卓（時空転送装置）で E → open_menu（Flow が採点ハブの画面＝問題の一覧・時代選択・自由探索を出す）。
## Esc でも同じ画面を開く。町の姿はこの世界の最終の歴史で変わる（HistoryVisuals.present → PresentWorld）。

signal open_menu

const INTERACT_R := 2.8

var world: PresentWorld
var player: Player
var cam: CameraRig
var active := true
var _ui: CanvasLayer
var _prompt: Label
var _info: Label
var _near := false


static func create(pr: Dictionary = {}) -> HubSession:
	var s := HubSession.new()
	s.name = "HubSession"
	s.world = PresentWorld.build(pr if not pr.is_empty() else HistoryVisuals.present(Game.state if Game.state else null))
	return s


func _ready() -> void:
	add_to_group("hub_session")
	add_child(world)
	Game.set_world(world)
	cam = CameraRig.new()
	add_child(cam)
	player = Player.new()
	add_child(player)
	player.global_position = world.player_spawn
	player.rotation.y = 0.0
	player.god_mode = true
	cam.set_target(player, CameraRig.Mode.ON_FOOT)
	cam.yaw = 0.0
	cam.snap()
	AmbienceDirector.attach(self, "present", true)   # 研究所の機械音・外の往来
	_build_ui()


func _build_ui() -> void:
	_ui = CanvasLayer.new()
	_ui.layer = 5
	add_child(_ui)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = JSUI.theme()
	_ui.add_child(root)
	_info = Label.new()
	_info.position = Vector2(28, 22)
	_info.add_theme_font_size_override("font_size", 20)
	_info.add_theme_color_override("font_color", Color(0.95, 0.97, 1.0))
	_info.add_theme_color_override("font_outline_color", Color(0.05, 0.06, 0.1))
	_info.add_theme_constant_override("outline_size", 6)
	var pr := world.pr
	_info.text = "令和八年（2026年）　時空研究所\n首都：%s　／　%s\n%s\n操作卓で E：時代を選ぶ　　Esc：一覧" % [pr.get("city", "東京"), pr.get("style_label", ""), pr.get("lang_label", "")]
	root.add_child(_info)
	_prompt = Label.new()
	_prompt.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_prompt.position = Vector2(-220, -120)
	_prompt.size = Vector2(440, 40)
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.add_theme_font_size_override("font_size", 26)
	_prompt.add_theme_color_override("font_color", Color(0.6, 1.0, 0.92))
	_prompt.add_theme_color_override("font_outline_color", Color(0.02, 0.05, 0.08))
	_prompt.add_theme_constant_override("outline_size", 8)
	_prompt.text = "E：時空転送装置（時代を選ぶ）"
	_prompt.visible = false
	root.add_child(_prompt)


## Flow が UI 画面の前後で切り替える（画面を出している間は描画も処理も止める）
func set_active(on: bool) -> void:
	active = on
	visible = on
	process_mode = Node.PROCESS_MODE_INHERIT if on else Node.PROCESS_MODE_DISABLED
	if _ui:
		_ui.visible = on
	if on:
		Game.set_world(world)
		Game.player = player
		if cam:
			cam.current = true
			CameraRig.I = cam


func _process(_dt: float) -> void:
	if not active or player == null:
		return
	CameraRig.indoor = world.in_lab(player.global_position)
	_near = player.global_position.distance_to(world.console_pos) < INTERACT_R
	_prompt.visible = _near and not Game.input_blocked
	if Game.input_blocked:
		return
	if (_near and Input.is_action_just_pressed("interact")) or Input.is_action_just_pressed("pause"):
		if _near:
			Audio.play("lab_beep", -2.0)
		open_menu.emit()


func end() -> void:
	CameraRig.indoor = false
	if Game.world == world:
		Game.set_world(null)
	if Game.player == player:
		Game.player = null
	queue_free()
