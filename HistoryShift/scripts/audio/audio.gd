class_name Audio
extends Node
## 音の再生の中心（ルート直下の "AudioHub" ノード。最初の再生か Audio.setup() で作る）。
## - バス: Master / Music / SFX / Ambience / Voice（設定画面の音量。Ambience は屋内でこもる・SFX は屋内で残響）
## - Audio.play(key) 2D / Audio.play_at(key, pos) 3D（距離減衰・ピッチと音量の揺らぎ・同時発音の上限）
## - Audio.loop_at(host, key) 乗り物・火・導火線などの鳴り続ける音（host の子。呼び出し側が play/stop）
## - Audio.music(key) BGM のクロスフェード
## 音の素材は assets/audio/（SoundBank / SoundManifest）。ヘッドレス（テスト）では何も鳴らさない。

const BUSES := ["Music", "SFX", "Ambience", "Voice"]
const POOL_3D := 40
const POOL_2D := 14
## key ごとの同時発音数（既定 4）
const PER_KEY := {"collapse_building": 2, "collapse_small": 2, "explosion_large": 3, "explosion_small": 3, "cannon_fire": 3,
	"break_wood": 4, "break_plaster": 3, "break_stone": 3, "break_tiles": 3, "break_glass": 3, "debris": 3, "temple_bell": 1,
	"fire_ignite": 2, "body_fall": 3, "gun_lmg": 6, "splash_big": 2, "time_warp": 1, "ui_hover": 2}
## 接頭辞ごとの距離減衰 [unit_size, max_distance, ピッチの揺らぎ, 音量の揺らぎ dB, 優先度]
const CATS := [
	["step_", 2.5, 32.0, 0.08, 2.5, 0], ["land_", 3.0, 40.0, 0.06, 2.0, 1], ["hoof_", 4.0, 60.0, 0.07, 2.0, 1],
	["gun_", 28.0, 420.0, 0.04, 1.0, 3], ["cannon", 60.0, 900.0, 0.05, 1.0, 4], ["explosion", 60.0, 900.0, 0.06, 1.0, 4],
	["collapse", 40.0, 600.0, 0.05, 1.0, 4], ["break_", 14.0, 250.0, 0.08, 2.0, 2], ["tree_fall", 20.0, 300.0, 0.05, 1.0, 2],
	["temple_bell", 120.0, 1500.0, 0.0, 0.0, 2], ["bird_", 18.0, 220.0, 0.06, 2.0, 0], ["ship_whistle", 80.0, 1200.0, 0.0, 0.0, 2],
	["train_whistle", 120.0, 1500.0, 0.0, 0.0, 1], ["swing_", 3.0, 30.0, 0.08, 1.5, 1], ["hit_", 5.0, 60.0, 0.08, 1.5, 2],
	["impact_", 5.0, 70.0, 0.1, 2.0, 1], ["sword_", 6.0, 80.0, 0.06, 1.5, 2], ["splash_big", 20.0, 300.0, 0.06, 1.0, 2],
	["fire_", 8.0, 120.0, 0.05, 1.0, 1], ["hansho", 60.0, 900.0, 0.0, 0.0, 2], ["dog_bark", 25.0, 300.0, 0.08, 2.0, 0],
	["wind_gust", 20.0, 220.0, 0.1, 2.0, 0],
]

static var I: Audio = null
static var enabled := true
static var _setup_done := false

var _pool3: Array = []
var _pool2: Array = []
var _info3 := {}           # player -> {key, t, prio}
var _count := {}           # key -> 鳴っている数
var _recent := {}          # key -> [time, pos]
var _music: Array = []     # [AudioStreamPlayer, AudioStreamPlayer]
var _music_cur := 0
var music_key := ""
var _indoor := 0.0
var _indoor_target := 0.0
var _lp_fx: AudioEffectLowPassFilter
var _rev_fx: AudioEffectReverb
var _rev_idx := -1
var _rng := RandomNumberGenerator.new()


# ================================================================ 準備
## バスとハブを用意する（Game の _ready から。何度呼んでもよい）
static func setup() -> void:
	ensure_buses()
	enabled = DisplayServer.get_name() != "headless"
	if I != null and is_instance_valid(I):
		return
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return
	I = Audio.new()
	I.name = "AudioHub"
	I.process_mode = Node.PROCESS_MODE_ALWAYS
	tree.root.add_child.call_deferred(I)


static func ensure_buses() -> void:
	if _setup_done and AudioServer.get_bus_index("SFX") >= 0:
		return
	_setup_done = true
	for b in BUSES:
		if AudioServer.get_bus_index(b) == -1:
			AudioServer.add_bus()
			var i := AudioServer.bus_count - 1
			AudioServer.set_bus_name(i, b)
			AudioServer.set_bus_send(i, "Master")
	var amb := AudioServer.get_bus_index("Ambience")
	if amb >= 0 and AudioServer.get_bus_effect_count(amb) == 0:
		var lpf := AudioEffectLowPassFilter.new()
		lpf.cutoff_hz = 20000.0
		AudioServer.add_bus_effect(amb, lpf)
		AudioServer.set_bus_effect_enabled(amb, 0, false)
	var sfx := AudioServer.get_bus_index("SFX")
	if sfx >= 0 and AudioServer.get_bus_effect_count(sfx) == 0:
		var rv := AudioEffectReverb.new()
		rv.room_size = 0.35
		rv.damping = 0.6
		rv.wet = 0.0
		rv.dry = 1.0
		rv.spread = 0.6
		AudioServer.add_bus_effect(sfx, rv)
		AudioServer.set_bus_effect_enabled(sfx, 0, false)
	# 破壊・爆発が重なっても割れないように Master にリミッタ
	if AudioServer.get_bus_effect_count(0) == 0 and ClassDB.class_exists("AudioEffectHardLimiter"):
		var lim = ClassDB.instantiate("AudioEffectHardLimiter")
		if lim is AudioEffect:
			lim.set("ceiling_db", -0.5)
			AudioServer.add_bus_effect(0, lim)


## バスの音量（0〜1）
static func set_bus_linear(bus: String, v: float) -> void:
	ensure_buses()
	var i := AudioServer.get_bus_index(bus)
	if i < 0:
		return
	AudioServer.set_bus_volume_db(i, linear_to_db(maxf(v, 0.0001)))
	AudioServer.set_bus_mute(i, v <= 0.001)


func _ready() -> void:
	_rng.randomize()
	for i in POOL_3D:
		var p := AudioStreamPlayer3D.new()
		p.process_mode = Node.PROCESS_MODE_PAUSABLE
		p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		p.finished.connect(_on_done.bind(p))
		add_child(p)
		_pool3.append(p)
	for i in POOL_2D:
		var p := AudioStreamPlayer.new()
		p.process_mode = Node.PROCESS_MODE_ALWAYS
		p.finished.connect(_on_done.bind(p))
		add_child(p)
		_pool2.append(p)
	for i in 2:
		var m := AudioStreamPlayer.new()
		m.bus = "Music"
		m.process_mode = Node.PROCESS_MODE_ALWAYS
		m.volume_db = -80.0
		add_child(m)
		_music.append(m)
	var amb := AudioServer.get_bus_index("Ambience")
	if amb >= 0 and AudioServer.get_bus_effect_count(amb) > 0:
		_lp_fx = AudioServer.get_bus_effect(amb, 0) as AudioEffectLowPassFilter
	var sfx := AudioServer.get_bus_index("SFX")
	if sfx >= 0 and AudioServer.get_bus_effect_count(sfx) > 0:
		_rev_fx = AudioServer.get_bus_effect(sfx, 0) as AudioEffectReverb
		_rev_idx = sfx


func _process(dt: float) -> void:
	# 屋内（建物・船内）: 環境音をこもらせ、効果音に部屋の残響
	if absf(_indoor - _indoor_target) > 0.001:
		_indoor = move_toward(_indoor, _indoor_target, dt * 2.0)
		var amb := AudioServer.get_bus_index("Ambience")
		if _lp_fx and amb >= 0:
			_lp_fx.cutoff_hz = lerpf(20000.0, 700.0, _indoor)
			AudioServer.set_bus_effect_enabled(amb, 0, _indoor > 0.01)
		if _rev_fx and _rev_idx >= 0:
			_rev_fx.wet = 0.16 * _indoor
			AudioServer.set_bus_effect_enabled(_rev_idx, 0, _indoor > 0.01)


static func hub() -> Audio:
	if I == null or not is_instance_valid(I):
		setup()
	return I if (I != null and is_instance_valid(I) and I.is_inside_tree()) else null


## 屋内の度合い（0 屋外〜1 屋内）。AmbienceDirector が毎フレーム設定する
static func set_indoor(k: float) -> void:
	var h := hub()
	if h:
		h._indoor_target = clampf(k, 0.0, 1.0)


# ================================================================ 位置・カテゴリ
static func listener_pos() -> Vector3:
	var tree := Engine.get_main_loop() as SceneTree
	if tree and tree.root:
		var cam := tree.root.get_viewport().get_camera_3d()
		if cam and cam.is_inside_tree():
			return cam.global_position
	return Vector3(0, -1e6, 0)


static func _cat(key: String) -> Array:
	for c in CATS:
		if key.begins_with(String(c[0])):
			return c
	return ["", 6.0, 90.0, 0.06, 1.5, 1]


# ================================================================ 再生
## 2D（UI・自分の手元・ジングル）
static func play(key: String, vol_db := 0.0, opts := {}) -> void:
	if not enabled:
		return
	var h := hub()
	if h == null:
		return
	h._play2(key, vol_db, opts)


## 3D の一発音。opts: pitch, pitch_var, vol_var, unit, max_dist, bus, prio
static func play_at(key: String, pos: Vector3, vol_db := 0.0, opts := {}) -> void:
	if not enabled:
		return
	var h := hub()
	if h == null:
		return
	h._play3(key, pos, vol_db, opts)


## host の子に鳴り続ける 3D の音を作る（停止中で返す。呼び出し側が play()）
static func loop_at(host: Node3D, key: String, vol_db := 0.0, opts := {}) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.name = "Snd_" + key
	p.stream = SoundBank.pick(key)
	var c := _cat(key)
	p.unit_size = float(opts.get("unit", maxf(6.0, float(c[1]))))
	p.max_distance = float(opts.get("max_dist", maxf(120.0, float(c[2]))))
	p.volume_db = vol_db + SoundBank.base_db(key)
	p.bus = String(opts.get("bus", SoundBank.bus(key)))
	p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	p.set_meta("base_db", p.volume_db)
	if host:
		host.add_child(p)
		if opts.get("autoplay", false) and enabled and p.is_inside_tree():
			p.play(randf() * maxf(0.0, SoundBank.length(key) - 0.1))
	return p


func _play2(key: String, vol_db: float, opts: Dictionary) -> void:
	if SoundBank.is_loop(key) and not key.begins_with("music_"):
		return   # ループ音は loop_at / AmbienceDirector で（一発の再生枠を占有しない）
	var s := SoundBank.pick(key)
	if s == null:
		return
	var limit: int = PER_KEY.get(key, 4)
	if int(_count.get(key, 0)) >= limit:
		return
	var p: AudioStreamPlayer = null
	for q in _pool2:
		if not (q as AudioStreamPlayer).playing:
			p = q
			break
	if p == null:
		return
	_release(p)
	p.stream = s
	p.bus = String(opts.get("bus", SoundBank.bus(key)))
	var vv := float(opts.get("vol_var", 0.0))
	p.volume_db = vol_db + SoundBank.base_db(key) + _rng.randf_range(-vv, vv)
	var pv := float(opts.get("pitch_var", 0.0))
	p.pitch_scale = float(opts.get("pitch", 1.0)) * _rng.randf_range(1.0 - pv, 1.0 + pv)
	p.set_meta("key", key)
	_count[key] = int(_count.get(key, 0)) + 1
	p.play()


func _play3(key: String, pos: Vector3, vol_db: float, opts: Dictionary) -> void:
	if SoundBank.is_loop(key):
		return
	var c := _cat(key)
	var maxd := float(opts.get("max_dist", c[2]))
	var lp := listener_pos()
	var dist := lp.distance_to(pos)
	if dist > maxd:
		return
	var now := Time.get_ticks_msec()
	# ほぼ同じ場所・同じ瞬間の同じ音は重ねない（位相の重なりで不自然に大きくなる）
	var rc: Array = _recent.get(key, [])
	if not rc.is_empty() and now - int(rc[0]) < 35 and (rc[1] as Vector3).distance_to(pos) < 1.5:
		return
	_recent[key] = [now, pos]
	var s := SoundBank.pick(key)
	if s == null:
		return
	var prio := int(opts.get("prio", c[5]))
	var limit: int = PER_KEY.get(key, 6 if key.begins_with("step_") else 4)
	var p: AudioStreamPlayer3D = null
	if int(_count.get(key, 0)) >= limit:
		# 同じ音の一番遠いものより近ければ置きかえる
		p = _steal(lp, dist, key, -1)
		if p == null:
			return
	else:
		for q in _pool3:
			if not (q as AudioStreamPlayer3D).playing:
				p = q
				break
		if p == null:
			p = _steal(lp, dist, "", prio)
			if p == null:
				return
	_release(p)
	p.stream = s
	p.bus = String(opts.get("bus", SoundBank.bus(key)))
	p.unit_size = float(opts.get("unit", c[1]))
	p.max_distance = maxd
	var vv := float(opts.get("vol_var", c[4]))
	p.volume_db = vol_db + SoundBank.base_db(key) + _rng.randf_range(-vv, vv)
	var pv := float(opts.get("pitch_var", c[3]))
	p.pitch_scale = float(opts.get("pitch", 1.0)) * _rng.randf_range(1.0 - pv, 1.0 + pv)
	p.global_position = pos
	p.set_meta("key", key)
	_info3[p] = {"key": key, "t": now, "prio": prio, "pos": pos}
	_count[key] = int(_count.get(key, 0)) + 1
	p.play()


## 置きかえ先：key 指定ならその音の中で、無指定なら優先度が低く遠いものから
func _steal(lp: Vector3, dist: float, key: String, prio: int) -> AudioStreamPlayer3D:
	var best: AudioStreamPlayer3D = null
	var best_score := -INF
	for q in _info3:
		var inf: Dictionary = _info3[q]
		if not (q as AudioStreamPlayer3D).playing:
			continue
		if key != "" and String(inf["key"]) != key:
			continue
		if key == "" and int(inf["prio"]) > prio:
			continue
		var d := lp.distance_to(inf["pos"])
		if d < dist:
			continue
		var score := d - float(inf["prio"]) * 50.0
		if score > best_score:
			best_score = score
			best = q
	if best:
		best.stop()
	return best


func _release(p: Node) -> void:
	if p.has_meta("key"):
		var k := String(p.get_meta("key"))
		_count[k] = maxi(0, int(_count.get(k, 0)) - 1)
		p.remove_meta("key")
	_info3.erase(p)


func _on_done(p: Node) -> void:
	_release(p)


# ================================================================ BGM
## BGM を切り替える（同じ曲なら何もしない）。key = "" で止める
static func music(key: String, fade := 2.5, vol_db := 0.0) -> void:
	var h := hub()
	if h == null or not enabled:
		return
	h._music_to(key, fade, vol_db)


static func music_stop(fade := 2.0) -> void:
	music("", fade)


func _music_to(key: String, fade: float, vol_db: float) -> void:
	if key == music_key:
		return
	music_key = key
	var old: AudioStreamPlayer = _music[_music_cur]
	if old.playing:
		var tw := create_tween()
		tw.tween_property(old, "volume_db", -60.0, fade)
		tw.tween_callback(old.stop)
	if key == "" or not SoundBank.has(key):
		return
	_music_cur = 1 - _music_cur
	var nw: AudioStreamPlayer = _music[_music_cur]
	nw.stream = SoundBank.pick(key)
	nw.volume_db = -50.0
	nw.play()
	var tw2 := create_tween()
	tw2.tween_property(nw, "volume_db", vol_db + SoundBank.base_db(key), fade)
