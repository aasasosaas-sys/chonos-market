class_name Sfx
extends RefCounted
## 旧来の効果音 API（互換用）。各関数は音の key（assets/audio の SoundManifest）を返し、
## play / play_at / loop_player は Audio（scripts/audio/audio.gd）に渡す。新しいコードは Audio.play_at("key", pos) を直接使う。

static func shot() -> String: return "gun_rifle"
static func musket() -> String: return "gun_matchlock"
static func bow() -> String: return "bow_release"
static func energy() -> String: return "gun_energy"
static func hit() -> String: return "hit_punch"
static func explode() -> String: return "explosion_large"
static func pickup() -> String: return "pickup_item"
static func success() -> String: return "stinger_success"
static func fail() -> String: return "stinger_fail"
static func warp() -> String: return "time_warp"
static func engine() -> String: return "car_engine_loop"
static func propeller() -> String: return "plane_engine_loop"
static func hooves() -> String: return "hoof_dirt"
static func wind() -> String: return "amb_wind_light"
static func click() -> String: return "ui_tick"
static func crumble() -> String: return "break_plaster"
static func wood_break() -> String: return "break_wood"
static func tiles() -> String: return "break_tiles"
static func fire_loop() -> String: return "fire_loop"
static func cannon() -> String: return "cannon_fire"
static func fuse() -> String: return "fuse_loop"
static func splash() -> String: return "splash_big"
static func whoosh() -> String: return "swing_blade"
static func rocket() -> String: return "rocket_loop"


## 2D で鳴らす（tree は互換のため。使わない）
static func play(_tree: SceneTree, key: String, vol_db := 0.0) -> void:
	Audio.play(key, vol_db)


static func play_at(_tree: SceneTree, key: String, pos: Vector3, vol_db := 0.0) -> void:
	Audio.play_at(key, pos, vol_db)


## 鳴り続ける 3D の音（host の子。停止中で返す）
static func loop_player(host: Node3D, key: String, vol_db := -6.0) -> AudioStreamPlayer3D:
	return Audio.loop_at(host, key, vol_db)
