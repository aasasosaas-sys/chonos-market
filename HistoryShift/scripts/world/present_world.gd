class_name PresentWorld
extends Node3D
## 2026年（令和八年）のハブ：時空研究所（出発・帰還の場）と、外の小さな町。
## 町の姿はこの世界の最終の歴史（HistoryVisuals.present）で決まる：
##   style  modern（史実：戦後に建て直したガラスとコンクリート）/ prewar（戦災が無く煉瓦・石造りの近代建築が残る）/
##          blocks（本土決戦の焼け跡から一斉に建てた同じ形の建物＋慰霊碑）/ wood（工業化が遅れた木造・瓦屋根の町）
##   lang   ja_en（日本語＋英語の看板）/ ja（日本語だけ）/ ja_old（漢字・縦書き）
##   city   首都の名（駅名・庁舎の看板）、height（豊かさ → 建物の高さ）、war（記念碑）
## EraWorld と同じ公開 API の一部（height_at / half_size / player_spawn / env_nodes / landmark_pos）を持つので Player・CameraRig がそのまま動く。
## 軽さ：建物はマテリアルごとに 1 つの結合メッシュ（MeshKit）、当たり判定は箱、看板は Label3D、灯りは屋内の 4 灯だけ。

const LAB_W := 26.0         # 研究所の内寸（x）
const LAB_D := 18.0         # 研究所の内寸（z）
const LAB_H := 5.6
const STREET_Z := 30.0      # 表通りの中心
const SIGNS := {
	"ja_en": {"station": ["%s駅", "%s Station"], "cafe": ["喫茶 ことのは", "CAFE"], "shop": ["書店", "BOOKS"], "bank": ["銀行", "BANK"],
		"exit": ["出口", "EXIT"], "lab": ["時空管理局 第七研究所", "Bureau of Time, Lab 7"], "gov": ["首都 %s", "Capital %s"], "street": ["表通り", "Omote-dori"]},
	"ja": {"station": ["%s駅", ""], "cafe": ["喫茶 ことのは", ""], "shop": ["書店", ""], "bank": ["銀行", ""],
		"exit": ["出口", ""], "lab": ["時空管理局 第七研究所", ""], "gov": ["首都 %s", ""], "street": ["表通り", ""]},
	"ja_old": {"station": ["%s驛", ""], "cafe": ["茶房", ""], "shop": ["書肆", ""], "bank": ["銀行", ""],
		"exit": ["出口", ""], "lab": ["時空管理局 第七研究所", ""], "gov": ["帝都 %s", ""], "street": ["表通", ""]},
}

var pr: Dictionary = {}
var half_size := 78.0
var water_level := -100.0
var player_spawn := Vector3(0, 0.1, 2.0)
var console_pos := Vector3.ZERO
var lab_rect := Rect2(-LAB_W * 0.5, -LAB_D * 0.5, LAB_W, LAB_D)
var env_nodes := {}
var style: Dictionary
var signature := ""
var era_id := "present"
var kit := MeshKit.new()
var body: StaticBody3D
var rng := RandomNumberGenerator.new()
var _ring: Node3D
var _t := 0.0


static func build(p_pr: Dictionary) -> PresentWorld:
	var w := PresentWorld.new()
	w.name = "PresentWorld"
	w.pr = p_pr
	w._build()
	return w


func height_at(_x: float, _z: float) -> float:
	return 0.0


func landmark_pos(key: String) -> Vector3:
	return console_pos if key == "lab" else Vector3(0, 0, STREET_Z)


func street_points() -> Array:
	var out: Array = []
	for i in 12:
		out.append(Vector3(-50 + i * 9.0, 0, STREET_Z + (6.5 if i % 2 == 0 else -6.5)))
	return out


func in_lab(p: Vector3) -> bool:
	return lab_rect.has_point(Vector2(p.x, p.z))


func _build() -> void:
	rng.seed = hash(str(pr.get("style", ""))) + hash(str(pr.get("city", "")))
	var st := str(pr.get("style", "modern"))
	var lang := str(pr.get("lang", "ja_en"))
	signature = "%s|%s|%s|%s|%.2f" % [st, lang, str(pr.get("city", "東京")), str(pr.get("war", "")), float(pr.get("height", 1.0))]
	style = EraStyles.get_style("showa")
	style["sun_elev"] = 38.0
	if st == "blocks":
		style["sky_zenith"] = Color(0.3, 0.45, 0.7)
	WorldMaterials.set_era_look(style)
	var img := Image.create(8, 8, false, Image.FORMAT_RF)
	img.fill(Color(0, 0, 0))
	WorldMaterials.set_world_params(ImageTexture.create_from_image(img), half_size, 8)
	body = StaticBody3D.new()
	body.name = "StaticWorld"
	body.collision_layer = 1
	body.collision_mask = 0
	add_child(body)
	_ground()
	_lab()
	_street(st, lang)
	match st:
		"prewar": _town_prewar()
		"blocks": _town_blocks()
		"wood": _town_wood()
		_: _town_modern()
	_station(st, lang)
	_monument(str(pr.get("war", "")), st)
	var mi := kit.commit("PresentMesh")
	add_child(mi)
	env_nodes = WorldAtmosphere.build_environment(self, style)
	var b := WorldAtmosphere.make_beacon(console_pos)
	b.name = "Beacon_lab"
	b.visible = false
	add_child(b)


func _ready() -> void:
	if get_viewport():
		get_viewport().msaa_3d = Viewport.MSAA_DISABLED
		get_viewport().screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA


func _process(dt: float) -> void:
	_t += dt
	if _ring != null:
		_ring.rotation.z = _t * 0.6
	var vp := get_viewport()
	var cam := vp.get_camera_3d() if vp else null
	if cam:
		WorldAtmosphere.update_post(env_nodes.get("post"), env_nodes.get("sun"), cam)


# ------------------------------------------------------------------ 共通
func _box(mat: String, c: Vector3, size: Vector3, col := Color.WHITE, collide := false, yaw := 0.0) -> void:
	var xf := Transform3D(Basis(Vector3.UP, yaw), c)
	kit.box(mat, xf, size, col)
	if collide:
		_col(xf, size, Surface.of_mat(mat))


func _col(xf: Transform3D, size: Vector3, surf := "") -> void:
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	cs.transform = xf
	if surf != "":
		cs.set_meta("surface", surf)   # 足音の床材（scripts/audio/surface.gd）
	body.add_child(cs)


func _label(text: String, pos: Vector3, yaw: float, px := 0.006, col := Color(0.1, 0.1, 0.12), modern := true, size := 96) -> Label3D:
	var lb := Label3D.new()
	lb.name = "PresentSign"
	lb.text = text
	lb.font = HistoryDressing.font(modern)
	lb.font_size = size
	lb.pixel_size = px
	lb.modulate = col
	lb.shaded = false
	lb.double_sided = false
	lb.outline_size = 0
	lb.transform = Transform3D(Basis(Vector3.UP, yaw), pos)
	add_child(lb)
	return lb


## 看板の文字（言語の設定ごと）。ja_old は縦書き
func _sign_text(key: String, arg := "") -> String:
	var lang := str(pr.get("lang", "ja_en"))
	var s: Array = SIGNS.get(lang, SIGNS["ja_en"]).get(key, ["", ""])
	var a := str(s[0]) % arg if "%s" in str(s[0]) else str(s[0])
	var b := (str(s[1]) % arg if "%s" in str(s[1]) else str(s[1])) if str(s[1]) != "" else ""
	if lang == "ja_old":
		var chars := PackedStringArray()
		for i in a.length():
			if a[i] != " ":
				chars.append(a[i])
		return "\n".join(chars)
	return a + ("\n" + b if b != "" else "")


func _signboard(key: String, pos: Vector3, yaw: float, board: Color, ink: Color, arg := "", scale := 1.0) -> void:
	var txt := _sign_text(key, arg)
	var lines := txt.split("\n")
	var vertical := str(pr.get("lang", "")) == "ja_old"
	var wmax := 0
	for l in lines:
		wmax = maxi(wmax, l.length())
	var wd := ((1.1 if vertical else maxf(wmax * 0.62, 2.0)) + 0.5) * scale
	var ht := ((lines.size() * 0.72 if vertical else lines.size() * 0.75) + 0.3) * scale
	var b := Basis(Vector3.UP, yaw)
	kit.box("flat", Transform3D(b, pos), Vector3(wd, ht, 0.14), board)
	_label(txt, pos + b * Vector3(0, 0, 0.08), yaw, 0.0062 * scale, ink, not vertical)


# ------------------------------------------------------------------ 地面
func _ground() -> void:
	_box("concrete", Vector3(0, -0.5, 0), Vector3(half_size * 2.0 + 40.0, 1.0, half_size * 2.0 + 40.0), Color(0.72, 0.72, 0.7), true)
	_box("grassmat", Vector3(0, 0.01, -half_size * 0.6), Vector3(half_size * 2.0, 0.02, half_size * 0.9), Color(0.55, 0.7, 0.4))
	_box("cobble", Vector3(0, 0.015, (LAB_D * 0.5 + STREET_Z - 6.0) * 0.5), Vector3(36, 0.03, STREET_Z - 6.0 - LAB_D * 0.5), Color(0.86, 0.84, 0.8))
	for k in 14:
		var x := -half_size + 6.0 + k * 11.0
		if absf(x) < LAB_W * 0.5 + 4.0:
			continue
		_tree(Vector3(x, 0, -half_size * 0.35 + rng.randf_range(-6, 6)), rng.randf_range(0.9, 1.3))


func _tree(p: Vector3, s: float) -> void:
	kit.cylinder("wood", Transform3D(Basis(), p), 0.22 * s, 0.16 * s, 3.2 * s, 7, Color(0.55, 0.4, 0.3))
	kit.sphere("flat", Transform3D(Basis(), p + Vector3(0, 4.2 * s, 0)), 2.0 * s, 10, 6, Color(0.36, 0.56, 0.3))
	kit.sphere("flat", Transform3D(Basis(), p + Vector3(0.9 * s, 3.6 * s, 0.4 * s)), 1.3 * s, 8, 5, Color(0.42, 0.62, 0.32))
	_col(Transform3D(Basis(), p + Vector3(0, 1.6 * s, 0)), Vector3(0.5, 3.2 * s, 0.5))


# ------------------------------------------------------------------ 研究所（中は 1 部屋：時空転送装置・端末・年表の壁）
func _lab() -> void:
	var hw := LAB_W * 0.5
	var hd := LAB_D * 0.5
	var wall := Color(0.93, 0.94, 0.95)
	var trim := Color(0.3, 0.34, 0.4)
	var th := 0.4
	# 床・天井・屋根
	_box("flat", Vector3(0, 0.05, 0), Vector3(LAB_W, 0.1, LAB_D), Color(0.78, 0.8, 0.84), true)
	for i in 9:
		_box("flat", Vector3(-hw + 1.5 + i * 2.9, 0.105, 0), Vector3(0.05, 0.01, LAB_D - 0.4), Color(0.66, 0.7, 0.76))
	kit.box("plaster", Transform3D(Basis(), Vector3(0, LAB_H + 0.25, 0)), Vector3(LAB_W + th * 2.0, 0.5, LAB_D + th * 2.0), Color(0.86, 0.87, 0.9), false)   # 天井（下面も作る）
	_col(Transform3D(Basis(), Vector3(0, LAB_H + 0.25, 0)), Vector3(LAB_W + th * 2.0, 0.5, LAB_D + th * 2.0))
	_box("concrete", Vector3(0, LAB_H + 0.55, 0), Vector3(LAB_W + 1.6, 0.2, LAB_D + 1.6), trim)
	# 壁（正面 +Z に幅 4m の入口）
	_box("plaster", Vector3(0, LAB_H * 0.5, -hd - th * 0.5), Vector3(LAB_W + th * 2.0, LAB_H, th), wall, true)
	for sx in [-1.0, 1.0]:
		_box("plaster", Vector3(sx * (hw + th * 0.5), LAB_H * 0.5, 0), Vector3(th, LAB_H, LAB_D), wall, true)
		var seg := hw - 2.0
		_box("plaster", Vector3(sx * (2.0 + seg * 0.5), LAB_H * 0.5, hd + th * 0.5), Vector3(seg, LAB_H, th), wall, true)
		# 正面のガラス窓
		_box("glass", Vector3(sx * (2.0 + seg * 0.5), 2.6, hd + th + 0.02), Vector3(seg - 2.0, 2.2, 0.06), Color(0.6, 0.75, 0.85))
	_box("plaster", Vector3(0, LAB_H - 0.8, hd + th * 0.5), Vector3(4.0, 1.6, th), wall, true)
	_box("metal", Vector3(0, 3.0 + 0.6, hd + th + 0.6), Vector3(7.0, 0.2, 1.8), trim)    # 庇
	_signboard("lab", Vector3(0, LAB_H - 0.75, hd + th + 0.12), 0.0, Color(0.16, 0.2, 0.28), Color(0.85, 0.95, 1.0), "", 0.9)
	# 室内の灯り（天井の帯＋実ライト 4 灯）
	for i in 3:
		_box("emissive", Vector3(-8 + i * 8.0, LAB_H - 0.02, 0), Vector3(5.0, 0.04, 0.6), Color(0.85, 0.95, 1.0))
	for pz in [-4.0, 4.0]:
		for px in [-7.0, 7.0]:
			var l := OmniLight3D.new()
			l.position = Vector3(px, LAB_H - 0.8, pz)
			l.light_color = Color(0.85, 0.92, 1.0)
			l.light_energy = 1.1
			l.omni_range = 11.0
			l.shadow_enabled = false
			add_child(l)
	# 時空転送装置：輪と台座（奥の壁際）
	var gz := -hd + 4.2
	kit.cylinder("metal", Transform3D(Basis(), Vector3(0, 0.1, gz)), 3.0, 3.2, 0.35, 28, Color(0.35, 0.38, 0.44))
	kit.cylinder("emissive", Transform3D(Basis(), Vector3(0, 0.45, gz)), 2.4, 2.4, 0.03, 28, Color(0.3, 0.85, 1.0))
	_col(Transform3D(Basis(), Vector3(0, 0.22, gz)), Vector3(6.0, 0.45, 6.0))
	_ring = Node3D.new()
	_ring.name = "TimeRing"
	_ring.position = Vector3(0, 2.75, gz)
	add_child(_ring)
	var rk := MeshKit.new()
	var n := 28
	for i in n:
		var a0 := TAU * i / n
		var pos := Vector3(cos(a0), sin(a0), 0) * 2.3
		rk.box("metal", Transform3D(Basis(Vector3.BACK, a0), pos), Vector3(0.36, 0.56, 0.5), Color(0.55, 0.58, 0.64))
		rk.box("emissive", Transform3D(Basis(Vector3.BACK, a0), pos * 0.9), Vector3(0.12, 0.5, 0.2), Color(0.35, 0.9, 1.0) if i % 2 == 0 else Color(1.0, 0.75, 0.3))
	_ring.add_child(rk.commit("Ring", false))
	var glow := OmniLight3D.new()
	glow.position = Vector3(0, 2.6, gz + 0.5)
	glow.light_color = Color(0.4, 0.85, 1.0)
	glow.light_energy = 1.6
	glow.omni_range = 7.0
	add_child(glow)
	# 操作卓（転送装置の手前右）
	var cxf := Transform3D(Basis(Vector3.UP, -0.5), Vector3(4.2, 0, gz + 3.2))
	kit.box("metal", cxf * Transform3D(Basis(), Vector3(0, 0.5, 0)), Vector3(2.4, 1.0, 1.0), Color(0.3, 0.33, 0.38))
	kit.box("metal", cxf * Transform3D(Basis(Vector3.RIGHT, -0.6), Vector3(0, 1.1, 0.05)), Vector3(2.3, 0.08, 0.9), Color(0.22, 0.24, 0.28))
	kit.box("emissive", cxf * Transform3D(Basis(Vector3.RIGHT, -0.6), Vector3(0, 1.15, 0.05)), Vector3(1.9, 0.02, 0.7), Color(0.4, 0.95, 0.8))
	_col(cxf * Transform3D(Basis(), Vector3(0, 0.6, 0)), Vector3(2.4, 1.2, 1.0))
	console_pos = cxf * Vector3(0, 0, 1.2)
	_label("時代を選ぶ", cxf * Vector3(0, 1.9, 0), -0.5, 0.004, Color(0.4, 0.95, 0.85), true, 64)
	# 壁の年表（この世界線）
	var lines := PackedStringArray(["この世界線　2026年", "首都：" + str(pr.get("city", "東京")), "太平洋戦争：" + str(pr.get("war", "")),
		str(pr.get("style_label", "")), str(pr.get("lang_label", ""))])
	_box("flat", Vector3(-hw + 0.06, 2.6, -1.0), Vector3(0.08, 2.6, 8.0), Color(0.12, 0.16, 0.22))
	_label("\n".join(lines), Vector3(-hw + 0.12, 2.6, -1.0), PI * 0.5, 0.0032, Color(0.75, 0.92, 1.0), true, 64)
	# 机と棚
	for k in 3:
		var dx := Vector3(-8.0 + k * 3.0, 0, hd - 3.5)
		_box("wood", dx + Vector3(0, 0.75, 0), Vector3(2.2, 0.08, 1.0), Color(0.8, 0.72, 0.6), true)
		_box("metal", dx + Vector3(0, 0.37, 0), Vector3(2.0, 0.74, 0.9), Color(0.4, 0.42, 0.46))
		_box("emissive", dx + Vector3(0, 1.1, -0.3), Vector3(0.7, 0.45, 0.04), Color(0.5, 0.8, 1.0))
	for k in 4:
		_box("metal", Vector3(hw - 0.5, 1.2, -hd + 2.0 + k * 2.2), Vector3(0.8, 2.4, 1.8), Color(0.45, 0.48, 0.52), true)
		_box("emissive", Vector3(hw - 0.92, 1.6, -hd + 2.0 + k * 2.2), Vector3(0.04, 0.12, 1.2), Color(0.3, 1.0, 0.6) if k % 2 == 0 else Color(1.0, 0.6, 0.3))
	player_spawn = Vector3(0, 0.2, gz + 4.5)


# ------------------------------------------------------------------ 表通り
func _street(st: String, lang: String) -> void:
	var road_col := Color(0.38, 0.39, 0.42) if st != "wood" else Color(0.7, 0.62, 0.5)
	_box("asphalt" if st != "wood" else "earth", Vector3(0, 0.02, STREET_Z), Vector3(half_size * 2.0 + 30.0, 0.04, 8.0), road_col)
	for sz in [-1.0, 1.0]:
		_box("concrete", Vector3(0, 0.08, STREET_Z + sz * 5.5), Vector3(half_size * 2.0 + 30.0, 0.16, 3.0), Color(0.8, 0.79, 0.76))
	if st != "wood":
		for k in 18:
			_box("flat", Vector3(-half_size + k * 9.0, 0.045, STREET_Z), Vector3(3.0, 0.01, 0.18), Color(0.95, 0.95, 0.9))
	# 街灯
	for k in 8:
		var x := -half_size + 10.0 + k * 20.0
		var p := Vector3(x, 0, STREET_Z + 7.2)
		if st == "wood":
			kit.cylinder("wood", Transform3D(Basis(), p), 0.1, 0.08, 3.0, 6, Color(0.45, 0.35, 0.28))
			kit.cylinder("emissive", Transform3D(Basis(), p + Vector3(0, 3.0, 0)), 0.3, 0.3, 0.6, 8, Color(1.0, 0.6, 0.3))
		else:
			kit.cylinder("metal", Transform3D(Basis(), p), 0.12, 0.09, 6.5, 8, Color(0.35, 0.36, 0.38))
			kit.rod("metal", p + Vector3(0, 6.4, 0), p + Vector3(0, 6.6, -1.6), 0.06, 5, Color(0.35, 0.36, 0.38))
			kit.box("emissive", Transform3D(Basis(), p + Vector3(0, 6.5, -1.7)), Vector3(0.3, 0.12, 0.6), Color(1.0, 0.95, 0.85))
		_col(Transform3D(Basis(), p + Vector3(0, 2, 0)), Vector3(0.3, 4.0, 0.3))
	# 通りの名の標識
	_signboard("street", Vector3(-6.0, 2.6, STREET_Z - 7.0), PI, Color(0.12, 0.3, 0.6) if lang != "ja_old" else Color(0.85, 0.8, 0.68),
		Color.WHITE if lang != "ja_old" else Color(0.1, 0.08, 0.06), "", 0.7)
	kit.cylinder("metal", Transform3D(Basis(), Vector3(-6.0, 0, STREET_Z - 7.0)), 0.06, 0.06, 2.2, 6, Color(0.5, 0.5, 0.52))
	# 停めた車（戦災・工業化で形が違う：木造の町は荷車）
	for k in 3:
		var cp := Vector3(-30.0 + k * 26.0, 0, STREET_Z + 2.2)
		if st == "wood":
			kit.box("wood", Transform3D(Basis(), cp + Vector3(0, 0.8, 0)), Vector3(2.6, 0.2, 1.3), Color(0.7, 0.55, 0.4))
			for sx in [-0.7, 0.7]:
				kit.cylinder("wood", Transform3D(Basis(Vector3.RIGHT, PI * 0.5), cp + Vector3(0, 0.55, sx)), 0.55, 0.55, 0.1, 10, Color(0.5, 0.38, 0.28))
		else:
			var cc: Color = [Color(0.85, 0.2, 0.18), Color(0.92, 0.92, 0.9), Color(0.2, 0.35, 0.6)][k]
			kit.box("metal", Transform3D(Basis(), cp + Vector3(0, 0.7, 0)), Vector3(4.2, 0.8, 1.8), cc)
			kit.box("glass", Transform3D(Basis(), cp + Vector3(-0.2, 1.4, 0)), Vector3(2.2, 0.65, 1.6), Color(0.5, 0.6, 0.7))
			for wx in [-1.4, 1.4]:
				for wz in [-0.9, 0.9]:
					kit.cylinder("metal", Transform3D(Basis(Vector3.RIGHT, PI * 0.5), cp + Vector3(wx, 0.35, wz)), 0.35, 0.35, 0.25, 10, Color(0.1, 0.1, 0.1))
		_col(Transform3D(Basis(), cp + Vector3(0, 0.8, 0)), Vector3(4.2, 1.6, 1.8))


## 通りの向こう側の敷地：x の範囲を区切って builder(x0, x1) を呼ぶ
func _lots(widths: Array, builder: Callable) -> void:
	var x := -half_size + 4.0
	var i := 0
	while x < half_size - 10.0:
		var wd: float = widths[i % widths.size()]
		if x + wd > half_size - 4.0:
			break
		builder.call(x, x + wd, i)
		x += wd + 1.5
		i += 1


func _shop_key(i: int) -> String:
	return ["cafe", "shop", "bank"][i % 3]


func _town_modern() -> void:
	var h := float(pr.get("height", 1.0))
	var zf := STREET_Z + 8.5
	_lots([14.0, 10.0, 18.0, 12.0, 16.0], func(x0: float, x1: float, i: int) -> void:
		var wd := x1 - x0
		var dp := rng.randf_range(10.0, 16.0)
		var tall := (rng.randf_range(18.0, 46.0) if i % 2 == 0 else rng.randf_range(9.0, 18.0)) * h
		var c := Vector3((x0 + x1) * 0.5, 0, zf + dp * 0.5)
		var glassy := i % 2 == 0
		var body_col: Color = Color(0.82, 0.84, 0.86) if glassy else [Color(0.9, 0.86, 0.78), Color(0.78, 0.8, 0.82), Color(0.86, 0.8, 0.76)][i % 3]
		_box("concrete", c + Vector3(0, tall * 0.5, 0), Vector3(wd, tall, dp), body_col, true)
		var floors := int(tall / 3.6)
		for f in floors:
			var y := 1.8 + f * 3.6
			if glassy:
				_box("glass", c + Vector3(0, y + 0.3, -dp * 0.5 - 0.03), Vector3(wd - 0.8, 2.6, 0.06), Color(0.45, 0.62, 0.78))
			else:
				for k in int(wd / 2.6):
					_box("glass", c + Vector3(-wd * 0.5 + 1.3 + k * 2.6, y + 0.4, -dp * 0.5 - 0.03), Vector3(1.4, 1.5, 0.06), Color(0.5, 0.62, 0.72))
		_box("metal", c + Vector3(0, tall + 0.4, 0), Vector3(wd * 0.4, 0.8, dp * 0.4), Color(0.6, 0.62, 0.64))
		_signboard(_shop_key(i), c + Vector3(0, 4.2, -dp * 0.5 - 0.12), PI, Color(0.98, 0.98, 0.96), Color(0.15, 0.2, 0.3), "", 0.8))


func _town_prewar() -> void:
	# 戦災を受けなかった煉瓦・石造りの近代建築（丸の内の「一丁倫敦」のような 3〜5 階）と、その後ろの新しい高層
	var h := float(pr.get("height", 1.0))
	var zf := STREET_Z + 8.5
	_lots([16.0, 13.0, 18.0, 14.0], func(x0: float, x1: float, i: int) -> void:
		var wd := x1 - x0
		var dp := 13.0
		var floors := 3 + (i % 3)
		var tall := floors * 4.0
		var c := Vector3((x0 + x1) * 0.5, 0, zf + dp * 0.5)
		var stone := i % 3 == 1
		var col := Color(0.92, 0.88, 0.8) if stone else Color(1.0, 0.68, 0.58)
		var trim := Color(0.94, 0.92, 0.86)
		_box("stonewall", c + Vector3(0, 0.6, 0), Vector3(wd + 0.4, 1.2, dp + 0.4), Color(0.8, 0.78, 0.74), true)
		_box("plaster" if stone else "brick", c + Vector3(0, 1.2 + tall * 0.5, 0), Vector3(wd, tall, dp), col, true)
		for f in floors:
			var y := 1.2 + f * 4.0 + 2.0
			_box("plaster", c + Vector3(0, y + 1.75, -dp * 0.5 - 0.1), Vector3(wd + 0.2, 0.25, 0.25), trim)
			for k in int(wd / 2.8):
				var wx := -wd * 0.5 + 1.4 + k * 2.8
				_box("plaster", c + Vector3(wx, y, -dp * 0.5 - 0.05), Vector3(1.3, 2.3, 0.1), trim)
				_box("glass", c + Vector3(wx, y - 0.05, -dp * 0.5 - 0.1), Vector3(0.95, 1.9, 0.05), Color(0.4, 0.5, 0.55))
		_box("plaster", c + Vector3(0, 1.2 + tall + 0.4, 0), Vector3(wd + 0.6, 0.8, dp + 0.6), trim)
		kit.roof(Transform3D(Basis(), c + Vector3(0, 1.2 + tall + 0.8, 0)), wd * 0.5, dp * 0.5, 2.2, 0.0, "rooftile", "plaster", Color(0.35, 0.4, 0.45), 1.0, 0.0, 0.3, trim, "plaster", trim)
		_signboard(_shop_key(i), c + Vector3(0, 3.6, -dp * 0.5 - 0.2), PI, Color(0.15, 0.25, 0.2), Color(0.95, 0.88, 0.6), "", 0.8)
		if i % 2 == 0:
			var tc := c + Vector3(0, 0, 22.0)
			var tt := rng.randf_range(30.0, 55.0) * h
			_box("concrete", tc + Vector3(0, tt * 0.5, 0), Vector3(wd * 0.8, tt, 12.0), Color(0.78, 0.8, 0.84))
			for f in int(tt / 4.0):
				_box("glass", tc + Vector3(0, 2.0 + f * 4.0, -6.03), Vector3(wd * 0.8 - 0.6, 2.8, 0.06), Color(0.45, 0.6, 0.75)))


func _town_blocks() -> void:
	# 焼け跡から同じ図面で一斉に建てた 5 階建ての鉄筋コンクリート（公団の団地のような箱）
	var zf := STREET_Z + 8.5
	_lots([24.0], func(x0: float, x1: float, i: int) -> void:
		var wd := x1 - x0
		var c := Vector3((x0 + x1) * 0.5, 0, zf + 6.0)
		var tall := 15.0
		_box("concrete", c + Vector3(0, tall * 0.5, 0), Vector3(wd, tall, 10.0), Color(0.82, 0.8, 0.74), true)
		for f in 5:
			var y := 1.5 + f * 3.0
			_box("concrete", c + Vector3(0, y - 1.0, -5.4), Vector3(wd, 0.15, 0.9), Color(0.7, 0.7, 0.68))
			for k in int(wd / 3.0):
				_box("glass", c + Vector3(-wd * 0.5 + 1.5 + k * 3.0, y + 0.3, -5.03), Vector3(1.6, 1.4, 0.05), Color(0.5, 0.58, 0.64))
		_label("%d号棟" % (i + 1), c + Vector3(wd * 0.5 - 2.0, tall - 1.5, -5.08), PI, 0.008, Color(0.2, 0.2, 0.22), true)
		if i == 1:
			_signboard("shop", c + Vector3(-wd * 0.25, 2.6, -5.6), PI, Color(0.95, 0.95, 0.92), Color(0.2, 0.2, 0.25), "", 0.7))


func _town_wood() -> void:
	# 工業化が遅れた世界：瓦屋根の 2 階建ての町家が並ぶ（電柱も少ない）
	var zf := STREET_Z + 8.5
	_lots([7.0, 6.0, 8.0], func(x0: float, x1: float, i: int) -> void:
		var wd := x1 - x0
		var dp := 10.0
		var c := Vector3((x0 + x1) * 0.5, 0, zf + dp * 0.5)
		var wood := Color(0.62, 0.45, 0.32)
		_box("darkwood", c + Vector3(0, 1.6, 0), Vector3(wd, 3.2, dp), wood, true)
		_box("plaster", c + Vector3(0, 4.4, 0.5), Vector3(wd, 2.4, dp - 1.0), Color(0.93, 0.9, 0.82), true)
		for k in int(wd / 1.0):
			_box("wood", c + Vector3(-wd * 0.5 + 0.5 + k * 1.0, 1.6, -dp * 0.5 - 0.06), Vector3(0.08, 2.6, 0.06), Color(0.42, 0.3, 0.22))
		kit.roof(Transform3D(Basis(), c + Vector3(0, 3.3, -dp * 0.5 + 0.4)), wd * 0.5 + 0.2, 1.0, 0.5, 1.0, "rooftile", "darkwood", Architecture.TILE_DARK, 1.0, 0.0, 0.2, Color(0.4, 0.3, 0.25), "darkwood", Color.WHITE)
		kit.roof(Transform3D(Basis(), c + Vector3(0, 5.6, 0.5)), wd * 0.5 + 0.3, dp * 0.5, 1.8, 1.0, "rooftile", "darkwood", Architecture.TILE_DARK, 1.0, 0.1, 0.3, Color(0.4, 0.3, 0.25), "darkwood", Color.WHITE)
		if i % 2 == 0:
			_signboard(_shop_key(i), c + Vector3(wd * 0.3, 2.4, -dp * 0.5 - 0.5), PI, Color(0.85, 0.8, 0.66), Color(0.1, 0.08, 0.06), "", 0.6))


# ------------------------------------------------------------------ 駅と記念碑
func _station(st: String, lang: String) -> void:
	var c := Vector3(half_size - 18.0, 0, STREET_Z - 16.0)
	var city := str(pr.get("city", "東京"))
	var mat := "brick" if st in ["prewar", "modern"] else ("darkwood" if st == "wood" else "concrete")
	var col := Color(1.0, 0.68, 0.58) if mat == "brick" else (Color(0.6, 0.45, 0.32) if st == "wood" else Color(0.82, 0.8, 0.76))
	_box(mat, c + Vector3(0, 3.5, 0), Vector3(22.0, 7.0, 10.0), col, true)
	if st == "wood":
		kit.roof(Transform3D(Basis(), c + Vector3(0, 7.0, 0)), 11.6, 5.6, 2.4, 0.42, "rooftile", "darkwood", Architecture.TILE_DARK, 1.0, 0.3, 0.3, Color(0.4, 0.3, 0.25), "darkwood", Color.WHITE)
	else:
		_box("plaster", c + Vector3(0, 7.3, 0), Vector3(22.6, 0.6, 10.6), Color(0.94, 0.92, 0.86))
		kit.sphere("metal", Transform3D(Basis().scaled(Vector3(1, 0.7, 1)), c + Vector3(0, 7.6, 0)), 3.2, 14, 7, Color(0.4, 0.42, 0.45) if mat == "concrete" else Architecture.COPPER)
	_box("glass", c + Vector3(0, 2.2, 5.03), Vector3(6.0, 3.4, 0.06), Color(0.4, 0.5, 0.6))
	_signboard("station", c + Vector3(0, 5.4, 5.15), 0.0, Color(0.98, 0.98, 0.96) if lang != "ja_old" else Color(0.85, 0.8, 0.68), Color(0.1, 0.12, 0.2), city, 1.0)
	_signboard("gov", Vector3(-half_size + 16.0, 3.2, STREET_Z - 9.5), 0.0, Color(0.2, 0.22, 0.3), Color(1, 0.95, 0.8), city, 0.8)
	kit.cylinder("metal", Transform3D(Basis(), Vector3(-half_size + 16.0, 0, STREET_Z - 9.6)), 0.07, 0.07, 2.6, 6, Color(0.5, 0.5, 0.52))


func _monument(war: String, st: String) -> void:
	var c := Vector3(-24.0, 0, STREET_Z - 15.0)
	match war:
		"本土決戦", "敗戦":
			var big := war == "本土決戦"
			var h := 7.0 if big else 3.2
			_box("stonewall", c + Vector3(0, 0.3, 0), Vector3(4.0, 0.6, 4.0), Color(0.8, 0.78, 0.74), true)
			_box("stonewall", c + Vector3(0, 0.6 + h * 0.5, 0), Vector3(1.4, h, 0.8), Color(0.62, 0.62, 0.6), true)
			_label("平和祈念碑" if big else "平和の碑", c + Vector3(0, 0.6 + h * 0.6, 0.42), 0.0, 0.006, Color(0.95, 0.92, 0.8), false)
			if big:
				for k in 6:
					kit.cylinder("flat", Transform3D(Basis(), c + Vector3(-2.5 + k, 0.6, 1.6)), 0.1, 0.1, 0.25, 6, [Color(0.95, 0.85, 0.3), Color(0.9, 0.3, 0.3)][k % 2])
		"勝利", "有利な休戦":
			_box("stonewall", c + Vector3(0, 0.4, 0), Vector3(5.0, 0.8, 5.0), Color(0.85, 0.82, 0.76), true)
			kit.cylinder("stonewall", Transform3D(Basis(), c + Vector3(0, 0.8, 0)), 0.7, 0.45, 11.0, 10, Color(0.88, 0.86, 0.8))
			kit.sphere("gold", Transform3D(Basis(), c + Vector3(0, 12.2, 0)), 0.6, 10, 6)
			_label("凱旋記念塔" if war == "勝利" else "休戦記念塔", c + Vector3(0, 1.6, 2.52), 0.0, 0.006, Color(0.2, 0.15, 0.1), false)
		_:
			pass
	if st == "wood":
		for k in 4:
			kit.cylinder("emissive", Transform3D(Basis(), Vector3(-40.0 + k * 22.0, 3.2, STREET_Z + 8.2)), 0.25, 0.25, 0.5, 8, Color(1.0, 0.6, 0.3))
