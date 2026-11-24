class_name Footsteps
extends Node
## 足音（プレイヤー・町人・兵・人物）と蹄の音（馬）。親の移動距離で一歩を数え、足元の床材（Surface）で音を選ぶ。
## 走り（速いとき）は別の音、跳んで着地すると落下の速さに応じた着地音、水に深く入ると泳ぐ音。
## 町人などは聞こえる距離（HEAR_DIST）の外では何もしない（数百人いても軽い）。

const HEAR_DIST := 30.0
const HORSE_GAITS := {
	# [ストライド長 m, 1 ストライド内の蹄の位相]
	"walk": [1.7, [0.0, 0.25, 0.5, 0.75]],
	"trot": [2.6, [0.0, 0.04, 0.5, 0.54]],
	"canter": [3.4, [0.0, 0.16, 0.22, 0.36]],
	"gallop": [4.8, [0.0, 0.09, 0.22, 0.3]],
}

var who := "npc"              # player / npc / horse
var body: Node3D
var vol_db := 0.0
var run_speed := 3.8          # これより速いと走りの音
var _last := Vector3.INF
var _acc := 0.0
var _speed := 0.0
var _foot := 1.0
var _was_floor := true
var _min_vy := 0.0
var _far := false
var _check_t := 0.0
var _swim_t := 0.0
var _pending: Array = []      # 馬の蹄: 鳴らす時刻（秒）
var _clock := 0.0
static var stats := {"steps": 0, "runs": 0, "lands": 0, "hooves": 0, "swims": 0, "surfaces": {}}   # 検査用の回数


static func attach(b: Node3D, kind := "npc", vol := 0.0) -> Footsteps:
	var f := Footsteps.new()
	f.name = "Footsteps"
	f.who = kind
	f.body = b
	f.vol_db = vol
	if kind == "player":
		f.run_speed = 6.5
	b.add_child(f)
	return f


func _ready() -> void:
	if not Audio.enabled:
		set_physics_process(false)
		return
	_check_t = randf() * 0.5


func _physics_process(dt: float) -> void:
	if body == null or not is_instance_valid(body) or not body.is_inside_tree():
		return
	_clock += dt
	var pos := body.global_position
	if _last == Vector3.INF:
		_last = pos
		return
	var d := Vector2(pos.x - _last.x, pos.z - _last.z).length()
	_last = pos
	if d > 4.0:          # 瞬間移動・乗り物の乗り降り
		_acc = 0.0
		return
	# 遠い者は時々距離だけ調べる
	if who != "player":
		_check_t -= dt
		if _check_t <= 0.0:
			_check_t = 0.5
			_far = Audio.listener_pos().distance_to(pos) > HEAR_DIST + (25.0 if who == "horse" else 0.0)
		if _far:
			_acc = 0.0
			_pending.clear()
			return
	_speed = lerpf(_speed, d / maxf(dt, 0.0001), 1.0 - exp(-dt * 8.0))
	if who == "horse":
		_horse(dt, pos)
		return
	if who == "player":
		if body.has_method("in_vehicle") and body.in_vehicle():
			_acc = 0.0
			_was_floor = true
			return
		if body.get("dead") == true:
			return
	var on_floor := true
	if body is CharacterBody3D:
		var cb := body as CharacterBody3D
		on_floor = cb.is_on_floor()
		if not on_floor:
			_min_vy = minf(_min_vy, cb.velocity.y)
		if who == "player":
			if _was_floor and not on_floor and cb.velocity.y > 3.0:
				Audio.play_at("cloth", pos + Vector3.UP, vol_db - 6.0)     # 跳ぶ
			elif on_floor and not _was_floor:
				_land(pos, -_min_vy)
			if on_floor:
				_min_vy = 0.0
	_was_floor = on_floor
	# 深い水：泳ぐ
	if who == "player" and Surface.water_at(Game.world, pos + Vector3.UP * 1.0):
		_swim_t -= dt
		if _speed > 0.6 and _swim_t <= 0.0:
			_swim_t = randf_range(0.8, 1.1)
			Audio.play_at("swim_stroke", pos + Vector3.UP * 1.2, vol_db)
			stats["swims"] = int(stats["swims"]) + 1
		_acc = 0.0
		return
	if not on_floor:
		return
	_acc += d
	var stride := clampf(0.45 + _speed * 0.17, 0.55, 2.0)
	if _speed < 0.35:
		_acc = minf(_acc, stride * 0.6)
		return
	if _acc >= stride:
		_acc -= stride
		_step(pos, _speed >= run_speed)


func _step(pos: Vector3, run: bool) -> void:
	var surf := weather_surface(surface(pos), pos)
	var key := "step_" + surf + ("_run" if run else "")
	if not SoundBank.has(key):
		key = "step_" + surf
	if not SoundBank.has(key):
		key = "step_dirt"
	_foot = -_foot
	var side := Vector3.ZERO
	if body is Node3D:
		side = (body as Node3D).global_basis.x * 0.12 * _foot
	var v := vol_db + (0.0 if who == "player" else -2.0) + (1.5 if run else 0.0)
	Audio.play_at(key, pos + side + Vector3.UP * 0.05, v)
	stats["steps"] = int(stats["steps"]) + 1
	if run:
		stats["runs"] = int(stats["runs"]) + 1
	(stats["surfaces"] as Dictionary)[surf] = int((stats["surfaces"] as Dictionary).get(surf, 0)) + 1
	# 板の間・縁側は時々きしむ（鶯張り）
	if surf == "wood" and randf() < 0.06:
		Audio.play_at("creak_wood", pos, v - 8.0)


func _land(pos: Vector3, vy: float) -> void:
	if vy < 4.5 or _clock < 1.5:
		return
	var surf := surface(pos)
	var key := "land_soft"
	match surf:
		"stone", "concrete", "gravel":
			key = "land_hard"
		"wood":
			key = "land_wood"
		"metal":
			key = "land_metal"
		"water", "mud", "wet", "wet_grass":
			key = "land_water"
		"tatami", "carpet":
			key = "land_tatami"
	var v := vol_db + clampf((vy - 4.5) * 1.2, -6.0, 6.0) - 3.0
	Audio.play_at(key, pos, v)
	stats["lands"] = int(stats["lands"]) + 1
	Audio.play_at("step_" + surf + "_run" if SoundBank.has("step_" + surf + "_run") else "step_dirt_run", pos + Vector3(0.15, 0, 0), v - 4.0)


## 足元の床材（レイは自分のボディを除く）
func surface(pos: Vector3) -> String:
	var space: PhysicsDirectSpaceState3D = null
	if body is Node3D and (body as Node3D).is_inside_tree():
		space = (body as Node3D).get_world_3d().direct_space_state
	var ex: Array = []
	if body is CollisionObject3D:
		ex.append((body as CollisionObject3D).get_rid())
	return Surface.at(pos, space, ex)


# ------------------------------------------------------------------ 馬
func _horse(dt: float, pos: Vector3) -> void:
	if body is CharacterBody3D and not (body as CharacterBody3D).is_on_floor():
		_was_floor = false
		_min_vy = minf(_min_vy, (body as CharacterBody3D).velocity.y)
		return
	if not _was_floor:
		_was_floor = true
		if -_min_vy > 4.0 and _clock > 1.5:
			for k in 4:
				_pending.append(_clock + k * 0.05)
		_min_vy = 0.0
	var gait := "walk"
	if _speed > 12.0:
		gait = "gallop"
	elif _speed > 7.0:
		gait = "canter"
	elif _speed > 3.0:
		gait = "trot"
	var g: Array = HORSE_GAITS[gait]
	var L: float = g[0]
	if _speed > 0.4:
		_acc += _speed * dt
		if _acc >= L:
			_acc -= L
			var period := L / maxf(_speed, 0.5)
			for ph in g[1]:
				_pending.append(_clock + float(ph) * period)
	else:
		_acc = 0.0
	if _pending.is_empty():
		return
	var surf := ""
	var i := 0
	while i < _pending.size():
		if float(_pending[i]) <= _clock:
			if surf == "":
				surf = weather_surface(surface(pos), pos)
			var key := "hoof_dirt"
			match surf:
				"stone", "concrete", "gravel":
					key = "hoof_stone"
				"wood", "metal":
					key = "hoof_wood"
				"grass", "sand", "snow", "mud", "tatami", "carpet", "wet_grass":
					key = "hoof_grass"
				"wet":
					key = "hoof_stone"
				"water":
					key = "step_water"
			var off := (body as Node3D).global_basis.z * randf_range(-0.9, 0.9)
			Audio.play_at(key, pos + off, vol_db + (2.0 if gait == "gallop" else 0.0))
			stats["hooves"] = int(stats["hooves"]) + 1
			_pending.remove_at(i)
		else:
			i += 1


## 天気で床材を言いかえる（屋外だけ）：雨の後の土は泥、草は濡れた草、石・板・舗装は水を踏む音。雪が積もれば雪
static func weather_surface(surf: String, pos: Vector3) -> String:
	var wet := HistWeather.cur("wet")
	var cover := HistWeather.cur("snow_cover")
	if wet < 0.3 and cover < 0.35:
		return surf
	if surf in ["water", "tatami", "carpet", "metal", "snow"]:
		return surf
	var w = Game.world
	if w != null and is_instance_valid(w) and w.has_method("interior_at") and int(w.interior_at(pos + Vector3.UP * 0.3)) >= 0:
		return surf
	return weather_variant(surf, wet, cover)


## 純関数（テスト用）：床材・濡れ・積雪 → 足音の床材
static func weather_variant(surf: String, wet: float, cover: float) -> String:
	if surf in ["water", "tatami", "carpet", "metal"]:
		return surf
	if cover >= 0.35 and surf in ["dirt", "grass", "gravel", "sand", "stone", "concrete", "mud", "wood"]:
		return "snow"
	if wet >= 0.3:
		match surf:
			"dirt", "mud":
				return "mud"
			"grass":
				return "wet_grass"
			"stone", "concrete", "gravel", "sand", "wood":
				return "wet"
	return surf

