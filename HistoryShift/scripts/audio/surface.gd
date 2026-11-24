class_name Surface
extends RefCounted
## 足元の床材（足音・着地・蹄の音を選ぶ）。
## 真下へのレイの当たり → 当たったコリジョンから判定する:
##  1. CollisionShape3D / ボディの meta "surface"（Architecture の土台・段・PresentWorld などが付ける）
##  2. 船（ShipBody）→ Ship.surface_at（木造船は板、鋼船は上甲板の材・船内は鋼）
##  3. 内装（group "interior"）→ WorldInteriors.surface_at（畳・板の間・土間・石・リノリウム…）
##  4. 破壊ユニット（Destructible）→ その種類の材（木造は板、蔵・天守・石垣は石、格納庫は鋼）
##  5. 地形 → 制御マップ（道・広場は時代の舗装 dirt/sand/cobble/asphalt/concrete、田は泥、森・草地は草、岸は砂、急斜面は岩、昭和の山頂は雪）
##  水面の下に足があれば（海・川・池・堀）"water"。
## 値: dirt grass gravel sand stone wood tatami concrete metal water snow carpet mud

const ALL := ["dirt", "grass", "gravel", "sand", "stone", "wood", "tatami", "concrete", "metal", "water", "snow", "carpet", "mud"]
## 天気で言いかえた足音の床材（Footsteps.weather_surface）。雨で濡れた石・板・舗装、濡れた草
const WEATHER := ["wet", "wet_grass"]


## 建物の材質キー（WorldMaterials / MeshKit の mat）→ 床材
static func of_mat(mat: String) -> String:
	match mat:
		"stonewall", "rock", "cobble", "brick", "plaster":
			return "stone"
		"wood", "darkwood", "bamboo", "boards":
			return "wood"
		"tatami":
			return "tatami"
		"earth":
			return "dirt"
		"sand":
			return "sand"
		"grassmat":
			return "grass"
		"asphalt", "concrete", "flat":
			return "concrete"
		"metal", "steel":
			return "metal"
		"cloth":
			return "carpet"
	return ""


## 地形の舗装キー（EraStyles の road / plaza）→ 床材
static func of_paving(key: String) -> String:
	match key:
		"dirt":
			return "dirt"
		"sand":
			return "gravel"      # 寺社・御所の白砂利
		"cobble", "stonewall":
			return "stone"
		"asphalt", "concrete":
			return "concrete"
	return "dirt"


## 足元（pos は足の位置）の床材。exclude はレイから外すもの（自分のボディ）
static func at(pos: Vector3, space: PhysicsDirectSpaceState3D, exclude: Array = []) -> String:
	if space == null:
		return terrain_at(Game.world, pos)
	var q := PhysicsRayQueryParameters3D.create(pos + Vector3.UP * 0.5, pos + Vector3.DOWN * 1.2,
		Game.COLLISION_WORLD | Game.COLLISION_VEHICLE | Game.COLLISION_PROP)
	q.exclude = exclude
	q.hit_back_faces = false
	var hit := space.intersect_ray(q)
	var w = Game.world
	if water_at(w, pos):
		return "water"
	if not hit.is_empty() and hit.get("collider") is ShipBody:
		return from_hit(hit, w)
	# 建物の中なら内装の床（土台・地形より優先）
	if w != null and is_instance_valid(w) and w.has_method("interior_at"):
		var id: int = w.interior_at(pos + Vector3.UP * 0.3)
		if id >= 0:
			return String(w.interiors.surface_at(id, pos))
	if hit.is_empty():
		return terrain_at(w, pos)
	return from_hit(hit, w)


## レイの当たりから
static func from_hit(hit: Dictionary, w) -> String:
	var col: Object = hit.get("collider")
	var p: Vector3 = hit.get("position", Vector3.ZERO)
	if col == null:
		return terrain_at(w, p)
	# 1. 形ごと・ボディの meta
	if col is CollisionObject3D:
		var co := col as CollisionObject3D
		var sidx := int(hit.get("shape", 0))
		var owner_id := co.shape_find_owner(sidx) if sidx >= 0 else -1
		if owner_id >= 0:
			var sh = co.shape_owner_get_owner(owner_id)
			if sh is Node and (sh as Node).has_meta("surface"):
				var s := String((sh as Node).get_meta("surface"))
				if s != "":
					return s
		if co.has_meta("surface"):
			return String(co.get_meta("surface"))
	# 2. 船
	if col is ShipBody:
		var ship = (col as ShipBody).ship
		if ship and is_instance_valid(ship) and ship.has_method("surface_at"):
			return String(ship.surface_at(p))
		return "wood"
	if col is Node:
		var n := col as Node
		# 3. 内装
		if n.is_in_group("interior"):
			var wi = w.get("interiors") if w else null
			if wi and is_instance_valid(wi):
				var id: int = wi.inside_at(p + Vector3.UP * 0.3)
				if id >= 0:
					return String(wi.surface_at(id, p))
			return "wood"
		# 4. 破壊ユニット
		if n.is_in_group("destructible") and n.get("cfg") is Dictionary:
			return unit_surface(String(n.get("kind")), String((n.get("cfg") as Dictionary).get("mat", "wood")))
		if n.is_in_group("vehicle"):
			return "wood" if String(n.get("kind")) in ["horse", "boat"] else "metal"
		if n.name == "TerrainBody":
			return terrain_at(w, p)
		if n is RigidBody3D or n.is_in_group("physics_prop"):
			return "wood"
		if w and n == w.get("static_body"):
			return "stone"
	return terrain_at(w, p)


static func unit_surface(kind: String, mat: String) -> String:
	if kind in ["bridge", "boat", "house", "hall", "gate", "tower", "school", "stall", "fence"]:
		return "wood"
	match mat:
		"wood":
			return "wood"
		"plaster", "stone", "brick":
			return "stone"
		"metal":
			return "metal"
	return "wood"


## 地形の材（EraWorld の TerrainGen の制御マップ）
static func terrain_at(w, p: Vector3) -> String:
	if w == null or not is_instance_valid(w) or w.get("terrain") == null:
		return "concrete" if (w != null and is_instance_valid(w) and w.has_method("in_lab")) else "dirt"
	var t: TerrainGen = w.terrain
	if absf(p.x) > t.half or absf(p.z) > t.half:
		return "grass"
	var st: Dictionary = w.get("style") if w.get("style") is Dictionary else {}
	var road := t.mask_at(t.road, p.x, p.z)
	if road > 0.45:
		return of_paving(String(st.get("road", "dirt")))
	var plaza := t.mask_at(t.plaza, p.x, p.z)
	if plaza > 0.45:
		return of_paving(String(st.get("plaza", "dirt")))
	var wl: float = w.get("water_level") if w.get("water_level") != null else 0.0
	var h := t.height_at(p.x, p.z)
	# 雪（昭和の山の頂: terrain シェーダの snow_height と同じ）
	if String(w.get("era_id")) == "showa" and h > 125.0:
		return "snow"
	if h < wl + 2.0:
		return "sand"
	if t.normal_at(p.x, p.z).y < 0.62:
		return "gravel"            # 急斜面の岩・ガレ場
	if t.mask_at(t.field, p.x, p.z) > 0.55:
		return "mud"               # 田
	if road > 0.2 or plaza > 0.2:
		return "dirt"
	return "grass"


## 足が水面の下か（海・川・池・堀）。浅瀬の足音・着水用
static func water_at(w, p: Vector3) -> bool:
	if w == null or not is_instance_valid(w) or w.get("terrain") == null:
		return false
	var t: TerrainGen = w.terrain
	var wl: float = w.get("water_level") if w.get("water_level") != null else 0.0
	if p.y < wl + 0.05 and t.height_at(p.x, p.z) < wl + 0.02:
		return true
	if t.river_pts.size() > 1 and t.river_dist_at(p.x, p.z) < t.river_half_w + 0.5:
		if p.y < t.river_surface_near(Vector2(p.x, p.z)) + 0.05:
			return true
	var rects = w.get("water_rects")
	if rects is Array:
		for r in rects:
			var c: Vector3 = r[0]
			if p.y > c.y + 0.05 or p.y < c.y - 3.0:
				continue
			var lp := Vector2(p.x - c.x, p.z - c.z).rotated(float(r[2]))
			var sz: Vector2 = r[1]
			if absf(lp.x) < sz.x * 0.5 and absf(lp.y) < sz.y * 0.5:
				return true
	return false
