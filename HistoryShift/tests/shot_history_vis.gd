extends Node
## 歴史の見た目の比較写真（同じ場所を別の歴史で）＋ 2026 年のハブ。
## xvfb-run -a godot --rendering-driver vulkan --path . --resolution 1280x720 res://tests/shot_history_vis.tscn [-- meiji showa edo hub]
## 出力: <scratch>/shots/history_vis/<era>_<year>_<history>_<view>.png、hub_<history>_<view>.png

const OUT_DIR := "/tmp/claude-0/-home-user-fight-315/d60522a2-6e99-536b-9a07-fc183994e33b/scratchpad/shots/history_vis"

var db: HistoryDB
var only: Array = []


func _ready() -> void:
	only = Array(OS.get_cmdline_user_args())
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	db = HistoryDB.load_all()
	_run.call_deferred()


func _want(k: String) -> bool:
	return only.is_empty() or k in only


func _run() -> void:
	var M := func(era: String, y: int, lead: Dictionary, tier := "敗戦", cap := "", sd := 0.0) -> Dictionary:
		return HistoryVisuals.make(era, y, lead, tier, cap, sd)
	if _want("meiji_lag"):
		await _era("meiji_taisho", 1877, {"lagging": M.call("meiji_taisho", 1877, {"industry": -20, "west": -45})}, {"capital": [Vector3(60, 34, 72), Vector3(0, 6, -10)]})
	if _want("meiji"):
		var cases := {
			"real": M.call("meiji_taisho", 1877, {}),
			"industrial": M.call("meiji_taisho", 1877, {"industry": 35, "west": 40}, "敗戦", "大坂", 12.0),
			"lagging": M.call("meiji_taisho", 1877, {"industry": -20, "west": -45}),
		}
		await _era("meiji_taisho", 1877, cases, {"capital": [Vector3(60, 34, 72), Vector3(0, 6, -10)], "village": [Vector3(-95, 60, 95), Vector3(0, 4, 0)],
			"port": [Vector3(-50, 34, -60), Vector3(0, 2, 70)], "temple": [Vector3(40, 26, 55), Vector3(0, 4, 0)]})
	if _want("showa"):
		var cases2 := {"defeat": M.call("showa", 1945, {}, "敗戦"), "no_war": M.call("showa", 1945, {}, "開戦回避"), "homeland": M.call("showa", 1945, {}, "本土決戦")}
		await _era("showa", 1945, cases2, {"village": [Vector3(45, 26, 60), Vector3(0, 3, 0)]})
	if _want("edo"):
		var cases3 := {"real": M.call("edo", 1853, {}), "industrial": M.call("edo", 1853, {"industry": 45, "west": 45}, "敗戦", "", 12.0)}
		await _era("edo", 1853, cases3, {"capital": [Vector3(62, 40, 70), Vector3(0, 8, -30)], "port": [Vector3(-40, 30, -70), Vector3(0, 0, 90)],
			"village": [Vector3(-80, 50, 80), Vector3(0, 4, 0)]})
	if _want("hub"):
		await _hubs()
	if _want("hub_lab"):
		await _hubs(true)
	get_tree().quit(0)


func _era(era_id: String, year: int, cases: Dictionary, views: Dictionary) -> void:
	var era := db.get_era(era_id)
	for hk in cases:
		var vis: Dictionary = cases[hk]
		HistoryVisuals.current = vis
		EraTimeline.set_current(era_id, year)
		var w := EraWorld.build(era, year, {"vis": vis})
		get_tree().root.add_child(w)
		w.set_time_of_day(10.5)
		var cam := Camera3D.new()
		cam.fov = 60.0
		cam.far = 4000.0
		get_tree().root.add_child(cam)
		cam.current = true
		# 町人（装いの比率が歴史で変わる）
		var crowd := Node3D.new()
		get_tree().root.add_child(crowd)
		var pts: Array = w.street_points()
		for i in mini(24, pts.size()):
			var o := Humanoid.outfit_for(era_id, "civilian")
			var h := Humanoid.build(o, i * 7 + 3, false)
			crowd.add_child(h)
			h.global_position = pts[(i * 37) % pts.size()]
			h.rotation.y = float(i) * 1.7
		for i in 4:
			await get_tree().process_frame
		print("[shot] %s %d %s: %s" % [era_id, year, hk, w.get_meta("hv_stats", {})])
		for vn in views:
			if not w.landmarks.has(vn):
				continue
			var lm: Dictionary = w.landmarks[vn]
			var b := Basis(Vector3.UP, float(lm["angle"]))
			var c: Vector3 = lm["pos"]
			cam.look_at_from_position(c + b * (views[vn][0] as Vector3), c + b * (views[vn][1] as Vector3))
			for i in 24:
				await get_tree().process_frame
			var img := get_viewport().get_texture().get_image()
			var path := OUT_DIR.path_join("%s_%d_%s_%s.png" % [era_id, year, hk, vn])
			img.save_png(path)
			print("saved ", path)
		crowd.queue_free()
		cam.queue_free()
		w.queue_free()
		for i in 4:
			await get_tree().process_frame
	HistoryVisuals.current = {}
	EraTimeline.set_current("", 0)


func _hubs(lab_only := false) -> void:
	var cases := {
		"real": HistoryVisuals.make("present", 2026, {}, "敗戦"),
		"no_war": HistoryVisuals.make("present", 2026, {"prosperity": 30}, "開戦回避"),
		"homeland_osaka": HistoryVisuals.make("present", 2026, {}, "本土決戦", "大坂"),
		"closed_old": HistoryVisuals.make("present", 2026, {"industry": -50, "west": -50}, "開戦回避", "京都"),
	}
	for hk in cases:
		if lab_only and hk != "real":
			continue
		var pr := HistoryVisuals.present_from(cases[hk])
		var hs := HubSession.create(pr)
		get_tree().root.add_child(hs)
		var cam := Camera3D.new()
		cam.fov = 62.0
		cam.far = 3000.0
		get_tree().root.add_child(cam)
		cam.current = true
		var views := {
			"street": [Vector3(-22, 7, 12), Vector3(8, 6, 44)],
			"front": [Vector3(14, 5, 26), Vector3(0, 2.5, 4)],
			"lab": [Vector3(-9, 2.6, 6.5), Vector3(1.5, 2.2, -5.0)],
		}
		for vn in views:
			if (vn == "lab" and hk != "real") or (vn == "front" and hk != "real") or (lab_only and vn != "lab"):
				continue
			cam.look_at_from_position(views[vn][0], views[vn][1])
			for i in 24:
				cam.current = true
				await get_tree().process_frame
			var img := get_viewport().get_texture().get_image()
			var path := OUT_DIR.path_join("hub_%s_%s.png" % [hk, vn])
			img.save_png(path)
			print("saved ", path, "  ", pr.get("style"), " ", pr.get("lang"))
		cam.queue_free()
		hs.end()
		for i in 4:
			await get_tree().process_frame
