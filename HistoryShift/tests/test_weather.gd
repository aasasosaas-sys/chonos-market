extends Node
## ヘッドレス: godot --headless --path . res://tests/test_weather.tscn
## 天気の検査:
##  1. 旧暦 → 西暦（Kyureki）：史料でよく知られた換算と一致すること（宣明暦の頃は ±1 日を許す日もある）・往復
##  2. 日付 → 天気（HistWeather.lookup）：有名な日の上書き（桜田門外の雪・弘安の役の台風・二・二六の雪・関ヶ原の霧…）、
##     上書きしない日（apply=false）、気候値の妥当さ（雨の日の割合・梅雨・小氷期の雪の多さ）、決まった乱数で毎回同じ
##  3. ゲームへの影響：火縄銃の不発の増分・見通し・ぬかるみ・グリップ・海の荒れ
##  4. 足音：雨の後の床材の言いかえ（濡れた石・濡れた草・泥・雪）と、その音の素材があること
##  5. WeatherDirector・HUD・環境音・Session がヘッドレスでエラーなく動くこと（雨・雪・霧・雷・台風）

var fails := 0
var checks := 0


func _ready() -> void:
	_run.call_deferred()


func _check(cond: bool, msg: String) -> void:
	checks += 1
	if not cond:
		print("FAIL " + msg)
		fails += 1
	elif OS.get_cmdline_user_args().has("-v"):
		print("OK   " + msg)


func _run() -> void:
	var keep_h := HistoryState.save_path
	var keep_p := PlayerProfile.save_path
	HistoryState.save_path = "user://test_weather_history.json"
	PlayerProfile.save_path = "user://test_weather_profile.json"
	_calendar()
	_lookups()
	_climatology()
	_gameplay()
	_footsteps()
	await _director()
	await _session()
	HistWeather.live = {}
	HistWeather.force = {}
	HistoryState.delete_save()
	HistoryState.save_path = keep_h
	PlayerProfile.save_path = keep_p
	print("weather: %s (%d checks, %d failures)" % ["ok" if fails == 0 else "FAILED", checks, fails])
	get_tree().quit(1 if fails > 0 else 0)


# ------------------------------------------------------------------ 1. 旧暦
func _calendar() -> void:
	# [正月のある西暦年, 月, 日, 閏, 西暦の年, 月, 日, 許す誤差（日）, 出来事]
	var cases := [
		[645, 6, 12, false, 645, 7, 10, 0, "乙巳の変"],
		[752, 4, 9, false, 752, 5, 26, 0, "大仏開眼"],
		[1185, 3, 24, false, 1185, 4, 25, 0, "壇ノ浦"],
		[1274, 10, 20, false, 1274, 11, 19, 0, "文永の役（荒川1958の先発グレゴリオ暦11月26日＝ユリウス暦11月19日）"],
		[1281, 7, 1, true, 1281, 8, 16, 1, "弘安の役（閏7月1日）"],
		[1333, 5, 22, false, 1333, 7, 4, 0, "鎌倉幕府の滅亡"],
		[1441, 6, 24, false, 1441, 7, 12, 0, "嘉吉の変"],
		[1543, 8, 25, false, 1543, 9, 23, 0, "鉄砲伝来"],
		[1549, 7, 22, false, 1549, 8, 15, 1, "ザビエル上陸（宣明暦の朔のずれで1日）"],
		[1560, 5, 19, false, 1560, 6, 12, 0, "桶狭間"],
		[1582, 6, 2, false, 1582, 6, 21, 0, "本能寺の変"],
		[1600, 9, 15, false, 1600, 10, 21, 0, "関ヶ原"],
		[1657, 1, 18, false, 1657, 3, 2, 0, "明暦の大火"],
		[1702, 12, 14, false, 1703, 1, 30, 0, "赤穂浪士の討ち入り"],
		[1783, 7, 8, false, 1783, 8, 5, 0, "浅間山"],
		[1837, 2, 19, false, 1837, 3, 25, 0, "大塩平八郎の乱"],
		[1853, 6, 3, false, 1853, 7, 8, 0, "ペリー来航"],
		[1860, 3, 3, false, 1860, 3, 24, 0, "桜田門外の変"],
		[1867, 11, 15, false, 1867, 12, 10, 0, "坂本龍馬の暗殺"],
		[1871, 7, 14, false, 1871, 8, 29, 0, "廃藩置県"],
	]
	for c in cases:
		var jd := Kyureki.lunar_to_jd(int(c[0]), int(c[1]), int(c[2]), bool(c[3]))
		var want := Kyureki.jd_from_western(int(c[4]), int(c[5]), int(c[6]))
		_check(jd > 0 and absi(jd - want) <= int(c[7]), "旧暦 %d年%s → %s（期待 %d-%d-%d）%s" % [int(c[0]), Kyureki.lunar_text(int(c[1]), int(c[2]), bool(c[3])), Kyureki.western_text(jd), int(c[4]), int(c[5]), int(c[6]), str(c[8])])
		var back := Kyureki.jd_to_lunar(jd)
		_check(int(back.get("year", 0)) == int(c[0]) and int(back.get("month", 0)) == int(c[1]) and int(back.get("day", 0)) == int(c[2]) and bool(back.get("leap", false)) == bool(c[3]), "往復 %s: %s" % [str(c[8]), back])
	# 閏月のある年：弘安4年（1281）は閏7月、無い月の閏は -1
	_check(Kyureki.lunar_to_jd(1281, 6, 1, true) < 0, "弘安4年に閏6月は無い")
	# ユリウス暦→グレゴリオ暦の切り替え（1582年10月4日の翌日が10月15日）
	_check(Kyureki.jd_from_julian(1582, 10, 4) + 1 == Kyureki.jd_from_gregorian(1582, 10, 15), "1582年10月4日（ユリウス暦）の翌日は10月15日（グレゴリオ暦）")
	# 旧暦14日の夜は満月に近い（赤穂浪士の討ち入りの夜）
	var age := Kyureki.moon_age(Kyureki.lunar_to_jd(1702, 12, 14))
	_check(age > 11.0 and age < 15.5, "元禄15年12月14日の月齢 %.1f（満月に近い）" % age)


# ------------------------------------------------------------------ 2. 日付 → 天気
func _lookups() -> void:
	HistWeather.force = {}
	var s := HistWeather.lookup("edo", 1860)
	_check(str(s["kind"]) == "snow" and str(s["source"]) == "record", "1860年（桜田門外の変の日）は雪・史実の記録: %s %s" % [s["kind"], s["source"]])
	_check(str((s.get("famous", {}) as Dictionary).get("line", "")).contains("大雪"), "桜田門外の変の一言に「大雪」")
	_check(str((s["date"] as Dictionary)["text"]) == "1860年3月24日" and str((s["date"] as Dictionary)["lunar_text"]) == "3月3日", "日付 1860年3月24日（旧暦3月3日）: %s" % (s["date"] as Dictionary)["text"])
	_check(float(s["snow_cover"]) > 0.5 and HistWeather.label_ja(s) == "大雪", "雪が積もっている・表示は「大雪」（%s）" % HistWeather.label_ja(s))
	var k := HistWeather.lookup("kamakura_muromachi", 1281)
	_check(str(k["kind"]) == "typhoon" and float(k["wind"]) >= 20.0 and str(k["region"]) == "fukuoka", "弘安の役（閏7月1日）は台風・博多")
	_check(HistWeather.label_ja(k) == "台風", "表示は「台風」")
	var b := HistWeather.lookup("kamakura_muromachi", 1274)
	_check(str((b["famous"] as Dictionary)["verdict"]) == "disputed" and str(b["kind"]) != "typhoon", "文永の役は論争中（台風とはしない）: %s" % b["kind"])
	_check(not (b.get("sequence", []) as Array).is_empty(), "文永の役の夜の大風雨は sequence で来る")
	var n := HistWeather.lookup("showa", 1936)
	_check(str(n["kind"]) == "snow" and float(n["snow_cover"]) >= 0.8, "二・二六事件の朝は雪・積雪")
	var g := HistWeather.lookup("sengoku", 1600)
	_check(str(g["kind"]) == "fog" and float(g["fog"]) > 0.8 and str(g["region"]) == "sekigahara", "関ヶ原は朝霧（関ヶ原の気候）")
	_check(str((g["famous"] as Dictionary)["verdict"]) == "secondary", "関ヶ原の霧は後世の記録（secondary）")
	var o := HistWeather.lookup("sengoku", 1560)
	var seq: Array = o.get("sequence", [])
	_check(not seq.is_empty() and str(seq[0].get("kind", "")) == "heavy_rain" and bool(seq[0].get("hail", false)), "桶狭間は途中で雹まじりの急雨（信長公記）")
	var e := HistWeather.lookup("showa", 1945)
	_check(str(e["kind"]) == "clear" and absf(float(e["temp"]) - 32.3) < 0.01, "1945年8月15日は晴れ・32.3℃")
	var x := HistWeather.lookup("showa", 1945, Kyureki.jd_from_gregorian(1945, 3, 10))
	_check(not (x.get("famous", {}) as Dictionary).is_empty() and float(x["wind"]) >= 10.0, "1945年3月10日（日付を指定）は強風の記録")
	var c := HistWeather.lookup("meiji_taisho", 1923)
	_check(float(c["wind"]) >= 10.0 and str(c["source"]) == "record", "関東大震災の日は強風（日本海の台風）")
	var h := HistWeather.lookup("sengoku", 1582)
	_check(str(h["source"]) == "climatology" and not (h.get("famous", {}) as Dictionary).is_empty(), "本能寺の変の日は記録未確認 → 気候値（上書きしない）")
	var m := HistWeather.lookup("meiji_taisho", 1889)
	_check(str(m["source"]) == "climatology", "憲法発布の日は未確認 → 気候値")
	# 決まった乱数：同じ日は毎回同じ
	var a1 := HistWeather.lookup("heian", 1016)
	var a2 := HistWeather.lookup("heian", 1016)
	_check(str(a1["kind"]) == str(a2["kind"]) and float(a1["temp"]) == float(a2["temp"]), "同じ日の天気は毎回同じ")
	_check(HistWeather.source_ja(a1) == "気候値＋代理指標" and not (a1["basis"] as Array).is_empty(), "平安は気候値＋代理指標（根拠つき）")
	# すべての時代・時点で引ける
	for era in HistoryDB.ERA_ORDER:
		for y in EraTimeline.years(era):
			var w := HistWeather.lookup(era, int(y))
			_check(str(w["kind"]) in HistWeather.KINDS and int((w["date"] as Dictionary)["jd"]) > 0, "%s %d の天気: %s" % [era, int(y), w["kind"]])
	# 有名な日はすべて出典と判定を持ち、日付が引ける
	for f in HistWeather.famous_days():
		_check(int(f.get("jd", -1)) > 0 and str(f.get("verdict", "")) in ["verified", "documented", "secondary", "disputed", "unverified"] and not (f.get("sources", []) as Array).is_empty() and str(f.get("basis", "")) != "", "有名な日 %s: 日付・判定・出典" % f.get("id", "?"))


func _climatology() -> void:
	var count := func(reg: String, yr: int) -> Dictionary:
		var out := {"rain": 0, "snow": 0, "tsuyu_rain": 0, "tsuyu": 0, "days": 0}
		var j0 := Kyureki.jd_from_gregorian(yr, 1, 1)
		for d in 365:
			var s := HistWeather.day_weather(reg, j0 + d, yr)
			out["days"] += 1
			var kd := str(s["kind"])
			if kd in ["rain", "heavy_rain", "thunder", "typhoon", "snow"]:
				out["rain"] += 1
			if kd == "snow":
				out["snow"] += 1
			if bool(s["tsuyu"]):
				out["tsuyu"] += 1
				if kd in ["rain", "heavy_rain", "thunder"]:
					out["tsuyu_rain"] += 1
		return out
	var t1990: Dictionary = count.call("tokyo", 1990)
	var ts_rain := 0
	var ts_days := 0
	for yy in range(1980, 2000):
		var cy: Dictionary = count.call("tokyo", yy)
		ts_rain += int(cy["tsuyu_rain"])
		ts_days += int(cy["tsuyu"])
	var t1700: Dictionary = count.call("tokyo", 1700)
	var normal := 0.0
	for v in HistWeather.region("tokyo")["rain_days"]:
		normal += float(v)
	_check(absf(float(t1990["rain"]) - normal) < normal * 0.3, "東京の降水日数（生成 %d 日 / 平年値 %.0f 日）" % [t1990["rain"], normal])
	_check(int(t1700["snow"]) > int(t1990["snow"]), "小氷期の江戸は今より雪の日が多い（1700年 %d 日 / 1990年 %d 日）" % [t1700["snow"], t1990["snow"]])
	_check(float(ts_rain) / maxf(1.0, float(ts_days)) > 0.45, "梅雨のさなかは雨が多い（20 年で %d / %d 日）" % [ts_rain, ts_days])
	var adj := HistWeather.period_adjust("tokyo", 1783, 7)
	_check(float(adj["dT"]) < -3.0, "天明3年の夏は冷夏（小氷期＋天明の飢饉 %.1f℃）" % float(adj["dT"]))


# ------------------------------------------------------------------ 3. ゲームへの影響
func _gameplay() -> void:
	_check(HistWeather.matchlock_misfire_add(0.0, 0.0, 2.0) == 0.0, "晴れなら火縄銃の不発は増えない")
	_check(absf(HistWeather.matchlock_misfire_add(1.0, 0.0, 2.0) - 0.35) < 0.001, "大雨で火縄銃の不発 +35%")
	_check(HistWeather.matchlock_misfire_add(0.3, 0.0, 2.0) > 0.09 and HistWeather.matchlock_misfire_add(0.3, 0.0, 2.0) < 0.12, "小雨で約 +10%")
	_check(HistWeather.matchlock_misfire_add(1.0, 0.0, 2.0, true) == 0.0, "屋内・軒下では増えない")
	HistWeather.live = {"rain": 0.9, "snow": 0.0, "wind": 4.0, "indoor": 0.0, "fog": 0.0, "storm": 0.6, "wet": 1.0, "snow_cover": 0.0}
	_check(HistWeather.misfire_add_now("hinawaju") > 0.3 and HistWeather.misfire_add_now("musket") > 0.3, "雨の中の火縄銃（自分の・敵の）は不発が増える")
	_check(HistWeather.misfire_add_now("arisaka38") == 0.0 and HistWeather.misfire_add_now("wakyu") == 0.0, "薬莢の小銃・弓は雨の影響なし")
	_check(HistWeather.visibility(1.0, 0.0, 0.0) < 0.45 and HistWeather.visibility(0.0, 0.0, 0.0) == 1.0, "濃霧で見通しが半分以下、晴れは 1")
	_check(HistWeather.visibility(1.0, 1.0, 1.0, 1.0) >= 0.35, "見通しの下限 0.35")
	_check(HistWeather.ground_speed_mult(1.0, 0.0, false) < 0.9 and HistWeather.ground_speed_mult(1.0, 0.0, true) > 0.95, "ぬかるみは土の道だけ遅い（舗装は少し）")
	_check(HistWeather.grip_mult(0.0, 1.0) < 0.65, "雪道は車のグリップが落ちる")
	_check(HistWeather.sea_state() > 0.4 and HistWeather.turbulence() > 0.1, "嵐で海が荒れ、乱気流")
	HistWeather.live = {}
	_check(HistWeather.visibility_now() == 1.0 and HistWeather.sea_state() == 0.0, "天気なし（ハブなど）は影響なし")


# ------------------------------------------------------------------ 4. 足音
func _footsteps() -> void:
	_check(Footsteps.weather_variant("grass", 0.8, 0.0) == "wet_grass", "雨の後の草 → 濡れた草")
	_check(Footsteps.weather_variant("stone", 0.8, 0.0) == "wet" and Footsteps.weather_variant("concrete", 0.5, 0.0) == "wet", "石畳・舗装 → 水を踏む音")
	_check(Footsteps.weather_variant("dirt", 0.8, 0.0) == "mud", "土の道 → 泥")
	_check(Footsteps.weather_variant("tatami", 1.0, 1.0) == "tatami", "畳は変わらない")
	_check(Footsteps.weather_variant("grass", 0.0, 0.8) == "snow", "雪が積もれば雪")
	_check(Footsteps.weather_variant("grass", 0.1, 0.1) == "grass", "乾いていれば元のまま")
	for s in Surface.WEATHER:
		for suf in ["", "_run"]:
			var key: String = "step_" + str(s) + str(suf)
			_check(SoundBank.has(key) and SoundBank.pick(key) != null, "足音の素材 %s" % key)
	HistWeather.live = {"wet": 0.9, "snow_cover": 0.0}
	_check(Footsteps.weather_surface("grass", Vector3.ZERO) == "wet_grass", "Footsteps.weather_surface（いまの天気で）")
	HistWeather.live = {}
	for k in ["amb_rain_light", "amb_rain_heavy", "amb_rain_roof_wood", "amb_rain_roof_tin", "amb_storm_wind", "amb_snow_hush", "thunder_near", "thunder_far", "wind_gust"]:
		_check(SoundBank.has(k) and SoundBank.pick(k) != null, "天気の音 %s" % k)


# ------------------------------------------------------------------ 5. ヘッドレスで動く
func _director() -> void:
	var w: EraWorld = EraWorld.build(Game.db.get_era("edo"), 1860, {})
	add_child(w)
	Game.set_world(w)
	var cam := Camera3D.new()
	add_child(cam)
	cam.global_position = w.player_spawn + Vector3(0, 3, 6)
	cam.current = true
	var hud := Hud.new()
	add_child(hud)
	var amb := AmbienceDirector.attach(self, "edo")
	var d := WeatherDirector.attach(self, w, "edo", 1860, hud)
	for i in 10:
		await get_tree().process_frame
	_check(hud.weather_text == "大雪", "HUD の天気「大雪」（%s）" % hud.weather_text)
	var ww: Vector4 = d.last_weather
	_check(ww.y > 0.5, "積雪がシェーダに渡る（world_weather.y = %.2f）" % ww.y)
	_check(str(HistWeather.live.get("kind", "")) == "snow" and float(HistWeather.live.get("snow", 0.0)) > 0.5, "HistWeather.live は雪")
	_check(d._snow.amount_ratio > 0.3 and d._rain.amount_ratio < 0.01, "雪の粒が降り、雨は止まっている")
	# 雷雨へ
	d.set_weather({"kind": "thunder", "rain": 1.0, "snow": 0.0, "thunder": 1.0, "storm": 0.8, "wind": 12.0, "cloud": 1.0, "wet": 1.0, "snow_cover": 0.0})
	d.strike(400.0, cam)
	var flashed := false
	for i in 30:
		await get_tree().process_frame
		var v: Vector4 = d.last_weather
		if v.w > 0.2:
			flashed = true
	_check(flashed and d.strikes >= 1, "稲光が光る")
	_check(d._rain.amount_ratio > 0.5, "雨の粒")
	_check(hud.weather_text == "雷雨", "HUD「雷雨」（%s）" % hud.weather_text)
	var sky: ShaderMaterial = w.env_nodes["sky_mat"]
	_check(float(sky.get_shader_parameter("overcast")) > 0.8, "空一面の雨雲")
	var env: Environment = w.env_nodes["env"]
	_check(env.adjustment_saturation < 0.85, "雨の日は色が沈む（彩度 %.2f）" % env.adjustment_saturation)
	var sun: DirectionalLight3D = w.env_nodes["sun"]
	_check(sun.light_energy < float(sun.get_meta("base_e")) * 0.6, "雨雲で日差しが弱まる")
	amb._update()
	_check(float(amb._target.get("amb_rain_heavy", 0.0)) > 0.5, "環境音：大雨の層（%.2f）" % float(amb._target.get("amb_rain_heavy", 0.0)))
	_check(float(amb._target.get("amb_birds_day", 1.0)) < 0.2, "雨の間は鳥が鳴かない")
	_check(Footsteps.weather_surface("stone", w.player_spawn + Vector3(500, 0, 500)) == "wet", "雨の日の屋外の石の足音は濡れた音")
	# 霧
	d.set_weather({"kind": "fog", "rain": 0.0, "thunder": 0.0, "storm": 0.0, "fog": 1.0, "wind": 1.0, "cloud": 0.8})
	await get_tree().process_frame
	await get_tree().process_frame
	_check(env.fog_density > 0.02, "霧：深度霧が濃い（%.4f）" % env.fog_density)
	_check(HistWeather.visibility_now() < 0.5, "霧：敵の見通しが落ちる")
	# 台風（雷・突風・海）
	d.set_weather({"kind": "typhoon", "rain": 0.9, "fog": 0.0, "storm": 1.0, "wind": 26.0, "cloud": 1.0})
	for i in 20:
		await get_tree().physics_frame
	_check(HistWeather.sea_state() > 0.8, "台風で時化")
	var wind: Vector4 = d.last_wind
	_check(wind.z > 2.0, "台風で草木が大きく揺れる（world_wind.z = %.1f）" % wind.z)
	amb._update()
	_check(float(amb._target.get("amb_storm_wind", 0.0)) > 0.5, "台風のうなり")
	d.queue_free()
	amb.queue_free()
	hud.queue_free()
	await get_tree().process_frame
	_check(HistWeather.live.is_empty() and WeatherDirector.I == null, "天気を片づけると元に戻る")
	Game.set_world(null)
	w.queue_free()
	cam.queue_free()
	await get_tree().process_frame


func _session() -> void:
	# 自由探索：二・二六事件の年（1936）に降り立つと、HUD に雪と史実の一言
	var s := Session.start_free_roam("showa", 1936)
	add_child(s)
	for i in 20:
		await get_tree().process_frame
	_check(s.weather != null and is_instance_valid(s.weather), "Session が天気を持つ")
	if s.weather:
		_check(str(s.weather.kind) == "snow", "1936年の自由探索は雪（%s）" % s.weather.kind)
	_check(s.hud.weather_text == "雪", "HUD「雪」（%s）" % s.hud.weather_text)
	var toasts := ""
	for c in s.hud._toast_box.get_children():
		if c is Control:
			for l in c.find_children("*", "Label", true, false):
				toasts += (l as Label).text
	_check(toasts.contains("史実"), "史実の一言が出る: %s" % toasts.substr(0, 80))
	# 雨の日：火縄銃の不発がゲームの銃に効く（江戸 1860 を雨にして）
	s.weather.set_weather({"kind": "heavy_rain", "rain": 1.0, "snow": 0.0, "wet": 1.0})
	await get_tree().process_frame
	_check(HistWeather.misfire_add_now("hinawaju") > 0.25, "雨のセッションで火縄銃の不発が増える（+%.0f%%）" % (HistWeather.misfire_add_now("hinawaju") * 100.0))
	s.end()
	await get_tree().process_frame
	await get_tree().process_frame
