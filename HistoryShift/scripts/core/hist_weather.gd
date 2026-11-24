class_name HistWeather
extends RefCounted
## 史実の天気（data/weather/）。時代・年・日付・場所 → その日の天気の状態。
## 層（どこまで遡れるか）:
##  1. 有名な日（famous_days.json）: 同時代の記録・観測・報道で天気が分かる日（verdict と出典つき）。apply=false は上書きしない
##  2. 気候値（regions.json）: 地点の月別の平年値（気象庁 1991〜2020年）から、その日の天気を決まった乱数で生成する
##  3. 代理指標による補正（eras.json の periods / anomalies）: 京都の桜の満開日による3月の気温の復元、年輪の酸素同位体比、
##     諏訪湖の御神渡り、飢饉の年の冷夏・長雨（寛喜・天明・天保）。気温を下げれば雪も増える
## 状態（Dictionary）: kind（clear cloudy overcast rain heavy_rain thunder typhoon snow fog）・rain snow fog cloud storm（0〜1）・
##   wind（m/s）・wind_from（度。北=0 東=90）・thunder（0〜1）・hail・temp（℃）・snow_cover・wet（地面）・ash・dust・night・tsuyu・
##   source（record / climatology）・basis・famous（有名な日の記録）・date（date_for の結果）
## Game を参照しない（-s で走るテストからも使える）。ゲームの側（武器・敵・乗り物）は live（WeatherDirector が毎フレーム書く）を読む。

const DIR := "res://data/weather"
const KINDS := ["clear", "cloudy", "overcast", "rain", "heavy_rain", "thunder", "typhoon", "snow", "fog"]
const LABEL := {"clear": "晴", "cloudy": "曇", "overcast": "曇", "rain": "雨", "heavy_rain": "大雨", "thunder": "雷雨",
	"typhoon": "台風", "snow": "雪", "fog": "霧"}
const DAYS_IN_MONTH := [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]

static var _regions := {}
static var _eras := {}
static var _famous: Array = []
static var _loaded := false
## いまの天気（WeatherDirector が毎フレーム更新。無ければ晴れ）。ゲームの側はこれを読む
static var live := {}
## テスト・写真用：次の Session の天気をこれで上書き（{} で無効）
static var force := {}


static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	var r: Variant = _json("regions.json")
	if r is Dictionary:
		_regions = (r as Dictionary).get("regions", {})
	var e: Variant = _json("eras.json")
	if e is Dictionary:
		_eras = e
	var f: Variant = _json("famous_days.json")
	if f is Dictionary:
		_famous = (f as Dictionary).get("days", [])
		for d in _famous:
			d["jd"] = _entry_jd(d)


static func _json(name: String) -> Variant:
	var p := DIR.path_join(name)
	if not FileAccess.file_exists(p):
		return null
	return JSON.parse_string(FileAccess.get_file_as_string(p))


static func reload() -> void:
	_loaded = false
	_load()


static func famous_days() -> Array:
	_load()
	return _famous


static func region(id: String) -> Dictionary:
	_load()
	return _regions.get(id, _regions.get("kyoto", {}))


static func _entry_jd(d: Dictionary) -> int:
	if d.has("lunar"):
		var l: Array = d["lunar"]
		return Kyureki.lunar_to_jd(int(l[0]), int(l[1]), int(l[2]), bool(l[3]) if l.size() > 3 else false)
	if d.has("date"):
		var g: Array = d["date"]
		return Kyureki.jd_from_western(int(g[0]), int(g[1]), int(g[2]))
	return -1


# ================================================================== 日付
## 時代の中の年 → ゲームの日付。時点の日付（eras.json の points：事件の日）・なければ時代の代表の季節
## {jd, western{y,m,d,cal}, text（西暦の表示）, lunar{year,month,day,leap}, lunar_text, doy（季節の日）, region, label, basis, exact}
static func date_for(era_id: String, year: int) -> Dictionary:
	_load()
	var ed: Dictionary = (_eras.get("eras", {}) as Dictionary).get(era_id, {})
	var reg := str(ed.get("region", "kyoto"))
	var pt: Dictionary = ((_eras.get("points", {}) as Dictionary).get(era_id, {}) as Dictionary).get(str(year), {})
	var jd := -1
	var exact := false
	if pt.has("lunar") or pt.has("date"):
		jd = _entry_jd(pt)
		exact = jd > 0
	if pt.has("region"):
		reg = str(pt["region"])
	if jd < 0:
		# その年の有名な日（既定にするもの）
		for f in famous_days():
			if str(f.get("era", "")) == era_id and int(f.get("year", 0)) == year and bool(f.get("default", true)) and int(f.get("jd", -1)) > 0:
				jd = int(f["jd"])
				reg = str(f.get("region", reg))
				exact = true
				break
	if jd < 0:
		var s: Array = ed.get("season", [6, 1])
		var y := year if year != 0 else 1700
		jd = Kyureki.jd_from_gregorian(y, int(s[0]), int(s[1]))   # 季節の代表日は先発グレゴリオ暦（太陽の位置で決める）
	return make_date(jd, reg, str(pt.get("label", "")), str(pt.get("basis", "")), exact)


static func make_date(jd: int, reg: String, label := "", basis := "", exact := false) -> Dictionary:
	var w := Kyureki.western_from_jd(jd)
	var l := Kyureki.jd_to_lunar(jd) if int(w["y"]) > -2000 else {}
	return {"jd": jd, "western": w, "text": Kyureki.western_text(jd), "lunar": l,
		"lunar_text": Kyureki.lunar_text(int(l.get("month", 1)), int(l.get("day", 1)), bool(l.get("leap", false))) if not l.is_empty() else "",
		"doy": Kyureki.season_doy(jd), "region": reg, "label": label, "basis": basis, "exact": exact}


## 季節の月（1〜12、小数。15 日が月の真ん中）
static func season_month(doy: int) -> float:
	var acc := 0
	for i in 12:
		var n: int = DAYS_IN_MONTH[i]
		if doy <= acc + n:
			return float(i) + (float(doy - acc) - 0.5) / float(n)
		acc += n
	return 11.99


## 月の値を季節の日で補間（月の中ほどが平年値）
static func clim(reg: Dictionary, key: String, doy: int) -> float:
	var arr: Array = reg.get(key, [])
	if arr.size() != 12:
		return 0.0
	var mf := season_month(doy) - 0.5
	var i0 := int(floor(mf))
	var t := mf - float(i0)
	return lerpf(float(arr[posmod(i0, 12)]), float(arr[posmod(i0 + 1, 12)]), t)


static func month_of(doy: int) -> int:
	return int(season_month(doy)) + 1


# ================================================================== 代理指標による補正
static func period_adjust(reg_id: String, year: int, month: int) -> Dictionary:
	_load()
	var out := {"dT": 0.0, "wet": 1.0, "fog_mult": 1.0, "basis": [], "confidence": "high"}
	if year == 0:
		return out
	for p in _eras.get("periods", []):
		if reg_id in (p.get("regions", []) as Array) and year >= int(p["from"]) and year < int(p["to"]):
			out["dT"] = float(out["dT"]) + float(p.get("dT", 0.0))
			out["wet"] = float(out["wet"]) * float(p.get("wet", 1.0))
			(out["basis"] as Array).append(str(p.get("basis", "")))
			out["confidence"] = str(p.get("confidence", "low"))
	for p in _eras.get("fog_mult", []):
		if year >= int(p["from"]) and year < int(p["to"]):
			out["fog_mult"] = float(p.get("mult", 1.0))
	for a in _eras.get("anomalies", []):
		if reg_id in (a.get("regions", []) as Array) and year >= int(a["from"]) and year <= int(a["to"]) and (a.get("months", []) as Array).map(func(x): return int(x)).has(month):
			out["dT"] = float(out["dT"]) + float(a.get("dT", 0.0))
			out["wet"] = float(out["wet"]) * float(a.get("wet", 1.0))
			(out["basis"] as Array).append(str(a.get("basis", "")))
	return out


# ================================================================== その日の天気（気候値から生成）
static func _h01(a: int, b: int) -> float:
	return float(absi(hash([a, b])) % 100000) / 100000.0


## 日をまたいで滑らかにつながる値（天気図の移り変わり：数日周期）
static func _vnoise(seed: int, x: float) -> float:
	var i := int(floor(x))
	var t := x - float(i)
	t = t * t * (3.0 - 2.0 * t)
	return lerpf(_h01(seed, i), _h01(seed, i + 1), t)


## 滑らかな値の分布は真ん中に寄るので、経験分布で一様（0〜1）に直す（雨の日の割合を平年値に合わせるため）
static var _cdf := PackedFloat32Array()


static func _uniform(v: float) -> float:
	if _cdf.is_empty():
		var arr: Array = []
		for i in 4000:
			arr.append(_vnoise(977, float(i) * 0.731) * 0.75 + _h01(991, i) * 0.25)
		arr.sort()
		_cdf = PackedFloat32Array(arr)
	var lo := 0
	var hi := _cdf.size() - 1
	while lo < hi:
		var mid := (lo + hi) / 2
		if _cdf[mid] < v:
			lo = mid + 1
		else:
			hi = mid
	return float(lo) / float(_cdf.size())


## 地面の雪・濡れを含まない、その日だけの天気
static func _raw_day(reg_id: String, jd: int, year: int) -> Dictionary:
	var reg := region(reg_id)
	var doy := Kyureki.season_doy(jd)
	var month := month_of(doy)
	var adj := period_adjust(reg_id, year, month)
	var dim: float = DAYS_IN_MONTH[month - 1]
	var seed := hash(reg_id) & 0xffff
	var temp := clim(reg, "temp", doy) + float(adj["dT"]) + (_vnoise(seed + 11, float(jd) / 4.0) - 0.5) * 6.0
	var p_rain := clampf(clim(reg, "rain_days", doy) / dim * float(adj["wet"]), 0.02, 0.85)
	var tsuyu := in_tsuyu(reg, doy)
	if tsuyu:
		p_rain = maxf(p_rain, 0.6)
	# 天気図の移り変わり（高気圧と低気圧が数日ごとに通る）＋その日の揺らぎ
	var v := _uniform(_vnoise(seed, float(jd) / 3.2) * 0.75 + _h01(seed + 3, jd) * 0.25)
	var st := {"kind": "clear", "rain": 0.0, "snow": 0.0, "fog": 0.0, "cloud": 0.0, "storm": 0.0, "thunder": 0.0, "hail": false,
		"temp": snappedf(temp, 0.1), "wind": clim(reg, "wind", doy), "wind_from": _wind_from(month, reg_id), "tsuyu": tsuyu,
		"ash": 0.0, "dust": 0.0, "night": false}
	var wet_thr := 1.0 - p_rain
	# 台風（接近数の平年値。1 つの接近で 2 日ほど影響）
	var p_ty := clim(reg, "typhoon", doy) * 2.0 / dim
	if p_ty > 0.0 and _vnoise(seed + 7, float(jd) / 2.0) > 1.0 - p_ty:
		st.merge({"kind": "typhoon", "rain": 0.9, "cloud": 1.0, "storm": 1.0, "wind": 20.0 + _h01(seed + 9, jd) * 10.0, "wind_from": 135.0}, true)
		return st
	if v > wet_thr:
		var k := (v - wet_thr) / maxf(p_rain, 0.01)          # 0〜1：雨の強さ
		var mm := clim(reg, "precip", doy) / maxf(clim(reg, "rain_days", doy), 1.0)
		var heavy := k > 0.72 and mm > 11.0 and not tsuyu
		# 降水の日は寒気が入りやすい（冬の南岸低気圧）。日平均気温 1.5℃ 以下ならほぼ雪、5.5℃ 以上なら雨
		var snow_p := clampf((5.5 - (temp - (1.0 if month in [12, 1, 2, 3] else 0.0))) / 4.0, 0.0, 1.0)
		st["cloud"] = 1.0
		if _h01(seed + 5, jd) < snow_p:
			st["kind"] = "snow"
			st["snow"] = clampf(0.3 + k * 0.7, 0.0, 1.0)
		else:
			var p_th := clim(reg, "thunder_days", doy) / maxf(clim(reg, "rain_days", doy), 1.0)
			if _h01(seed + 6, jd) < p_th * 1.1 and temp > 12.0:
				st["kind"] = "thunder"
				st["rain"] = clampf(0.6 + k * 0.4, 0.0, 1.0)
				st["thunder"] = 1.0
				st["storm"] = 0.7
			elif heavy:
				st["kind"] = "heavy_rain"
				st["rain"] = 0.9
				st["storm"] = 0.45
			else:
				st["kind"] = "rain"
				st["rain"] = clampf(0.25 + k * 0.5, 0.0, 0.7) * (0.8 if tsuyu else 1.0)
				st["storm"] = 0.1
		st["wind"] = float(st["wind"]) * (1.3 + float(st["storm"]))
		return st
	# 降らない日：雲の量と霧
	var c := clampf(v / maxf(wet_thr, 0.01), 0.0, 1.0)
	st["cloud"] = snappedf(c * (0.75 if month in [1, 2, 12] and reg_id == "tokyo" else 1.0), 0.01)   # 冬の太平洋側は乾いた晴天
	st["kind"] = "clear" if c < 0.6 else ("cloudy" if c < 0.88 else "overcast")
	var p_fog := clim(reg, "fog_days", doy) / dim * float(adj["fog_mult"])
	if _h01(seed + 4, jd) < p_fog * 1.2:
		st["kind"] = "fog"
		st["fog"] = 0.55 + _h01(seed + 8, jd) * 0.4
		st["wind"] = float(st["wind"]) * 0.4
	return st


static func in_tsuyu(reg: Dictionary, doy: int) -> bool:
	var ts: Array = reg.get("tsuyu", [])
	if ts.size() != 2:
		return false
	var a := _doy(int(ts[0][0]), int(ts[0][1]))
	var b := _doy(int(ts[1][0]), int(ts[1][1]))
	return doy >= a and doy <= b


static func _doy(m: int, d: int) -> int:
	var n := d
	for i in m - 1:
		n += int(DAYS_IN_MONTH[i])
	return n


## 風の吹いてくる方位（度）: 冬は北西の季節風、夏は南寄り
static func _wind_from(month: int, reg_id: String) -> float:
	if month in [11, 12, 1, 2, 3]:
		return 315.0
	if month in [6, 7, 8]:
		return 180.0 if reg_id != "fukuoka" else 225.0
	return 90.0 if month in [4, 5, 9, 10] and reg_id == "tokyo" else 250.0


## 気候値から：その日の天気＋前の日々からの地面（積雪・濡れ）
static func day_weather(reg_id: String, jd: int, year: int) -> Dictionary:
	var st := _raw_day(reg_id, jd, year)
	var cover := 0.0
	var wet := 0.0
	for back in range(12, 0, -1):
		var d := _raw_day(reg_id, jd - back, year)
		if str(d["kind"]) == "snow":
			cover += 0.22 * float(d["snow"])
		cover = maxf(0.0, cover - maxf(0.0, float(d["temp"]) - 1.0) * 0.06)
		if back <= 2:
			wet = maxf(wet, float(d["rain"]) * (0.55 if back == 1 else 0.25))
	if str(st["kind"]) == "snow":
		cover += 0.25 * float(st["snow"])
	st["snow_cover"] = snappedf(clampf(cover, 0.0, 1.0), 0.01)
	st["wet"] = snappedf(clampf(maxf(wet, float(st["rain"])), 0.0, 1.0), 0.01)
	st["source"] = "climatology"
	return st


# ================================================================== その日（有名な日の上書きを含む）
## 有名な日（その日・その時代の記録）。無ければ {}
static func famous_at(era_id: String, jd: int) -> Dictionary:
	for f in famous_days():
		if str(f.get("era", "")) == era_id and int(f.get("jd", -2)) == jd:
			return f
	return {}


## 時代・年（・日）→ 天気。jd = 0 なら date_for の日
static func lookup(era_id: String, year: int, jd := 0) -> Dictionary:
	var dt := date_for(era_id, year)
	if jd != 0 and jd != int(dt["jd"]):
		dt = make_date(jd, str(dt["region"]))
	var reg_id := str(dt["region"])
	var st := day_weather(reg_id, int(dt["jd"]), year)
	var f := famous_at(era_id, int(dt["jd"]))
	if not f.is_empty():
		st["famous"] = f
		reg_id = str(f.get("region", reg_id))
		if bool(f.get("apply", false)):
			var fs: Dictionary = f.get("state", {})
			for k in ["rain", "snow", "fog", "storm", "thunder", "ash", "dust"]:
				st[k] = 0.0
			st["night"] = false
			st.merge(fs, true)
			st["cloud"] = float(fs.get("cloud", 1.0 if str(fs.get("kind", "")) in ["rain", "heavy_rain", "thunder", "typhoon", "snow", "overcast"] else st["cloud"]))
			if not fs.has("wet"):
				st["wet"] = maxf(float(st["rain"]), 0.0)
			st["sequence"] = f.get("sequence", [])
			st["source"] = "record"
	st["date"] = dt
	st["region"] = reg_id
	st["region_name"] = str(region(reg_id).get("name", reg_id))
	var adj := period_adjust(reg_id, year, month_of(int(dt["doy"])))
	st["basis"] = adj["basis"]
	st["confidence"] = adj["confidence"]
	if not force.is_empty():
		st.merge(force, true)
		st["source"] = "forced"
	return st


## HUD の文字（「晴」「雨」「雪」…）。梅雨・小雨・大雪・降灰の言い分け
static func label_ja(st: Dictionary) -> String:
	var k := str(st.get("kind", "clear"))
	if float(st.get("ash", 0.0)) > 0.3:
		return "降灰"
	if k == "rain" and float(st.get("rain", 0.0)) < 0.35:
		return "小雨"
	if k == "snow" and float(st.get("snow", 0.0)) > 0.7:
		return "大雪"
	if k == "clear" and float(st.get("wind", 0.0)) >= 10.0:
		return "晴・強風"
	if k == "cloudy" and float(st.get("wind", 0.0)) >= 10.0:
		return "曇・強風"
	return str(LABEL.get(k, "晴"))


## 出典の種類（HUD の小さな注記）
static func source_ja(st: Dictionary) -> String:
	match str(st.get("source", "")):
		"record":
			var f: Dictionary = st.get("famous", {})
			return {"verified": "史実の記録", "documented": "同時代の記録", "secondary": "後世の記録", "disputed": "記録（論争あり）"}.get(str(f.get("verdict", "")), "記録")
		"forced":
			return "設定"
	var y := int((st.get("date", {}) as Dictionary).get("western", {}).get("y", 2000))
	return "気候値" if y >= 1875 else "気候値＋代理指標"


# ================================================================== ゲームへの影響（史実に基づく、控えめな値。docs/ARCHITECTURE.md「天気」）
static func cur(key: String, def := 0.0) -> float:
	return float(live.get(key, def))


## 火縄銃の不発の増分：雨は火皿の口薬と火縄を湿らせる（雨覆・火蓋はあるが完全ではない）。屋内・軒下は 0
## rain 1.0（大雨）で +35%、小雨（0.3）で約 +10%、雪で最大 +12%、強風は火皿の口薬を吹き飛ばす（+4%）
static func matchlock_misfire_add(rain: float, snow: float, wind: float, sheltered := false) -> float:
	if sheltered:
		return 0.0
	var add := clampf(rain, 0.0, 1.0) * 0.35 + clampf(snow, 0.0, 1.0) * 0.12
	if wind > 9.0:
		add += 0.04
	return add


static func misfire_add_now(weapon_id: String) -> float:
	if not (weapon_id in ["hinawaju", "musket", "tanegashima"]):
		return 0.0
	return matchlock_misfire_add(cur("rain"), cur("snow"), cur("wind"), cur("indoor") > 0.5)


## 見通し（敵がこちらに気づく距離の倍率）：霧・大雨・雪・夜。0.35〜1
static func visibility(fog: float, rain: float, snow: float, night := 0.0) -> float:
	var v := 1.0 - 0.62 * clampf(fog, 0.0, 1.0)
	v *= 1.0 - 0.3 * clampf(rain - 0.3, 0.0, 1.0) / 0.7
	v *= 1.0 - 0.3 * clampf(snow, 0.0, 1.0)
	v *= 1.0 - 0.2 * clampf(night, 0.0, 1.0)
	return clampf(v, 0.35, 1.0)


static func visibility_now() -> float:
	if live.is_empty():
		return 1.0
	return visibility(cur("fog"), cur("rain"), cur("snow"), cur("night_k"))


## ぬかるみ・雪道（馬の速さ・車のグリップの倍率）。舗装（石畳・アスファルト）は泥にならない
static func ground_speed_mult(wet: float, snow_cover: float, paved := false) -> float:
	var m := 1.0 - (0.04 if paved else 0.13) * clampf(wet, 0.0, 1.0)
	m *= 1.0 - 0.16 * clampf(snow_cover, 0.0, 1.0)
	return m


static func grip_mult(wet: float, snow_cover: float, paved := true) -> float:
	var g := 1.0 - (0.18 if paved else 0.28) * clampf(wet, 0.0, 1.0)
	g *= 1.0 - 0.4 * clampf(snow_cover, 0.0, 1.0)
	return g


## 海の荒れ（0〜1。船の揺れ・波の高さ）
static func sea_state() -> float:
	return clampf(cur("storm") * 0.8 + maxf(0.0, cur("wind") - 6.0) / 25.0, 0.0, 1.0)


## 飛行機の乱気流（機体の揺れの増分）。雷雨・台風で大きい
static func turbulence() -> float:
	return clampf(cur("storm") * 0.35 + maxf(0.0, cur("wind") - 8.0) / 60.0, 0.0, 0.5)
