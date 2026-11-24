extends Node
## 見た目の検証（第 2 弾）: 自分で建てた施設の全種類・軍艦の外観/甲板/船内（HUD つきで部屋の名前も）。
## xvfb-run -a -s "-screen 0 1920x1080x24" godot --path . --rendering-driver vulkan --resolution 1280x720 res://tests/shot_vis2.tscn -- <mode> <era> <tag>
##   mode = facilities | ships
## 出力: <scratch>/shots/vis2/<tag>_<mode>_<name>.png
const OUT := "/tmp/claude-0/-home-user-fight-315/d60522a2-6e99-536b-9a07-fc183994e33b/scratchpad/shots/vis2/"
const VISUALS := [["seishi", "mill"], ["kikai_kojo", "factory"], ["hansharo", "reverb"], ["koro", "blast"], ["ginko", "bank"],
	["hatsudensho", "power"], ["kagaku", "chemical"], ["suishagoya", "watermill"], ["kobo", "workshop"], ["zosensho", "shipyard"],
	["tataraba", "tatara"], ["tanko", "mine"], ["gakko", "school"]]

var sess: Session
var tag := "x"
var mode := "facilities"
var cam: Camera3D


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	_run.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _shot(name: String, frames := 20) -> void:
	await _frames(frames)
	get_viewport().get_texture().get_image().save_png(OUT + "%s_%s_%s.png" % [tag, mode, name])
	print("saved ", name)


func _cam(pos: Vector3, at: Vector3, fov := 55.0) -> void:
	if cam == null:
		cam = Camera3D.new()
		cam.near = 0.05
		cam.far = 3000.0
		sess.add_child(cam)
	cam.fov = fov
	cam.global_position = pos
	cam.look_at(at, Vector3.UP)
	cam.make_current()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	mode = args[0] if args.size() > 0 else "facilities"
	var era_id: String = args[1] if args.size() > 1 else "meiji_taisho"
	tag = args[2] if args.size() > 2 else "x"
	sess = Session.start_free_roam(era_id)
	get_tree().root.add_child(sess)
	await _frames(3)
	Game.lock_mouse(false)
	sess.player.god_mode = true
	await _frames(20)
	if mode == "facilities":
		await _facilities()
	else:
		await _ships()
	get_tree().quit()


func _facilities() -> void:
	var w: EraWorld = sess.world
	sess.hud.visible = false
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var base: Vector3 = w.landmark_pos("village")
	var i := 0
	for pair in VISUALS:
		var p := w.random_ground_point_near(base + Vector3(-60 + (i % 5) * 30, 0, -40 + int(i / 5.0) * 40), 12.0, rng)
		p.y = w.height_at(p.x, p.z)
		var rec := {"id": "shot_%d" % i, "type": pair[0], "era": w.era.get("id", ""), "at": "village", "pos": [p.x, p.y, p.z],
			"yaw": 0.4, "workers": 20, "skill": 60.0, "scale": 1, "power": "steam", "stock": {"sekitan": 50}}
		var f := Facility.spawn_rec(sess, rec)
		await _frames(2)
		var far := 30.0 if pair[1] in ["mill", "shipyard", "factory"] else 22.0
		_cam(p + Basis(Vector3.UP, 0.4) * Vector3(far * 0.75, far * 0.42, far * 0.75), p + Vector3(0, 3.5, 0), 50.0)
		sess.player.teleport(p + Vector3(far * 0.5, 0, far * 0.2))
		await _shot(String(pair[1]), 25)
		f.queue_free()
		i += 1


func _ships() -> void:
	var yard := ShipYard.current
	if yard == null:
		return
	var p: Player = sess.player
	for s in yard.ships:
		var sh := s as Ship
		var sd := sh.sd
		if not sd.steel:
			continue
		var xf := sh.xf_cur
		var d := maxf(sd.L * 0.6, 30.0)
		p.teleport(xf * Vector3(sd.B * 0.5 + 40.0, 0, 0) + Vector3(0, 0.5, 0))
		sess.hud.visible = false
		_cam(xf * Vector3(sd.B * 0.5 + d * 0.8, maxf(sd.top_m + d * 0.18, 6.0), -sd.L * 0.3), xf * Vector3(0, sd.top_m * 0.6 + 2.0, 0), 50.0)
		await _shot(sd.id + "_ext", 12)
		# 船内: いちばん大きい囲われた部屋（船体内）に立ち、HUD に部屋の名前を出す
		var best: Dictionary = {}
		var ba := 0.0
		for r in sd.rooms:
			var rd: Dictionary = r
			var a := (float(rd["z1"]) - float(rd["z0"])) * (float(rd["x1"]) - float(rd["x0"]))
			if bool(rd["enclosed"]) and a > ba and String(rd["region"]) == "hull":
				ba = a
				best = rd
		if best.is_empty():
			continue
		var c := Vector3((float(best["x0"]) + float(best["x1"])) * 0.5, float(best["y"]) + 0.15, (float(best["z0"]) + float(best["z1"])) * 0.5)
		p.teleport(xf * c)
		for k in 240:
			await get_tree().process_frame
			if sh.int_ready:
				break
		sess.hud.visible = true
		var corner := Vector3(float(best["x1"]) - 0.4, float(best["y"]) + 1.6, float(best["z1"]) - 0.4)
		_cam(xf * corner, xf * Vector3(c.x - 0.5, c.y + 0.9, float(best["z0"])), 70.0)
		await _shot(sd.id + "_int", 20)
