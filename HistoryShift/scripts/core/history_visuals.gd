class_name HistoryVisuals
extends RefCounted
## 歴史の見た目（data/visuals/history_visuals.json）。HistoryState の再計算結果を「その時代のその年に、史実とどれだけ違うか」の
## 小さな辞書（profile）にまとめる。箱庭（HistoryDressing・TimelineWorld）と町人の装い（EraTimeline.crowd_outfit）とハブ（PresentWorld）が読む。
## Game を参照しない（-s で走るテストからも使える）。
##
## profile = {era, year, axes{industry, west, prosperity, military}, lead{同じキー: 史実より何年早いか（負は遅い）},
##            capital, capital_base, war, standing_delta, standing_score}
## present = {city, lang, lang_label, style, style_label, height, war, axes, lead, capital}

const PATH := "res://data/visuals/history_visuals.json"
static var _data := {}
static var _base_cache := {}     # db の id → 史実の再計算結果（snaps・standing）
## いまの箱庭の profile（Session が設定。町人の装いが読む）
static var current := {}


static func data() -> Dictionary:
	if _data.is_empty():
		var v: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH)) if FileAccess.file_exists(PATH) else null
		_data = v if v is Dictionary else {"axes": {}, "features": []}
	return _data


static func clear_cache() -> void:
	_base_cache.clear()


## 史実（介入・混乱・行動なし）の再計算。db ごとに一度だけ
static func baseline(st: HistoryState) -> Dictionary:
	var key := st.db.get_instance_id()
	if not _base_cache.has(key):
		_base_cache[key] = st._simulate_war({}, [], [])
	return _base_cache[key]


## 設問ごとの状態の列から、その時代のその年の状態（その年以前で最後の設問の後）
static func state_at(snaps: Array, era_id: String, year: int) -> Dictionary:
	var me := HistoryDB.ERA_ORDER.find(era_id)
	var best: Dictionary = HistoryState.base_state()
	for s in snaps:
		var e := int(s["e"])
		if e < me or (e == me and (year == 0 or int(s["y"]) <= year)):
			best = s["st"]
		elif e > me:
			break
	return best


static func axis_value(axis: Dictionary, cur: Dictionary, base: Dictionary) -> float:
	var v := 0.0
	var wv: Dictionary = axis.get("vars", {})
	for k in wv:
		v += float(wv[k]) * (float(cur.get(k, 0.0)) - float(base.get(k, 0.0)))
	return v


static func lead_years(axis: Dictionary, v: float) -> int:
	var m := float(axis.get("max_years", 60))
	return int(round(clampf(v * float(axis.get("years_per_point", 1.0)), -m, m)))


## 国際的地位：その年以前で最後の時点の（いま − 史実）
static func _standing_at(sd: Dictionary, year: int) -> Array:
	var out := [0.0, 0.0]
	for p in sd.get("points", []):
		if year == 0 or int(p["year"]) <= year:
			out = [float(p["score"]) - float(p["base"]), float(p["score"])]
	return out


## 箱庭の profile。st = Game.state
static func profile(st: HistoryState, era_id: String, year: int) -> Dictionary:
	if st == null:
		return {}
	var base := baseline(st)
	var cur_st := state_at(st.snapshots, era_id, year)
	var base_st := state_at(base.get("snaps", []), era_id, year)
	var sd := _standing_at(st.standing, year)
	return from_states(era_id, year, cur_st, base_st, st.war_tier(), sd[0], sd[1])


static func from_states(era_id: String, year: int, cur_st: Dictionary, base_st: Dictionary, war_tier: String, standing_delta := 0.0, standing_score := 0.0) -> Dictionary:
	var axes := {}
	var lead := {}
	var ad: Dictionary = data().get("axes", {})
	for k in ad:
		var v := axis_value(ad[k], cur_st, base_st)
		axes[k] = snappedf(v, 0.01)
		lead[k] = lead_years(ad[k], v)
	return {"era": era_id, "year": year, "axes": axes, "lead": lead,
		"capital": str(cur_st.get("capital", "")), "capital_base": str(base_st.get("capital", "")),
		"war": war_tier, "standing_delta": standing_delta, "standing_score": standing_score}


## 手で作る profile（テスト・写真用）：lead を年で直接与える
static func make(era_id: String, year: int, p_lead: Dictionary, war_tier := "敗戦", capital := "", standing_delta := 0.0) -> Dictionary:
	var lead := {"industry": 0, "west": 0, "prosperity": 0, "military": 0}
	var axes := {}
	var ad: Dictionary = data().get("axes", {})
	for k in p_lead:
		lead[k] = int(p_lead[k])
	for k in lead:
		var ypp := float(ad.get(k, {}).get("years_per_point", 1.0))
		axes[k] = float(lead[k]) / maxf(ypp, 0.01)
	return {"era": era_id, "year": year, "axes": axes, "lead": lead, "capital": capital, "capital_base": "",
		"war": war_tier, "standing_delta": standing_delta, "standing_score": 0.0}


static func lead_of(p: Dictionary, axis: String) -> int:
	return int(p.get("lead", {}).get(axis, 0))


# ================================================================== 箱庭の規則
static func _in(v: Variant, key: String) -> bool:
	return (v is Array and key in v) or (v is String and v == key)


static func _list(v: Variant) -> Array:
	return v if v is Array else [v]


## この箱庭に現れる追加の建物・設備（features）。[{def, lead, frac}]
static func features_for(p: Dictionary) -> Array:
	var out: Array = []
	if p.is_empty():
		return out
	var era := str(p.get("era", ""))
	var year := int(p.get("year", 0))
	if year == 0:
		return out
	for f in data().get("features", []):
		if not _in(f.get("eras", []), era):
			continue
		var ld := lead_of(p, str(f.get("axis", "industry")))
		if not bool(f.get("real", false)) and ld < int(f.get("min_lead", 1)):
			continue
		if year + ld < int(f["year"]) or year < int(f.get("earliest", -99999)):
			continue
		var frac := 0.0
		if f.has("frac_per_year"):
			frac = minf(float(f.get("max_frac", 0.5)), float(f["frac_per_year"]) * float(year + ld - int(f["year"]) + 6))
		out.append({"def": f, "lead": ld, "frac": frac})
	return out


## 史実より遅れているので、まだ無い建物（absent）。[{def, frac}]
static func absent_for(p: Dictionary) -> Array:
	var out: Array = []
	if p.is_empty():
		return out
	var era := str(p.get("era", ""))
	var year := int(p.get("year", 0))
	for r in data().get("absent", []):
		if not _in(r.get("eras", []), era):
			continue
		var ld := lead_of(p, str(r.get("axis", "west")))
		if ld >= 0 or year == 0:
			continue
		if year + ld < int(r["year"]):
			out.append({"def": r, "frac": clampf(float(int(r["year"]) - (year + ld)) / 25.0, 0.3, 1.0)})
	return out


## 戦争の帰趨（昭和の applies_from 年以後）。{tier, ruin_mult, extra_ruin, signs, crowd, basis}
static func war_for(p: Dictionary) -> Dictionary:
	var wd: Dictionary = data().get("war", {})
	if str(p.get("era", "")) != "showa" or int(p.get("year", 0)) < int(wd.get("applies_from", 1945)):
		return {}
	var tier := str(p.get("war", ""))
	var t: Dictionary = wd.get("tiers", {}).get(tier, {})
	if t.is_empty():
		return {}
	var out := t.duplicate(true)
	out["tier"] = tier
	var year := int(p["year"])
	var ss: Dictionary = wd.get("sign_sets", {}).get(str(t.get("signs", "")), {})
	out["sign_set"] = ss if not ss.is_empty() and year <= int(ss.get("until", 9999)) else {}
	var late: Dictionary = t.get("late_ruin", {})
	if year > int(wd.get("applies_from", 1945)):
		out["ruin_mult"] = 1.0
		out["extra_ruin"] = late.get("rules", []) if year <= int(late.get("until", 0)) else []
	if year >= 1950:
		out.erase("crowd")
	return out


## 首都が史実と違うとき {city, style, text, sub, basis}（箱庭の都に看板を立てる）
static func capital_for(p: Dictionary) -> Dictionary:
	var cd: Dictionary = data().get("capital", {})
	var cur := str(p.get("capital", ""))
	if cur == str(p.get("capital_base", "")) or cur == "":
		return {}
	var era := str(p.get("era", ""))
	var spec: Dictionary = cd.get("eras", {}).get(era, {})
	var city := str(cd.get("city", {}).get(cur, cur))
	if spec.is_empty() or city == str(cd.get("here", {}).get(era, "")):
		return {}
	var out := {"city": city, "style": str(spec.get("style", "board"))}
	for k in ["text", "sub", "basis"]:
		out[k] = str(spec.get(k, "")).replace("{city}", city)
	return out


## 港の艦隊（国際的地位が史実より standing_delta 以上高い）。{kind, count, label, basis, port_extra}
static func navy_for(p: Dictionary) -> Dictionary:
	var nd: Dictionary = data().get("navy", {})
	if not _in(nd.get("eras", []), str(p.get("era", ""))) or float(p.get("standing_delta", 0.0)) < float(nd.get("standing_delta", 8)):
		return {}
	var year := int(p.get("year", 0)) + maxi(0, lead_of(p, "industry"))
	for v in nd.get("variants", []):
		if year <= int(v["until"]):
			var out: Dictionary = v.duplicate()
			out["port_extra"] = nd.get("port_extra", {})
			return out
	return {}


## 町人の装いの比率を、この世界の歴史で変える（EraTimeline.crowd_outfit が呼ぶ）
static func adjust_crowd(mix: Dictionary, era_id: String, year: int) -> Dictionary:
	var p := current
	if p.is_empty() or str(p.get("era", "")) != era_id or int(p.get("year", 0)) != year:
		return mix
	var wr: Dictionary = war_for(p)
	if wr.has("crowd"):
		return (wr["crowd"] as Dictionary).duplicate()
	var out := mix.duplicate()
	var changed := false
	for r in data().get("crowd", []):
		if not _in(r.get("eras", []), era_id):
			continue
		var ld := lead_of(p, str(r.get("axis", "west")))
		if ld == 0:
			continue
		if out.is_empty():
			out = (data().get("default_crowd", {}).get(era_id, {}) as Dictionary).duplicate()
			if out.is_empty():
				return mix
		changed = true
		var k := str(r["key"])
		var v := float(out.get(k, 0.0)) + float(r["per_year"]) * ld
		v = clampf(v, float(r.get("min", 0.0)), maxf(float(r.get("max", 1.0)), float(out.get(k, 0.0))))
		out[k] = v
	return out if changed else mix


# ================================================================== 2026年（ハブ）
## 最終の歴史から現代の町の姿。st = Game.state（null なら史実）
static func present(st: HistoryState) -> Dictionary:
	if st == null:
		return present_from(make("present", 2026, {}, "敗戦"))
	var base := baseline(st)
	var p := from_states("present", 2026, st.final_state, base.get("final", HistoryState.base_state()), st.war_tier())
	return present_from(p)


static func present_from(p: Dictionary) -> Dictionary:
	var pd: Dictionary = data().get("present", {})
	var lead: Dictionary = p.get("lead", {})
	var tier := str(p.get("war", "敗戦"))
	var out := {"war": tier, "lead": lead, "axes": p.get("axes", {}), "capital": str(p.get("capital", ""))}
	var cd: Dictionary = data().get("capital", {})
	var city := str(cd.get("city", {}).get(str(p.get("capital", "")), ""))
	out["city"] = city if city != "" and city != "江戸" else "東京"
	for group in [["lang", "lang"], ["style", "style"]]:
		for r in pd.get(group[0], []):
			if _rule_ok(r, p):
				out[group[1]] = str(r[group[1]])
				out[group[1] + "_label"] = str(r.get("label", ""))
				break
	var pr: Dictionary = pd.get("prosperity", {})
	out["height"] = clampf(1.0 + float(p.get("axes", {}).get(str(pr.get("axis", "prosperity")), 0.0)) * float(pr.get("height_per_point", 0.02)),
		float(pr.get("min", 0.5)), float(pr.get("max", 1.8)))
	return out


static func _rule_ok(r: Dictionary, p: Dictionary) -> bool:
	if r.has("if_war") and not (str(p.get("war", "")) in r["if_war"]):
		return false
	for k in r.get("if", {}):
		var c := str(r["if"][k])
		var v := float(p.get("axes", {}).get(k, 0.0)) * float(data().get("axes", {}).get(k, {}).get("years_per_point", 1.0))
		var n := float(c.trim_prefix(">=").trim_prefix("<="))
		if c.begins_with("<=") and not (v <= n):
			return false
		if c.begins_with(">=") and not (v >= n):
			return false
	return true


## 説明（UI・ログ用）：この箱庭で歴史のせいで変わって見えるもの
static func summary(p: Dictionary) -> PackedStringArray:
	var out: PackedStringArray = []
	for f in features_for(p):
		var d: Dictionary = f["def"]
		if not bool(d.get("real", false)) or int(f["lead"]) != 0:
			out.append("・%s（%s）" % [d.get("label", d["id"]), d.get("basis", "")])
	for a in absent_for(p):
		out.append("・" + str(a["def"].get("basis", "")))
	var wr: Dictionary = war_for(p)
	if not wr.is_empty() and wr["tier"] != "敗戦":
		out.append("・" + str(wr.get("basis", "")))
	var cp: Dictionary = capital_for(p)
	if not cp.is_empty():
		out.append("・" + cp["basis"])
	var nv: Dictionary = navy_for(p)
	if not nv.is_empty():
		out.append("・%s（%s）" % [nv["label"], nv["basis"]])
	return out
