extends Node
## ヘッドレス: godot --headless --path . res://tests/test_audio.tscn [-- --no-world]
## 音の検査:
##  1. コードが使う音の key（Audio.play*/loop_at/music・Sfx・UISfx・足音の床材×歩き/走り・着地・蹄・環境音の層・BGM）が
##     すべて SoundManifest にあり、AudioStream として読み込めること。素材ファイルが全部読み込めること。
##  2. 足音の床材の判定（Surface）: 生成した江戸の箱庭の道（土）・草地・屋内の畳・土間、明治の石畳、
##     船の甲板（三笠＝チーク張りの上甲板と鋼の船内、安宅船＝板）、2026 年の研究所の床。
##  3. ヘッドレス（音声デバイスなし）で Audio / AmbienceDirector / Footsteps がエラーなく動くこと。

var fails := 0
var checks := 0
const KEY_PREFIXES := ["step_", "land_", "hoof_", "gun_", "reload_", "bow_", "arrow_", "swing_", "sword_", "hit_", "hurt_", "body_",
	"impact_", "ricochet", "bullet_", "explosion_", "cannon_", "shell_", "fuse_", "rocket_", "break_", "collapse_", "debris",
	"tree_", "fire_", "creak_", "car_", "tire_", "plane_", "boat_", "ship_", "oar_", "hull_", "splash_", "swim_", "pickup_",
	"cloth", "book_", "paper_", "door_", "latch", "chop", "pot_", "bell_", "valve_", "lever", "craft_", "rin", "hyoshigi", "hansho",
	"ui_", "stinger_", "time_", "amb_", "bird_", "temple_", "wind_", "dog_", "train_", "lab_", "music_", "horse_", "thunder_"]


func _ready() -> void:
	_run.call_deferred()


func _check(cond: bool, msg: String) -> void:
	checks += 1
	if not cond:
		print("FAIL " + msg)
		fails += 1
	elif OS.get_cmdline_user_args().has("-v"):
		print("OK   " + msg)


func _run() -> void:
	var keep_h := HistoryState.save_path
	var keep_p := PlayerProfile.save_path
	HistoryState.save_path = "user://test_audio_history.json"
	PlayerProfile.save_path = "user://test_audio_profile.json"
	_check(not Audio.enabled, "headless: Audio is disabled (no device) and nothing plays")
	_buses()
	_manifest()
	_code_keys()
	if not ("--no-world" in OS.get_cmdline_user_args()):
		await _surfaces_world()
		await _surfaces_ships()
		await _surface_hub()
		await _smoke()
	await _fallback()
	HistoryState.delete_save()
	HistoryState.save_path = keep_h
	PlayerProfile.save_path = keep_p
	print("audio: %s (%d checks, %d failures)" % ["ok" if fails == 0 else "FAILED", checks, fails])
	get_tree().quit(1 if fails > 0 else 0)


# ------------------------------------------------------------------ 1. バス・素材
func _buses() -> void:
	Audio.ensure_buses()
	for b in ["Master", "Music", "SFX", "Ambience", "Voice"]:
		_check(AudioServer.get_bus_index(b) >= 0, "bus %s exists" % b)
	GameSettings.apply(false)
	_check(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Music")) < 0.0, "music volume setting applied to the Music bus")


func _manifest() -> void:
	var n_files := 0
	for key in SoundBank.keys():
		var inf := SoundBank.info(String(key))
		var arr := SoundBank.streams(String(key))
		_check(arr.size() == (inf["files"] as Array).size() and arr.size() > 0, "all %d files of '%s' load" % [(inf["files"] as Array).size(), key])
		n_files += arr.size()
		if bool(inf.get("loop", false)) and not arr.is_empty():
			var s = arr[0]
			_check((s is AudioStreamOggVorbis and (s as AudioStreamOggVorbis).loop) or (s is AudioStreamWAV), "'%s' loops" % key)
		_check(String(inf.get("bus", "")) in ["SFX", "Music", "Ambience", "Voice"], "'%s' has a valid bus" % key)
	_check(n_files >= 400, "sound files loaded: %d" % n_files)


## コードに書かれた key・組み立てる key がすべて素材を持つ
func _code_keys() -> void:
	var used := {}
	var re := RegEx.new()
	re.compile("\"([a-z][a-z0-9]*(?:_[a-z0-9]+)*)\"")
	for f in _collect("res://scripts"):
		if f.ends_with("sound_manifest.gd"):
			continue
		var txt := FileAccess.get_file_as_string(f)
		for m in re.search_all(txt):
			var k := m.get_string(1)
			for p in KEY_PREFIXES:
				if k.begins_with(p) and (k.length() > String(p).length() or p in ["cloth", "rin", "chop", "latch", "lever", "debris", "ricochet", "hyoshigi", "hansho"]):
					# ふつうの識別子（ui_kit の名前や関数名など）と区別するため、音の文脈の行だけ数える
					var line := _line_of(txt, m.get_start())
					if f.begins_with("res://scripts/audio/") or _audio_context(line):
						used[k] = f
					break
	# 組み立てる key
	for s in Surface.ALL:
		used["step_" + s] = "Surface.ALL"
		used["step_" + s + "_run"] = "Surface.ALL"
	for s in Surface.WEATHER:
		used["step_" + s] = "Surface.WEATHER"
		used["step_" + s + "_run"] = "Surface.WEATHER"
	for k in ["land_soft", "land_hard", "land_wood", "land_metal", "land_water", "land_tatami", "hoof_dirt", "hoof_stone", "hoof_wood", "hoof_grass"]:
		used[k] = "Footsteps"
	for k in AmbienceDirector.LAYERS:
		used[k] = "AmbienceDirector.LAYERS"
	for e in AmbienceDirector.ERA:
		used[AmbienceDirector.era_music(String(e))] = "AmbienceDirector.ERA"
	for k in UISfx.KEYS.values():
		used[String(k)] = "UISfx.KEYS"
	for k in [Sfx.shot(), Sfx.musket(), Sfx.bow(), Sfx.energy(), Sfx.hit(), Sfx.explode(), Sfx.pickup(), Sfx.success(), Sfx.fail(),
			Sfx.warp(), Sfx.engine(), Sfx.propeller(), Sfx.hooves(), Sfx.wind(), Sfx.click(), Sfx.crumble(), Sfx.wood_break(),
			Sfx.tiles(), Sfx.fire_loop(), Sfx.cannon(), Sfx.fuse(), Sfx.splash(), Sfx.whoosh(), Sfx.rocket()]:
		used[String(k)] = "Sfx"
	for id in ["hinawaju", "murataju", "arisaka38", "pistol14", "lmg96", "jikuju"]:
		used[PlayerArms.gun_key(id)] = "PlayerArms.gun_key"
	for m in ["wood", "plaster", "stone", "brick", "metal"]:
		used[Destruction.break_key(m)] = "Destruction.break_key"
	for s in Surface.ALL:
		used[Impacts.of_surface(s)] = "Impacts.of_surface"
	var missing: Array = []
	for k in used:
		if not SoundBank.has(String(k)) or SoundBank.pick(String(k)) == null:
			missing.append("%s (%s)" % [k, used[k]])
	_check(missing.is_empty(), "every sound key used in code resolves to a stream (%d keys) missing: %s" % [used.size(), missing])
	print("sound keys used by code: %d / manifest %d" % [used.size(), SoundBank.keys().size()])


func _line_of(txt: String, at: int) -> String:
	var a := txt.rfind("\n", at) + 1
	var b := txt.find("\n", at)
	return txt.substr(a, (b if b >= 0 else txt.length()) - a)


func _audio_context(line: String) -> bool:
	var l := line.strip_edges()
	for w in ["Audio.", "SoundBank.", "Sfx."]:
		if l.contains(w):
			return true
	# 音の key を返す関数（gun_key / reload_key / break_key …）の return "key"
	return l.begins_with("return \"") and l.count("\"") == 2


func _collect(dir: String) -> Array:
	var out: Array = []
	for d in DirAccess.get_directories_at(dir):
		out.append_array(_collect(dir.path_join(d)))
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".gd"):
			out.append(dir.path_join(f))
	return out


# ------------------------------------------------------------------ 2. 床材
func _surf(pos: Vector3, ex: Array = []) -> String:
	var space := get_viewport().world_3d.direct_space_state
	return Surface.at(pos, space, ex)


func _surfaces_world() -> void:
	var db := Game.db
	var w: EraWorld = EraWorld.build(db.get_era("edo"), 0, {})
	add_child(w)
	Game.set_world(w)
	for i in 3:
		await get_tree().physics_frame
	var t := w.terrain
	# 道（江戸の道は土）
	var road := Vector3.INF
	var grass := Vector3.INF
	for line in t.road_lines:
		var pts: PackedVector2Array = line["pts"]
		for k in range(2, pts.size() - 2):
			var p := pts[k]
			if t.mask_at(t.road, p.x, p.y) > 0.8 and not t.is_occupied(p.x, p.y) and not t.is_water(p.x, p.y) and w.interior_at(Vector3(p.x, t.height_at(p.x, p.y), p.y)) < 0:
				road = Vector3(p.x, t.height_at(p.x, p.y), p.y)
				break
		if road != Vector3.INF:
			break
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for k in 4000:
		var x := rng.randf_range(-t.half + 10.0, t.half - 10.0)
		var z := rng.randf_range(-t.half + 10.0, t.half - 10.0)
		if t.mask_at(t.road, x, z) > 0.05 or t.mask_at(t.plaza, x, z) > 0.05 or t.mask_at(t.field, x, z) > 0.2 or t.is_occupied(x, z) or t.is_water(x, z):
			continue
		var h := t.height_at(x, z)
		if h < w.water_level + 4.0 or t.normal_at(x, z).y < 0.85:
			continue
		# 木の幹・建物に当たらない所
		var q := PhysicsRayQueryParameters3D.create(Vector3(x, h + 3.0, z), Vector3(x, h - 1.0, z), Game.COLLISION_WORLD)
		var hit := get_viewport().world_3d.direct_space_state.intersect_ray(q)
		if hit.is_empty() or (hit["collider"] as Node).name != "TerrainBody":
			continue
		grass = Vector3(x, h, z)
		break
	_check(road != Vector3.INF, "found a road point")
	if road != Vector3.INF:
		_check(_surf(road + Vector3.UP * 0.02) == "dirt", "edo road → dirt (got %s at %s)" % [_surf(road + Vector3.UP * 0.02), road])
	_check(grass != Vector3.INF, "found an open grass point")
	if grass != Vector3.INF:
		_check(_surf(grass + Vector3.UP * 0.02) == "grass", "edo open ground → grass (got %s)" % _surf(grass + Vector3.UP * 0.02))
	# 海
	var sea := Vector3.INF
	for k in 4000:
		var x := rng.randf_range(-t.half + 5.0, t.half - 5.0)
		var z := rng.randf_range(-t.half + 5.0, t.half - 5.0)
		var h := t.height_at(x, z)
		if h < w.water_level - 0.3 and h > w.water_level - 1.2:
			sea = Vector3(x, h, z)
			break
	if sea != Vector3.INF:
		_check(_surf(sea) == "water", "shallow sea → water (got %s)" % _surf(sea))
	# 屋内：畳と土間
	var tat_ok := false
	var doma_ok := false
	for id in w.interiors.ids:
		var ty := String(w.interiors.defs[id]["type"])
		if not (ty in ["machiya", "nagaya", "shoin", "minka", "farmhouse", "chaya", "goten"]):
			continue
		w.ensure_interior(id, true)
		w.interiors.spots(id)
		var xf: Transform3D = w.interiors.defs[id]["xf"]
		await get_tree().physics_frame
		await get_tree().physics_frame
		for f in w.interiors._surfs.get(id, []):
			var r: Rect2 = f["r"]
			var c := r.get_center()
			var wp := xf * Vector3(c.x, float(f["y"]) + 0.02, c.y)
			var want := WorldInteriors.finish_surface(String(f["s"]))
			if want == "tatami" and not tat_ok:
				var got := _surf(wp)
				_check(got == "tatami", "%s #%d tatami room → tatami (got %s)" % [ty, id, got])
				tat_ok = got == "tatami"
			elif want == "dirt" and not doma_ok:
				var got2 := _surf(wp)
				_check(got2 == "dirt", "%s #%d doma (earthen floor) → dirt (got %s)" % [ty, id, got2])
				doma_ok = got2 == "dirt"
		w.release_interior(id)
		if tat_ok and doma_ok:
			break
	_check(tat_ok, "a tatami interior floor was found and detected")
	_check(doma_ok, "an earthen doma floor was found and detected")
	# 土台（石）と破壊ユニット（木造の縁・床）
	var base_found := false
	for c in w.static_body.get_children():
		if c is CollisionShape3D and (c as Node).get_meta("surface", "") == "stone":
			var cs := c as CollisionShape3D
			var top := cs.global_transform * Vector3(0, (cs.shape as BoxShape3D).size.y * 0.5, 0)
			if w.interior_at(top) >= 0:
				continue
			var got := _surf(top + Vector3.UP * 0.02)
			if got == "stone":
				base_found = true
				break
	_check(base_found, "stone foundation / steps tagged and detected as stone")
	w.queue_free()
	Game.set_world(null)
	await get_tree().process_frame
	# 明治の石畳
	var w2: EraWorld = EraWorld.build(db.get_era("meiji_taisho"), 0, {})
	add_child(w2)
	Game.set_world(w2)
	for i in 3:
		await get_tree().physics_frame
	var t2 := w2.terrain
	var ok2 := false
	for line in t2.road_lines:
		var pts: PackedVector2Array = line["pts"]
		for k in range(2, pts.size() - 2, 3):
			var p := pts[k]
			if t2.mask_at(t2.road, p.x, p.y) > 0.8 and not t2.is_occupied(p.x, p.y) and not t2.is_water(p.x, p.y):
				var got := _surf(Vector3(p.x, t2.height_at(p.x, p.y) + 0.02, p.y))
				_check(got == "stone", "meiji cobbled street → stone (got %s)" % got)
				ok2 = true
				break
		if ok2:
			break
	_check(ok2, "found a meiji street point")
	# 環境音の監督がヘッドレスで動く
	var amb := AmbienceDirector.attach(self, "meiji_taisho")
	for i in 3:
		await get_tree().create_timer(0.3).timeout
	_check(not amb.ctx.is_empty() and float(amb.ctx.get("sea", -1.0)) >= 0.0, "ambience director computes its context headless (%s)" % [amb.ctx])
	amb.queue_free()
	w2.queue_free()
	Game.set_world(null)
	await get_tree().process_frame


func _surfaces_ships() -> void:
	for spec in [["mikasa", "wood", "metal"], ["atakebune", "wood", "wood"]]:
		var sd := ShipData.load_ship(String(spec[0]))
		if sd == null:
			_check(false, "ship data %s" % spec[0])
			continue
		var s := Ship.create(sd, Transform3D(Basis(), Vector3(2000, 0, 2000)), "test", 3)
		add_child(s)
		for i in 3:
			await get_tree().physics_frame
		var top := sd.top_at(0.0)
		var deck := s.xf_cur * Vector3(0.0, top + 0.05, 0.0)
		# 上甲板：レイで船体（ShipBody）に当てて判定
		var q := PhysicsRayQueryParameters3D.create(deck + Vector3.UP * 0.5, deck + Vector3.DOWN * 1.2, Game.COLLISION_WORLD | Game.COLLISION_VEHICLE)
		var hit := get_viewport().world_3d.direct_space_state.intersect_ray(q)
		_check(not hit.is_empty() and hit["collider"] is ShipBody, "%s: a ray hits the deck's ShipBody" % spec[0])
		var got := _surf(deck)
		_check(got == String(spec[1]), "%s weather deck → %s (got %s)" % [spec[0], spec[1], got])
		var inside := s.surface_at(s.xf_cur * Vector3(0.0, top - 2.6, 0.0))
		_check(inside == String(spec[2]), "%s lower deck → %s (got %s)" % [spec[0], spec[2], inside])
		s.queue_free()
		await get_tree().process_frame


func _surface_hub() -> void:
	var w := PresentWorld.build(HistoryVisuals.present(null))
	add_child(w)
	Game.set_world(w)
	for i in 3:
		await get_tree().physics_frame
	var lab := _surf(w.console_pos + Vector3(2.0, 0.12, 2.0))
	_check(lab == "concrete", "2026 lab floor → concrete (got %s)" % lab)
	# 足音ノードがヘッドレスでエラーなく付く（音は鳴らさない）
	var pl := Player.new()
	add_child(pl)
	pl.global_position = w.player_spawn
	await get_tree().physics_frame
	_check(pl.get_node_or_null("Footsteps") != null, "player has a Footsteps node")
	pl.queue_free()
	w.queue_free()
	Game.set_world(null)
	await get_tree().process_frame


# ------------------------------------------------------------------ 3. 音を鳴らす経路をヘッドレスで通す（ダミーの音声ドライバ）
## Audio.enabled を一時的に true にして、自由探索の箱庭で歩く・走る・跳ぶ・撃つ・爆発・乗り物・環境音・BGM の
## 再生の経路をすべて通す。スクリプトのエラーが出ないこと、同時発音の上限が守られることを確かめる。
func _smoke() -> void:
	Audio.enabled = true
	var hubn := Audio.hub()
	_check(hubn != null, "AudioHub exists")
	var s := Session.start_free_roam("edo")
	add_child(s)
	for i in 5:
		await get_tree().physics_frame
	var pl: Player = s.player
	_check(pl != null and pl.get_node_or_null("Footsteps") != null, "free-roam player has footsteps")
	# 歩く・走る
	var p0 := pl.global_position
	for k in 120:
		var dir := Vector3(cos(k * 0.03), 0, sin(k * 0.03))
		var np: Vector3 = pl.global_position + dir * (0.09 if k < 60 else 0.16)
		np.y = Game.world.height_at(np.x, np.z)
		pl.global_position = np
		await get_tree().physics_frame
	_check(int(Footsteps.stats["steps"]) >= 6 and int(Footsteps.stats["runs"]) >= 1, "player footsteps played while walking and running (%s)" % [Footsteps.stats])
	# 跳んで着地
	pl.velocity = Vector3(0, -9.0, 0)
	pl.global_position += Vector3.UP * 3.0
	for k in 40:
		await get_tree().physics_frame
	_check(int(Footsteps.stats["lands"]) >= 1, "landing sound after a fall")
	# すべての一発音（同時発音の上限）
	for key in SoundBank.keys():
		if not SoundBank.is_loop(String(key)):
			Audio.play_at(String(key), pl.global_position + Vector3(2, 1, 0), -20.0)
	for k in 30:
		Audio.play_at("break_wood", pl.global_position + Vector3(k * 0.5, 0, 0), -20.0)
	_check(int(hubn._count.get("break_wood", 0)) <= int(Audio.PER_KEY.get("break_wood", 4)), "voice limit per key holds (%d)" % int(hubn._count.get("break_wood", 0)))
	var playing := 0
	for q in hubn._pool3:
		if (q as AudioStreamPlayer3D).playing:
			playing += 1
	_check(playing <= Audio.POOL_3D, "3D voices within the pool (%d)" % playing)
	Audio.play_at("car_engine_loop", pl.global_position, 0.0)   # ループは一発では鳴らさない
	# 武器・爆発・破壊
	Effects.explosion(get_tree(), pl.global_position + Vector3(25, 0, 0), 8.0, 50.0, 1, 0.0)
	Effects.explosion(get_tree(), pl.global_position + Vector3(-25, 0, 0), 4.0, 20.0, 1, 0.0)
	for k in 10:
		await get_tree().physics_frame
	# 乗り物
	for v in get_tree().get_nodes_in_group("vehicle"):
		if v.get("driver") == null and v.has_method("enter") and String(v.get("kind")) in ["horse", "car"]:
			pl.enter_vehicle(v)
			for k in 60:
				if v is Horse:
					(v as Horse).speed = 8.0   # 騎乗して駆ける（入力なしで速さを与える）
				await get_tree().physics_frame
			if v is Horse:
				_check(int(Footsteps.stats["hooves"]) >= 2, "horse hooves while moving (%s)" % [Footsteps.stats])
			pl.exit_vehicle()
			break
	# 環境音・BGM
	for k in 8:
		await get_tree().create_timer(0.3).timeout
	var amb: AmbienceDirector = s.get_node_or_null("Ambience")
	_check(amb != null and not amb.ctx.is_empty(), "session has an ambience director with context")
	_check(Audio.hub().music_key == AmbienceDirector.era_music("edo"), "edo music playing (%s)" % Audio.hub().music_key)
	Audio.music("music_hub", 0.1)
	Audio.music_stop(0.1)
	s.end()
	await get_tree().process_frame
	await get_tree().process_frame
	Audio.enabled = false
	_check(Audio.hub() != null, "smoke run finished without losing the audio hub")


## ミッション検査で使う簡易ワールド（地形・名所なし）でも環境音と床材がエラーにならない
func _fallback() -> void:
	var w := FallbackWorld.build(Game.db.get_era("sengoku"))
	add_child(w)
	Game.set_world(w)
	var amb := AmbienceDirector.attach(self, "sengoku")
	for i in 3:
		await get_tree().create_timer(0.3).timeout
	_check(not amb.ctx.is_empty(), "ambience works on FallbackWorld")
	_check(Surface.at(Vector3(0, 0.05, 0), get_viewport().world_3d.direct_space_state) in Surface.ALL, "surface on FallbackWorld is a known material")
	amb.queue_free()
	w.queue_free()
	Game.set_world(null)
	await get_tree().process_frame
