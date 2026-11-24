class_name SoundBank
extends RefCounted
## 音の表（SoundManifest：tools/audio/build.py が生成）から AudioStream を引く。
## key ごとに複数のバリエーションがあり、pick() は直前と同じものを避けてランダムに選ぶ。
## ループ音（環境音・エンジン・火）は読み込み時に loop を立てる。

static var _streams := {}      # key -> Array[AudioStream]
static var _last := {}         # key -> 直前に選んだ番号
static var _rng := RandomNumberGenerator.new()


static func has(key: String) -> bool:
	return SoundManifest.SOUNDS.has(key)


static func info(key: String) -> Dictionary:
	return SoundManifest.SOUNDS.get(key, {})


static func keys() -> Array:
	return SoundManifest.SOUNDS.keys()


static func is_loop(key: String) -> bool:
	return bool(info(key).get("loop", false))


static func base_db(key: String) -> float:
	return float(info(key).get("db", 0.0))


static func bus(key: String) -> String:
	return String(info(key).get("bus", "SFX"))


static func length(key: String) -> float:
	return float(info(key).get("len", 1.0))


## key のすべてのバリエーション（読み込みは初回だけ）
static func streams(key: String) -> Array:
	if _streams.has(key):
		return _streams[key]
	var out: Array = []
	var inf := info(key)
	var loop: bool = inf.get("loop", false)
	for f in inf.get("files", []):
		var path := String(f)
		if not ResourceLoader.exists(path):
			continue
		var s := load(path) as AudioStream
		if s == null:
			continue
		if loop:
			if s is AudioStreamOggVorbis:
				(s as AudioStreamOggVorbis).loop = true
			elif s is AudioStreamWAV:
				(s as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD
		out.append(s)
	_streams[key] = out
	return out


## ランダムなバリエーション（無ければ null）
static func pick(key: String) -> AudioStream:
	var arr := streams(key)
	if arr.is_empty():
		return null
	if arr.size() == 1:
		return arr[0]
	var last: int = _last.get(key, -1)
	var i := _rng.randi_range(0, arr.size() - 1)
	if i == last:
		i = (i + 1 + _rng.randi_range(0, arr.size() - 2)) % arr.size()
	_last[key] = i
	return arr[i]
