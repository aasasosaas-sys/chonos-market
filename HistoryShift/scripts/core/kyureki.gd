class_name Kyureki
extends RefCounted
## 旧暦（太陰太陽暦）⇔ 西暦。天気の史料（日記・軍記）は旧暦で書かれているので、ゲームの日付（季節・梅雨・台風の季節）に直すのに使う。
## 計算: 朔（新月）は Meeus『Astronomical Algorithms』49 章の式、太陽黄経は 25 章の略算式、ΔT は Espenak–Meeus の多項式。
## 暦法の規則: 朔の日を 1 日とし、冬至を含む月を 11 月、中気を含まない月を閏月（冬至から次の冬至までに 13 か月ある年だけ）。
##  - 1844 年（天保暦）以後は定気（太陽黄経 30° ごと）、それより前は平気（冬至から 1 太陽年の 1/12 ごと）。
##  - 日付の境は日本時間（UT+9h）の真夜中。
## 限界: 実際の宣明暦（862〜1684 年）・貞享暦・宝暦暦は独自の天文定数で朔や冬至を計算していたため、
##        史料の日付と 1 日ずれる月がある（宣明暦の冬至は江戸初期には実際より約 2 日遅れていた）。
##        有名な日は data/weather/famous_days.json に換算済みの日付（典拠つき）を持たせ、計算は検算と、それ以外の日に使う。
## 西暦の表示: 1582 年 10 月 15 日より前はユリウス暦、以後はグレゴリオ暦（史料の換算の慣例どおり）。季節の計算は先発グレゴリオ暦の日付で行う。

const GREGORIAN_START_JD := 2299161      # 1582-10-15（グレゴリオ暦の始まり）
const TEIKI_FROM := 1844                 # 天保暦（定気）
const TROPICAL_YEAR := 365.24219
const JST := 9.0 / 24.0

static var _cache := {}


# ================================================================== 西暦 ⇔ ユリウス日（その日の正午の JD を整数で）
static func jd_from_gregorian(y: int, m: int, d: int) -> int:
	var a := int(floor((14 - m) / 12.0))
	var yy := y + 4800 - a
	var mm := m + 12 * a - 3
	return d + int(floor((153 * mm + 2) / 5.0)) + 365 * yy + int(floor(yy / 4.0)) - int(floor(yy / 100.0)) + int(floor(yy / 400.0)) - 32045


static func jd_from_julian(y: int, m: int, d: int) -> int:
	var a := int(floor((14 - m) / 12.0))
	var yy := y + 4800 - a
	var mm := m + 12 * a - 3
	return d + int(floor((153 * mm + 2) / 5.0)) + 365 * yy + int(floor(yy / 4.0)) - 32083


## 史料の慣例の暦（1582-10-15 より前はユリウス暦）
static func jd_from_western(y: int, m: int, d: int) -> int:
	var g := jd_from_gregorian(y, m, d)
	return g if g >= GREGORIAN_START_JD else jd_from_julian(y, m, d)


static func gregorian_from_jd(jd: int) -> Dictionary:
	var a := jd + 32044
	var b := int(floor((4 * a + 3) / 146097.0))
	var c := a - int(floor(146097 * b / 4.0))
	var d := int(floor((4 * c + 3) / 1461.0))
	var e := c - int(floor(1461 * d / 4.0))
	var m := int(floor((5 * e + 2) / 153.0))
	return {"y": 100 * b + d - 4800 + int(floor(m / 10.0)), "m": m + 3 - 12 * int(floor(m / 10.0)),
		"d": e - int(floor((153 * m + 2) / 5.0)) + 1, "cal": "gregorian"}


static func julian_from_jd(jd: int) -> Dictionary:
	var c := jd + 32082
	var d := int(floor((4 * c + 3) / 1461.0))
	var e := c - int(floor(1461 * d / 4.0))
	var m := int(floor((5 * e + 2) / 153.0))
	return {"y": d - 4800 + int(floor(m / 10.0)), "m": m + 3 - 12 * int(floor(m / 10.0)),
		"d": e - int(floor((153 * m + 2) / 5.0)) + 1, "cal": "julian"}


static func western_from_jd(jd: int) -> Dictionary:
	return gregorian_from_jd(jd) if jd >= GREGORIAN_START_JD else julian_from_jd(jd)


## 季節（太陽の位置）に合う「年の何日目」。先発グレゴリオ暦で数える（ユリウス暦の日付は中世で 7〜10 日ずれるため）
static func season_doy(jd: int) -> int:
	var g := gregorian_from_jd(jd)
	return jd - jd_from_gregorian(int(g["y"]), 1, 1) + 1


static func western_text(jd: int) -> String:
	var w := western_from_jd(jd)
	return "%s%d年%d月%d日" % ["ユリウス暦" if w["cal"] == "julian" else "", int(w["y"]), int(w["m"]), int(w["d"])] if int(w["y"]) > 0 \
		else "紀元前%d年%d月%d日" % [1 - int(w["y"]), int(w["m"]), int(w["d"])]


# ================================================================== 天文
static func _delta_t_days(y: float) -> float:
	var dt := 0.0
	if y < 500.0:
		var u := y / 100.0
		dt = 10583.6 - 1014.41 * u + 33.78311 * u * u - 5.952053 * pow(u, 3) - 0.1798452 * pow(u, 4) + 0.022174192 * pow(u, 5) + 0.0090316521 * pow(u, 6)
	elif y < 1600.0:
		var u := (y - 1000.0) / 100.0
		dt = 1574.2 - 556.01 * u + 71.23472 * u * u + 0.319781 * pow(u, 3) - 0.8503463 * pow(u, 4) - 0.005050998 * pow(u, 5) + 0.0083572073 * pow(u, 6)
	elif y < 1700.0:
		var t := y - 1600.0
		dt = 120.0 - 0.9808 * t - 0.01532 * t * t + pow(t, 3) / 7129.0
	elif y < 1800.0:
		var t := y - 1700.0
		dt = 8.83 + 0.1603 * t - 0.0059285 * t * t + 0.00013336 * pow(t, 3) - pow(t, 4) / 1174000.0
	elif y < 1860.0:
		var t := y - 1800.0
		dt = 13.72 - 0.332447 * t + 0.0068612 * t * t + 0.0041116 * pow(t, 3) - 0.00037436 * pow(t, 4) + 0.0000121272 * pow(t, 5) - 0.0000001699 * pow(t, 6) + 0.000000000875 * pow(t, 7)
	elif y < 1900.0:
		var t := y - 1860.0
		dt = 7.62 + 0.5737 * t - 0.251754 * t * t + 0.01680668 * pow(t, 3) - 0.0004473624 * pow(t, 4) + pow(t, 5) / 233174.0
	else:
		dt = 30.0 + 0.4 * (y - 1950.0)
	return dt / 86400.0


## k 番目の朔（k=0 が 2000 年 1 月 6 日）の UT のユリウス日（小数）
static func new_moon_ut(k: int) -> float:
	var kk := float(k)
	var T := kk / 1236.85
	var jde := 2451550.09766 + 29.530588861 * kk + 0.00015437 * T * T - 0.00000015 * T * T * T + 0.00000000073 * pow(T, 4)
	var E := 1.0 - 0.002516 * T - 0.0000074 * T * T
	var M := deg_to_rad(2.5534 + 29.1053567 * kk - 0.0000014 * T * T - 0.00000011 * T * T * T)
	var Mp := deg_to_rad(201.5643 + 385.81693528 * kk + 0.0107582 * T * T + 0.00001238 * T * T * T - 0.000000058 * pow(T, 4))
	var F := deg_to_rad(160.7108 + 390.67050284 * kk - 0.0016118 * T * T - 0.00000227 * T * T * T + 0.000000011 * pow(T, 4))
	var Om := deg_to_rad(124.7746 - 1.56375588 * kk + 0.0020672 * T * T + 0.00000215 * T * T * T)
	var c := -0.4072 * sin(Mp) + 0.17241 * E * sin(M) + 0.01608 * sin(2 * Mp) + 0.01039 * sin(2 * F) \
		+ 0.00739 * E * sin(Mp - M) - 0.00514 * E * sin(Mp + M) + 0.00208 * E * E * sin(2 * M) \
		- 0.00111 * sin(Mp - 2 * F) - 0.00057 * sin(Mp + 2 * F) + 0.00056 * E * sin(2 * Mp + M) \
		- 0.00042 * sin(3 * Mp) + 0.00042 * E * sin(M + 2 * F) + 0.00038 * E * sin(M - 2 * F) \
		- 0.00024 * E * sin(2 * Mp - M) - 0.00017 * sin(Om) - 0.00007 * sin(Mp + 2 * M) \
		+ 0.00004 * sin(2 * Mp - 2 * F) + 0.00004 * sin(3 * M) + 0.00003 * sin(Mp + M - 2 * F) \
		+ 0.00003 * sin(2 * Mp + 2 * F) - 0.00003 * sin(Mp + M + 2 * F) + 0.00003 * sin(Mp - M + 2 * F) \
		- 0.00002 * sin(Mp - M - 2 * F) - 0.00002 * sin(3 * Mp + M) + 0.00002 * sin(4 * Mp)
	jde += c
	var year := 2000.0 + kk / 12.3685
	return jde - _delta_t_days(year)


## 太陽の視黄経（度）。jde は力学時
static func sun_longitude(jde: float) -> float:
	var T := (jde - 2451545.0) / 36525.0
	var L0 := 280.46646 + 36000.76983 * T + 0.0003032 * T * T
	var M := deg_to_rad(357.52911 + 35999.05029 * T - 0.0001537 * T * T)
	var C := (1.914602 - 0.004817 * T - 0.000014 * T * T) * sin(M) + (0.019993 - 0.000101 * T) * sin(2 * M) + 0.000289 * sin(3 * M)
	var om := deg_to_rad(125.04 - 1934.136 * T)
	return fposmod(L0 + C - 0.00569 - 0.00478 * sin(om), 360.0)


## 太陽黄経が target（度）になる時刻（UT のユリウス日）。guess の近く
static func solar_term_ut(target: float, guess_jd: float) -> float:
	var jd := guess_jd
	for i in 40:
		var y := 2000.0 + (jd - 2451545.0) / 365.25
		var lam := sun_longitude(jd + _delta_t_days(y))
		var diff := fposmod(target - lam + 180.0, 360.0) - 180.0
		jd += diff * TROPICAL_YEAR / 360.0
		if absf(diff) < 1e-7:
			break
	return jd


## 日本時間の暦日（その日の正午の JD 整数）
static func local_day(jd_ut: float) -> int:
	return int(floor(jd_ut + JST + 0.5))


## 西暦 y 年 12 月の冬至の日（暦日）
static func winter_solstice_ut(y: int) -> float:
	return solar_term_ut(270.0, float(jd_from_gregorian(y, 12, 21)))


# ================================================================== 月の並び
## 西暦 y 年の冬至を含む月（11 月）から始まる 15 か月：[{start(暦日 JD), month, leap}]
static func months_from_solstice(y: int) -> Array:
	var key := y
	if _cache.has(key):
		return _cache[key]
	var ws := winter_solstice_ut(y)
	var ws_day := local_day(ws)
	var ws_next := winter_solstice_ut(y + 1)
	# 冬至の日以前で最も新しい朔
	var k := int(floor((ws - 2451550.09766) / 29.530588861)) + 1
	while local_day(new_moon_ut(k)) > ws_day:
		k -= 1
	var starts: Array = []
	for i in 16:
		starts.append(local_day(new_moon_ut(k + i)))
	# 中気の日
	var teiki := y + 1 >= TEIKI_FROM
	var chuki: Array = []
	for j in 26:
		var t := 0.0
		if teiki:
			t = solar_term_ut(fposmod(270.0 + 30.0 * j, 360.0), ws + j * TROPICAL_YEAR / 12.0)
		else:
			t = ws + j * TROPICAL_YEAR / 12.0
		chuki.append(local_day(t))
	var has_chuki := func(i: int) -> bool:
		for d in chuki:
			if int(d) >= int(starts[i]) and int(d) < int(starts[i + 1]):
				return true
		return false
	# 次の冬至を含む月までの月数（12 か 13）
	var ws2_day := local_day(ws_next)
	var n_to_next := 0
	for i in range(1, 15):
		if int(starts[i]) <= ws2_day and ws2_day < int(starts[i + 1]):
			n_to_next = i
			break
	var leap_at := -1
	if n_to_next == 13:
		for i in range(1, 13):
			if not has_chuki.call(i):
				leap_at = i
				break
	var out: Array = []
	var m := 11
	for i in 15:
		var leap := false
		if i > 0:
			if i == leap_at:
				leap = true
			else:
				m = m % 12 + 1
		out.append({"start": int(starts[i]), "end": int(starts[i + 1]), "month": m, "leap": leap})
	_cache[key] = out
	return out


## 旧暦 → 暦日（JD 整数）。year = その年の正月がある西暦年（元禄15年 = 1702。12 月は翌年 1 月の日付になる）
## 見つからなければ -1
static func lunar_to_jd(year: int, month: int, day: int, leap := false) -> int:
	var src: Array = months_from_solstice(year - 1) if month < 11 else months_from_solstice(year)
	var begun := month >= 11
	for mo in src:
		if int(mo["month"]) == 1 and not bool(mo["leap"]):
			begun = true
		if not begun:
			continue
		if int(mo["month"]) == month and bool(mo["leap"]) == leap:
			if day < 1 or day > int(mo["end"]) - int(mo["start"]):
				return -1
			return int(mo["start"]) + day - 1
	return -1


## 暦日 → 旧暦 {year, month, day, leap}
static func jd_to_lunar(jd: int) -> Dictionary:
	var g := gregorian_from_jd(jd)
	for yy in [int(g["y"]) - 1, int(g["y"]) - 2]:
		var ly: int = yy
		for mo in months_from_solstice(yy):
			if int(mo["month"]) == 1 and not bool(mo["leap"]):
				ly = yy + 1
			if jd >= int(mo["start"]) and jd < int(mo["end"]):
				return {"year": ly, "month": int(mo["month"]), "day": jd - int(mo["start"]) + 1, "leap": bool(mo["leap"])}
	return {}


static func lunar_text(month: int, day: int, leap := false) -> String:
	return "%s%d月%d日" % ["閏" if leap else "", month, day]


## 月齢（朔からの日数、0〜29.5）。旧暦の夜の月の明るさ（14〜16 日は満月に近い）
static func moon_age(jd: int) -> float:
	var t := float(jd) - JST
	var k := int(floor((t - 2451550.09766) / 29.530588861)) + 1
	while new_moon_ut(k) > t:
		k -= 1
	return t - new_moon_ut(k)
