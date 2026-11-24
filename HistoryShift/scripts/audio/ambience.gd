class_name AmbienceDirector
extends Node
## 環境音の監督（Session・HubSession の子）。聞き手（プレイヤー／カメラ）のまわりを 4 回/秒調べ、
## 環境音の層（ループ、Ambience バス）の音量をなめらかに合わせ、ときどき一発の音（鳥・鐘・犬・汽笛…）を空間に置く。
##  時代: 季節（平安・飛鳥奈良は春の鶯、昭和・江戸は夏の蝉、戦国は夕暮れのひぐらし、鎌倉室町・明治は秋の虫）、寺の鐘（仏教伝来後）、
##        江戸の風鈴・拍子木、明治・昭和の汽笛・汽船
##  場所: 海までの距離（波）、川（せせらぎ）、森の濃さ（鳥・蝉）、田（蛙）、町人の数（ざわめき）、合戦（遠い喊声）、高さ（強い風）
##  屋内・船: 屋内の空気（木造／洋館）＋外の音をこもらせる（Audio.set_indoor）、木造船のきしみ、鋼船の機関のうなり
##  2026 年のハブ: 研究所の機械音、外の車の往来
##  天気（HistWeather.live・WeatherDirector）: 小雨／大雨（屋外）、屋内は屋根を打つ雨（木造の瓦・茅の屋根／洋館・昭和のトタン・鋼船）、
##        台風のうなり、強風。雨の間は鳥・虫が黙り、雪の日は音が吸われて静かになる（鳥・虫・ざわめきを下げ、雪のしじまの層）
## 夜（太陽が弱い）は虫・蛙・梟。昼夜の切り替えは EraWorld.set_time_of_day に追従する。

const ERA := {
	"jomon_kofun": {"music": "music_jomon", "cicada": 0.35, "uguisu": 0.4, "bell": false, "crow": 0.4, "kite": 0.6},
	"asuka_nara": {"music": "music_nara", "uguisu": 1.0, "bell": true, "crow": 0.5, "kite": 0.5},
	"heian": {"music": "music_heian", "uguisu": 1.0, "bell": true, "crow": 0.6, "kite": 0.4},
	"kamakura_muromachi": {"music": "music_kamakura", "uguisu": 0.15, "bell": true, "insects_day": 0.25, "crow": 0.7, "kite": 0.6},
	"sengoku": {"music": "music_sengoku", "higurashi": 1.0, "bell": true, "crow": 0.8, "kite": 0.5, "insects_day": 0.3, "battle": true},
	"edo": {"music": "music_edo", "cicada": 0.55, "bell": true, "chime": true, "hyoshigi": true, "crow": 0.8, "kite": 0.4},
	"meiji_taisho": {"music": "music_meiji", "bell": true, "train": true, "steamer": true, "insects_day": 0.2, "crow": 0.8, "kite": 0.3},
	"showa": {"music": "music_showa", "cicada": 1.0, "bell": true, "chime": true, "train": true, "steamer": true, "crow": 0.7, "kite": 0.2},
}
const LAYERS := ["amb_wind_light", "amb_wind_strong", "amb_birds_day", "amb_cicada_summer", "amb_higurashi", "amb_night_insects",
	"amb_frogs", "amb_sea_waves", "amb_lapping", "amb_river", "amb_crowd_town", "amb_battle_distant", "amb_room_wood",
	"amb_room_modern", "amb_ship_wood", "amb_ship_steel", "amb_lab", "amb_city_traffic", "amb_factory",
	"amb_rain_light", "amb_rain_heavy", "amb_rain_roof_wood", "amb_rain_roof_tin", "amb_storm_wind", "amb_snow_hush"]
const TICK := 0.25

var hub := false
var era_id := ""
var conf: Dictionary = {}
var _players := {}           # key -> AudioStreamPlayer
var _vol := {}               # key -> 今の音量（0〜1）
var _target := {}            # key -> 目標
var _t := 0.0
var _spot_t := {}            # 一発音の次の時刻
var _clock := 0.0
var _rng := RandomNumberGenerator.new()
var _sea_grid := PackedFloat32Array()
var _sea_n := 0
var _sea_lo := 0.0
var _sea_cell := 1.0
var _indoor_k := 0.0
var _was_in_lab := false
var ctx := {}                # 最後に調べた状況（テスト・デバッグ用）


static func attach(parent: Node, p_era: String, p_hub := false) -> AmbienceDirector:
	var d := AmbienceDirector.new()
	d.name = "Ambience"
	d.era_id = p_era
	d.hub = p_hub
	parent.add_child(d)
	return d


static func era_music(id: String) -> String:
	return String(ERA.get(id, {}).get("music", "music_hub"))


func _ready() -> void:
	_rng.randomize()
	conf = ERA.get(era_id, {})
	for k in ["bird", "bell", "dog", "chime", "hyoshigi", "train", "steamer", "owl", "gull", "beep", "horn", "creak"]:
		_spot_t[k] = _rng.randf_range(2.0, 12.0)
	_spot_t["bell"] = _rng.randf_range(15.0, 45.0)


func _exit_tree() -> void:
	Audio.set_indoor(0.0)


func _process(dt: float) -> void:
	_clock += dt
	_t += dt
	if _t >= TICK:
		_t = 0.0
		_update()
		_spots()
	# なめらかに追従（2 秒ほどで入れ替わる）
	for k in _target:
		var tg: float = _target[k]
		var v: float = _vol.get(k, 0.0)
		if absf(v - tg) < 0.0005 and not _players.has(k):
			continue
		v = move_toward(v, tg, dt * 0.5)
		_vol[k] = v
		_apply(k, v)
	Audio.set_indoor(_indoor_k)


func _apply(key: String, v: float) -> void:
	if not Audio.enabled:
		return
	var p: AudioStreamPlayer = _players.get(key)
	if v <= 0.002:
		if p and p.playing:
			p.stop()
		return
	if p == null:
		p = AudioStreamPlayer.new()
		p.name = key
		p.stream = SoundBank.pick(key)
		p.bus = "Ambience"
		add_child(p)
		_players[key] = p
	if not p.playing:
		p.play(_rng.randf() * maxf(0.0, SoundBank.length(key) - 1.0))
	p.volume_db = SoundBank.base_db(key) + linear_to_db(v)


func _want(key: String, v: float) -> void:
	_target[key] = clampf(v, 0.0, 1.0)


# ================================================================ 状況を調べる
func _listener() -> Vector3:
	var pl = Game.player
	if pl != null and is_instance_valid(pl) and (pl as Node3D).is_inside_tree():
		return (pl as Node3D).global_position
	return Audio.listener_pos()


## 太陽: [昼の度合い 0〜1, 夕方の度合い 0〜1]
func _daylight(w) -> Array:
	var env = w.get("env_nodes") if w else null
	if not (env is Dictionary):
		return [1.0, 0.0]
	var sun: DirectionalLight3D = (env as Dictionary).get("sun")
	if sun == null or not is_instance_valid(sun):
		return [1.0, 0.0]
	if float(sun.get_meta("base_e", sun.light_energy)) < 0.25:   # 天気・屋内で暗くした分は除く
		return [0.0, 0.0]          # 夜（月明かり）
	var elev := rad_to_deg(asin(clampf(sun.global_basis.z.y, -1.0, 1.0)))
	var day := clampf((elev + 2.0) / 10.0, 0.0, 1.0)
	var dusk := 1.0 - clampf((elev - 6.0) / 14.0, 0.0, 1.0)
	return [day, dusk * day]


func _update() -> void:
	for k in LAYERS:
		_want(k, 0.0)
	var w = Game.world
	if w == null or not is_instance_valid(w):
		_indoor_k = 0.0
		return
	var p := _listener()
	if hub or w.has_method("in_lab"):
		_update_hub(w, p)
		return
	var dl := _daylight(w)
	var day: float = dl[0]
	var dusk: float = dl[1]
	var night := 1.0 - day
	var t: TerrainGen = w.get("terrain") if w.get("terrain") is TerrainGen else null
	# 屋内・船
	var indoor := 0.0
	var room_key := ""
	var wi = w.get("interiors")
	if wi and is_instance_valid(wi) and int(wi.player_inside) >= 0:
		indoor = 1.0
		var ty := String(wi.defs[int(wi.player_inside)]["type"])
		room_key = "amb_room_modern" if WorldInteriors.kind_surface(ty) == "concrete" else "amb_room_wood"
	var ship_k := 0.0
	var ship_steel := false
	for s in get_tree().get_nodes_in_group("ship"):
		var sh := s as Ship
		if sh and sh.player_aboard:
			ship_steel = sh.sd.steel
			ship_k = 1.0 if sh.player_inside else 0.45
			if sh.player_inside:
				indoor = maxf(indoor, 0.8)
			break
	var out := 1.0 - indoor * 0.75      # 外の音（こもりは Audio.set_indoor のローパス）
	# 森・田・水・高さ
	var forest := 0.0
	var field := 0.0
	if t:
		for o in [Vector2.ZERO, Vector2(18, 0), Vector2(-18, 0), Vector2(0, 18), Vector2(0, -18)]:
			var q := Vector2(clampf(p.x + o.x, -t.half, t.half), clampf(p.z + o.y, -t.half, t.half))
			forest += t.mask_at(t.forest, q.x, q.y) * 0.2
			field = maxf(field, t.mask_at(t.field, q.x, q.y))
	var sea_d := _sea_dist(w, p)
	var river_d := 999.0
	if t and t.river_pts.size() > 1 and absf(p.x) < t.half and absf(p.z) < t.half:
		river_d = maxf(0.0, t.river_dist_at(p.x, p.z) - t.river_half_w)
	var ground := t.height_at(p.x, p.z) if t else 0.0
	var wl0 = w.get("water_level")
	var height := maxf(0.0, p.y - (float(wl0) if wl0 != null else 0.0))
	# 町人の数（ざわめき）・敵（合戦）
	var civ := 0
	for c in get_tree().get_nodes_in_group("civilian"):
		if (c as Node3D).global_position.distance_squared_to(p) < 35.0 * 35.0:
			civ += 1
	var foes := 0
	for e in get_tree().get_nodes_in_group("enemy"):
		if e.get("dead") != true and (e as Node3D).global_position.distance_squared_to(p) < 130.0 * 130.0:
			foes += 1
	var crowd := clampf(sqrt(float(civ)) / 4.0, 0.0, 1.0)
	var town := crowd
	var lmall: Dictionary = _landmarks(w)
	for key in ["capital", "port"]:
		var lm: Dictionary = lmall.get(key, {})
		if not lm.is_empty():
			var dd := Vector2(p.x, p.z).distance_to(lm["center"])
			town = maxf(town, (1.0 - clampf((dd - float(lm["r"])) / 60.0, 0.0, 1.0)) * 0.6)
	# ---- 層
	var exposed := clampf((height - 25.0) / 40.0, 0.0, 1.0)
	_want("amb_wind_light", (0.55 + 0.25 * night) * out)
	_want("amb_wind_strong", maxf(exposed, ship_k * 0.4 * (1.0 - indoor)) * out)
	var birds := day * (0.25 + 0.75 * forest) * (1.0 - town * 0.6)
	_want("amb_birds_day", birds * out)
	_want("amb_cicada_summer", float(conf.get("cicada", 0.0)) * day * (0.35 + 0.65 * forest) * (1.0 - dusk * 0.7) * out)
	_want("amb_higurashi", float(conf.get("higurashi", 0.0)) * maxf(dusk, 0.0) * (0.4 + 0.6 * forest) * out)
	_want("amb_night_insects", maxf(night, dusk * float(conf.get("insects_day", 0.0)) * 2.5 + float(conf.get("insects_day", 0.0)) * 0.6) * (1.0 - town * 0.4) * out)
	_want("amb_frogs", clampf(field * 1.4 - 0.2, 0.0, 1.0) * maxf(night, 0.35 * float(conf.get("cicada", 0.0) > 0.0 or conf.get("uguisu", 0.0) > 0.5)) * out)
	_want("amb_sea_waves", pow(clampf(1.0 - sea_d / 140.0, 0.0, 1.0), 1.6) * out)
	_want("amb_lapping", (clampf(1.0 - sea_d / 18.0, 0.0, 1.0) * 0.8 + ship_k * 0.5) * out)
	_want("amb_river", pow(clampf(1.0 - river_d / 60.0, 0.0, 1.0), 1.5) * out)
	_want("amb_crowd_town", town * out)
	if conf.get("battle", false) or era_id == "kamakura_muromachi":
		_want("amb_battle_distant", clampf((float(foes) - 3.0) / 6.0, 0.0, 0.8) * out)
	if room_key != "":
		_want(room_key, 1.0)
	if ship_k > 0.0:
		_want("amb_ship_steel" if ship_steel else "amb_ship_wood", ship_k)
	_weather_layers(indoor, room_key, ship_steel, out)
	_indoor_k = indoor
	ctx = {"day": day, "dusk": dusk, "forest": forest, "field": field, "sea": sea_d, "river": river_d, "civ": civ,
		"foes": foes, "indoor": indoor, "ship": ship_k, "town": town, "ground": ground, "pos": p}


## 天気の層（雨音・屋根の雨・台風・雪の静けさ）と、雨・雪のときに黙る生き物
func _weather_layers(indoor: float, room_key: String, ship_steel: bool, out: float) -> void:
	var wx: Dictionary = HistWeather.live
	if wx.is_empty():
		return
	var r := float(wx.get("rain_out", 0.0))
	var sn := float(wx.get("snow", 0.0))
	var wnd := float(wx.get("wind", 0.0))
	var cover := float(wx.get("snow_cover", 0.0))
	var open := 1.0 - indoor
	_want("amb_rain_light", clampf(r * 2.0, 0.0, 1.0) * (1.0 - clampf((r - 0.55) * 2.0, 0.0, 0.6)) * (open + indoor * 0.25))
	_want("amb_rain_heavy", clampf((r - 0.35) / 0.5, 0.0, 1.0) * (open + indoor * 0.2))
	if indoor > 0.5 and r > 0.03:
		var tin := room_key == "amb_room_modern" or ship_steel
		_want("amb_rain_roof_tin" if tin else "amb_rain_roof_wood", clampf(r * 1.4, 0.2, 1.0))
	_want("amb_storm_wind", clampf((wnd - 13.0) / 10.0, 0.0, 1.0) * (1.0 - indoor * 0.45))
	_target["amb_wind_strong"] = maxf(float(_target.get("amb_wind_strong", 0.0)), clampf((wnd - 7.0) / 8.0, 0.0, 1.0) * out)
	var hush := clampf(sn * 0.8 + cover * 0.35, 0.0, 1.0)
	_want("amb_snow_hush", hush * 0.7 * open)
	var quiet := (1.0 - clampf(r * 0.9, 0.0, 0.85)) * (1.0 - hush * 0.7)
	for k in ["amb_birds_day", "amb_cicada_summer", "amb_higurashi", "amb_night_insects", "amb_frogs"]:
		_target[k] = float(_target.get(k, 0.0)) * quiet * (1.35 if k == "amb_frogs" and r > 0.1 else 1.0)
	for k in ["amb_crowd_town", "amb_battle_distant", "amb_wind_light"]:
		_target[k] = float(_target.get(k, 0.0)) * (1.0 - hush * 0.5) * (1.0 - clampf(r - 0.4, 0.0, 0.5))


func _update_hub(w, p: Vector3) -> void:
	var lab: bool = w.in_lab(p) if w.has_method("in_lab") else false
	if lab != _was_in_lab:
		_was_in_lab = lab
		Audio.play_at("door_modern_open", p, -2.0)
	_indoor_k = 1.0 if lab else 0.0
	if lab:
		_want("amb_lab", 1.0)
		_want("amb_city_traffic", 0.35)
		_want("amb_room_modern", 0.5)
	else:
		_want("amb_city_traffic", 0.9)
		_want("amb_wind_light", 0.35)
		_want("amb_crowd_town", 0.35)
		_want("amb_birds_day", 0.15)
	ctx = {"lab": lab, "pos": p}


func _landmarks(w) -> Dictionary:
	var l = w.get("landmarks") if w else null
	return l if l is Dictionary else {}


# ================================================================ 海までの距離（粗い格子＋距離変換、最初に一度だけ）
func _sea_dist(w, p: Vector3) -> float:
	var t: TerrainGen = w.get("terrain") if w.get("terrain") is TerrainGen else null
	if t == null:
		return 999.0
	if _sea_grid.is_empty():
		_build_sea(w, t)
	var i := clampi(int((p.x - _sea_lo) / _sea_cell), 0, _sea_n - 1)
	var j := clampi(int((p.z - _sea_lo) / _sea_cell), 0, _sea_n - 1)
	return _sea_grid[j * _sea_n + i]


func _build_sea(w, t: TerrainGen) -> void:
	_sea_n = 56
	_sea_lo = -t.half - 60.0
	_sea_cell = (t.half * 2.0 + 120.0) / _sea_n
	var wl := float(w.get("water_level"))
	var n := _sea_n
	_sea_grid.resize(n * n)
	var queue: Array = []
	for j in n:
		for i in n:
			var x := _sea_lo + (i + 0.5) * _sea_cell
			var z := _sea_lo + (j + 0.5) * _sea_cell
			var sea := t.height_at(x, z) < wl - 0.3
			if sea and absf(x) < t.half and absf(z) < t.half and t.river_pts.size() > 1 and t.river_dist_at(x, z) < t.river_half_w + 6.0:
				sea = false   # 川は海ではない
			_sea_grid[j * n + i] = 0.0 if sea else INF
			if sea:
				queue.append(j * n + i)
	# 8 近傍の距離変換（ダイクストラ風に 2 回の掃引）
	for pass_i in 2:
		var order := range(n * n) if pass_i == 0 else range(n * n - 1, -1, -1)
		for idv in order:
			var id: int = idv
			var i: int = id % n
			var j: int = id / n
			var best: float = _sea_grid[id]
			for o in [[-1, 0, 1.0], [1, 0, 1.0], [0, -1, 1.0], [0, 1, 1.0], [-1, -1, 1.414], [1, -1, 1.414], [-1, 1, 1.414], [1, 1, 1.414]]:
				var ii: int = i + int(o[0])
				var jj: int = j + int(o[1])
				if ii < 0 or jj < 0 or ii >= n or jj >= n:
					continue
				best = minf(best, _sea_grid[jj * n + ii] + float(o[2]) * _sea_cell)
			_sea_grid[id] = best
	if queue.is_empty():
		_sea_grid.fill(999.0)


# ================================================================ 一発の音
func _due(k: String, lo: float, hi: float) -> bool:
	if _clock < float(_spot_t.get(k, 0.0)):
		return false
	_spot_t[k] = _clock + _rng.randf_range(lo, hi)
	return true


func _around(p: Vector3, r0: float, r1: float, up0: float, up1: float) -> Vector3:
	var a := _rng.randf() * TAU
	var r := _rng.randf_range(r0, r1)
	return p + Vector3(cos(a) * r, _rng.randf_range(up0, up1), sin(a) * r)


func _spots() -> void:
	if not Audio.enabled:
		return
	var w = Game.world
	if w == null or not is_instance_valid(w):
		return
	var p := _listener()
	if hub or w.has_method("in_lab"):
		if bool(ctx.get("lab", false)):
			if _due("beep", 3.0, 9.0):
				Audio.play_at("lab_beep", _around(p, 3.0, 9.0, 0.5, 1.5), -4.0)
		elif _due("horn", 18.0, 45.0):
			Audio.play_at("car_horn_modern", _around(p, 30.0, 60.0, 0.0, 1.0), -10.0)
		return
	if ctx.is_empty():
		return
	var day: float = ctx["day"]
	var indoor: float = ctx["indoor"]
	var out_db := -10.0 * indoor
	# 鳥（雨・雪の間は鳴かない）
	var wx_quiet := float(HistWeather.live.get("rain_out", 0.0)) + float(HistWeather.live.get("snow", 0.0)) > 0.25
	if day > 0.3 and not wx_quiet and _due("bird", 3.0, 9.0):
		var town: float = ctx["town"]
		var r := _rng.randf()
		var key := "bird_chirp"
		if r < float(conf.get("uguisu", 0.0)) * 0.35 * float(ctx["forest"] + 0.3):
			key = "bird_uguisu"
		elif r < 0.55 and _rng.randf() < float(conf.get("crow", 0.5)) * (0.3 + town):
			key = "bird_crow"
		elif r < 0.7 and float(ctx["sea"]) < 60.0:
			key = "bird_gull"
		elif r < 0.78 and _rng.randf() < float(conf.get("kite", 0.3)):
			key = "bird_kite"
		elif r < 0.9:
			key = "bird_hiyodori"
		var high := key == "bird_kite" or key == "bird_gull"
		Audio.play_at(key, _around(p, 15.0, 55.0, 30.0 if high else 5.0, 60.0 if high else 14.0), out_db + _rng.randf_range(-4.0, 0.0))
	# 夜の梟
	if day < 0.2 and float(ctx["forest"]) > 0.25 and _due("owl", 20.0, 50.0):
		Audio.play_at("bird_owl", _around(p, 25.0, 60.0, 6.0, 15.0), out_db - 2.0)
	# 寺の鐘（仏教が伝わってから。寺の名所から）
	if conf.get("bell", false) and _due("bell", 70.0, 160.0):
		var lms: Dictionary = _landmarks(w)
		if lms.has("temple"):
			Audio.play_at("temple_bell", (lms["temple"]["pos"] as Vector3) + Vector3.UP * 8.0, 0.0)
	# 村の犬
	if _due("dog", 25.0, 70.0):
		var lms2: Dictionary = _landmarks(w)
		if lms2.has("village") and p.distance_to(lms2["village"]["pos"]) < 150.0:
			Audio.play_at("dog_bark", _around(lms2["village"]["pos"], 5.0, 40.0, 0.5, 1.5), out_db - 2.0)
	# 江戸・昭和の夏の風鈴（町なか）
	if conf.get("chime", false) and float(ctx["town"]) > 0.2 and day > 0.3 and _due("chime", 14.0, 40.0):
		Audio.play_at("wind_chime", _around(p, 6.0, 20.0, 2.5, 4.0), out_db - 4.0)
	# 江戸の夜回りの拍子木
	if conf.get("hyoshigi", false) and day < 0.4 and _due("hyoshigi", 35.0, 90.0):
		Audio.play_at("hyoshigi", _around(p, 30.0, 70.0, 1.0, 2.0), out_db)
	# 明治・昭和の汽車・汽船の汽笛
	if conf.get("train", false) and _due("train", 90.0, 200.0):
		Audio.play_at("train_whistle", _around(p, 220.0, 320.0, 3.0, 6.0), out_db)
	if conf.get("steamer", false) and float(ctx["sea"]) < 200.0 and _due("steamer", 80.0, 170.0):
		Audio.play_at("ship_whistle", _around(p, 150.0, 260.0, 8.0, 12.0), out_db - 3.0)
	# 木造船の上：ときどき大きくきしむ
	if float(ctx["ship"]) > 0.0 and _due("creak", 4.0, 10.0):
		Audio.play_at("creak_wood", _around(p, 2.0, 8.0, -1.0, 2.0), -4.0)
