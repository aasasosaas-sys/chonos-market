class_name Facility
extends CraftStation
## 主人公が過去に建てた施設（data/crafting/buildings.json）。rec は PlayerProfile.buildings の 1 件（保存される）。
## 生産：cycle 秒ごとに inputs（蔵 rec.stock に入れた原料・燃料）を使って outputs / money_out を蔵にためる。
## 効率 = 働き手の充足 × (0.5 + 0.7×職人の腕) × 動力（水力 0.7・蒸気 1.0）× 規模。蒸気は 1 回ごとに石炭 1。
## 離れていた間の分は、次に来たとき最大 30 回ぶんまとめて生産する（Time.get_unix_time_from_system）。
## 動かすたびに必要な知識の習熟が上がる（Knowledge.CAP_RUN まで）。

var rec: Dictionary = {}
var bdef: Dictionary = {}
var running := false
var _smoke: Array = []
var _wheel: Node3D = null
var _train: Node3D = null
var _line_a := Vector3.ZERO
var _line_b := Vector3.ZERO
var _train_t := 0.0
var _lamps: Array = []

const MAX_STOCK := 300
const OFFLINE_CYCLES := 30


static func spawn_rec(parent: Node, p_rec: Dictionary) -> Facility:
	var f := Facility.new()
	f.rec = p_rec
	f.bdef = Knowledge.building(str(p_rec.get("type", "")))
	f.kind = "factory"
	f.landmark = str(p_rec.get("at", ""))
	f.display_name = str(f.bdef.get("name", "施設"))
	var d := f.bdef.duplicate()
	d["stations"] = f.bdef.get("station", [])
	f.def = d
	parent.add_child(f)
	var pv: Array = p_rec.get("pos", [0, 0, 0])
	f.global_position = Vector3(float(pv[0]), float(pv[1]), float(pv[2]))
	f.rotation.y = float(p_rec.get("yaw", 0.0))
	f.catch_up()
	return f


func _ready() -> void:
	add_to_group("craft_station")
	add_to_group("facility")
	_build_visual(str(bdef.get("visual", "workshop")))
	var tag := Label3D.new()
	tag.text = display_name + ("（規模 %d）" % int(rec.get("scale", 1)) if int(rec.get("scale", 1)) > 1 else "") + "\n（あなたの施設）"
	tag.font = load("res://assets/fonts/NotoSansJP-Bold.ttf")
	tag.font_size = 44
	tag.pixel_size = 0.007
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.outline_size = 10
	tag.modulate = Color(0.6, 1.0, 0.7)
	tag.position = Vector3(0, 7.5, 0)
	add_child(tag)


func prompt() -> String:
	return "E：%s（あなたの施設：働き手・原料・受け取り・拡張）" % display_name


# ------------------------------------------------------------------ 生産
func needed_workers() -> int:
	return int(bdef.get("workers", 1))


func _has_inputs() -> bool:
	var st: Dictionary = rec.get("stock", {})
	for k in bdef.get("inputs", {}):
		if int(st.get(k, 0)) < int(bdef["inputs"][k]):
			return false
	if str(rec.get("power", "none")) == "steam" and int(st.get("sekitan", 0)) < 1:
		return false
	return true


func status_text() -> String:
	if int(rec.get("workers", 0)) <= 0:
		return "止まっている（働き手がいない）"
	if not _has_inputs():
		var need: PackedStringArray = []
		for k in bdef.get("inputs", {}):
			need.append("%s %d" % [CraftDB.item_name(k), int(bdef["inputs"][k])])
		if str(rec.get("power", "")) == "steam":
			need.append("石炭 1")
		return "止まっている（原料・燃料が足りない：1回に " + "、".join(need) + "）"
	return "稼働中　効率 %d%%" % roundi(Knowledge.efficiency(rec) * 100)


## 1 回生産する（成功したら true）
func produce_once() -> bool:
	if int(rec.get("workers", 0)) <= 0 or not _has_inputs():
		return false
	var st: Dictionary = rec.get("stock", {})
	for k in bdef.get("inputs", {}):
		st[k] = int(st.get(k, 0)) - int(bdef["inputs"][k])
	if str(rec.get("power", "none")) == "steam":
		st["sekitan"] = int(st.get("sekitan", 0)) - 1
	var outs: Dictionary = (bdef.get("outputs", {}) as Dictionary).duplicate()
	var bonus: Dictionary = bdef.get("bonus", {})
	var prof: PlayerProfile = Game.profile
	if bonus.has("outputs") and prof and Knowledge.mastery(prof, str(bonus.get("know", ""))) >= float(bonus.get("need", 30)):
		for k in bonus["outputs"]:
			outs[k] = int(outs.get(k, 0)) + int(bonus["outputs"][k])
	for k in outs:
		st["out_" + k] = mini(MAX_STOCK, int(st.get("out_" + k, 0)) + int(outs[k]))
	rec["money"] = mini(MAX_STOCK * 10000, int(rec.get("money", 0)) + int(bdef.get("money_out", 0)))
	rec["stock"] = st
	rec["made"] = int(rec.get("made", 0)) + 1
	if prof:
		for k in bdef.get("know", {}):
			Knowledge.train(prof, k, 0.25, Knowledge.CAP_RUN)
	run_milestone()
	return true


## 稼働が軌道に乗った（生産 Knowledge.RUN_MILESTONE 回）：歴史にもう一度知らせる。自由探索の外なら次の機会に
func run_milestone() -> Dictionary:
	if int(rec.get("made", 0)) < Knowledge.RUN_MILESTONE or rec.get("run_told", false):
		return {}
	if Game.chaos == null or not Game.chaos.is_active() or Game.profile == null:
		return {}
	rec["run_told"] = true
	var sc := int(rec.get("scale", 1))
	var hit: Dictionary = Game.chaos.act("industry", str(rec.get("type", "")), {"landmark": str(rec.get("at", "")), "scale": sc, "stage": "run",
		"mult": 0.5 * Knowledge.industry_scale(Game.profile, rec) / (1.0 + 0.5 * (sc - 1))})
	if is_inside_tree():
		var hud = get_tree().get_first_node_in_group("hud")
		if hud and hud.has_method("toast"):
			hud.toast("%sが軌道に乗った。まねをする者が現れ始めた" % display_name, 4.0)
	return hit


## できた品を問屋に卸す（時代の需要・売れ残りで値が変わる）。[[id, n, 稼ぎ]...]
func sell_outputs(prof: PlayerProfile, era_id: String) -> Array:
	var sold: Array = []
	var st: Dictionary = rec.get("stock", {})
	for k in st.keys():
		if str(k).begins_with("out_") and int(st[k]) > 0:
			var id := str(k).substr(4)
			var n := int(st[k])
			var mon := Knowledge.market_sell(prof, id, n, era_id)
			prof.add_money(mon)
			prof.practice("rhetoric", 0.05 * n)
			sold.append([id, n, mon])
			st[k] = 0
	rec["stock"] = st
	return sold


func catch_up() -> void:
	var now := Time.get_unix_time_from_system()
	var last := float(rec.get("last", now))
	var cyc := float(bdef.get("cycle", 30)) / maxf(0.05, Knowledge.efficiency(rec))
	var n := mini(OFFLINE_CYCLES, int((now - last) / maxf(1.0, cyc)))
	for i in n:
		if not produce_once():
			break
	rec["last"] = now


var _snd: AudioStreamPlayer3D


func _process(dt: float) -> void:
	var eff := Knowledge.efficiency(rec)
	running = eff > 0.0 and _has_inputs()
	# 稼働中の機械・槌・ベルトの音
	if Audio.enabled:
		if _snd == null:
			_snd = Audio.loop_at(self, "amb_factory", 0.0, {"unit": 8.0, "max_dist": 80.0, "bus": "SFX"})
			_snd.position = Vector3(0, 2.0, 0)
		if running and not _snd.playing:
			_snd.play(randf() * 10.0)
		elif not running and _snd.playing:
			_snd.stop()
	if running:
		rec["prog"] = float(rec.get("prog", 0.0)) + dt * eff / float(bdef.get("cycle", 30))
		if float(rec["prog"]) >= 1.0:
			rec["prog"] = float(rec["prog"]) - 1.0
			produce_once()
		rec["last"] = Time.get_unix_time_from_system()
	for s in _smoke:
		if is_instance_valid(s):
			(s as CPUParticles3D).emitting = running
	if _wheel and running:
		_wheel.rotation.x += dt * 1.2
	for l in _lamps:
		if is_instance_valid(l):
			(l as OmniLight3D).visible = running
	if _train and running:
		_train_t += dt * 0.06
		var k := 0.5 - 0.5 * cos(_train_t * TAU)
		var p := _line_a.lerp(_line_b, k)
		var w = Game.world
		if w and w.has_method("height_at"):
			p.y = w.height_at(p.x, p.z) + 0.3
		_train.global_position = p
		var dir := (_line_b - _line_a) * (1.0 if sin(_train_t * TAU) >= 0.0 else -1.0)
		if Vector2(dir.x, dir.z).length() > 0.1:
			_train.global_rotation.y = atan2(-dir.x, -dir.z)


## 蔵の中身を持ち物へ
func collect(prof: PlayerProfile) -> Array:
	var got: Array = []
	var st: Dictionary = rec.get("stock", {})
	for k in st.keys():
		if str(k).begins_with("out_") and int(st[k]) > 0:
			var id := str(k).substr(4)
			prof.add(id, int(st[k]), 0.4 + 0.5 * clampf(float(rec.get("skill", 10)) / 100.0, 0.0, 1.0))
			got.append([id, int(st[k])])
			st[k] = 0
	var m := int(rec.get("money", 0))
	if m > 0:
		prof.add_money(m)
		got.append(["money", m])
		rec["money"] = 0
	return got


## 持ち物の原料・燃料を入れる
func deposit(prof: PlayerProfile) -> Array:
	var put: Array = []
	var st: Dictionary = rec.get("stock", {})
	var ids: Array = (bdef.get("inputs", {}) as Dictionary).keys()
	if str(rec.get("power", "")) == "steam" and not ("sekitan" in ids):
		ids.append("sekitan")
	for id in ids:
		var n := prof.count(id) - int(prof.loan_stacks.get(id, 0))
		if n > 0:
			prof.take(id, n)
			st[id] = int(st.get(id, 0)) + n
			put.append([id, n])
	rec["stock"] = st
	return put


# ------------------------------------------------------------------ 見た目
# 建物は MeshKit（街の建物と同じ手描き風の建物シェーダ）で組む。腰石・付柱・窓枠とまぐさ・軒の出・棟・煙突の帯など、
# 安いが効く凹凸を付ける。時代考証: 製糸場＝富岡製糸場の木骨煉瓦造・瓦屋根・越屋根（1872）、機械工場＝鋸屋根の北側採光、
# 反射炉＝韮山反射炉の白い連双煙突と鉄の帯（1857）、高炉＝橋野・釜石の石積みの炉（1858）、銀行＝石造の列柱と破風。
var _k: MeshKit = null

const BRICK := Color(1.0, 0.66, 0.56)
const BRICK_DARK := Color(0.78, 0.48, 0.42)
const WOOD := Color(0.95, 0.9, 0.85)
const DARK := Color(0.42, 0.38, 0.36)
const ROOF := Color(0.42, 0.45, 0.5)
const STONE := Color(0.86, 0.84, 0.8)
const TRIM := Color(0.93, 0.91, 0.86)
const PLASTER := Color(0.95, 0.93, 0.88)
const IRON := Color(0.2, 0.2, 0.22)


func _mat(c: Color, rough := 0.85) -> StandardMaterial3D:
	return Humanoid.mat(c, rough)


func _kb(mat: String, c: Vector3, s: Vector3, col := Color.WHITE, yaw := 0.0) -> void:
	_k.box(mat, Transform3D(Basis(Vector3.UP, yaw), c), s, col)


func _kcyl(mat: String, base: Vector3, r0: float, r1: float, h: float, segs := 10, col := Color.WHITE) -> void:
	_k.cylinder(mat, Transform3D(Basis(), base), r0, r1, h, segs, col)


## 面（2 枚の三角形。n_hint 側が表）
func _kq(mat: String, a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color, n_hint: Vector3) -> void:
	var u := (b - a).normalized()
	var v := n_hint.normalized().cross(u)
	var ua := Vector2(a.dot(u), a.dot(v))
	_k.tri(mat, a, b, c, ua, Vector2(b.dot(u), b.dot(v)), Vector2(c.dot(u), c.dot(v)), col, n_hint)
	_k.tri(mat, a, c, d, ua, Vector2(c.dot(u), c.dot(v)), Vector2(d.dot(u), d.dot(v)), col, n_hint)


func _solid(c: Vector3, s: Vector3) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = Game.COLLISION_WORLD
	var cs := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	bx.size = s
	cs.shape = bx
	cs.position = c
	body.add_child(cs)
	add_child(body)


## 窓: 壁面の中心 p・外向き n。ガラス（空を映す）・白い枠と十字の桟・石の窓台・まぐさ（arch=要石つき）
func _window(p: Vector3, n: Vector3, w: float, h: float, frame := TRIM, arch := false, sill := true) -> void:
	var r := Vector3.UP.cross(n).normalized()
	var bs := Basis(r, Vector3.UP, n)
	var x := func(lx: float, ly: float, lz: float) -> Transform3D: return Transform3D(bs, p + r * lx + Vector3.UP * ly + n * lz)
	_k.box("glass", x.call(0.0, 0.0, 0.02), Vector3(w, h, 0.04), Color(0.55, 0.6, 0.7))
	_k.box("flat", x.call(0.0, h * 0.5 + 0.04, 0.06), Vector3(w + 0.16, 0.08, 0.1), frame)
	_k.box("flat", x.call(0.0, -h * 0.5 - 0.04, 0.06), Vector3(w + 0.16, 0.08, 0.1), frame)
	for sx: float in [-1.0, 1.0]:
		_k.box("flat", x.call(sx * (w * 0.5 + 0.04), 0.0, 0.06), Vector3(0.08, h + 0.16, 0.1), frame)
	_k.box("flat", x.call(0.0, 0.0, 0.06), Vector3(0.05, h, 0.06), frame)
	_k.box("flat", x.call(0.0, h * 0.18, 0.06), Vector3(w, 0.05, 0.06), frame)
	if sill:
		_k.box("stonewall", x.call(0.0, -h * 0.5 - 0.14, 0.12), Vector3(w + 0.4, 0.12, 0.26), STONE)
	if arch:
		_k.box("stonewall", x.call(0.0, h * 0.5 + 0.2, 0.08), Vector3(w + 0.5, 0.26, 0.18), STONE)
		_k.box("stonewall", x.call(0.0, h * 0.5 + 0.24, 0.13), Vector3(0.24, 0.36, 0.2), STONE)


## 煉瓦などの棟: 腰石（地面の下まで）・壁・付柱・胴蛇腹・軒蛇腹・窓。front_door で正面（+Z）中央に入口
func _hall(at: Vector3, ln: float, dp: float, h: float, wall_mat: String, wall_col: Color, o := {}) -> void:
	var floors: int = o.get("floors", 1)
	var bay: float = o.get("bay", 3.2)
	var ww: float = o.get("win_w", 1.0)
	var wh: float = o.get("win_h", minf(2.0, h / floors - 1.4))
	var timber: bool = o.get("timber", false)
	var trim: Color = o.get("trim", TRIM)
	_kb("stonewall", at + Vector3(0, -0.6, 0), Vector3(ln + 0.3, 1.8, dp + 0.3), STONE)
	_kb(wall_mat, at + Vector3(0, h * 0.5 + 0.3, 0), Vector3(ln, h - 0.6, dp), wall_col)
	# 軒蛇腹（軒下の段）・階ごとの胴蛇腹
	_kb("stonewall" if not timber else "darkwood", at + Vector3(0, h - 0.12, 0), Vector3(ln + 0.24, 0.24, dp + 0.24), trim if not timber else DARK)
	for f in range(1, floors):
		_kb("stonewall" if not timber else "darkwood", at + Vector3(0, f * h / floors, 0), Vector3(ln + 0.14, 0.18, dp + 0.14), trim if not timber else DARK)
	var bays := maxi(2, int(round(ln / bay)))
	var dbays := maxi(1, int(round(dp / bay)))
	# 付柱（木骨煉瓦は柱と梁の木部が外に見える）
	for i in bays + 1:
		var px := -ln * 0.5 + i * ln / bays
		for sz: float in [-1.0, 1.0]:
			if timber:
				_kb("darkwood", at + Vector3(px, h * 0.5 + 0.3, sz * (dp * 0.5 + 0.04)), Vector3(0.24, h - 0.6, 0.1), DARK)
			else:
				_kb(wall_mat, at + Vector3(px, h * 0.5 + 0.3, sz * (dp * 0.5 + 0.08)), Vector3(0.5, h - 0.6, 0.16), wall_col * Color(0.93, 0.92, 0.92))
	if timber:
		for f in floors:
			for sz: float in [-1.0, 1.0]:
				_kb("darkwood", at + Vector3(0, 0.5 + f * h / floors, sz * (dp * 0.5 + 0.04)), Vector3(ln, 0.2, 0.1), DARK)
	for f in floors:
		var wy := at.y + (f + 0.55) * h / floors
		for i in bays:
			var px := at.x - ln * 0.5 + (i + 0.5) * ln / bays
			for sz: float in [-1.0, 1.0]:
				if o.get("front_door", false) and sz > 0.0 and f == 0 and i == (bays >> 1):
					continue
				_window(Vector3(px, wy, at.z + sz * (dp * 0.5 + 0.02)), Vector3(0, 0, sz), ww, wh, trim, not timber)
		for j in dbays:
			var pz := at.z - dp * 0.5 + (j + 0.5) * dp / dbays
			for sx: float in [-1.0, 1.0]:
				_window(Vector3(at.x + sx * (ln * 0.5 + 0.02), wy, pz), Vector3(sx, 0, 0), ww, wh, trim, not timber)
	if o.get("front_door", false):
		var dx := at.x - ln * 0.5 + (float(bays >> 1) + 0.5) * ln / bays
		_kb("darkwood", Vector3(dx, at.y + 1.45, at.z + dp * 0.5 + 0.05), Vector3(1.8, 2.5, 0.08), Color(0.35, 0.26, 0.2))
		_kb("stonewall", Vector3(dx, at.y + 2.9, at.z + dp * 0.5 + 0.1), Vector3(2.4, 0.3, 0.22), STONE)
		_kb("stonewall", Vector3(dx, at.y + 0.12, at.z + dp * 0.5 + 0.6), Vector3(2.4, 0.24, 1.0), STONE)
	_solid(at + Vector3(0, h * 0.5, 0), Vector3(ln, h, dp))


## 切妻の瓦屋根（軒の出・鼻隠し・軒裏・棟）。棟は x 方向
func _gable(at: Vector3, hw: float, hd: float, rise: float, col := ROOF, gable_mat := "brick", gable_col := BRICK) -> void:
	var xf := Transform3D(Basis(), at)
	_k.roof(xf, hw, hd, rise, 1.0, "rooftile", "darkwood", col, 1.0, 0.0, 0.28, Color(0.5, 0.42, 0.36), gable_mat, gable_col)
	_k.ridge_cap(xf, hw, hd, rise, 1.0, "rooftile", col * Color(0.7, 0.7, 0.72), 0.45)


## 寄棟（洋館・銀行）
func _hip(at: Vector3, hw: float, hd: float, rise: float, col := ROOF) -> void:
	var xf := Transform3D(Basis(), at)
	_k.roof(xf, hw, hd, rise, 0.0, "rooftile", "darkwood", col, 1.0, 0.0, 0.28, Color(0.5, 0.42, 0.36))
	_k.ridge_cap(xf, hw, hd, rise, 0.0, "rooftile", col * Color(0.7, 0.7, 0.72), 0.4)


## 鋸屋根: 棟は z 方向、歯は x 方向に並ぶ。急な面は北向きのガラス（採光）、緩い面は瓦（スレート）
func _sawtooth(at: Vector3, ln: float, dp: float, teeth: int, rise: float) -> void:
	var tw := ln / teeth
	var hz := dp * 0.5 + 0.35
	for i in teeth:
		var x0 := at.x - ln * 0.5 + i * tw
		var x1 := x0 + tw
		var lo := at.y
		var hi := at.y + rise
		# 緩い面（低い x0 から高い x1 へ）
		_kq("rooftile", Vector3(x0, lo, at.z + hz), Vector3(x1, hi, at.z + hz), Vector3(x1, hi, at.z - hz), Vector3(x0, lo, at.z - hz), ROOF, Vector3(-rise, tw, 0))
		_kq("darkwood", Vector3(x0, lo - 0.18, at.z + hz), Vector3(x1, hi - 0.18, at.z + hz), Vector3(x1, hi - 0.18, at.z - hz), Vector3(x0, lo - 0.18, at.z - hz), Color(0.5, 0.42, 0.36), Vector3(rise, -tw, 0))
		# 急な面: 北向きの明かり窓（ガラス＋桟）
		_kq("glass", Vector3(x1, lo, at.z + hz - 0.2), Vector3(x1, lo, at.z - hz + 0.2), Vector3(x1, hi - 0.1, at.z - hz + 0.2), Vector3(x1, hi - 0.1, at.z + hz - 0.2), Color(0.5, 0.56, 0.66), Vector3(1, 0, 0))
		var nm := int(dp / 1.2)
		for m in nm + 1:
			var zz := at.z - hz + 0.2 + m * (2.0 * hz - 0.4) / nm
			_kb("flat", Vector3(x1 + 0.03, lo + rise * 0.5, zz), Vector3(0.05, rise, 0.07), TRIM)
		# 妻（三角の煉瓦壁）
		for sz: float in [-1.0, 1.0]:
			var zf := at.z + sz * dp * 0.5
			_k.tri("brick", Vector3(x0, lo, zf), Vector3(x1, lo, zf), Vector3(x1, hi, zf), Vector2(x0, -lo), Vector2(x1, -lo), Vector2(x1, -hi), BRICK, Vector3(0, 0, sz))
		# 歯の頂部の笠木（雨仕舞の板金）
		_kb("metal", Vector3(x1, hi + 0.04, at.z), Vector3(0.22, 0.1, 2.0 * hz + 0.1), IRON)


## 煉瓦の煙突（先細り・数段の帯・頂部の持ち出し）。煙は稼働中だけ
func _chimney(at: Vector3, h: float, r := 0.6, col := BRICK, mat := "brick", square := false) -> void:
	var segs := 4 if square else 12
	_kb("stonewall", at + Vector3(0, -0.4, 0), Vector3(r * 3.2, 1.6, r * 3.2), STONE)
	if square:
		_k.cylinder(mat, Transform3D(Basis(Vector3.UP, PI * 0.25), at + Vector3(0, 0.4, 0)), r * 1.45, r * 1.05, h - 0.4, segs, col)
	else:
		_kcyl(mat, at + Vector3(0, 0.4, 0), r * 1.3, r * 0.9, h - 0.4, segs, col)
	var n := maxi(2, int(h / 6.0))
	for i in n:
		var y := 0.4 + (i + 1) * (h - 1.2) / (n + 1)
		var rr := lerpf(r * 1.3, r * 0.9, y / h) + 0.06
		if square:
			_k.cylinder("metal", Transform3D(Basis(Vector3.UP, PI * 0.25), at + Vector3(0, y, 0)), rr * 1.12, rr * 1.12, 0.22, segs, IRON, true)
		else:
			_kcyl(mat, at + Vector3(0, y, 0), rr, rr, 0.3, segs, col * Color(0.82, 0.8, 0.8))
	# 頂部の持ち出し（笠）と黒い口
	if square:
		_k.cylinder(mat, Transform3D(Basis(Vector3.UP, PI * 0.25), at + Vector3(0, h - 0.5, 0)), r * 1.25, r * 1.25, 0.5, segs, col * Color(0.85, 0.85, 0.85))
	else:
		_kcyl(mat, at + Vector3(0, h - 0.6, 0), r * 1.1, r * 1.15, 0.6, segs, col * Color(0.82, 0.8, 0.8))
	_kcyl("flat", at + Vector3(0, h - 0.02, 0), r * 0.75, r * 0.75, 0.04, 10, Color(0.05, 0.05, 0.05))
	var body := StaticBody3D.new()
	body.collision_layer = Game.COLLISION_WORLD
	var cs := CollisionShape3D.new()
	var cy := CylinderShape3D.new()
	cy.radius = r * 1.2
	cy.height = h
	cs.shape = cy
	cs.position = at + Vector3(0, h * 0.5, 0)
	body.add_child(cs)
	add_child(body)
	var sm := CPUParticles3D.new()
	sm.amount = 26
	sm.lifetime = 4.0
	sm.direction = Vector3.UP
	sm.spread = 12.0
	sm.initial_velocity_min = 1.5
	sm.initial_velocity_max = 2.5
	sm.gravity = Vector3(0.6, 0.4, 0)
	sm.scale_amount_min = 1.2
	sm.scale_amount_max = 2.6
	var g := Gradient.new()
	g.set_color(0, Color(0.3, 0.3, 0.32, 0.7))
	g.set_color(1, Color(0.5, 0.5, 0.52, 0.0))
	sm.color_ramp = g
	var q := QuadMesh.new()
	q.material = Effects.particle_mat(Color.WHITE, false)
	sm.mesh = q
	sm.position = at + Vector3(0, h + 0.3, 0)
	sm.emitting = false
	add_child(sm)
	_smoke.append(sm)


## 小さな建物（町の工房・駅舎・電信局・付属屋）。wa = 和風（板壁＋漆喰・瓦の切妻・庇）、それ以外は洋風の小屋
func _house(size: Vector3, wall: Color, roof: Color, at := Vector3.ZERO, wa := true) -> void:
	if _k == null:
		_k = MeshKit.new()
	_kb("stonewall", at + Vector3(0, -0.5, 0), Vector3(size.x + 0.3, 1.4, size.z + 0.3), STONE)
	if wa:
		# 腰は下見板（焼杉）、上は漆喰。柱を見せる
		_kb("plaster", at + Vector3(0, size.y * 0.5 + 0.2, 0), Vector3(size.x, size.y - 0.4, size.z), PLASTER)
		_kb("darkwood", at + Vector3(0, 0.75, 0), Vector3(size.x + 0.06, 1.1, size.z + 0.06), Color(0.36, 0.3, 0.27))
		var nb := maxi(2, int(size.x / 1.8))
		for i in nb + 1:
			for sz: float in [-1.0, 1.0]:
				_kb("darkwood", at + Vector3(-size.x * 0.5 + i * size.x / nb, size.y * 0.5 + 0.2, sz * (size.z * 0.5 + 0.05)), Vector3(0.18, size.y - 0.4, 0.1), DARK)
		for sz: float in [-1.0, 1.0]:
			_kb("darkwood", at + Vector3(0, size.y - 0.25, sz * (size.z * 0.5 + 0.05)), Vector3(size.x, 0.22, 0.1), DARK)
		# 格子窓と入口（暖簾）
		_kb("darkwood", at + Vector3(size.x * 0.22, 1.8, size.z * 0.5 + 0.08), Vector3(size.x * 0.3, 0.9, 0.06), Color(0.16, 0.13, 0.12))
		for k in 8:
			_kb("wood", at + Vector3(size.x * 0.22 - size.x * 0.15 + k * size.x * 0.3 / 7.0, 1.8, size.z * 0.5 + 0.12), Vector3(0.04, 0.9, 0.04), WOOD)
		_kb("darkwood", at + Vector3(-size.x * 0.2, 1.1, size.z * 0.5 + 0.06), Vector3(1.4, 2.0, 0.06), Color(0.14, 0.12, 0.11))
		_kb("cloth", at + Vector3(-size.x * 0.2, 1.75, size.z * 0.5 + 0.14), Vector3(1.5, 0.7, 0.03), Color(0.16, 0.22, 0.45))
		# 庇（下屋）
		var ang := atan2(0.4, 1.2)
		_k.box("rooftile", Transform3D(Basis(Vector3.RIGHT, ang), at + Vector3(0, 2.6, size.z * 0.5 + 0.55)), Vector3(size.x + 0.2, 0.1, 1.27), roof)
		_gable(at + Vector3(0, size.y + 0.05, 0), size.x * 0.5 + 0.55, size.z * 0.5 + 0.7, size.z * 0.38, roof, "plaster", PLASTER)
	else:
		_kb("brick" if wall.r > wall.b * 1.2 else "plaster", at + Vector3(0, size.y * 0.5 + 0.2, 0), Vector3(size.x, size.y - 0.4, size.z), wall)
		_kb("stonewall", at + Vector3(0, size.y - 0.1, 0), Vector3(size.x + 0.2, 0.2, size.z + 0.2), TRIM)
		for i in 2:
			_window(at + Vector3(-size.x * 0.25 + i * size.x * 0.5, size.y * 0.55, size.z * 0.5 + 0.02), Vector3(0, 0, 1), 0.8, 1.3, TRIM, true)
		_hip(at + Vector3(0, size.y + 0.05, 0), size.x * 0.5 + 0.5, size.z * 0.5 + 0.5, size.z * 0.35, roof)
	_solid(at + Vector3(0, size.y * 0.5, 0), size)


func _build_visual(v: String) -> void:
	_k = MeshKit.new()
	match v:
		"watermill":
			# 板壁の小屋・瓦の切妻・木樋（とい）から水を落とす上掛け水車
			_house(Vector3(4.5, 3.2, 4), WOOD, Color(0.5, 0.48, 0.44))
			_kb("wood", Vector3(2.4, 4.6, -1.2), Vector3(0.7, 0.35, 5.0), WOOD * Color(0.8, 0.75, 0.7))
			for z: float in [-3.4, 0.8]:
				_kb("wood", Vector3(2.4, 2.3, z), Vector3(0.2, 4.6, 0.2), DARK)
			_wheel = Node3D.new()
			_wheel.position = Vector3(2.6, 2.0, 1.2)
			add_child(_wheel)
			var wk := MeshKit.new()
			var rb := Basis(Vector3.BACK, PI * 0.5)
			for sx: float in [-0.35, 0.35]:
				wk.cylinder("wood", Transform3D(rb, Vector3(sx - 0.06, 0, 0)), 1.85, 1.85, 0.12, 20, WOOD, true)
			wk.cylinder("darkwood", Transform3D(rb, Vector3(-0.5, 0, 0)), 0.22, 0.22, 1.0, 10, DARK, true)
			for i in 16:
				var a := i * TAU / 16.0
				var pr := Vector3(0, sin(a), cos(a))
				wk.box("wood", Transform3D(Basis(Vector3.RIGHT, -a), pr * 1.75), Vector3(0.8, 0.5, 0.06), WOOD * Color(0.85, 0.8, 0.75))
				if i % 2 == 0:
					wk.box("wood", Transform3D(Basis(Vector3.RIGHT, -a), pr * 0.9), Vector3(0.08, 1.7, 0.08), WOOD)
			_wheel.add_child(wk.commit("Wheel"))
		"workshop", "school":
			if v == "workshop":
				_house(Vector3(7, 3.6, 5), WOOD, ROOF)
				_chimney(Vector3(2.6, 0, -1.4), 6.5, 0.32, DARK, "stonewall", true)
			else:
				# 擬洋風の私塾: 白い下見板・縦長の窓・寄棟・小さな塔屋
				_hall(Vector3.ZERO, 10.0, 6.0, 4.2, "plaster", PLASTER, {"bay": 2.4, "win_w": 0.8, "win_h": 1.8, "front_door": true, "trim": Color(0.55, 0.62, 0.58)})
				_hip(Vector3(0, 4.25, 0), 5.6, 3.6, 2.0, ROOF)
				_kb("plaster", Vector3(0, 6.6, 0), Vector3(1.8, 2.0, 1.8), PLASTER)
				_hip(Vector3(0, 7.6, 0), 1.3, 1.3, 1.2, ROOF)
		"tatara":
			# 高殿（たかどの）: 土壁の大きな作業小屋・急な屋根・棟の越屋根（煙出し）
			_house(Vector3(9, 4.2, 7), WOOD, Color(0.36, 0.34, 0.32))
			_kb("darkwood", Vector3(0, 8.1, 0), Vector3(3.2, 1.1, 1.4), Color(0.22, 0.2, 0.19))
			_gable(Vector3(0, 8.6, 0), 2.0, 1.2, 0.7, Color(0.36, 0.34, 0.32), "darkwood", DARK)
		"mine":
			# 坑口（石積みの抗門＋坑木）・木造の櫓（巻上げ）・ズリ山・付属小屋
			_kb("stonewall", Vector3(0, 2.4, -2.2), Vector3(7.5, 4.8, 4.0), Color(0.62, 0.58, 0.54))
			_kb("flat", Vector3(0, 1.4, -0.15), Vector3(2.6, 2.8, 0.1), Color(0.03, 0.03, 0.03))
			for x: float in [-1.45, 1.45]:
				_kb("darkwood", Vector3(x, 1.5, 0.05), Vector3(0.3, 3.0, 0.3), DARK)
			_kb("darkwood", Vector3(0, 3.1, 0.05), Vector3(3.4, 0.32, 0.36), DARK)
			_kb("stonewall", Vector3(0, 3.6, 0.0), Vector3(4.2, 0.5, 0.5), STONE)
			_solid(Vector3(0, 2.4, -2.2), Vector3(7.5, 4.8, 4.0))
			for sx: float in [-1.0, 1.0]:
				for sz: float in [-1.0, 1.0]:
					_k.rod("darkwood", Vector3(-6 + sx * 1.6, 0, 3 + sz * 1.6), Vector3(-6 + sx * 0.5, 9.0, 3 + sz * 0.5), 0.14, 6, DARK)
			for yy: float in [3.0, 6.0]:
				_kb("darkwood", Vector3(-6, yy, 3), Vector3(2.6, 0.16, 2.6), DARK)
			_k.cylinder("metal", Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(-5.6, 9.2, 3)), 0.8, 0.8, 0.2, 14, IRON, true)
			_k.sphere("rock", Transform3D(Basis().scaled(Vector3(1.4, 0.55, 1.2)), Vector3(4.5, 0.0, 2.5)), 2.6, 10, 6, Color(0.25, 0.24, 0.24))
			_house(Vector3(4, 3, 3.5), WOOD, ROOF, Vector3(5.5, 0, -5.5))
		"reverb":
			# 韮山反射炉: 石の炉体に、白い漆喰で塗った連双の煉瓦煙突（鉄の帯で締める）
			for sx: float in [-1.0, 1.0]:
				_kb("stonewall", Vector3(sx * 2.3, 1.6, 0), Vector3(3.2, 3.2, 5.0), Color(0.72, 0.7, 0.66))
				_kb("brick", Vector3(sx * 2.3, 1.2, 2.56), Vector3(1.2, 1.4, 0.1), Color(0.3, 0.16, 0.12))
				for k in 2:
					var cx := sx * 2.3 + (k - 0.5) * 1.3
					_kb("plaster", Vector3(cx, 3.2 + 6.0, -0.9), Vector3(1.1, 12.0, 1.1), PLASTER)
					for b in 5:
						_kb("metal", Vector3(cx, 4.4 + b * 2.3, -0.9), Vector3(1.18, 0.12, 1.18), IRON)
					_kb("brick", Vector3(cx, 15.25, -0.9), Vector3(1.0, 0.1, 1.0), Color(0.1, 0.08, 0.08))
			_solid(Vector3(0, 1.6, 0), Vector3(8.0, 3.2, 5.0))
			_solid(Vector3(0, 9.2, -0.9), Vector3(6.0, 12.0, 1.2))
			_house(Vector3(5, 3, 4), WOOD, ROOF, Vector3(0, 0, 6.5))
		"blast":
			# 洋式高炉（橋野・釜石）: 花崗岩を積んだ四角い炉・鋳床の上屋・送風の水車小屋・煙突
			_k.cylinder("stonewall", Transform3D(Basis(Vector3.UP, PI * 0.25), Vector3(0, 0, 0)), 4.6, 3.2, 10.0, 4, Color(0.76, 0.74, 0.7))
			_k.cylinder("stonewall", Transform3D(Basis(Vector3.UP, PI * 0.25), Vector3(0, 10.0, 0)), 3.5, 3.5, 0.5, 4, STONE)
			_kcyl("brick", Vector3(0, 10.5, 0), 1.4, 1.2, 1.6, 10, BRICK_DARK)
			_kb("flat", Vector3(0, 1.3, 2.35), Vector3(1.2, 1.8, 0.1), Color(0.08, 0.04, 0.03))
			_solid(Vector3(0, 5.0, 0), Vector3(6.0, 10.0, 6.0))
			_house(Vector3(7, 3.2, 5), WOOD, ROOF, Vector3(0, 0, 6.8))
			_chimney(Vector3(-6, 0, -1), 16.0, 0.7)
			var glow := OmniLight3D.new()
			glow.light_color = Color(1.0, 0.5, 0.15)
			glow.light_energy = 2.5
			glow.omni_range = 9.0
			glow.position = Vector3(0, 1.5, 3.4)
			add_child(glow)
			_lamps.append(glow)
		"factory":
			# 機械工場: 煉瓦の平屋に鋸屋根（北側採光）・事務所の切妻・高い煙突
			_hall(Vector3.ZERO, 14.0, 9.0, 5.0, "brick", BRICK, {"bay": 3.5, "win_w": 1.2, "win_h": 2.2, "front_door": true})
			_sawtooth(Vector3(0, 5.0, 0), 14.0, 9.0, 4, 2.4)
			_house(Vector3(5, 3.6, 4), BRICK, ROOF, Vector3(-4.5, 0, 8.0), false)
			_chimney(Vector3(9.6, 0, -2.0), 20.0, 0.85)
		"mill":
			# 製糸場・紡績工場（富岡製糸場の繰糸所）: 木骨煉瓦の細長い棟・瓦の切妻・棟の越屋根（湯気抜き）・大きなガラス窓・煙突
			_hall(Vector3.ZERO, 20.0, 9.0, 5.4, "brick", BRICK, {"bay": 2.5, "win_w": 1.3, "win_h": 2.6, "timber": true, "front_door": true})
			_gable(Vector3(0, 5.4, 0), 10.8, 5.3, 3.0, ROOF, "brick", BRICK)
			# 越屋根: 棟の上に低い屋根を浮かせ、側面は板の鎧戸
			_kb("darkwood", Vector3(0, 8.75, 0), Vector3(14.0, 0.9, 1.6), Color(0.26, 0.22, 0.2))
			for k in 24:
				for sz: float in [-1.0, 1.0]:
					_kb("wood", Vector3(-6.8 + k * 13.6 / 23.0, 8.75, sz * 0.82), Vector3(0.05, 0.8, 0.05), WOOD)
			_gable(Vector3(0, 9.2, 0), 7.4, 1.3, 0.55, ROOF, "darkwood", DARK)
			_chimney(Vector3(13.5, 0, -3.0), 22.0, 0.9)
		"chemical":
			# 化学工場（硫酸・ソーダ）: 煉瓦の棟・帯鉄で締めた槽・配管・煙突
			_hall(Vector3.ZERO, 9.0, 6.0, 4.4, "brick", BRICK, {"bay": 3.0, "front_door": true})
			_gable(Vector3(0, 4.4, 0), 5.0, 3.6, 2.0, ROOF)
			for i in 3:
				var tp := Vector3(-3 + i * 3, 0, 5.8)
				_kcyl("metal", tp, 1.1, 1.1, 5.0, 14, Color(0.55, 0.57, 0.56))
				_kcyl("metal", tp + Vector3(0, 5.0, 0), 1.1, 0.5, 0.6, 14, Color(0.5, 0.52, 0.5))
				for b in 3:
					_kcyl("metal", tp + Vector3(0, 0.9 + b * 1.5, 0), 1.15, 1.15, 0.12, 14, IRON)
				_k.rod("metal", tp + Vector3(0, 5.5, 0), Vector3(-3 + i * 3, 4.0, 3.1), 0.1, 6, IRON)
				_solid(tp + Vector3(0, 2.5, 0), Vector3(2.2, 5.0, 2.2))
			_chimney(Vector3(5.6, 0, -2.0), 14.0, 0.6)
		"shipyard":
			# 洋式造船所: 船台（斜路）・盤木の上の竜骨と肋材・門形の起重機・付属屋
			_k.box("wood", Transform3D(Basis(Vector3.RIGHT, -0.07), Vector3(0, 0.4, 0)), Vector3(6, 0.5, 24), Color(0.72, 0.62, 0.5))
			_k.box("darkwood", Transform3D(Basis(Vector3.RIGHT, -0.07), Vector3(0, 1.3, 0)), Vector3(0.5, 0.7, 20), DARK)
			for i in 13:
				var z := -9.0 + i * 1.5
				var y := 1.5 - z * 0.07
				var hw := 2.0 * sqrt(maxf(0.0, 1.0 - pow(z / 10.5, 2.0))) + 0.2
				_k.rod("wood", Vector3(0, y, z), Vector3(hw, y + 1.4, z), 0.12, 5, WOOD)
				_k.rod("wood", Vector3(0, y, z), Vector3(-hw, y + 1.4, z), 0.12, 5, WOOD)
				_k.rod("wood", Vector3(hw, y + 1.4, z), Vector3(hw * 1.05, y + 3.2, z), 0.11, 5, WOOD)
				_k.rod("wood", Vector3(-hw, y + 1.4, z), Vector3(-hw * 1.05, y + 3.2, z), 0.11, 5, WOOD)
			for z: float in [-8.0, 8.0]:
				for x: float in [-4.0, 4.0]:
					_kb("darkwood", Vector3(x, 5, z), Vector3(0.45, 10, 0.45), DARK)
					_k.rod("darkwood", Vector3(x, 0, z - 1.6), Vector3(x, 6, z), 0.12, 5, DARK)
				_kb("darkwood", Vector3(0, 10, z), Vector3(9.0, 0.5, 0.5), DARK)
			_kb("metal", Vector3(0, 9.6, 0), Vector3(0.4, 0.4, 16.5), IRON)
			_house(Vector3(6, 3.4, 5), WOOD, ROOF, Vector3(9.5, 0, 0))
		"power":
			# 発電所: 煉瓦の高い棟（縦長のアーチ窓）・寄棟・煙突・碍子の柱
			_hall(Vector3.ZERO, 11.0, 8.0, 7.0, "brick", BRICK, {"bay": 2.75, "win_w": 1.1, "win_h": 4.0, "front_door": true})
			_hip(Vector3(0, 7.0, 0), 6.1, 4.6, 2.6, ROOF)
			_chimney(Vector3(7.2, 0, 0), 18.0, 0.8)
			for i in 3:
				_kcyl("darkwood", Vector3(-4 + i * 4, 0, 6.5), 0.12, 0.1, 7.0, 6, DARK)
				_kb("darkwood", Vector3(-4 + i * 4, 6.6, 6.5), Vector3(1.6, 0.12, 0.12), DARK)
			var w = Game.world
			var pts: Array = w.street_points() if w and w.has_method("street_points") else []
			for i in mini(8, pts.size()):
				var l := OmniLight3D.new()
				l.light_color = Color(1.0, 0.92, 0.7)
				l.light_energy = 1.6
				l.omni_range = 10.0
				get_parent().add_child.call_deferred(l)
				l.set_deferred("global_position", (pts[(i * 7) % pts.size()] as Vector3) + Vector3.UP * 4.0)
				_lamps.append(l)
		"bank":
			# 銀行（第一国立銀行・日本銀行風）: 石造の基壇と階段・列柱・三角破風・軒蛇腹・寄棟
			_hall(Vector3(0, 0.8, 0), 10.0, 8.0, 5.6, "plaster", Color(0.88, 0.86, 0.82), {"bay": 2.5, "win_w": 1.0, "win_h": 2.4, "trim": STONE})
			_kb("stonewall", Vector3(0, 0.4, 0), Vector3(10.6, 0.8, 8.6), STONE)
			for k in 3:
				_kb("stonewall", Vector3(0, 0.13 + k * 0.27, 5.1 - k * 0.35), Vector3(6.0, 0.27, 0.6), STONE)
			for i in 4:
				var cx := -2.7 + i * 1.8
				_kcyl("stonewall", Vector3(cx, 0.8, 4.6), 0.34, 0.3, 5.0, 12, Color(0.94, 0.93, 0.9))
				_kb("stonewall", Vector3(cx, 0.95, 4.6), Vector3(0.8, 0.3, 0.8), STONE)
				_kb("stonewall", Vector3(cx, 5.7, 4.6), Vector3(0.75, 0.3, 0.75), STONE)
			_kb("stonewall", Vector3(0, 6.1, 4.6), Vector3(6.6, 0.55, 1.1), STONE)
			_k.tri("stonewall", Vector3(-3.4, 6.38, 5.16), Vector3(3.4, 6.38, 5.16), Vector3(0, 7.9, 5.16), Vector2(-3.4, -6.38), Vector2(3.4, -6.38), Vector2(0, -7.9), STONE, Vector3(0, 0, 1))
			_kq("rooftile", Vector3(-3.6, 6.36, 5.25), Vector3(0, 8.0, 5.25), Vector3(0, 8.0, 3.6), Vector3(-3.6, 6.36, 3.6), ROOF, Vector3(-1.6, 3.6, 0))
			_kq("rooftile", Vector3(0, 8.0, 5.25), Vector3(3.6, 6.36, 5.25), Vector3(3.6, 6.36, 3.6), Vector3(0, 8.0, 3.6), ROOF, Vector3(1.6, 3.6, 0))
			_hip(Vector3(0, 6.4, 0), 5.5, 4.5, 2.2, ROOF)
		"railway", "telegraph":
			_build_line(v)
		_:
			_house(Vector3(6, 3, 5), WOOD, ROOF)
	if not _k.is_empty():
		var mi := _k.commit("FacilityMesh")
		add_child(mi)
	_k = null


## 鉄道・電信：rec.pos から rec.to の名所まで
func _build_line(v: String) -> void:
	var w = Game.world
	var to := str(rec.get("to", ""))
	if w == null or to == "":
		_house(Vector3(4, 3, 4), WOOD, ROOF)
		return
	_line_a = global_position
	_line_b = (w.landmark_pos(to) as Vector3) + Vector3(8, 0, 8)
	var d := _line_b - _line_a
	var flat := Vector3(d.x, 0, d.z)
	var length := flat.length()
	var dir := flat.normalized()
	var right := dir.cross(Vector3.UP)
	var root := Node3D.new()
	root.top_level = true
	add_child(root)
	if v == "railway":
		# 枕木（MultiMesh）とレール（区間ごとの細い箱）
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		var bm := BoxMesh.new()
		bm.size = Vector3(2.2, 0.15, 0.3)
		bm.material = _mat(Color(0.32, 0.24, 0.18))
		mm.mesh = bm
		var n := int(length / 1.5)
		mm.instance_count = n
		for i in n:
			var p := _line_a + dir * (i * 1.5)
			p.y = w.height_at(p.x, p.z) + 0.08
			mm.set_instance_transform(i, Transform3D(Basis(Vector3.UP, atan2(-dir.x, -dir.z)), p))
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		root.add_child(mmi)
		var seg := 6.0
		var m := int(length / seg)
		for i in m:
			var a := _line_a + dir * (i * seg)
			var b := _line_a + dir * ((i + 1) * seg)
			a.y = w.height_at(a.x, a.z) + 0.25
			b.y = w.height_at(b.x, b.z) + 0.25
			for s in [-0.72, 0.72]:
				var mi := MeshInstance3D.new()
				var rb := BoxMesh.new()
				rb.size = Vector3(0.1, 0.12, a.distance_to(b))
				mi.mesh = rb
				mi.material_override = Humanoid.mat(Color(0.4, 0.38, 0.36), 0.3, 0.8)
				root.add_child(mi)
				mi.global_transform = Transform3D(Basis.looking_at((b - a).normalized(), Vector3.UP), (a + b) * 0.5 + right * s)
		# 機関車
		_train = Node3D.new()
		_train.top_level = true
		add_child(_train)
		Humanoid.part(_train, "cyl", _mat(Color(0.12, 0.12, 0.13), 0.4), Vector3(0, 1.6, -0.5), Vector3(1.6, 4.0, 1.6), Vector3(90, 0, 0))
		Humanoid.part(_train, "box", _mat(Color(0.15, 0.15, 0.16)), Vector3(0, 1.9, 2.2), Vector3(2.2, 2.4, 2.0))
		Humanoid.part(_train, "box", _mat(Color(0.5, 0.12, 0.1)), Vector3(0, 0.6, 0.5), Vector3(2.4, 0.5, 6.5))
		Humanoid.part(_train, "cyl", _mat(Color(0.1, 0.1, 0.1)), Vector3(0, 3.2, -2.0), Vector3(0.6, 1.4, 0.6))
		var sm := CPUParticles3D.new()
		sm.amount = 20
		sm.lifetime = 2.5
		sm.direction = Vector3.UP
		sm.initial_velocity_min = 2.0
		sm.initial_velocity_max = 3.0
		sm.scale_amount_min = 0.8
		sm.scale_amount_max = 1.6
		var q := QuadMesh.new()
		q.material = Effects.particle_mat(Color(0.85, 0.85, 0.85, 0.6), false)
		sm.mesh = q
		sm.local_coords = false
		sm.position = Vector3(0, 4.0, -2.0)
		_train.add_child(sm)
		_smoke.append(sm)
		_train.global_position = _line_a
		_house(Vector3(6, 3.6, 4), BRICK, ROOF, Vector3(0, 0, 6), false)   # 駅舎
	else:
		var n2 := int(length / 25.0) + 1
		var prev := Vector3.ZERO
		for i in n2 + 1:
			var p := _line_a + dir * minf(length, i * 25.0)
			p.y = w.height_at(p.x, p.z)
			var pole := MeshInstance3D.new()
			var cm := CylinderMesh.new()
			cm.top_radius = 0.1
			cm.bottom_radius = 0.14
			cm.height = 6.0
			pole.mesh = cm
			pole.material_override = _mat(WOOD)
			root.add_child(pole)
			pole.global_position = p + Vector3.UP * 3.0
			var top := p + Vector3.UP * 5.8
			if i > 0:
				var wi := MeshInstance3D.new()
				var wb := BoxMesh.new()
				wb.size = Vector3(0.03, 0.03, prev.distance_to(top))
				wi.mesh = wb
				wi.material_override = _mat(Color(0.1, 0.1, 0.1))
				root.add_child(wi)
				wi.global_transform = Transform3D(Basis.looking_at((top - prev).normalized(), Vector3.UP), (prev + top) * 0.5)
			prev = top
		_house(Vector3(4, 3.4, 4), PLASTER, ROOF, Vector3(0, 0, 5), false)   # 電信局
