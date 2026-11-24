extends Node
## 天気の写真（同じ時代・場所を天気ごとに）。
## xvfb-run -a godot --path . --rendering-driver vulkan --resolution 1280x720 res://tests/shot_weather.tscn -- edo:1860 showa:1936:rain kamakura_muromachi:1281
##  引数 = 時代:年[:天気[:時刻]]。天気を書かなければ、その日の史実・気候値の天気（HistWeather.lookup）。
##  天気: clear rain heavy_rain thunder typhoon snow fog（強さは代表値）
## 出力: <scratch>/shots/weather/weather_<era>_<year>_<kind>.png

const OUT_DIR := "/tmp/claude-0/-home-user-fight-315/d60522a2-6e99-536b-9a07-fc183994e33b/scratchpad/shots/weather"
const PRESET := {
	"clear": {"kind": "clear", "rain": 0.0, "snow": 0.0, "fog": 0.0, "cloud": 0.2, "storm": 0.0, "wind": 2.0, "wet": 0.0, "snow_cover": 0.0, "thunder": 0.0},
	"rain": {"kind": "rain", "rain": 0.6, "snow": 0.0, "fog": 0.1, "cloud": 1.0, "storm": 0.2, "wind": 5.0, "wet": 0.9, "snow_cover": 0.0, "thunder": 0.0},
	"heavy_rain": {"kind": "heavy_rain", "rain": 1.0, "snow": 0.0, "fog": 0.15, "cloud": 1.0, "storm": 0.5, "wind": 9.0, "wet": 1.0, "snow_cover": 0.0, "thunder": 0.0},
	"thunder": {"kind": "thunder", "rain": 0.9, "snow": 0.0, "fog": 0.1, "cloud": 1.0, "storm": 0.85, "wind": 11.0, "wet": 1.0, "snow_cover": 0.0, "thunder": 1.0},
	"typhoon": {"kind": "typhoon", "rain": 0.95, "snow": 0.0, "fog": 0.2, "cloud": 1.0, "storm": 1.0, "wind": 26.0, "wet": 1.0, "snow_cover": 0.0, "thunder": 0.0},
	"snow": {"kind": "snow", "rain": 0.0, "snow": 0.8, "fog": 0.15, "cloud": 1.0, "storm": 0.0, "wind": 3.0, "wet": 0.0, "snow_cover": 0.85, "thunder": 0.0},
	"fog": {"kind": "fog", "rain": 0.0, "snow": 0.0, "fog": 0.95, "cloud": 0.8, "storm": 0.0, "wind": 1.0, "wet": 0.5, "snow_cover": 0.0, "thunder": 0.0},
}

var specs: Array = ["edo:1860", "edo:1700:heavy_rain", "sengoku:1600", "kamakura_muromachi:1281"]


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		specs = Array(args)
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	if OS.get_environment("WX_HF") == "1":
		WeatherDirector.roof_collision = true   # 屋根で粒を止める高さの場を試す（GPU 版の Vulkan で）
	_run.call_deferred()


func _run() -> void:
	for sp in specs:
		var parts := str(sp).split(":")
		var era_id := parts[0]
		var year := int(parts[1]) if parts.size() > 1 else 0
		var kind := parts[2] if parts.size() > 2 else ""
		var tod := float(parts[3]) if parts.size() > 3 else 10.5
		var w := EraWorld.build(Game.db.get_era(era_id), year, {})
		get_tree().root.add_child(w)
		Game.set_world(w)
		w.set_time_of_day(tod)
		var cam := Camera3D.new()
		cam.fov = 58.0
		cam.far = 4000.0
		get_tree().root.add_child(cam)
		cam.current = true
		# 町なかの目線（低い視点で通りと建物と空）
		var lm: Dictionary = w.landmarks
		var b := Basis(Vector3.UP, float(lm["capital"]["angle"]))
		var cap: Vector3 = lm["capital"]["pos"]
		var look := cap + b * Vector3(-6, 0, -10)
		look.y = w.height_at(look.x, look.z) + 9.0
		await get_tree().physics_frame
		await get_tree().physics_frame
		# 建物の中や壁の目の前にならない視点を選ぶ（目から注視点までの見通しがある所）
		var eye := Vector3.ZERO
		for off in [Vector3(46, 0, 58), Vector3(-50, 0, 55), Vector3(58, 0, -20), Vector3(30, 0, 80), Vector3(-60, 0, -30)]:
			eye = cap + b * off
			eye.y = maxf(w.height_at(eye.x, eye.z), cap.y) + 5.5
			var q := PhysicsRayQueryParameters3D.create(eye, eye + (look - eye).normalized() * 30.0, 1)
			if get_viewport().world_3d.direct_space_state.intersect_ray(q).is_empty():
				break
		cam.look_at_from_position(eye, look)
		var d := WeatherDirector.attach(w, w, era_id, year, null)
		if kind != "":
			d.set_weather(PRESET.get(kind, PRESET["clear"]))
		var label := kind if kind != "" else str(d.kind)
		for i in 30:
			await get_tree().process_frame
		if label in ["thunder", "typhoon"]:
			d.strike(700.0, cam)
		for i in 110:
			await get_tree().process_frame
			if label in ["thunder", "typhoon"] and i == 104:
				d.strike(650.0, cam)
		var img := get_viewport().get_texture().get_image()
		var path := OUT_DIR.path_join("weather_%s_%d_%s.png" % [era_id, year, label])
		img.save_png(path)
		print("saved ", path, "  (", HistWeather.label_ja(d.day), " ", d.day.get("date", {}).get("text", ""), ")")
		cam.queue_free()
		Game.set_world(null)
		w.queue_free()
		for i in 4:
			await get_tree().process_frame
	get_tree().quit(0)
