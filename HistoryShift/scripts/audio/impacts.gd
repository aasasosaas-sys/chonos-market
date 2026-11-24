class_name Impacts
extends RefCounted
## 弾・矢が当たった所の音（当たった物の材質。地形・建物・内装・船は Surface と同じ判定）。


## 弾（hit = intersect_ray の結果）
static func bullet_key(hit: Dictionary, w) -> String:
	var col: Object = hit.get("collider")
	if col is Node:
		var n := col as Node
		var tgt: Node = Effects.find_target(n)
		if tgt and (tgt.has_method("is_enemy") or tgt.has_method("panic") or tgt is Player):
			return "impact_flesh"
		if tgt and tgt.is_in_group("vehicle"):
			match String(tgt.get("kind")):
				"horse":
					return "impact_flesh"
				"boat":
					return "impact_wood"
			return "impact_metal"
		if tgt is Explosive or n is RigidBody3D or n.is_in_group("physics_prop"):
			return "impact_plank"
		if n.is_in_group("destructible") and n.get("cfg") is Dictionary:
			match String((n.get("cfg") as Dictionary).get("mat", "wood")):
				"wood":
					return "impact_wood"
				"metal":
					return "impact_metal"
				"plaster":
					return "impact_dirt"
			return "impact_stone"
	return of_surface(Surface.from_hit(hit, w))


static func of_surface(s: String) -> String:
	match s:
		"wood", "tatami", "carpet":
			return "impact_wood"
		"stone", "concrete":
			return "impact_stone"
		"metal":
			return "impact_metal"
		"water":
			return "splash_small"
	return "impact_dirt"


## 矢：木に刺さる音（他は弾と同じ材質の音）
static func arrow_key(hit: Dictionary, w) -> String:
	var k := bullet_key(hit, w)
	return "arrow_hit_wood" if k in ["impact_wood", "impact_plank", "impact_dirt"] else k
