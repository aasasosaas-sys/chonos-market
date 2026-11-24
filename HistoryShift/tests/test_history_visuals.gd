extends Node
## ヘッドレス: godot --headless --path . res://tests/test_history_visuals.tscn [-- --no-world]
## 歴史の見た目（data/visuals/history_visuals.json・HistoryVisuals・HistoryDressing・PresentWorld）：
## 歴史の状態を切り替えると、箱庭（明治の町・江戸の港・昭和の町）とハブ（2026年）の姿が変わることを確かめる。

var fails := 0
var db: HistoryDB


func _ready() -> void:
	_run.call_deferred()


func _check(cond: bool, msg: String) -> void:
	print(("OK   " if cond else "FAIL ") + msg)
	if not cond:
		fails += 1


func _run() -> void:
	db = HistoryDB.load_all()
	var keep := HistoryState.save_path
	HistoryState.save_path = "user://test_history_visuals_save.json"
	_profiles()
	_crowd()
	_present()
	if not ("--no-world" in OS.get_cmdline_user_args()):
		await _worlds()
		await _hub()
		await _flow_hub()
	HistoryState.delete_save()
	HistoryState.save_path = keep
	print("history visuals: %s (%d failures)" % ["ok" if fails == 0 else "FAILED", fails])
	get_tree().quit(1 if fails > 0 else 0)


# ------------------------------------------------------------------ 1. 歴史の状態 → profile
func _profiles() -> void:
	var st := HistoryState.new(db)
	var p0 := HistoryVisuals.profile(st, "meiji_taisho", 1889)
	_check(HistoryVisuals.lead_of(p0, "industry") == 0 and HistoryVisuals.lead_of(p0, "west") == 0, "real history: no lead (%s)" % [p0["lead"]])
	var ids0: Array = HistoryVisuals.features_for(p0).map(func(f): return f["def"]["id"])
	_check("railway" in ids0 and "arc_lamps" in ids0, "real meiji 1889 has 新橋－横浜 railway and arc lamps (%s)" % [ids0])
	_check(not ("silk_mill" in ids0) and not ("steelworks" in ids0), "real meiji 1889: no factory in the village, no steelworks at Yokohama")
	var ids71: Array = HistoryVisuals.features_for(HistoryVisuals.profile(st, "meiji_taisho", 1871)).map(func(f): return f["def"]["id"])
	_check(not ("railway" in ids71), "real meiji 1871: railway not yet (opened 1872)")
	_check(HistoryVisuals.war_for(HistoryVisuals.profile(st, "showa", 1945)).get("tier", "") == "敗戦", "real history: 敗戦 in 1945")
	# 江戸で技術・西洋との交流を大きく伸ばす（自由探索の混乱と同じ経路）
	st.apply_chaos({"id": "hv_test_industry", "title": "テスト：江戸の産業革命", "year": 1750, "vars": {"tech": 30, "economy": 20, "open_west": 30, "education": 15}}, "edo")
	var p1 := HistoryVisuals.profile(st, "meiji_taisho", 1877)
	_check(HistoryVisuals.lead_of(p1, "industry") >= 15 and HistoryVisuals.lead_of(p1, "west") >= 15, "edo industrialisation → meiji lead (%s)" % [p1["lead"]])
	var ids1: Array = HistoryVisuals.features_for(p1).map(func(f): return f["def"]["id"])
	_check("silk_mill" in ids1 and "brick_town" in ids1, "industrialised meiji 1877: silk mill + brick town (%s)" % [ids1])
	var pe := HistoryVisuals.profile(st, "edo", 1853)
	var ide: Array = HistoryVisuals.features_for(pe).map(func(f): return f["def"]["id"])
	_check(HistoryVisuals.lead_of(pe, "industry") > 0, "edo 1853 itself is ahead (%d)" % HistoryVisuals.lead_of(pe, "industry"))
	var pe0 := HistoryVisuals.profile(st, "edo", 1745)
	_check(HistoryVisuals.lead_of(pe0, "industry") == 0, "edo 1745 (before the 1750 change) not ahead")
	var big := HistoryVisuals.make("edo", 1853, {"industry": 40, "west": 40})
	var idb: Array = HistoryVisuals.features_for(big).map(func(f): return f["def"]["id"])
	_check("railway" in idb and "telegraph" in idb and "gas_lamps" in idb, "edo 1853 with 40y lead: railway, telegraph, gas lamps (%s)" % [idb])
	_check(not ("arc_lamps" in idb), "edo 1853: no arc lamps before 1878 even with a lead (earliest)")
	var idv: Array = HistoryVisuals.features_for(HistoryVisuals.make("edo", 1615, {"industry": 90})).map(func(f): return f["def"]["id"])
	_check(not ("railway" in idv), "edo 1615: no railway even with 90y lead (steam railways only from 1830)")
	var lag := HistoryVisuals.make("meiji_taisho", 1877, {"west": -40})
	_check(HistoryVisuals.absent_for(lag).size() >= 2, "west lag → absent brick / lamps rules")
	_check(not HistoryVisuals.capital_for(HistoryVisuals.make("meiji_taisho", 1889, {}, "敗戦", "大坂")).is_empty(), "capital in 大坂 → sign in Tokyo")
	_check(HistoryVisuals.capital_for(HistoryVisuals.make("meiji_taisho", 1889, {}, "敗戦", "")).is_empty(), "real capital → no sign")
	_check(not HistoryVisuals.navy_for(HistoryVisuals.make("meiji_taisho", 1877, {}, "敗戦", "", 12.0)).is_empty(), "early great power → navy at the port")
	_check(HistoryVisuals.summary(p1).size() > 0, "summary lines (%d)" % HistoryVisuals.summary(p1).size())


# ------------------------------------------------------------------ 2. 町人の装い
func _crowd() -> void:
	var counts := {}
	for case in [["real", {}], ["west", {"west": 45}]]:
		HistoryVisuals.current = HistoryVisuals.make("meiji_taisho", 1877, case[1])
		EraTimeline.set_current("meiji_taisho", 1877)
		var n := 0
		for i in 400:
			if EraTimeline.crowd_outfit("meiji_taisho", "civilian", (i + 0.5) / 400.0) == EraTimeline.OUTFIT_KEYS.find("WESTERN"):
				n += 1
		counts[case[0]] = n
	_check(int(counts["west"]) > int(counts["real"]) + 40, "westernised meiji 1877 crowd has more 洋装 (%s)" % [counts])
	HistoryVisuals.current = HistoryVisuals.make("showa", 1945, {}, "開戦回避")
	EraTimeline.set_current("showa", 1945)
	var sol := 0
	for i in 200:
		if EraTimeline.crowd_outfit("showa", "civilian", (i + 0.5) / 200.0) == EraTimeline.OUTFIT_KEYS.find("SOLDIER"):
			sol += 1
	_check(sol == 0, "no-war 1945 crowd has no soldiers / 国民服")
	HistoryVisuals.current = {}
	EraTimeline.set_current("", 0)


# ------------------------------------------------------------------ 3. 2026年
func _present() -> void:
	var real := HistoryVisuals.present_from(HistoryVisuals.make("present", 2026, {}, "敗戦"))
	var peace := HistoryVisuals.present_from(HistoryVisuals.make("present", 2026, {}, "開戦回避"))
	var war := HistoryVisuals.present_from(HistoryVisuals.make("present", 2026, {}, "本土決戦"))
	var osaka := HistoryVisuals.present_from(HistoryVisuals.make("present", 2026, {}, "敗戦", "大坂"))
	var poor := HistoryVisuals.present_from(HistoryVisuals.make("present", 2026, {"industry": -50}, "敗戦"))
	_check(real["style"] == "modern" and real["lang"] == "ja_en" and real["city"] == "東京", "2026 real: modern Tokyo, ja+en signs (%s)" % [real])
	_check(peace["style"] == "prewar" and peace["lang"] == "ja", "2026 no war: pre-war buildings survive, Japanese-only signs")
	_check(war["style"] == "blocks", "2026 本土決戦: rebuilt blocks + memorial")
	_check(osaka["city"] == "大坂", "2026 capital 大坂")
	_check(poor["style"] == "wood", "2026 industry far behind: wooden low town")


# ------------------------------------------------------------------ 4. 実際の箱庭
func _count_feature(w: EraWorld) -> Array:
	return (w.get_meta("hv_stats", {}) as Dictionary).get("features", [])


func _worlds() -> void:
	var era := db.get_era("meiji_taisho")
	var w0: EraWorld = EraWorld.build(era, 1877, {"vis": HistoryVisuals.make("meiji_taisho", 1877, {})})
	get_tree().root.add_child(w0)
	await get_tree().process_frame
	var n0: int = w0.destruction.units.size()
	var f0 := _count_feature(w0)
	_check("railway" in f0, "meiji 1877 real world: railway built (%s)" % [f0])
	_check(not ("silk_mill" in f0), "meiji 1877 real world: no silk mill")
	for id in w0.destruction.units:
		_kind_cache[id] = str(w0.destruction.units[id].kind)
	w0.queue_free()
	await get_tree().process_frame
	var w1: EraWorld = EraWorld.build(era, 1877, {"vis": HistoryVisuals.make("meiji_taisho", 1877, {"industry": 30, "west": 35}, "敗戦", "大坂", 12.0)})
	get_tree().root.add_child(w1)
	await get_tree().process_frame
	var f1 := _count_feature(w1)
	var st1: Dictionary = w1.get_meta("hv_stats", {})
	_check("silk_mill" in f1 and "brick_town" in f1, "industrialised meiji 1877: silk mill + brick town built (%s)" % [f1])
	_check(int(st1.get("swapped", 0)) >= 3, "machiya replaced by brick (%d)" % int(st1.get("swapped", 0)))
	_check(w1.destruction.units.size() > n0, "more units in the industrialised world (%d > %d)" % [w1.destruction.units.size(), n0])
	_check(f1.any(func(x): return str(x).begins_with("navy_")), "great power: warships at Yokohama (%s)" % [f1])
	_check(f1.any(func(x): return str(x).begins_with("capital_")), "capital elsewhere: sign at the capital")
	var vids: Array = w1.get_meta("hv_vanish", [])
	var gone := vids.filter(func(id): return w1.destruction.units.has(id) and w1.destruction.units[id].destroyed and w1.destruction.units[id].hide_bits == 3)
	_check(not vids.is_empty() and gone.size() == vids.size(), "swapped originals are hidden (%d/%d)" % [gone.size(), vids.size()])
	var same := true
	for id in range(1, mini(n0, 400)):
		if not w1.destruction.units.has(id) or str(w1.destruction.units[id].kind) != str(_kind_cache.get(id, "")):
			same = false
	_check(same, "original unit ids unchanged")
	_check(w1.find_children("HistorySign", "Label3D", true, false).size() >= 1, "sign label exists")
	w1.queue_free()
	await get_tree().process_frame
	var w2: EraWorld = EraWorld.build(era, 1877, {"vis": HistoryVisuals.make("meiji_taisho", 1877, {"west": -40})})
	get_tree().root.add_child(w2)
	await get_tree().process_frame
	_check("late_brick" in _count_feature(w2) and int(w2.timeline_stats.get("history", 0)) > 0, "west lag: brick → machiya, lamps removed (%s, %d)" % [_count_feature(w2), int(w2.timeline_stats.get("history", 0))])
	w2.queue_free()
	await get_tree().process_frame
	# 昭和 1945：戦争の帰趨で焼け跡が変わる
	var sh := db.get_era("showa")
	var ruins := {}
	for tier in ["敗戦", "開戦回避", "本土決戦", "早期講和"]:
		var w3: EraWorld = EraWorld.build(sh, 1945, {"vis": HistoryVisuals.make("showa", 1945, {}, tier)})
		get_tree().root.add_child(w3)
		await get_tree().process_frame
		ruins[tier] = int(w3.timeline_stats.get("ruin", 0))
		if tier == "敗戦":
			_check("signs_occupation" in _count_feature(w3), "敗戦 1945: occupation signs")
		w3.queue_free()
		await get_tree().process_frame
	_check(int(ruins["開戦回避"]) == 0 and int(ruins["敗戦"]) > 10, "1945: no ruins without the war, ruins after 空襲 (%s)" % [ruins])
	_check(int(ruins["本土決戦"]) > int(ruins["敗戦"]) and int(ruins["早期講和"]) < int(ruins["敗戦"]), "本土決戦 > 敗戦 > 早期講和 ruins")
	# 江戸 1853：産業革命が早い世界では鉄道と電信
	var w4: EraWorld = EraWorld.build(db.get_era("edo"), 1853, {"vis": HistoryVisuals.make("edo", 1853, {"industry": 40, "west": 40})})
	get_tree().root.add_child(w4)
	await get_tree().process_frame
	var f4 := _count_feature(w4)
	_check("railway" in f4 and "telegraph" in f4, "edo 1853 industrialised: railway + telegraph (%s)" % [f4])
	w4.queue_free()
	await get_tree().process_frame


var _kind_cache := {}


func _hub() -> void:
	var S = load("res://scripts/world/present_world.gd")
	if S == null:
		_check(false, "present_world.gd loads")
		return
	var looks := {}
	for case in [["real", "敗戦", ""], ["peace", "開戦回避", ""], ["war", "本土決戦", "大坂"]]:
		var pr := HistoryVisuals.present_from(HistoryVisuals.make("present", 2026, {}, case[1], case[2]))
		var hw: Node3D = S.build(pr)
		get_tree().root.add_child(hw)
		await get_tree().process_frame
		looks[case[0]] = hw.get("signature")
		_check(hw.has_method("height_at") and hw.get("half_size") > 10.0, "hub %s builds (%s)" % [case[0], hw.get("signature")])
		_check(hw.get("console_pos") is Vector3, "hub %s has the time machine console" % case[0])
		hw.queue_free()
		await get_tree().process_frame
	_check(looks["real"] != looks["peace"] and looks["real"] != looks["war"], "hub town looks differ by history (%s)" % [looks])


## Flow：ハブが歩ける 3D になり、操作卓から一覧（採点ハブの画面）を開き、研究所へ戻れる
func _flow_hub() -> void:
	var G: Node = get_tree().root.get_node_or_null("Game")
	if G == null:
		return
	var was: bool = G.state.exam_submitted
	G.state.exam_submitted = true
	var flow: Node = load("res://scripts/ui/flow.gd").new()
	flow.name = "FlowHV"
	flow.allow_backdrop = false
	get_tree().root.add_child(flow)
	await get_tree().create_timer(0.3).timeout
	flow.show_hub()
	await get_tree().create_timer(0.5).timeout
	_check(flow.hub3d != null and flow.current == "hub" and not G.input_blocked, "flow: 3D hub walkable (current=%s)" % flow.current)
	_check(G.world is PresentWorld, "flow: Game.world is the 2026 world")
	flow.hub3d.open_menu.emit()
	await get_tree().create_timer(0.4).timeout
	_check(flow.current == "hub" and G.input_blocked and not flow.hub3d.active, "flow: console opens the era list (HubScreen)")
	flow._show_hub3d()
	await get_tree().create_timer(0.3).timeout
	_check(flow.hub3d.active and not G.input_blocked, "flow: back to walking")
	flow.show_title()
	await get_tree().create_timer(0.3).timeout
	_check(flow.hub3d == null, "flow: hub world freed on title")
	flow.queue_free()
	G.state.exam_submitted = was
	await get_tree().process_frame
