class_name FpsOverlay
extends CanvasLayer
## 画面右下の FPS 表示（設定「FPS 表示」でオン・オフ。GameSettings.apply から付け外しする）

const NODE_NAME := "FpsOverlay"
var _label: Label
var _acc := 0.0
var _frames := 0


static func set_visible_on(game: Node, on: bool) -> void:
	if game == null:
		return
	var cur := game.get_node_or_null(NODE_NAME)
	if on and cur == null:
		var o := FpsOverlay.new()
		o.name = NODE_NAME
		game.add_child(o)
	elif not on and cur != null:
		cur.queue_free()


func _ready() -> void:
	layer = 120
	process_mode = Node.PROCESS_MODE_ALWAYS
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	var bg := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.02, 0.02, 0.05, 0.55)
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	bg.add_theme_stylebox_override("panel", sb)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	bg.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	bg.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bg.offset_left = -10
	bg.offset_top = -10
	bg.offset_right = -14
	bg.offset_bottom = -14
	root.add_child(bg)
	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 18)
	_label.text = "FPS --"
	bg.add_child(_label)


func _process(delta: float) -> void:
	_acc += delta
	_frames += 1
	if _acc < 0.5:
		return
	var fps := float(_frames) / _acc
	var ms := 1000.0 * _acc / float(_frames)
	_acc = 0.0
	_frames = 0
	_label.text = "FPS %d　%.1f ms" % [roundi(fps), ms]
	var c := Color(0.45, 0.95, 0.55)
	if fps < 30.0:
		c = Color(1.0, 0.42, 0.38)
	elif fps < 50.0:
		c = Color(1.0, 0.85, 0.35)
	_label.add_theme_color_override("font_color", c)
