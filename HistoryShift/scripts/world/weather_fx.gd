class_name WeatherDirector
extends Node3D
## 天気の演出（Session の子）。HistWeather.lookup の「その日の天気」を目標に、今の値をなめらかに近づける
## （雨は十数秒、霧は数十秒で移る）。有名な日の sequence（桶狭間の急雨、関ヶ原の霧が晴れる…）は時刻どおりに次の目標へ。
##  見た目: 雨筋（カメラに付いてくる GPU パーティクル。屋根の高さで止まり、はねる）・雪・霧（環境の深度霧と高さ霧）・
##          空一面の雲（anime_sky の overcast）・稲光（画面の閃光と遠くの稲妻）・風（草木の揺れ world_wind）・
##          濡れた地面・水たまり・積雪（global world_weather → toon.gdshaderinc の weather_*）・海の荒れ・色調（彩度・明るさ）
##  音: 雷（光ってから距離÷音速の後）・突風。雨音などの層は AmbienceDirector が HistWeather.live を読んで鳴らす
##  ゲーム: HistWeather.live に今の値を書く（火縄銃の不発・敵の見通し・ぬかるみ・船の揺れ・乱気流が読む）
## 昼夜: 雨筋・雲の色は world_night に合わせる。屋内（WorldInteriors.player_inside）では雨・雪の粒を止める。

const FLOAT_KEYS := ["rain", "snow", "fog", "cloud", "storm", "wind", "wet", "snow_cover", "thunder", "ash", "dust"]
const RATE := {"rain": 0.08, "snow": 0.06, "fog": 0.025, "cloud": 0.05, "storm": 0.06, "wind": 1.2, "wet": 0.02,
	"snow_cover": 0.01, "thunder": 0.1, "ash": 0.02, "dust": 0.05}

static var I: WeatherDirector
## 屋根・木で雨粒を止める高さの場（GPUParticlesCollisionHeightField3D）を使うか。
## ソフトウェアの Vulkan（lavapipe）では高さの場が正しく描かれず、粒が出てすぐ消えたため既定は使わない
## （屋内では粒そのものを止める。はねは足元の地面に置く）
static var roof_collision := false

var world: Node3D
var era_id := ""
var year := 0
var hud = null
var day: Dictionary = {}          # HistWeather.lookup の結果（その日）
var target: Dictionary = {}       # 目標の状態
var cur: Dictionary = {}          # 今の状態
var kind := "clear"
var hail := false
var _t := 0.0
var _seq: Array = []
var _apply_t := 0.0
var _rain: GPUParticles3D
var _snow: GPUParticles3D
var _splash: GPUParticles3D
var _hf: GPUParticlesCollisionHeightField3D
var _rain_mat: ParticleProcessMaterial
var _snow_mat: ParticleProcessMaterial
var _drop_mat: ShaderMaterial
var _splash_mat: ParticleProcessMaterial
var _bolt: MeshInstance3D
var _flash := 0.0
var _flash_t := -1.0
var _next_strike := 8.0
var _pending_thunder: Array = []   # [[時刻, key, db]]
var _next_gust := 6.0
var _indoor_k := 0.0
var _base := {}
var _last_sky := {}
var _label := ""
var _rng := RandomNumberGenerator.new()
var strikes := 0                    # 検査用
var last_weather := Vector4.ZERO     # 検査用：最後に渡した world_weather / world_wind（global_shader_parameter_get は実行時に使えない）
var last_wind := Vector4.ZERO
var gusts := 0


static func attach(parent: Node, p_world: Node3D, p_era: String, p_year: int, p_hud = null, p_jd := 0) -> WeatherDirector:
	var d := WeatherDirector.new()
	d.name = "Weather"
	d.world = p_world
	d.era_id = p_era
	d.year = p_year
	d.hud = p_hud
	d.day = HistWeather.lookup(p_era, p_year, p_jd)
	parent.add_child(d)
	return d


func _ready() -> void:
	I = self
	_rng.seed = hash([era_id, year])
	target = _state_from(day)
	cur = target.duplicate()
	kind = str(day.get("kind", "clear"))
	hail = bool(day.get("hail", false))
	_seq = (day.get("sequence", []) as Array).duplicate()
	_capture_base()
	_build_particles()
	_build_bolt()
	_apply(0.0, true)
	_announce()


func _exit_tree() -> void:
	if I == self:
		I = null
	HistWeather.live = {}
	RenderingServer.global_shader_parameter_set("world_weather", Vector4.ZERO)
	RenderingServer.global_shader_parameter_set("world_wind", Vector4(0.8, 0.6, 1.0, 0.0))


func _state_from(s: Dictionary) -> Dictionary:
	var o := {}
	for k in FLOAT_KEYS:
		o[k] = float(s.get(k, 0.0))
	return o


## 天気をすぐ変える（テスト・写真・デバッグ）。instant=false なら目標だけ
func set_weather(st: Dictionary, instant := true) -> void:
	for k in FLOAT_KEYS:
		if st.has(k):
			target[k] = float(st[k])
	if st.has("kind"):
		kind = str(st["kind"])
	hail = bool(st.get("hail", false))
	if instant:
		cur = target.duplicate()
		_apply(0.0, true)
	_announce_hud()


# ================================================================== 生成
func _capture_base() -> void:
	var env_nodes: Dictionary = world.get("env_nodes") if world and world.get("env_nodes") is Dictionary else {}
	var st: Dictionary = world.get("style") if world and world.get("style") is Dictionary else {}
	_base["style"] = st
	var env: Environment = env_nodes.get("env")
	if env:
		_base["fog"] = env.fog_density
		_base["fog_h"] = env.fog_height_density
		_base["fog_col"] = env.fog_light_color
		_base["scatter"] = env.fog_sun_scatter
	var sea := world.get_node_or_null("Sea") as MeshInstance3D if world else null
	if sea and sea.material_override:
		var wv: Variant = (sea.material_override as ShaderMaterial).get_shader_parameter("wave_amp")
		_base["wave"] = float(wv) if wv != null else 0.35   # 未設定ならシェーダの既定値


func _quality() -> int:
	return int(EraWorld.quality)


func _build_particles() -> void:
	var q := _quality()
	_drop_mat = ShaderMaterial.new()
	_drop_mat.shader = WorldMaterials.shader("weather_drop")
	_drop_mat.set_shader_parameter("mode", 0)
	_drop_mat.set_shader_parameter("width", 0.03)
	_drop_mat.set_shader_parameter("length_m", 0.75)
	_drop_mat.set_shader_parameter("opacity", 0.5)
	# 雨
	_rain = GPUParticles3D.new()
	_rain.name = "Rain"
	_rain.amount = [3000, 5500, 9000][clampi(q, 0, 2)]
	_rain.lifetime = 2.0
	_rain.preprocess = 2.0
	_rain.local_coords = false
	_rain.fixed_fps = 0
	_rain.visibility_aabb = AABB(Vector3(-40, -40, -40), Vector3(80, 80, 80))
	_rain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_rain_mat = ParticleProcessMaterial.new()
	_rain_mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	_rain_mat.emission_box_extents = Vector3(13, 1.5, 13)
	_rain_mat.direction = Vector3(0, -1, 0)
	_rain_mat.spread = 2.0
	_rain_mat.initial_velocity_min = 10.0
	_rain_mat.initial_velocity_max = 13.0
	_rain_mat.gravity = Vector3(0, -4, 0)
	_rain_mat.collision_mode = ParticleProcessMaterial.COLLISION_HIDE_ON_CONTACT
	_rain_mat.sub_emitter_mode = ParticleProcessMaterial.SUB_EMITTER_AT_COLLISION
	_rain_mat.sub_emitter_amount_at_collision = 1
	_rain.process_material = _rain_mat
	var qm := QuadMesh.new()
	qm.size = Vector2(1, 1)
	qm.material = _drop_mat
	_rain.draw_pass_1 = qm
	_rain.amount_ratio = 0.0
	add_child(_rain)
	_rain.top_level = true
	_rain.global_transform = Transform3D.IDENTITY
	# はね（雨粒が屋根・地面に当たったところ）
	_splash = GPUParticles3D.new()
	_splash.name = "Splash"
	_splash.amount = [400, 800, 1400][clampi(q, 0, 2)]
	_splash.lifetime = 0.35
	_splash.local_coords = false
	_splash.visibility_aabb = AABB(Vector3(-40, -40, -40), Vector3(80, 80, 80))
	_splash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var sp := ParticleProcessMaterial.new()
	sp.direction = Vector3(0, 1, 0)
	_splash_mat = sp
	if not roof_collision:
		sp.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
		sp.emission_box_extents = Vector3(11, 0.0, 11)
	sp.initial_velocity_min = 0.0
	sp.initial_velocity_max = 0.2
	sp.gravity = Vector3.ZERO
	_splash.process_material = sp
	var sm := _drop_mat.duplicate() as ShaderMaterial
	sm.set_shader_parameter("mode", 2)
	sm.set_shader_parameter("width", 0.16)
	sm.set_shader_parameter("opacity", 0.55)
	var qm2 := QuadMesh.new()
	qm2.size = Vector2(1, 1)
	qm2.material = sm
	_splash.draw_pass_1 = qm2
	add_child(_splash)
	_splash.top_level = true
	_splash.global_transform = Transform3D.IDENTITY
	if roof_collision:
		_rain.sub_emitter = _rain.get_path_to(_splash)
	# 雪
	_snow = GPUParticles3D.new()
	_snow.name = "Snow"
	_snow.amount = [1500, 2500, 4000][clampi(q, 0, 2)]
	_snow.lifetime = 9.0
	_snow.preprocess = 9.0
	_snow.local_coords = false
	_snow.visibility_aabb = AABB(Vector3(-40, -40, -40), Vector3(80, 80, 80))
	_snow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_snow_mat = ParticleProcessMaterial.new()
	_snow_mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	_snow_mat.emission_box_extents = Vector3(22, 3, 22)
	_snow_mat.direction = Vector3(0, -1, 0)
	_snow_mat.spread = 15.0
	_snow_mat.initial_velocity_min = 0.8
	_snow_mat.initial_velocity_max = 1.4
	_snow_mat.gravity = Vector3(0, -0.4, 0)
	_snow_mat.damping_min = 0.3
	_snow_mat.damping_max = 0.6
	_snow_mat.turbulence_enabled = true
	_snow_mat.turbulence_noise_strength = 1.6
	_snow_mat.turbulence_noise_scale = 4.0
	_snow_mat.turbulence_influence_min = 0.05
	_snow_mat.turbulence_influence_max = 0.12
	_snow_mat.scale_min = 0.6
	_snow_mat.scale_max = 1.4
	_snow_mat.collision_mode = ParticleProcessMaterial.COLLISION_HIDE_ON_CONTACT
	_snow.process_material = _snow_mat
	var fm := _drop_mat.duplicate() as ShaderMaterial
	fm.set_shader_parameter("mode", 1)
	fm.set_shader_parameter("width", 0.07)
	fm.set_shader_parameter("opacity", 0.9)
	var qm3 := QuadMesh.new()
	qm3.size = Vector2(1, 1)
	qm3.material = fm
	_snow.draw_pass_1 = qm3
	_snow.amount_ratio = 0.0
	add_child(_snow)
	_snow.top_level = true
	_snow.global_transform = Transform3D.IDENTITY
	# 屋根・木の高さで粒を止める（上から見た高さの場。カメラに付いてくる）
	if not roof_collision:
		_rain_mat.collision_mode = ParticleProcessMaterial.COLLISION_DISABLED
		_rain_mat.sub_emitter_mode = ParticleProcessMaterial.SUB_EMITTER_DISABLED
		_snow_mat.collision_mode = ParticleProcessMaterial.COLLISION_DISABLED
		return
	_hf = GPUParticlesCollisionHeightField3D.new()
	_hf.name = "RoofField"
	_hf.size = Vector3(48, 80, 48)
	_hf.resolution = GPUParticlesCollisionHeightField3D.RESOLUTION_512 if q >= 2 else GPUParticlesCollisionHeightField3D.RESOLUTION_256
	_hf.update_mode = GPUParticlesCollisionHeightField3D.UPDATE_MODE_WHEN_MOVED
	_hf.follow_camera_enabled = true
	add_child(_hf)


## 稲妻（遠くに一瞬だけ見える、光る折れ線の帯）
func _build_bolt() -> void:
	_bolt = MeshInstance3D.new()
	_bolt.name = "Bolt"
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(0.85, 0.9, 1.0)
	m.emission_enabled = true
	m.emission = Color(0.75, 0.85, 1.0)
	m.emission_energy_multiplier = 6.0
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.disable_fog = true
	_bolt.material_override = m
	_bolt.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_bolt.visible = false
	add_child(_bolt)


func _make_bolt_mesh(top: Vector3, bottom: Vector3, cam_pos: Vector3) -> ArrayMesh:
	var pts: Array = [top]
	var n := 14
	for i in range(1, n):
		var t := float(i) / n
		var p := top.lerp(bottom, t)
		p += Vector3(_rng.randf_range(-1, 1), 0, _rng.randf_range(-1, 1)) * 28.0 * (1.0 - t * 0.5)
		pts.append(p)
	pts.append(bottom)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var w := 3.5
	for i in pts.size() - 1:
		var a: Vector3 = pts[i]
		var b: Vector3 = pts[i + 1]
		var side := (b - a).cross(cam_pos - a).normalized() * w * (1.0 - float(i) / pts.size() * 0.6)
		st.add_vertex(a - side); st.add_vertex(a + side); st.add_vertex(b + side)
		st.add_vertex(a - side); st.add_vertex(b + side); st.add_vertex(b - side)
	return st.commit()


# ================================================================== 毎フレーム
func _process(dt: float) -> void:
	_t += dt
	# その日の移り変わり（有名な日の sequence）
	while not _seq.is_empty() and _t >= float(_seq[0].get("t", 0.0)):
		var step: Dictionary = _seq.pop_front()
		for k in FLOAT_KEYS:
			if step.has(k):
				target[k] = float(step[k])
		if step.has("kind"):
			kind = str(step["kind"])
			if not step.has("cloud"):
				target["cloud"] = 1.0 if kind in ["rain", "heavy_rain", "thunder", "typhoon", "snow", "overcast"] else minf(float(target["cloud"]), 0.7)
		hail = bool(step.get("hail", false))
		_announce_hud()
	for k in FLOAT_KEYS:
		var r: float = RATE.get(k, 0.05)
		cur[k] = move_toward(float(cur[k]), float(target[k]), dt * r)
	# 雨が降っている間は地面が濡れていく、雪は積もる
	if float(cur["rain"]) > 0.2:
		cur["wet"] = maxf(float(cur["wet"]), minf(float(cur["rain"]), float(cur["wet"]) + dt * 0.03))
	if float(cur["snow"]) > 0.2:
		cur["snow_cover"] = minf(1.0, float(cur["snow_cover"]) + dt * 0.002 * float(cur["snow"]))
	_apply(dt, false)


func _apply(dt: float, force: bool) -> void:
	var cam := get_viewport().get_camera_3d() if is_inside_tree() and get_viewport() else null
	var night := WorldAtmosphere._night
	var wi = world.get("interiors") if world and is_instance_valid(world) else null
	var inside: bool = wi != null and is_instance_valid(wi) and int(wi.player_inside) >= 0
	_indoor_k = move_toward(_indoor_k, 1.0 if inside else 0.0, dt * 3.0) if not force else (1.0 if inside else 0.0)
	# 揺らぎ：雨の帯・突風
	var band := 0.82 + 0.18 * sin(_t * 0.21) * sin(_t * 0.057 + 1.3)
	var rain := float(cur["rain"]) * band
	var gust := 1.0 + 0.3 * sin(_t * 0.7) * sin(_t * 0.23 + 0.5) + (0.25 if fmod(_t, 9.0) < 1.2 and float(cur["wind"]) > 8.0 else 0.0)
	var wind := float(cur["wind"]) * gust
	var snow := float(cur["snow"])
	var cloud := float(cur["cloud"])
	var storm := float(cur["storm"])
	var fog := float(cur["fog"])
	var ash := float(cur["ash"])
	var overcast := clampf((cloud - 0.55) / 0.4, 0.0, 1.0)
	overcast = maxf(overcast, clampf(rain * 1.5 + snow * 1.2 + storm, 0.0, 1.0))
	# 風（草木・旗）: 吹いていく向き
	var wf := deg_to_rad(float(day.get("wind_from", 315.0)))
	var to := -Vector2(sin(wf), -cos(wf))
	var wstr := clampf(wind / 6.0, 0.3, 2.6)
	last_wind = Vector4(to.x, to.y, wstr, rain)
	RenderingServer.global_shader_parameter_set("world_wind", last_wind)
	# 稲光
	_lightning(dt, cam)
	last_weather = Vector4(float(cur["wet"]), float(cur["snow_cover"]), clampf(storm * 0.8 + overcast * 0.35, 0.0, 1.0), _flash)
	RenderingServer.global_shader_parameter_set("world_weather", last_weather)
	# 雨・雪の粒（カメラに付いてくる。屋内では止める）
	if cam:
		var cp := cam.global_position
		var slant := minf(wind * 0.07, 1.4)
		var fall := Vector3(to.x * slant, -1.0, to.y * slant).normalized()
		# 粒はワールド座標（local_coords=false）。ノードは原点に置いたまま放出位置だけをカメラの上へ動かす
		# （ノードを動かすと描画の MODEL_MATRIX にノードの位置が二重に掛かり、粒が遠くへ飛んでしまう）
		var rp := cp + Vector3(0, 9, 0) - Vector3(to.x, 0, to.y) * slant * 9.0
		var spos := cp + Vector3(0, 10, 0) - Vector3(to.x, 0, to.y) * wind * 1.5
		_rain_mat.emission_shape_offset = rp
		_snow_mat.emission_shape_offset = spos
		var vis := AABB(cp - Vector3(40, 40, 40), Vector3(80, 80, 80))
		_rain.visibility_aabb = vis
		_snow.visibility_aabb = vis
		_splash.visibility_aabb = vis
		if not roof_collision:
			var gy := cp.y - 1.6
			var pl = Game.player
			if pl != null and is_instance_valid(pl):
				gy = (pl as Node3D).global_position.y
			elif world and world.has_method("height_at"):
				gy = float(world.height_at(cp.x, cp.z))
			_splash_mat.emission_shape_offset = Vector3(cp.x, gy + 0.04, cp.z)
		_rain_mat.direction = fall
		_drop_mat.set_shader_parameter("fall_dir", fall)
		_snow_mat.gravity = Vector3(to.x * slant, -0.4, to.y * slant)
	var out := 1.0 - _indoor_k
	_rain.amount_ratio = clampf(rain * 1.1, 0.0, 1.0) * out
	_rain.emitting = _rain.amount_ratio > 0.01
	_snow.amount_ratio = clampf(snow, 0.0, 1.0) * out
	_snow.emitting = _snow.amount_ratio > 0.01
	if not roof_collision:
		_splash.amount_ratio = _rain.amount_ratio
		_splash.emitting = _rain.emitting
	_drop_mat.set_shader_parameter("length_m", 0.7 + rain * 0.6)
	_drop_mat.set_shader_parameter("opacity", lerpf(0.35, 0.6, rain) * (1.0 if not hail else 1.3))
	# 環境（空・霧・日・色調）は 10 回/秒
	_apply_t -= dt
	if _apply_t <= 0.0 or force:
		_apply_t = 0.1
		_apply_env(overcast, rain, snow, fog, storm, ash, night)
	_audio(dt, wind, cam)
	HistWeather.live = {"kind": kind, "rain": rain * out + 0.0, "rain_out": rain, "snow": snow, "fog": fog, "cloud": cloud, "storm": storm,
		"wind": wind, "wet": float(cur["wet"]), "snow_cover": float(cur["snow_cover"]), "thunder": float(cur["thunder"]),
		"ash": ash, "indoor": _indoor_k, "night_k": night, "label": _label, "hail": hail}


func _apply_env(overcast: float, rain: float, snow: float, fog: float, storm: float, ash: float, night: float) -> void:
	if world == null or not is_instance_valid(world):
		return
	var env_nodes: Dictionary = world.get("env_nodes") if world.get("env_nodes") is Dictionary else {}
	var st: Dictionary = _base.get("style", {})
	var env: Environment = env_nodes.get("env")
	var sun: DirectionalLight3D = env_nodes.get("sun")
	var sky: ShaderMaterial = env_nodes.get("sky_mat")
	var grey := Color(0.6, 0.63, 0.7)
	if snow > 0.2:
		grey = Color(0.74, 0.77, 0.83)
	if ash > 0.2:
		grey = Color(0.62, 0.55, 0.47)
	if storm > 0.6:
		grey = grey.darkened(0.25)
	if env:
		var bf := float(_base.get("fog", env.fog_density))
		env.fog_density = bf + fog * fog * 0.032 + rain * 0.0025 + snow * 0.005 + ash * 0.012 + float(cur["dust"]) * 0.004
		env.fog_height_density = float(_base.get("fog_h", env.fog_height_density)) * (1.0 + fog * 6.0)
		var bcol: Color = env.get_meta("base_fog_col", _base.get("fog_col", env.fog_light_color))
		var fogc := grey.lerp(Color(0.86, 0.88, 0.9), fog * 0.6) * lerpf(1.0, 0.22, night)
		if float(cur["dust"]) > 0.1:
			fogc = fogc.lerp(Color(0.86, 0.76, 0.6), float(cur["dust"]) * 0.6)
		env.fog_light_color = bcol.lerp(fogc, clampf(maxf(fog, overcast * 0.8) + ash, 0.0, 1.0))
		env.fog_sun_scatter = float(_base.get("scatter", 0.22)) * (1.0 - overcast)
		# 霧・雨雲の日は空も霧に溶ける（遠くの山の稜線だけが空より明るく浮かないように）
		env.fog_sky_affect = clampf(fog * 0.85 + overcast * 0.35 + ash * 0.4, 0.0, 0.9)
		# 雪の日は白と木の色の対比を残す（彩度を落としすぎない）
		env.adjustment_saturation = 1.0 - (0.18 - 0.08 * clampf(snow * 1.5, 0.0, 1.0)) * overcast - 0.15 * fog - 0.2 * ash
		env.adjustment_brightness = 1.0 - 0.1 * storm - 0.05 * overcast + 0.06 * snow * (1.0 - night)
		env.adjustment_contrast = 1.0 - 0.06 * overcast - 0.08 * fog
	if sun:
		sun.set_meta("wx_e", clampf(1.0 - 0.62 * overcast - 0.25 * fog - 0.3 * ash, 0.3, 1.0))
		WorldAtmosphere.refresh_sun(sun)
	# 空・日の色（影の照り返し・リム・水の映り込み）
	var day_k := 1.0 - night
	var base_sky: Color = Color(0.12, 0.16, 0.3).lerp(st.get("sky_horizon", Color(0.6, 0.8, 0.97)), day_k)
	var base_sun: Color = Color(0.6, 0.7, 1.0).lerp(st.get("sun_color", Color(1, 0.95, 0.88)), day_k)
	RenderingServer.global_shader_parameter_set("world_sky_color", base_sky.lerp(grey * lerpf(1.0, 0.25, night), overcast * 0.7))
	RenderingServer.global_shader_parameter_set("world_sun_color", base_sun.lerp(Color(0.85, 0.87, 0.92) * lerpf(1.0, 0.5, night), overcast * 0.6))
	if sky:
		var want := {"overcast": snappedf(overcast, 0.01), "storm_dark": snappedf(clampf(storm, 0.0, 1.0), 0.01),
			"cloud_cover": snappedf(clampf(float(st.get("cloud_cover", 0.45)) + float(cur["cloud"]) * 0.35, 0.0, 1.0), 0.01),
			"tower": snappedf(float(st.get("tower", 0.6)) * (1.0 - overcast * 0.85), 0.01)}
		if want != _last_sky:
			_last_sky = want
			for k in want:
				sky.set_shader_parameter(k, want[k])
			sky.set_shader_parameter("storm_color", grey)
	var sea := world.get_node_or_null("Sea") as MeshInstance3D
	if sea and sea.material_override and _base.has("wave"):
		(sea.material_override as ShaderMaterial).set_shader_parameter("wave_amp", float(_base["wave"]) * (1.0 + 2.5 * HistWeather.sea_state()))


# ================================================================== 稲光・雷・突風
func _lightning(dt: float, cam: Camera3D) -> void:
	var th := maxf(float(cur["thunder"]), 1.0 if kind == "typhoon" and float(cur["storm"]) > 0.7 else 0.0)
	if th > 0.3:
		_next_strike -= dt * th
		if _next_strike <= 0.0:
			_next_strike = _rng.randf_range(7.0, 22.0)
			strike(_rng.randf_range(250.0, 2600.0), cam)
	if _flash_t >= 0.0:
		_flash_t += dt
		# 二度光る（ピカッ…ピカッ）
		var f := 0.0
		if _flash_t < 0.08:
			f = 1.0
		elif _flash_t < 0.16:
			f = 0.2
		elif _flash_t < 0.26:
			f = 0.75
		elif _flash_t < 0.6:
			f = 0.75 * (1.0 - (_flash_t - 0.26) / 0.34)
		else:
			_flash_t = -1.0
			_bolt.visible = false
		_flash = f * float(_bolt.get_meta("amp", 0.6))
	else:
		_flash = 0.0
	var now := _t
	while not _pending_thunder.is_empty() and float(_pending_thunder[0][0]) <= now:
		var e: Array = _pending_thunder.pop_front()
		Audio.play(str(e[1]), float(e[2]))


## 稲妻を落とす（dist m 先）。光ってから dist / 343 秒後に雷鳴
func strike(dist: float, cam: Camera3D = null) -> void:
	strikes += 1
	var amp := clampf(1.25 - dist / 2400.0, 0.25, 1.0) * (1.0 - _indoor_k * 0.6)
	_bolt.set_meta("amp", amp)
	_flash_t = 0.0
	if cam and dist < 1800.0:
		var fwd := -cam.global_basis.z
		fwd.y = 0.0
		var a := _rng.randf_range(-0.9, 0.9)
		var dir := fwd.normalized().rotated(Vector3.UP, a)
		var base := cam.global_position + dir * dist
		_bolt.mesh = _make_bolt_mesh(base + Vector3(0, 380, 0), base + Vector3(0, -5, 0), cam.global_position)
		_bolt.global_transform = Transform3D.IDENTITY
		_bolt.visible = true
	var key := "thunder_near" if dist < 900.0 else "thunder_far"
	var db := lerpf(0.0, -10.0, clampf(dist / 2600.0, 0.0, 1.0)) - _indoor_k * 6.0
	_pending_thunder.append([_t + dist / 343.0, key, db])
	_pending_thunder.sort_custom(func(x, y): return float(x[0]) < float(y[0]))


func _audio(dt: float, wind: float, cam: Camera3D) -> void:
	if wind < 8.0:
		return
	_next_gust -= dt
	if _next_gust <= 0.0:
		_next_gust = _rng.randf_range(4.0, 11.0) * (12.0 / maxf(wind, 8.0))
		gusts += 1
		var p := cam.global_position if cam else Audio.listener_pos()
		var a := _rng.randf() * TAU
		Audio.play_at("wind_gust", p + Vector3(cos(a), 0.4, sin(a)) * 12.0, -4.0 + clampf((wind - 10.0) * 0.4, 0.0, 6.0) - _indoor_k * 8.0)


# ================================================================== 表示
func _announce() -> void:
	_announce_hud()
	if hud == null:
		return
	var f: Dictionary = day.get("famous", {})
	var dt: Dictionary = day.get("date", {})
	var line := str(f.get("line", ""))
	if line != "":
		hud.toast(line, 7.0)
	if not dt.is_empty() and hud.has_method("set_weather_date"):
		var lt := str(dt.get("lunar_text", ""))
		hud.set_weather_date("%s%s" % [str(dt.get("text", "")), ("（旧暦 " + lt + "）") if lt != "" and int((dt.get("western", {}) as Dictionary).get("y", 2000)) < 1873 else ""])


func _announce_hud() -> void:
	var st := day.duplicate()
	st["kind"] = kind
	for k in FLOAT_KEYS:
		st[k] = float(target.get(k, 0.0))
	_label = HistWeather.label_ja(st)
	if day.get("tsuyu", false) and kind in ["rain", "cloudy", "overcast"]:
		_label = "梅雨・" + _label
	if hail:
		_label = "雹まじりの" + _label
	if hud and hud.has_method("set_weather"):
		hud.set_weather(kind, _label, HistWeather.source_ja(day), "%s　%d℃　風%dm/s" % [str(day.get("region_name", "")), roundi(float(day.get("temp", 15.0))), roundi(float(target.get("wind", 2.0)))])
