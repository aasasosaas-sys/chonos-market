class_name Projectile
extends Node3D
## 敵の飛び道具（矢・鉄砲玉・小銃弾・機銃弾・エネルギー弾）。避けられる実体弾。

var vel := Vector3.ZERO
var gravity := 0.0
var damage := 10.0
var team := 1
var life := 4.0
var homing := 0.0
var kind := ""
var _whizzed := false
var _mesh: MeshInstance3D


static func fire(tree: SceneTree, from: Vector3, dir: Vector3, kind: String, team := 1) -> Projectile:
	var p := Projectile.new()
	p.team = team
	p.kind = kind
	var c := Color(1, 0.8, 0.4)
	var size := Vector3(0.05, 0.05, 0.6)
	var spd := 160.0
	match kind:
		"bow":
			spd = 42.0; p.gravity = 6.0; p.damage = 11.0; c = Color(0.55, 0.4, 0.25); size = Vector3(0.03, 0.03, 0.9)
		"musket":
			spd = 170.0; p.damage = 20.0; size = Vector3(0.06, 0.06, 0.8)
		"rifle":
			spd = 210.0; p.damage = 14.0
		"mg":
			spd = 230.0; p.damage = 7.0
		"energy":
			spd = 46.0; p.damage = 10.0; p.homing = 1.2; c = Effects.GUARD; size = Vector3(0.22, 0.22, 0.7)
		"air":
			spd = 260.0; p.damage = 9.0
	p.vel = dir.normalized() * spd
	p._mesh = MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	p._mesh.mesh = bm
	p._mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p._mesh.material_override = Humanoid.mat(c, 0.7) if kind == "bow" else Effects.emissive(c, 5.0)
	p.add_child(p._mesh)
	var root := tree.current_scene if tree.current_scene else tree.root
	var sess = tree.get_first_node_in_group("session")
	(sess if sess else root).add_child(p)
	p.global_position = from
	p._orient()
	return p


func _orient() -> void:
	if vel.length_squared() > 0.01 and absf(vel.normalized().dot(Vector3.UP)) < 0.999:
		look_at(global_position + vel, Vector3.UP)


func _physics_process(dt: float) -> void:
	life -= dt
	if life <= 0.0:
		queue_free()
		return
	if homing > 0.0 and Game.player:
		var to: Vector3 = (Game.player.global_position + Vector3.UP * 1.2 - global_position).normalized()
		vel = vel.lerp(to * vel.length(), clampf(homing * dt, 0, 1))
	vel.y -= gravity * dt
	var from := global_position
	var to2 := from + vel * dt
	var q := PhysicsRayQueryParameters3D.create(from, to2, Game.COLLISION_WORLD | Game.COLLISION_PLAYER | Game.COLLISION_VEHICLE | Game.COLLISION_PROP | Game.COLLISION_CIVILIAN)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		var tgt: Node = Effects.find_target(hit["collider"] as Node) if hit["collider"] is Node else null
		if kind == "bow":
			Player.apply_hit(get_tree(), hit, vel.normalized(), damage, team, false)
			Audio.play_at("impact_flesh" if tgt is Player else Impacts.arrow_key(hit, Game.world), hit["position"], 0.0)
		else:
			Player.apply_hit(get_tree(), hit, vel.normalized(), damage, team)
		queue_free()
		return
	# 至近を通り過ぎた弾・矢（ひゅん）
	if not _whizzed and team != 0 and Game.player != null and is_instance_valid(Game.player):
		var pp: Vector3 = (Game.player as Node3D).global_position + Vector3.UP * 1.5
		var seg := to2 - from
		var tq := clampf((pp - from).dot(seg) / maxf(seg.length_squared(), 1e-6), 0.0, 1.0)
		var cp := from + seg * tq
		if cp.distance_to(pp) < 3.0 and tq > 0.0 and tq < 1.0:
			_whizzed = true
			Audio.play_at("arrow_whiz" if kind == "bow" else "bullet_whiz", cp, 0.0)
	global_position = to2
	_orient()
