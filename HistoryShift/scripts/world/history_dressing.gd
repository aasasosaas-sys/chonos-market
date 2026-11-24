class_name HistoryDressing
extends RefCounted
## この世界の歴史で箱庭の姿を変える（data/visuals/history_visuals.json・HistoryVisuals）。
##  - build(w, a)：WorldLayouts.build_all の最後（破壊システムの前）に 1 行で呼ぶ。追加の建物（製糸場・製鉄所・鉄道・電信・街灯・
##    港の艦隊）と、建て替え（町家→煉瓦の洋館／洋館→町家）は普通の破壊ユニットとして建てる（壊せる・燃える・屋内にも入れる）。
##    ユニット ID は元の建物の後ろに付くので、元の建物の ID は歴史によらず同じ（TimelineWorld の前提を崩さない）。
##  - after(w)：TimelineWorld.apply の中で呼ぶ。建て替えた元の建物と「史実より遅れてまだ無い」建物を消す。
##  - ruin_rules(w, rules)：昭和の被災（空襲）を戦争の帰趨で強め・弱め・無くす。
## 入力は w.hist["vis"]（Session.world_history が HistoryVisuals.profile を入れる）。無ければ何もしない（従来どおり）。
## 軽さ：追加はすべて Architecture の結合メッシュ（描画コールは増えない）。煙は 1 本の煙突に GPUParticles 1 つ（最大 4）、看板は Label3D。

const SIGN_FONT := "res://assets/fonts/NotoSerifJP-Bold.ttf"
const SIGN_FONT_MODERN := "res://assets/fonts/NotoSansJP-Bold.ttf"
const MAX_SMOKE := 4

static var _font_cache := {}


static func profile_of(w: Node3D) -> Dictionary:
	var hist: Variant = w.get("hist")
	if hist is Dictionary and (hist as Dictionary).get("vis") is Dictionary:
		return hist["vis"]
	return {}


# ================================================================== 組み上げ（破壊システムの前）
static func build(w: EraWorld, a: Architecture) -> Dictionary:
	var p := profile_of(w)
	var stats := {"features": [], "swapped": 0, "added_units": 0}
	if p.is_empty() or int(p.get("year", 0)) == 0:
		return stats
	var d := HistoryDressing.new()
	d.w = w
	d.a = a
	d.t = w.terrain
	d.p = p
	d.rng.seed = hash(str(p.get("era", ""))) + int(p.get("year", 0)) * 31 + 7
	var u0: int = w.unit_defs.size()
	d._run(stats)
	a.landmark = ""
	a.flush("Arch_history")
	stats["added_units"] = w.unit_defs.size() - u0
	w.set_meta("hv_vanish", d.vanish_ids)
	w.set_meta("hv_stats", stats)
	if not (stats["features"] as Array).is_empty() or int(stats["swapped"]) > 0:
		print("[HistoryDressing] %s %d: %s, swapped %d, +%d units" % [p["era"], int(p["year"]), ",".join(PackedStringArray(stats["features"])), int(stats["swapped"]), int(stats["added_units"])])
	return stats


var w: EraWorld
var a: Architecture
var t: TerrainGen
var p: Dictionary
var rng := RandomNumberGenerator.new()
var vanish_ids: Array = []
var smoke_n := 0


func _run(stats: Dictionary) -> void:
	var defs_before: Array = w.unit_defs.duplicate()   # 建て替えの対象は元からある建物だけ
	for f in HistoryVisuals.features_for(p):
		var fd: Dictionary = f["def"]
		var ok := false
		match str(fd.get("builder", "")):
			"telegraph": ok = _telegraph()
			"gas_lamps": ok = _lamps(fd, "gas")
			"electric_lamps": ok = _lamps(fd, "electric")
			"railway": ok = _railway(fd)
			"factory": ok = _factories(fd)
			"steelworks": ok = _steelworks(fd)
			"brick_swap":
				var n := _swap(defs_before, HistoryVisuals._list(fd.get("landmark", "capital")), "house", "machiya", "brick", float(f["frac"]))
				stats["swapped"] += n
				ok = n > 0
		if ok:
			stats["features"].append(str(fd["id"]))
	for ab in HistoryVisuals.absent_for(p):
		var ad: Dictionary = ab["def"]
		if ad.has("swap"):
			var n2 := _swap(defs_before, HistoryVisuals._list(ad.get("landmark", "capital")), str(HistoryVisuals._list(ad["kind"])[0]), "brick_building", str(ad["swap"]), float(ab["frac"]))
			stats["swapped"] += n2
			if n2 > 0:
				stats["features"].append(str(ad["id"]))
	var nv: Dictionary = HistoryVisuals.navy_for(p)
	if not nv.is_empty() and _navy(nv):
		stats["features"].append("navy_" + str(nv["kind"]))
	var cp: Dictionary = HistoryVisuals.capital_for(p)
	if not cp.is_empty():
		_capital_sign(cp)
		stats["features"].append("capital_" + str(cp["city"]))
	var wr: Dictionary = HistoryVisuals.war_for(p)
	if not (wr.get("sign_set", {}) as Dictionary).is_empty():
		_war_signs(wr["sign_set"], str(wr.get("signs", "")))
		stats["features"].append("signs_" + str(wr.get("signs", "")))


# ------------------------------------------------------------------ 場所探し
func _lm(key: String) -> Dictionary:
	return w.landmarks.get(key, {})


## 足場が平らで、建物・水・道に掛からない場所（建物の正面 +Z を中心へ向ける）
func _find_spot(key: String, wd: float, dp: float, rmin: float, rmax: float, avoid_road := true) -> Variant:
	var lm := _lm(key)
	if lm.is_empty():
		return null
	var c: Vector2 = lm["center"]
	var lim := t.half - 14.0
	for tries in 220:
		var ang := rng.randf() * TAU
		var rr := rng.randf_range(rmin, rmax)
		var q := c + Vector2(cos(ang), sin(ang)) * rr
		if absf(q.x) > lim or absf(q.y) > lim:
			continue
		var yaw := atan2(c.x - q.x, c.y - q.y)
		var b := Basis(Vector3.UP, yaw)
		var lo := INF
		var hi := -INF
		var bad := false
		for ix in 5:
			for iz in 5:
				var lp := Vector3((ix / 4.0 - 0.5) * (wd + 3.0), 0, (iz / 4.0 - 0.5) * (dp + 3.0))
				var wp: Vector3 = b * lp + Vector3(q.x, 0, q.y)
				if t.is_occupied(wp.x, wp.z) or t.is_water(wp.x, wp.z) or t.river_dist_at(wp.x, wp.z) < t.river_half_w + 5.0 \
						or (avoid_road and t.mask_at(t.road, wp.x, wp.z) > 0.35):
					bad = true
					break
				var hh := t.height_at(wp.x, wp.z)
				lo = minf(lo, hh)
				hi = maxf(hi, hh)
			if bad:
				break
		if bad or hi - lo > 2.2:
			continue
		return Transform3D(b, Vector3(q.x, lo, q.y))
	return null


## landmark の中心に近い道の点（中心から r 以内）を、道の脇へずらして返す
func _road_side_points(key: String, r: float, spacing: float, side_off: float) -> Array:
	var lm := _lm(key)
	var out: Array = []
	if lm.is_empty() and key != "roads":
		return out
	var c: Vector2 = lm.get("center", Vector2.ZERO)
	for line in t.road_lines:
		var pts: PackedVector2Array = line["pts"]
		var acc := spacing
		for k in range(1, pts.size() - 1):
			acc += pts[k].distance_to(pts[k - 1])
			if key != "roads" and pts[k].distance_to(c) > r:
				continue
			if acc < spacing:
				continue
			var d := (pts[k + 1] - pts[k - 1]).normalized()
			for s in [1.0, -1.0]:
				var q: Vector2 = pts[k] + Vector2(-d.y, d.x) * (float(line["w"]) + side_off) * s
				if not t.is_occupied(q.x, q.y) and not t.is_water(q.x, q.y) and t.river_dist_at(q.x, q.y) > t.river_half_w + 4.0:
					out.append(Vector3(q.x, t.height_at(q.x, q.y), q.y))
					acc = 0.0
					break
	return out


# ------------------------------------------------------------------ 電信・街灯
func _telegraph() -> bool:
	var n := 0
	a.landmark = "roads"
	for line in t.road_lines:
		var pts: PackedVector2Array = line["pts"]
		var poles: Array = []
		for k in range(3, pts.size() - 3, 10):
			var d := (pts[k + 1] - pts[k - 1]).normalized()
			var got := false
			for off in [2.0, -2.0, 3.5, -3.5]:
				var q := pts[k] - Vector2(-d.y, d.x) * (float(line["w"]) + absf(off)) * signf(off)
				if not t.is_occupied(q.x, q.y) and not t.is_water(q.x, q.y) and t.river_dist_at(q.x, q.y) > t.river_half_w + 4.0:
					poles.append(Vector3(q.x, 0, q.y))
					got = true
					break
			if not got:
				if poles.size() > 1:
					a.utility_line(poles, 7.0)
					n += poles.size()
				poles = []
		if poles.size() > 1:
			a.utility_line(poles, 7.0)
			n += poles.size()
	return n >= 4


func _lamps(fd: Dictionary, kind: String) -> bool:
	var key := str(fd.get("landmark", "capital"))
	a.landmark = key
	var lm := _lm(key)
	var pts := _road_side_points(key, float(lm.get("r", 50.0)) + 30.0, 12.0, 1.4)
	var n := mini(int(fd.get("count", 6)), pts.size())
	var poles: Array = []
	for i in n:
		a.lamp(pts[i], kind)
		t.occupy_rect(Vector2(pts[i].x, pts[i].z), 0.0, 0.4, 0.4)
		poles.append(pts[i])
	if kind == "electric" and poles.size() > 1:
		a.utility_line(poles, 8.0)
	return n > 0


# ------------------------------------------------------------------ 鉄道
func _railway(fd: Dictionary) -> bool:
	var ca := _lm(str(fd.get("landmark", "capital")))
	var cb := _lm(str(fd.get("to", "port")))
	if ca.is_empty() or cb.is_empty():
		return false
	var best = null
	var bd := INF
	for line in t.road_lines:
		var pts: PackedVector2Array = line["pts"]
		var e0: Vector2 = pts[0]
		var e1: Vector2 = pts[pts.size() - 1]
		var dd := minf(e0.distance_to(ca["center"]) + e1.distance_to(cb["center"]), e1.distance_to(ca["center"]) + e0.distance_to(cb["center"]))
		if dd < bd:
			bd = dd
			best = line
	if best == null:
		return false
	a.landmark = "roads"
	var pts2: PackedVector2Array = best["pts"]
	if pts2[0].distance_to(ca["center"]) > pts2[pts2.size() - 1].distance_to(ca["center"]):
		pts2.reverse()
	var off := float(best["w"]) + 4.5
	var track: Array = []       # 連続した線路の点 [Vector3]
	var runs: Array = []
	for k in range(0, pts2.size()):
		var d := (pts2[mini(k + 1, pts2.size() - 1)] - pts2[maxi(k - 1, 0)]).normalized()
		var q := pts2[k] + Vector2(d.y, -d.x) * off
		var free := not t.is_occupied(q.x, q.y) and not t.is_water(q.x, q.y) and t.river_dist_at(q.x, q.y) > t.river_half_w + 3.0
		if free:
			track.append(Vector3(q.x, t.height_at(q.x, q.y), q.y))
		elif track.size() > 1:
			runs.append(track)
			track = []
		else:
			track = []
	if track.size() > 1:
		runs.append(track)
	var total := 0.0
	var longest: Array = []
	for r in runs:
		_track(r)
		if r.size() > longest.size():
			longest = r
		for i in r.size() - 1:
			total += (r[i] as Vector3).distance_to(r[i + 1])
	if longest.size() < 3:
		return false
	# 都の側の端に停車場と機関車（1号機関車のような 1B タンク機関車と客車 2 両）
	var p0: Vector3 = longest[0]
	var p1: Vector3 = longest[mini(4, longest.size() - 1)]
	var dir := Vector2(p1.x - p0.x, p1.z - p0.z).normalized()
	var yaw := atan2(dir.x, dir.y)
	var mid: Vector3 = p0.lerp(p1, 0.5)
	_train(Transform3D(Basis(Vector3.UP, yaw), mid + Vector3(0, 0.25, 0)))
	var side := Vector3(dir.y, 0, -dir.x)
	var sxf := Transform3D(Basis(Vector3.UP, yaw - PI * 0.5), mid + side * 7.5)
	sxf.origin.y = t.height_at(sxf.origin.x, sxf.origin.z)
	var free_st := true
	for s in [Vector3(0, 0, 0), Vector3(6, 0, 0), Vector3(-6, 0, 0)]:
		var sp: Vector3 = sxf * s
		if t.is_occupied(sp.x, sp.z) or t.is_water(sp.x, sp.z):
			free_st = false
	if free_st:
		a.landmark = str(fd.get("landmark", "capital"))
		a.brick_building(sxf, 14.0, 8.0, 1, {"mat": "plaster", "col": Color(0.93, 0.9, 0.82), "trim": Color(0.55, 0.5, 0.45)})
		_sign(sxf * Vector3(0, 6.4, 4.3), yaw - PI * 0.5, "停車場", "", "board", 0.9)
		a.landmark = "roads"
	return total > 20.0


## 線路（狭軌 1067mm：1872 年の新橋－横浜から日本の標準）。道床・枕木・2 本のレール
func _track(pts: Array) -> void:
	for i in pts.size() - 1:
		var pa: Vector3 = pts[i]
		var pb: Vector3 = pts[i + 1]
		var L := Vector2(pb.x - pa.x, pb.z - pa.z).length()
		if L < 0.3:
			continue
		var d := Vector2(pb.x - pa.x, pb.z - pa.z) / L
		var yaw := atan2(d.x, d.y)
		var b := Basis(Vector3.UP, yaw)
		var side := Vector3(d.y, 0, -d.x)
		var midp := pa.lerp(pb, 0.5)
		a.kit.box("cobble", Transform3D(b, midp + Vector3(0, 0.05, 0)), Vector3(2.7, 0.3, L + 0.1), Color(0.72, 0.7, 0.66))
		var n := int(L / 0.9)
		for s in n:
			var q := pa.lerp(pb, (s + 0.5) / maxf(n, 1))
			a.kit.box("darkwood", Transform3D(b, q + Vector3(0, 0.24, 0)), Vector3(1.9, 0.12, 0.22), Color(0.55, 0.45, 0.36))
		for g in [-0.535, 0.535]:
			a.kit.rod("metal", pa + side * g + Vector3(0, 0.36, 0), pb + side * g + Vector3(0, 0.36, 0), 0.05, 4, Color(0.42, 0.4, 0.38))


func _train(xf: Transform3D) -> void:
	var blk := Color(0.12, 0.12, 0.13)
	var red := Color(0.62, 0.14, 0.1)
	var brass := Color(0.85, 0.65, 0.3)
	var loco := xf * Transform3D(Basis(), Vector3(0, 0, 6.0))
	# ボイラー（前が -Z）
	a.kit.cylinder("metal", loco * Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 1.9, -1.8)), 0.62, 0.62, 4.4, 12, blk)
	a.kit.cylinder("metal", loco * Transform3D(Basis(), Vector3(0, 2.4, -3.5)), 0.2, 0.3, 1.4, 8, blk)         # 煙突
	a.kit.cylinder("gold", loco * Transform3D(Basis(), Vector3(0, 2.45, -1.6)), 0.24, 0.2, 0.5, 8, brass)     # 蒸気ドーム
	a.kit.box("metal", loco * Transform3D(Basis(), Vector3(0, 0.95, -1.0)), Vector3(1.9, 0.35, 6.6), blk)    # 台枠
	a.kit.box("metal", loco * Transform3D(Basis(), Vector3(0, 0.75, -4.3)), Vector3(2.1, 0.3, 0.3), red)     # 緩衝梁
	a.kit.box("darkwood", loco * Transform3D(Basis(), Vector3(0, 2.1, 1.5)), Vector3(2.0, 1.9, 1.8), Color(0.3, 0.32, 0.3))   # 運転台
	a.kit.box("metal", loco * Transform3D(Basis(), Vector3(0, 3.15, 1.5)), Vector3(2.3, 0.12, 2.1), blk)
	for zz in [-3.0, -0.6, 1.2]:
		for sx in [-0.62, 0.62]:
			a.kit.cylinder("metal", loco * Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(sx + signf(sx) * 0.1, 0.62, zz)), 0.56 if zz > -2.0 else 0.4, 0.56 if zz > -2.0 else 0.4, 0.12, 12, red)
	a.col(loco, Vector3(0, 1.6, -1.0), Vector3(2.1, 3.0, 7.0))
	# 客車（木造 2 軸）
	for k in 2:
		var cxf: Transform3D = xf * Transform3D(Basis(), Vector3(0, 0, -2.4 - k * 7.6))
		a.kit.box("darkwood", cxf * Transform3D(Basis(), Vector3(0, 1.75, 0)), Vector3(2.2, 2.0, 6.8), Color(0.55, 0.3, 0.2))
		a.kit.box("metal", cxf * Transform3D(Basis(), Vector3(0, 2.85, 0)), Vector3(2.4, 0.18, 7.0), Color(0.25, 0.25, 0.25))
		for zz2 in [-2.4, -0.8, 0.8, 2.4]:
			for sx2 in [-1.12, 1.12]:
				a.kit.box("glass", cxf * Transform3D(Basis(), Vector3(sx2, 2.0, zz2)), Vector3(0.05, 0.7, 0.9), Color(0.7, 0.8, 0.85))
		for zz3 in [-2.2, 2.2]:
			for sx3 in [-0.62, 0.62]:
				a.kit.cylinder("metal", cxf * Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(sx3, 0.5, zz3)), 0.45, 0.45, 0.1, 10, blk)
		a.col(cxf, Vector3(0, 1.5, 0), Vector3(2.3, 2.9, 6.9))
	_smoke(loco * Vector3(0, 3.2, -3.5), 0.6)


# ------------------------------------------------------------------ 工場（器械製糸場：木骨煉瓦造・瓦屋根・煙突）
func _factories(fd: Dictionary) -> bool:
	var key := str(fd.get("landmark", "village"))
	var lm := _lm(key)
	var r := float(lm.get("r", 50.0))
	var n := 0
	for i in int(fd.get("count", 1)):
		var xf = _find_spot(key, 30.0, 12.0, r * 0.55, r + 45.0)
		if xf == null:
			continue
		a.landmark = key
		_silk_mill(xf)
		n += 1
	return n > 0


func _silk_mill(xf: Transform3D) -> void:
	var wd := 30.0
	var dp := 12.0
	var h := 7.2
	var brick := Color(1.0, 0.66, 0.55)
	var timber := Color(0.92, 0.9, 0.84)
	a.begin_unit("warehouse", xf, {"kind_detail": "silk_mill"})
	a.foundation(xf, wd + 0.4, dp + 0.4, 0.5, "stonewall", Color(0.82, 0.8, 0.76))
	a.bx("brick", xf, Vector3(0, 0.5 + h * 0.5, 0), Vector3(wd, h, dp), brick)
	# 木骨（柱・胴差し）を外に見せる
	var bays := 10
	for i in bays + 1:
		var x := -wd * 0.5 + wd * i / bays
		for sgn in [-1.0, 1.0]:
			a.bx("wood", xf, Vector3(x, 0.5 + h * 0.5, sgn * (dp * 0.5 + 0.06)), Vector3(0.32, h, 0.12), timber)
			if i < bays:
				var cx := x + wd / bays * 0.5
				for fy in [2.3, 5.6]:
					a.bx("glass", xf, Vector3(cx, 0.5 + fy, sgn * (dp * 0.5 + 0.08)), Vector3(1.4, 1.8, 0.06), Color(0.55, 0.62, 0.68))
	for sgn in [-1.0, 1.0]:
		a.bx("wood", xf, Vector3(0, 0.5 + h * 0.5, sgn * (dp * 0.5 + 0.06)), Vector3(wd, 0.28, 0.12), timber)
	a.bx("darkwood", xf, Vector3(0, 0.5 + 1.4, dp * 0.5 + 0.1), Vector3(2.4, 2.8, 0.1), Color(0.4, 0.3, 0.22))
	a.roof(xf, 0.5 + h, wd * 0.5 + 0.7, dp * 0.5 + 0.9, 2.8, "gable", "rooftile", Architecture.TILE_DARK, 0.0)
	a.col(xf, Vector3(0, 0.5 + h * 0.5, 0), Vector3(wd, h, dp))
	a.occupy(xf, wd + 1.0, dp + 1.0, 2.0)
	a.end_unit()
	# 煙突（煉瓦）
	var cxf: Transform3D = xf * Transform3D(Basis(), Vector3(wd * 0.5 + 5.0, 0, -dp * 0.2))
	cxf.origin.y = t.height_at(cxf.origin.x, cxf.origin.z) - 0.3
	_chimney(cxf, 24.0, 1.4, brick)


func _chimney(xf: Transform3D, h: float, r: float, colr: Color) -> void:
	a.begin_unit("tower", xf, {"kind_detail": "chimney"})
	a.bx("stonewall", xf, Vector3(0, 0.6, 0), Vector3(r * 2.6, 1.2, r * 2.6), Color(0.8, 0.78, 0.74))
	a.cyl("brick", xf, Vector3(0, 1.2, 0), r, r * 0.62, h, 12, colr)
	a.cyl("metal", xf, Vector3(0, 1.2 + h, 0), r * 0.7, r * 0.7, 0.5, 12, Color(0.2, 0.2, 0.2))
	a.col(xf, Vector3(0, h * 0.5, 0), Vector3(r * 1.8, h, r * 1.8))
	t.occupy_rect(Vector2(xf.origin.x, xf.origin.z), 0.0, r * 1.4, r * 1.4)
	a.end_unit()
	_smoke(xf * Vector3(0, h + 1.8, 0), r)


## 煙（GPUParticles、ワールドで最大 MAX_SMOKE 本）
func _smoke(pos: Vector3, scale: float) -> void:
	if smoke_n >= MAX_SMOKE:
		return
	smoke_n += 1
	var ps := GPUParticles3D.new()
	ps.name = "HistorySmoke"
	ps.amount = 18
	ps.lifetime = 7.0
	ps.preprocess = 7.0
	ps.visibility_aabb = AABB(Vector3(-20, -2, -20), Vector3(40, 40, 40))
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0.25, 1, 0)
	pm.spread = 12.0
	pm.initial_velocity_min = 1.2
	pm.initial_velocity_max = 2.0
	pm.gravity = Vector3(0.35, 0.25, 0.1)
	pm.scale_min = 1.2 * scale
	pm.scale_max = 2.0 * scale
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.5))
	curve.add_point(Vector2(1, 2.6))
	var ct := CurveTexture.new()
	ct.curve = curve
	pm.scale_curve = ct
	var grad := Gradient.new()
	grad.set_color(0, Color(0.42, 0.4, 0.4, 0.55))
	grad.set_color(1, Color(0.75, 0.75, 0.75, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = grad
	pm.color_ramp = gt
	ps.process_material = pm
	var qm := QuadMesh.new()
	qm.size = Vector2(2, 2)
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = _puff_tex()
	qm.material = mat
	ps.draw_pass_1 = qm
	ps.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ps.position = pos
	w.add_child(ps)


static var _puff: Texture2D


static func _puff_tex() -> Texture2D:
	if _puff == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		var gt := GradientTexture2D.new()
		gt.gradient = g
		gt.fill = GradientTexture2D.FILL_RADIAL
		gt.fill_from = Vector2(0.5, 0.5)
		gt.fill_to = Vector2(0.5, 0.0)
		gt.width = 64
		gt.height = 64
		_puff = gt
	return _puff


# ------------------------------------------------------------------ 製鉄所（高炉・熱風炉・煙突・鋳床）
func _steelworks(fd: Dictionary) -> bool:
	var key := str(fd.get("landmark", "port"))
	var lm := _lm(key)
	var r := float(lm.get("r", 40.0))
	var xf = _find_spot(key, 34.0, 18.0, r * 0.6, r + 60.0)
	if xf == null:
		return false
	a.landmark = key
	var dark := Color(0.28, 0.27, 0.27)
	var rust := Color(0.55, 0.32, 0.22)
	a.begin_unit("warehouse", xf, {"kind_detail": "steelworks"})
	a.foundation(xf, 34.4, 18.4, 0.4, "concrete", Color(0.7, 0.7, 0.68))
	# 鋳床の上屋
	a.bx("metal", xf, Vector3(6, 0.4 + 3.5, 0), Vector3(18, 7, 14), Color(0.5, 0.48, 0.46))
	a.roof(xf * Transform3D(Basis(), Vector3(6, 0, 0)), 0.4 + 7.0, 9.4, 7.4, 2.0, "gable", "rooftile", Color(0.35, 0.36, 0.38), 0.0)
	a.col(xf, Vector3(6, 4, 0), Vector3(18, 8, 14))
	a.occupy(xf, 35.0, 19.0, 2.0)
	a.end_unit()
	# 高炉（下すぼまりの塔＋斜めの装入橋）
	var bxf: Transform3D = xf * Transform3D(Basis(), Vector3(-10, 0.4, -2))
	a.begin_unit("tower", bxf, {"kind_detail": "blast_furnace"})
	a.cyl("metal", bxf, Vector3.ZERO, 3.2, 4.0, 6.0, 14, dark)
	a.cyl("metal", bxf, Vector3(0, 6, 0), 4.0, 2.6, 12.0, 14, rust)
	a.cyl("metal", bxf, Vector3(0, 18, 0), 2.6, 1.6, 3.0, 12, dark)
	a.cyl("metal", bxf, Vector3(0, 21, 0), 0.7, 0.7, 4.0, 8, dark)
	a.kit.rod("metal", bxf * Vector3(0, 19, 0), bxf * Vector3(0, 1, 14), 0.5, 6, Color(0.4, 0.38, 0.36))
	a.col(bxf, Vector3(0, 10, 0), Vector3(7, 20, 7))
	a.end_unit()
	# 熱風炉（ドームのついた円筒 3 基）
	for k in 3:
		var sxf: Transform3D = xf * Transform3D(Basis(), Vector3(-15.5 + k * 5.5, 0.4, 6.5))
		a.begin_unit("tower", sxf, {"kind_detail": "hot_blast_stove"})
		a.cyl("metal", sxf, Vector3.ZERO, 2.1, 2.1, 15.0, 12, Color(0.45, 0.44, 0.43))
		a.kit.sphere("metal", sxf * Transform3D(Basis().scaled(Vector3(1, 0.6, 1)), Vector3(0, 15, 0)), 2.1, 12, 6, Color(0.45, 0.44, 0.43))
		a.col(sxf, Vector3(0, 7.5, 0), Vector3(4, 15, 4))
		a.end_unit()
	var cxf: Transform3D = xf * Transform3D(Basis(), Vector3(15, 0, -6))
	cxf.origin.y = t.height_at(cxf.origin.x, cxf.origin.z) - 0.3
	_chimney(cxf, 32.0, 1.6, Color(0.85, 0.55, 0.45))
	return true


# ------------------------------------------------------------------ 建て替え（町家→洋館 / 洋館→町家）
## defs の中から kind・kind_detail が合うものを frac だけ選び、同じ敷地に新しい建物を建てて、元を消す予定に入れる
func _swap(defs: Array, landmarks: Array, kind: String, detail: String, to: String, frac: float) -> int:
	var n := 0
	var salt := hash(str(p.get("era", ""))) + 977
	for def in defs:
		if str(def["kind"]) != kind or not (str(def.get("landmark", "")) in landmarks):
			continue
		if str(def.get("opts", {}).get("kind_detail", "")) != detail:
			continue
		if int(def["id"]) in vanish_ids or not EraTimeline.ruin_pick(int(def["id"]), frac, salt):
			continue
		var fp := _footprint(def)
		if fp.is_empty():
			continue
		var xf: Transform3D = fp["xf"]
		var wd: float = fp["w"]
		var dp: float = fp["d"]
		if wd * dp > 320.0:
			continue   # 大きな官庁（太政官の時計塔など）は建て替えない
		a.landmark = str(def.get("landmark", ""))
		match to:
			"brick":
				var floors := 2 if rng.randf() < 0.75 else 3
				var opt := {"mansard": false}
				if rng.randf() < 0.35:
					opt = {"mat": "plaster", "col": Color(0.95, 0.93, 0.88), "trim": Color(0.78, 0.74, 0.68)}
				a.brick_building(xf, maxf(wd, 7.0), maxf(dp - 1.0, 7.0), floors, opt)
			"machiya":
				var k := maxi(1, int(round(wd / 6.5)))
				for i in k:
					var x := -wd * 0.5 + wd * (i + 0.5) / k
					a.machiya(xf * Transform3D(Basis(), Vector3(x, 0, 0)), wd / k - 0.3, minf(dp, 11.0), 2)
		vanish_ids.append(int(def["id"]))
		n += 1
	return n


## 建物の敷地（建物の向きの枠で、当たり判定の箱から）{xf: 中心・地面, w, d}
func _footprint(def: Dictionary) -> Dictionary:
	var xf0: Transform3D = def["xf"]
	var fr := Transform3D(Basis(Vector3.UP, xf0.basis.get_euler().y), xf0.origin)
	var inv := fr.affine_inverse()
	var mn := Vector3(INF, INF, INF)
	var mx := Vector3(-INF, -INF, -INF)
	for sh in def.get("shapes", []):
		var st: Transform3D = sh[0]
		var s: Vector3 = (sh[1] as Vector3) * 0.5
		for cx in [-1.0, 1.0]:
			for cz in [-1.0, 1.0]:
				var q: Vector3 = inv * (st * Vector3(s.x * cx, 0, s.z * cz))
				mn = mn.min(q)
				mx = mx.max(q)
	if mn.x == INF:
		return {}
	var c := Vector3((mn.x + mx.x) * 0.5, 0, (mn.z + mx.z) * 0.5)
	var out := fr * Transform3D(Basis(), c)
	return {"xf": out, "w": mx.x - mn.x, "d": mx.z - mn.z}


# ------------------------------------------------------------------ 港の艦隊（国際的地位が早く上がった世界）
func _navy(nv: Dictionary) -> bool:
	var lm := _lm("port")
	if lm.is_empty():
		return false
	var shore := 40.0
	for zz in range(0, 90):
		var q: Vector3 = lm["xf"] * Vector3(0, 0, zz)
		if t.height_at(q.x, q.z) < w.water_level + 0.6:
			shore = zz
			break
	a.landmark = "port"
	var taken: Array = []
	var yard := w.get_node_or_null("ShipYard")
	if yard != null:
		for pl in yard.get("placements"):
			taken.append((pl["xf"] as Transform3D).origin)
	var ex: Dictionary = nv.get("port_extra", {})
	# 増えた桟橋とクレーン
	for k in int(ex.get("piers", 0)):
		var x := -48.0 + k * 96.0
		var px: Transform3D = lm["xf"] * Transform3D(Basis(), Vector3(x, 0, shore - 5.0))
		var e: Vector3 = px.origin
		px.origin.y = w.water_level + 1.0
		if t.is_occupied(e.x, e.z):
			continue
		a.pier(px, 30.0, 7.0, "stone")
		if k < int(ex.get("cranes", 0)) and nv["kind"] != "galleon":
			_crane(lm["xf"] * Transform3D(Basis(), Vector3(x - 2.5, 0, shore + 4.0)))
	var placed := 0
	for i in int(nv.get("count", 1)):
		var lp := Vector3(-36.0 + i * 72.0 + rng.randf_range(-6, 6), 0, shore + 62.0 + i * 14.0)
		var sxf: Transform3D = lm["xf"] * Transform3D(Basis(Vector3.UP, PI * 0.5 + rng.randf_range(-0.2, 0.2)), lp)
		sxf.origin.y = w.water_level
		var clash := false
		for o in taken:
			if Vector2(o.x - sxf.origin.x, o.z - sxf.origin.z).length() < 55.0:
				clash = true
		if clash or not t.is_water(sxf.origin.x, sxf.origin.z):
			continue
		taken.append(sxf.origin)
		match str(nv["kind"]):
			"galleon": _galleon(sxf)
			"ironclad": _ironclad(sxf)
			_: _battleship(sxf)
		placed += 1
	return placed > 0


func _crane(xf: Transform3D) -> void:
	xf.origin.y = w.water_level + 1.8
	var col := Color(0.55, 0.3, 0.2)
	for cx in [-1.5, 1.5]:
		for cz in [-1.5, 1.5]:
			a.kit.box("metal", xf * Transform3D(Basis(), Vector3(cx, 5, cz)), Vector3(0.35, 10, 0.35), col)
	a.kit.box("metal", xf * Transform3D(Basis(), Vector3(0, 10.4, 4)), Vector3(1.0, 1.0, 14), col)
	a.kit.box("metal", xf * Transform3D(Basis(), Vector3(0, 10.0, -1)), Vector3(2.4, 2.2, 3.0), Color(0.3, 0.3, 0.3))
	a.kit.rod("wire", xf * Vector3(0, 10.0, 10.5), xf * Vector3(0, 4.0, 10.5), 0.04, 3, Color(0.1, 0.1, 0.1))


## 船体（前が -Z。水線が原点）：箱＋尖った舳先
func _hull(xf: Transform3D, L: float, B: float, H: float, colr: Color, deck: Color, mat := "metal") -> void:
	var body := L * 0.78
	a.kit.box(mat, xf * Transform3D(Basis(), Vector3(0, H * 0.5 - 1.2, L * 0.11)), Vector3(B, H, body), colr)
	var bow := xf * Transform3D(Basis(Vector3.UP, PI * 0.25), Vector3(0, H * 0.5 - 1.2, -L * 0.28))
	var s := B / sqrt(2.0)
	a.kit.box(mat, bow, Vector3(s, H, s), colr)
	a.kit.box("wood", xf * Transform3D(Basis(), Vector3(0, H - 1.15, L * 0.11)), Vector3(B - 0.4, 0.1, body - 0.4), deck)
	a.cols.append([xf * Transform3D(Basis(), Vector3(0, H * 0.5 - 1.2, 0)), Vector3(B, H, L * 0.9)])


func _galleon(xf: Transform3D) -> void:
	var hull := Color(0.42, 0.28, 0.18)
	_hull(xf, 42.0, 10.0, 6.0, hull, Color(0.75, 0.62, 0.45), "darkwood")
	a.kit.box("darkwood", xf * Transform3D(Basis(), Vector3(0, 6.6, 15.0)), Vector3(9.0, 3.2, 9.0), hull)    # 船尾楼
	a.kit.box("darkwood", xf * Transform3D(Basis(), Vector3(0, 5.6, -11.0)), Vector3(8.0, 1.6, 6.0), hull)   # 船首楼
	for m in [[-9.0, 26.0], [2.0, 30.0], [12.0, 20.0]]:
		var z: float = m[0]
		var h: float = m[1]
		a.kit.cylinder("wood", xf * Transform3D(Basis(), Vector3(0, 4.8, z)), 0.45, 0.25, h, 8, Color(0.6, 0.45, 0.3))
		for k in 2:
			var y := 4.8 + h * (0.35 + k * 0.33)
			a.kit.box("cloth", xf * Transform3D(Basis(), Vector3(0, y, z + 0.4)), Vector3(12.0 - k * 3.0, h * 0.26, 0.15), Color(0.95, 0.93, 0.86))
		a.kit.box("cloth", xf * Transform3D(Basis(), Vector3(0, 4.8 + h + 0.8, z)), Vector3(0.08, 1.2, 2.0), Color(0.85, 0.12, 0.1))


func _ironclad(xf: Transform3D) -> void:
	var blk := Color(0.15, 0.15, 0.16)
	_hull(xf, 58.0, 12.0, 6.0, blk, Color(0.7, 0.62, 0.5))
	a.kit.box("metal", xf * Transform3D(Basis(), Vector3(0, 6.2, 4.0)), Vector3(9.0, 2.6, 16.0), blk)            # 砲郭
	a.kit.cylinder("metal", xf * Transform3D(Basis(), Vector3(0, 7.5, 2.0)), 1.3, 1.3, 7.0, 12, Color(0.25, 0.22, 0.2))   # 煙突
	for z in [-14.0, 18.0]:
		a.kit.cylinder("wood", xf * Transform3D(Basis(), Vector3(0, 4.8, z)), 0.4, 0.25, 22.0, 8, Color(0.55, 0.42, 0.3))
	for k in 3:
		for sx in [-1.0, 1.0]:
			a.kit.rod("metal", xf * Vector3(sx * 4.4, 6.4, -2.0 + k * 5.0), xf * Vector3(sx * 6.6, 6.4, -2.0 + k * 5.0), 0.22, 6, blk)
	_smoke(xf * Vector3(0, 15.5, 2.0), 1.0)


func _battleship(xf: Transform3D) -> void:
	var grey := Color(0.55, 0.57, 0.6)
	_hull(xf, 84.0, 15.0, 7.0, grey, Color(0.72, 0.66, 0.56))
	a.kit.box("metal", xf * Transform3D(Basis(), Vector3(0, 7.8, 0)), Vector3(10.0, 3.0, 26.0), grey)          # 上部構造
	a.kit.box("metal", xf * Transform3D(Basis(), Vector3(0, 11.0, -9.0)), Vector3(6.0, 3.4, 5.0), grey)        # 艦橋
	for z in [-2.0, 6.0]:
		a.kit.cylinder("metal", xf * Transform3D(Basis(), Vector3(0, 9.3, z)), 1.5, 1.5, 7.0, 12, Color(0.4, 0.4, 0.42))
	for z in [-24.0, 26.0]:
		var txf := xf * Transform3D(Basis(Vector3.UP, 0.0 if z < 0 else PI), Vector3(0, 6.3, z))
		a.kit.cylinder("metal", txf, 3.4, 3.0, 2.2, 14, grey)
		for sx in [-0.7, 0.7]:
			a.kit.rod("metal", txf * Vector3(sx, 1.2, -2.5), txf * Vector3(sx, 1.5, -11.0), 0.28, 6, Color(0.45, 0.46, 0.48))
	for z in [-12.0, 12.0]:
		a.kit.cylinder("metal", xf * Transform3D(Basis(), Vector3(0, 9.0, z)), 0.35, 0.25, 22.0, 6, Color(0.4, 0.4, 0.42))
	_smoke(xf * Vector3(0, 17.0, 2.0), 1.1)


# ------------------------------------------------------------------ 看板
static func font(modern: bool) -> Font:
	var path := SIGN_FONT_MODERN if modern else SIGN_FONT
	if not _font_cache.has(path):
		_font_cache[path] = load(path) if ResourceLoader.exists(path) else null
	return _font_cache[path]


## 看板（立て札・高札・洋風の看板・横断幕）。pos は看板の中心、yaw は表の向き（+Z）
func _sign(pos: Vector3, yaw: float, title: String, sub: String, style: String, scale := 1.0) -> void:
	var b := Basis(Vector3.UP, yaw)
	var xf := Transform3D(b, pos)
	var wd := maxf(2.4, title.length() * 0.95 + 0.8) * scale
	var ht := (1.6 if sub != "" else 1.1) * scale
	var board_col := Color(0.92, 0.88, 0.78)
	var ink := Color(0.12, 0.1, 0.08)
	match style:
		"kosatsu":   # 高札（屋根つきの板）
			board_col = Color(0.88, 0.82, 0.68)
			a.kit.roof(xf * Transform3D(Basis(), Vector3(0, ht * 0.5 + 0.1, 0)), wd * 0.5 + 0.3, 0.45, 0.4, 1.0, "rooftile", "darkwood", Architecture.TILE_DARK, 1.0, 0.0, 0.12, Color(0.5, 0.4, 0.3), "darkwood", Color.WHITE)
		"banner":
			board_col = Color(0.95, 0.95, 0.92)
			ink = Color(0.75, 0.08, 0.06)
		"occupation":
			board_col = Color(0.95, 0.95, 0.9)
			ink = Color(0.1, 0.1, 0.12)
	a.kit.box("wood" if style != "occupation" else "metal", xf, Vector3(wd, ht, 0.12), board_col)
	if style != "banner":
		for sx in [-0.42, 0.42]:
			var g := t.height_at((xf * Vector3(sx * wd, 0, 0)).x, (xf * Vector3(sx * wd, 0, 0)).z)
			var top := xf * Vector3(sx * wd, ht * 0.5, -0.1)
			a.kit.rod("darkwood", Vector3(top.x, g - 0.2, top.z), top, 0.08 * scale, 6, Color(0.45, 0.35, 0.28))
	var lb := Label3D.new()
	lb.name = "HistorySign"
	lb.text = title + ("\n" + sub if sub != "" else "")
	lb.font = font(style in ["occupation", "board"])
	lb.font_size = 96
	lb.pixel_size = 0.0055 * scale
	lb.modulate = ink
	lb.outline_size = 0
	lb.shaded = false
	lb.double_sided = false
	lb.no_depth_test = false
	lb.fixed_size = false
	lb.line_spacing = -8.0
	lb.transform = xf * Transform3D(Basis(), Vector3(0, 0, 0.075))
	w.add_child(lb)


## 首都が別の町にある：都の広場に看板（江戸は高札、明治以後は庁舎の看板）
func _capital_sign(cp: Dictionary) -> void:
	var lm := _lm("capital")
	if lm.is_empty():
		return
	var pts := _road_side_points("capital", float(lm["r"]) * 0.7, 10.0, 2.5)
	var c: Vector3 = lm["pos"]
	var pos: Vector3 = pts[0] if not pts.is_empty() else c + Vector3(6, 0, 6)
	var yaw := atan2(c.x - pos.x, c.z - pos.z) + PI   # 表を道の側へ
	_sign(pos + Vector3(0, 1.9, 0), yaw, cp["text"], cp["sub"], cp["style"], 1.0)
	# のぼり（江戸）／旗（明治以後）
	if cp["style"] == "kosatsu":
		for k in 3:
			a.nobori(pos + Basis(Vector3.UP, yaw) * Vector3(-3.0 + k * 3.0, 0, -2.0), Color(0.15, 0.15, 0.18))


func _war_signs(ss: Dictionary, kind: String) -> void:
	var boards: Array = ss.get("boards", [])
	var bi := 0
	for key in ss.get("landmarks", []):
		var lm := _lm(str(key))
		if lm.is_empty() or boards.is_empty():
			continue
		var pts := _road_side_points(str(key), float(lm["r"]) + 10.0, 14.0, 2.2)
		var c: Vector3 = lm["pos"]
		for i in mini(2, pts.size()):
			var pos: Vector3 = pts[i * maxi(1, pts.size() / 2)] if i * maxi(1, pts.size() / 2) < pts.size() else pts[i]
			var yaw := atan2(c.x - pos.x, c.z - pos.z) + PI
			var bd: Array = boards[bi % boards.size()]
			bi += 1
			_sign(pos + Vector3(0, 2.0, 0), yaw, str(bd[0]), str(bd[1]), "occupation" if kind == "occupation" else "banner", 1.0)
			for fl in ss.get("flags", []):
				_flag(pos + Basis(Vector3.UP, yaw) * Vector3(3.2, 0, 0), str(fl))
				break


## 旗竿と旗（日章旗 / 星条旗＝占領期の進駐軍）
func _flag(pos: Vector3, kind: String) -> void:
	var g := t.height_at(pos.x, pos.z)
	var base := Vector3(pos.x, g, pos.z)
	a.kit.cylinder("metal", Transform3D(Basis(), base), 0.07, 0.05, 6.5, 6, Color(0.85, 0.85, 0.85))
	var fxf := Transform3D(Basis(), base + Vector3(0.95, 5.9, 0))
	match kind:
		"jp":
			a.kit.box("cloth", fxf, Vector3(1.8, 1.2, 0.04), Color(0.97, 0.97, 0.95))
			a.kit.cylinder("cloth", fxf * Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 0, 0.03)), 0.36, 0.36, 0.02, 16, Color(0.8, 0.08, 0.1))
		"us":
			for k in 7:
				a.kit.box("cloth", fxf * Transform3D(Basis(), Vector3(0, 0.6 - 0.09 - k * 0.172, 0)), Vector3(1.8, 0.172, 0.04), Color(0.75, 0.1, 0.12) if k % 2 == 0 else Color(0.97, 0.97, 0.95))
			a.kit.box("cloth", fxf * Transform3D(Basis(), Vector3(-0.5, 0.25, 0.03)), Vector3(0.8, 0.68, 0.02), Color(0.12, 0.16, 0.42))


# ================================================================== 組み上げの後（破壊システムの後：TimelineWorld.apply から）
static func after(w: Node3D) -> Dictionary:
	var stats := {"vanished": 0}
	var d = w.get("destruction")
	if d == null:
		return stats
	var units: Dictionary = d.get("units")
	var ids: Array = w.get_meta("hv_vanish", []) if w.has_meta("hv_vanish") else []
	for id in ids:
		if units.has(id) and not units[id].destroyed:
			TimelineWorld.vanish(w, units[id])
			stats["vanished"] += 1
	var p := profile_of(w)
	var salt := hash(str(p.get("era", ""))) + 4111
	for ab in HistoryVisuals.absent_for(p):
		var ad: Dictionary = ab["def"]
		if ad.has("swap"):
			continue
		var kinds: Array = HistoryVisuals._list(ad.get("kind", []))
		var lms: Array = HistoryVisuals._list(ad.get("landmark", []))
		for id in units:
			var u = units[id]
			if u.destroyed or not (str(u.kind) in kinds) or not (str(u.landmark) in lms):
				continue
			if EraTimeline.ruin_pick(int(id), float(ab["frac"]), salt):
				TimelineWorld.vanish(w, u)
				stats["vanished"] += 1
	return stats


## 昭和の被災（空襲）を戦争の帰趨で変える。rules = EraTimeline.ruin_rules の結果
static func ruin_rules(w: Node3D, rules: Array) -> Array:
	var p := profile_of(w)
	var wr: Dictionary = HistoryVisuals.war_for(p)
	if wr.is_empty():
		return rules
	var mult := float(wr.get("ruin_mult", 1.0))
	var out: Array = []
	for r in rules:
		if mult <= 0.0:
			break
		var r2: Dictionary = (r as Dictionary).duplicate()
		r2["frac"] = clampf(float(r.get("frac", 0.5)) * mult, 0.0, 0.95)
		out.append(r2)
	for r in wr.get("extra_ruin", []):
		out.append(r)
	return out
