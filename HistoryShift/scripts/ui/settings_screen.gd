extends RefCounted
## 設定モーダル。SettingsScreen.open(parent)


static func open(parent: Control, on_close: Callable = Callable()) -> Control:
	var r := JSUI.modal(parent, 820, "設定")
	var overlay: Control = r[0]
	var outer: VBoxContainer = r[1]
	var vals := GameSettings.values
	# 項目はスクロールする枠の中に入れる（画面の高さの約 6 割まで。閉じるボタンは枠の外で常に見える）
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	var vh := 1080.0
	if parent.is_inside_tree():
		vh = parent.get_viewport_rect().size.y
	scroll.custom_minimum_size = Vector2(0, clampf(vh * 0.6, 360.0, 640.0))
	outer.add_child(scroll)
	var pad := MarginContainer.new()
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pad.add_theme_constant_override("margin_right", 16)   # スクロールバーと重ならないように
	scroll.add_child(pad)
	var v := JSUI.vbox(10)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pad.add_child(v)

	# 画質
	var q := OptionButton.new()
	for i in GameSettings.QUALITY_NAMES.size():
		q.add_item(GameSettings.QUALITY_NAMES[i], i)
	q.selected = int(vals["quality"])
	q.custom_minimum_size = Vector2(200, 44)
	q.add_theme_font_size_override("font_size", 20)
	q.item_selected.connect(func(i: int): UISfx.play("click"); GameSettings.set_value("quality", i))
	v.add_child(_row("画質", "影・描画距離・植生の密度（次の時空跳躍から反映）", q))

	var sd := CheckButton.new()
	sd.button_pressed = bool(vals["sdfgi"])
	sd.text = "オン" if sd.button_pressed else "オフ"
	sd.toggled.connect(func(on: bool): UISfx.play("click"); sd.text = "オン" if on else "オフ"; GameSettings.set_value("sdfgi", on))
	v.add_child(_row("SDFGI（大域照明）", "高品質な間接光。重い場合はオフに", sd))

	var sens := _slider(0.2, 3.0, 0.05, float(vals["mouse_sensitivity"]), func(x: float): return "%.2f×" % x,
		func(x: float): GameSettings.set_value("mouse_sensitivity", x))
	v.add_child(_row("マウス感度", "視点操作の速さ", sens))

	# 音量（Master と Music / SFX / Ambience / Voice バス）。画面に収まるよう 2 列にまとめる
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 28)
	grid.add_theme_constant_override("v_separation", 6)
	for spec in [["volume", "全体"], ["vol_music", "BGM"], ["vol_sfx", "効果音"], ["vol_ambience", "環境音"], ["vol_voice", "声"]]:
		var key := String(spec[0])
		var cell := JSUI.hbox(10)
		var lb := JSUI.label(String(spec[1]), 18, Color.WHITE, JSUI.sans_bold())
		lb.custom_minimum_size = Vector2(70, 0)
		cell.add_child(lb)
		var sl := _slider(0.0, 1.0, 0.01, float(vals.get(key, 1.0)), func(x: float): return "%d%%" % roundi(x * 100),
			func(x: float): GameSettings.set_value(key, x))
		(sl.get_child(0) as Control).custom_minimum_size = Vector2(120, 30)
		cell.add_child(sl)
		grid.add_child(cell)
	v.add_child(_row("音量", "", grid))

	var fs := CheckButton.new()
	fs.button_pressed = bool(vals["fullscreen"])
	fs.text = "オン" if fs.button_pressed else "オフ"
	fs.toggled.connect(func(on: bool): UISfx.play("click"); fs.text = "オン" if on else "オフ"; GameSettings.set_value("fullscreen", on))
	v.add_child(_row("フルスクリーン", "", fs))

	var fp := CheckButton.new()
	fp.button_pressed = bool(vals.get("show_fps", true))
	fp.text = "オン" if fp.button_pressed else "オフ"
	fp.toggled.connect(func(on: bool): UISfx.play("click"); fp.text = "オン" if on else "オフ"; GameSettings.set_value("show_fps", on))
	v.add_child(_row("FPS 表示", "画面右下に1秒あたりの描画回数を出す（緑 50以上・黄 30〜49・赤 30未満）", fp))

	# 技術（弟子入り・稽古が面倒な人向け）
	var mm := CheckButton.new()
	mm.button_pressed = bool(vals.get("master_mode", false))
	mm.text = "オン" if mm.button_pressed else "オフ"
	mm.toggled.connect(func(on: bool): UISfx.play("click"); mm.text = "オン" if on else "オフ"; GameSettings.set_value("master_mode", on))
	v.add_child(_row("技術完全習得モード", "すべての技能が100（極み）になり、すべてのレシピを作れる。オフに戻すと学んだ値に戻る", mm))
	var sa := CheckButton.new()
	sa.button_pressed = bool(vals.get("start_armed", false))
	sa.text = "オン" if sa.button_pressed else "オフ"
	sa.toggled.connect(func(on: bool): UISfx.play("click"); sa.text = "オン" if on else "オフ"; GameSettings.set_value("start_armed", on))
	v.add_child(_row("最初から武装", "時空跳躍のたびに「時空銃」（弾は尽きない）と焙烙玉などを貸与する", sa))

	# 成人向け：民間人への危害（教育版・未所有では行ごと出さない。scripts/core/civil_harm.gd）
	if MatureContent.is_unlocked():
		v.add_child(_civil_harm_row(parent))

	outer.add_child(JSUI.gap(2))
	var row := JSUI.hbox()
	row.alignment = BoxContainer.ALIGNMENT_END
	var close := JSUI.button("閉じる", "primary", 22, 180)
	close.pressed.connect(func():
		UISfx.play("back")
		GameSettings.save()
		JSUI.close_modal(overlay)
		if on_close.is_valid():
			on_close.call())
	row.add_child(close)
	outer.add_child(row)
	close.call_deferred("grab_focus")
	return overlay


const CIVIL_WARNING := "【注意・成人向け】オンにすると、名もない町人（農民・職人・商人・町人・漁民）が、あなたの攻撃・爆発・火事・瓦礫・乗り物で倒れるようになります（流血や遺体の描写はなく、倒れて消えます）。名のある人物は倒れません。史実の虐殺・戦災に重なる場面では無効です。\n犠牲は手配度を最大にし、その時代の民心離反・一揆や打ちこわしを招き、歴史に「犠牲」として刻まれます。"


static func _civil_harm_row(parent: Control) -> Control:
	var ch := CheckButton.new()
	ch.button_pressed = bool(GameSettings.values.get("civil_harm", false))
	ch.text = "オン" if ch.button_pressed else "オフ"
	ch.toggled.connect(func(on: bool):
		UISfx.play("click")
		if not on:
			ch.text = "オフ"
			GameSettings.set_value("civil_harm", false)
			return
		ch.set_pressed_no_signal(false)
		JSUI.confirm(parent, "民間人への危害（成人向け）", CIVIL_WARNING + "\n\n本当にオンにしますか？", "オンにする", "やめる", func():
			ch.set_pressed_no_signal(true)
			ch.text = "オン"
			GameSettings.set_value("civil_harm", true), true))
	var p := JSUI.panel(JSUI.sb(Color(JSUI.SHU, 0.06), 10, 1, Color(JSUI.SHU, 0.35), 0, 10))
	var h := JSUI.hbox(16)
	p.add_child(h)
	var tv := JSUI.vbox(4)
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tv.add_child(JSUI.label("民間人への危害（成人向け）", 22, Color.WHITE, JSUI.sans_bold()))
	var warn := JSUI.label(CIVIL_WARNING, 15, JSUI.MUTED, null, true)
	warn.custom_minimum_size = Vector2(480, 0)
	tv.add_child(warn)
	h.add_child(tv)
	ch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(ch)
	return p


static func _row(title: String, desc: String, ctl: Control) -> Control:
	var p := JSUI.panel(JSUI.sb(Color(1, 1, 1, 0.03), 10, 1, Color(1, 1, 1, 0.05), 0, 10))
	var h := JSUI.hbox(16)
	p.add_child(h)
	var tv := JSUI.vbox(0)
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tv.add_child(JSUI.label(title, 22, Color.WHITE, JSUI.sans_bold()))
	if desc != "":
		var d := JSUI.label(desc, 16, JSUI.MUTED, null, true)
		d.custom_minimum_size = Vector2(380, 0)
		tv.add_child(d)
	h.add_child(tv)
	ctl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(ctl)
	return p


static func _slider(lo: float, hi: float, step: float, val: float, fmt: Callable, on_change: Callable) -> Control:
	var h := JSUI.hbox(14)
	var s := HSlider.new()
	s.min_value = lo; s.max_value = hi; s.step = step; s.value = val
	s.custom_minimum_size = Vector2(220, 32)
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var l := JSUI.label(fmt.call(val), 20, JSUI.CYAN, JSUI.sans_bold())
	l.custom_minimum_size = Vector2(76, 0)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	s.value_changed.connect(func(x: float): l.text = fmt.call(x); on_change.call(x))
	h.add_child(s)
	h.add_child(l)
	return h
