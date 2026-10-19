extends Control

const StateScript := preload("res://scripts/state.gd")
const PlotScript := preload("res://scripts/plot.gd")
const HudScript := preload("res://scripts/hud.gd")
const Orbit := preload("res://scripts/orbit_model.gd")

const BASE := Vector2i(1920, 1080)
const PLOT_RECT := Rect2(396.0, 124.0, 1128.0, 752.0)

var state = StateScript.new()
var vp: SubViewport
var plot
var hud
var _shot_path := ""
var _scene := ""
var _gif_dir := ""
var _frames := 0
var _drag := false
var end_panel

func _ready() -> void:
	_shot_path = OS.get_environment("DSH_SHOT")
	_scene = OS.get_environment("DSH_SCENE")
	_gif_dir = OS.get_environment("DSH_GIF")
	# 截图/GIF 时先冻结动效，让相机不自转，画面可复现
	if _shot_path != "" or _gif_dir != "":
		state.capture = true
		state.paused = true
	print("MAIN READY shot=", _shot_path, " scene=", _scene, " gif=", _gif_dir)
	var st := Orbit.selftest()
	print("ORBIT SELFTEST period_s=", st.period_s,
		" two_body_pos_err_m=", st.two_body_pos_err_m,
		" two_body_vel_err_mps=", st.two_body_vel_err_mps,
		" local_err_300s_m=", st.local_err_300s_m,
		" local_err_2000s_m=", st.local_err_2000s_m)
	print("L1 TIDAL kx=", st.kx, " ky=", st.ky, " kz=", st.kz, " n=", st.n_lunar)
	get_window().title = "AD-FLEET // 战术显控台 — V1.5"
	get_window().size = Vector2i(1600, 900)
	var screen := DisplayServer.screen_get_size()
	get_window().position = Vector2i((screen.x - 1600) / 2, (screen.y - 900) / 2)
	if _shot_path != "" or _gif_dir != "":
		get_window().borderless = true
		get_window().size = Vector2i(1920, 1080)
		get_window().position = Vector2i(0, 0)

	var svc := SubViewportContainer.new()
	svc.stretch = true
	svc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	svc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(svc)

	vp = SubViewport.new()
	vp.size = BASE
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.transparent_bg = false
	vp.gui_disable_input = true
	svc.add_child(vp)

	var root := Control.new()
	root.size = Vector2(BASE)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vp.add_child(root)

	plot = PlotScript.new()
	plot.state = state
	plot.position = Vector2(396, 124)
	plot.size = Vector2(1128, 752)
	plot.clip_contents = true
	plot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(plot)

	hud = HudScript.new()
	hud.state = state
	hud.position = Vector2.ZERO
	hud.size = Vector2(BASE)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(hud)

	var crt := ColorRect.new()
	crt.position = Vector2(40, 40)
	crt.size = Vector2(1840, 1000)
	crt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/crt.gdshader")
	crt.material = mat
	root.add_child(crt)

	# P1g：END 归档页由 hud.gd 负责；main 只保留 R/Q 键位转发，避免双 EndPanel。
	end_panel = null

	if _shot_path != "":
		state.boot_t = 2.0
		_set_scene(_scene)
	elif _gif_dir != "":
		_capture_gif(_gif_dir)

func _set_scene(sc: String) -> void:
	state.sensor = 0
	if sc == "ir":
		state.sensor = 1
	elif sc == "radar":
		state.sensor = 2
	elif sc == "optical":
		state.sensor = 3
	elif sc == "iff":
		state.sensor = 4
	elif sc == "elint":
		state.sensor = 5
	if sc == "boot":
		state.boot_t = 1.0
	if hud != null:
		hud.menu_open = (sc == "menu")
		hud.menu_t = 0.5
	state.sensor_fx_t = -1.0
	# 基准：DSH_DATUM=earth|moon|l1（可选）
	var dm := OS.get_environment("DSH_DATUM")
	if dm != "":
		state.set_datum(dm)
	# 传感器：DSH_SENSOR=0..5（可选，覆盖 DSH_SCENE 的图层）
	var sn := OS.get_environment("DSH_SENSOR")
	if sn != "":
		state.sensor = clampi(int(sn), 0, state.sensors.size() - 1)
		state.sensor_fx_t = -1.0
	plot.reset_camera()
	# 视图：flat = 正交战略图；l1 / moon = 切到对应基准的 3D 板
	if sc == "flat" or sc == "planar":
		plot.force_planar(true)
	elif sc == "l1":
		state.set_datum("L1")
		plot.force_planar(false)
	elif sc == "moon":
		state.set_datum("MOON")
		plot.force_planar(false)
	elif sc == "l1flat":
		state.set_datum("L1")
		plot.force_planar(true)
	elif sc == "moonflat":
		state.set_datum("MOON")
		plot.force_planar(true)
	# 可选的相机预设：DSH_YAW / DSH_PITCH（度）/ DSH_DIST（km）
	var ys := OS.get_environment("DSH_YAW")
	if ys != "":
		plot.yaw3d = deg_to_rad(float(ys))
		plot.yaw2d = plot.yaw3d
	var ps := OS.get_environment("DSH_PITCH")
	if ps != "":
		plot.pitch = deg_to_rad(float(ps))
	var ds := OS.get_environment("DSH_DIST")
	if ds != "":
		plot.dist = clampf(float(ds) * 1000.0, 300000.0, 1400000.0)
	var rs := OS.get_environment("DSH_ROLL")
	if rs != "":
		plot.roll3d = deg_to_rad(float(rs))
		plot.roll_unlocked = true
	if OS.get_environment("DSH_ROLL_UNLOCK") == "1":
		plot.roll_unlocked = true
	# 调试/验证用：DSH_ZOOM=+n 滚轮放大 n 次，-n 缩小；DSH_FLIP=1 翻转；触发自动压平切换
	var zs := OS.get_environment("DSH_ZOOM")
	if zs != "":
		var zn := int(zs)
		for i in range(absi(zn)):
			plot.zoom_map(0.9 if zn > 0 else 1.1)
	if OS.get_environment("DSH_FLIP") == "1":
		plot.flip_map()
	# 调试/验证用：DSH_CLOCK 直接设定仿真时刻（秒），用来看预测/历史随时间推进
	var ck := OS.get_environment("DSH_CLOCK")
	if ck != "":
		state.clock = float(ck)
	# P1d 截图钩子：DSH_CMD=demo 显示脚本化演示（BURN 待生效 + SHADOW 待生效）
	#                  DSH_CMD=queue 额外叠一条待生效命令 + 一条已撤销命令
	var cmd_env := OS.get_environment("DSH_CMD")
	if cmd_env != "":
		if ck == "":
			state.clock = state.clock - state.tau() + 3.2
		state.refresh(state.clock)
		if cmd_env == "queue":
			state.issue_command("SHADOW", {"hold_km": 40.0}, "案卷 4471")
			var extra: Dictionary = state.issue_command("BURN", {
				"exec_t": state.tau() + 16.8, "dv_ms": 30.0, "brg": 120.0, "elev": 5.0,
			})
			state.abort_command(String(extra.get("id", "")))
			state.cmd_model.selected_id = "CMD-03"
		elif cmd_env == "sim":
			# P1e：命令状态机多态 + 传感器开关/EMCON + preview draft 同屏
			state.set_sensor("apsis", 2, true)      # YW-R9 手动开机（早于脚本时序）-> EMIT
			state.set_sensor("harmattan", 1, false) # CH-R0 手动关闭
			state.set_emcon("summons_4471", true)   # 敌舰 EMCON（发射类全关）
			state.issue_command("SHADOW", {"hold_km": 40.0}, "案卷 4471")
			var extra2: Dictionary = state.issue_command("BURN", {
				"exec_t": state.tau() + 55.0, "dv_ms": 30.0, "brg": 120.0, "elev": 5.0,
			})
			state.abort_command(String(extra2.get("id", "")))
			state.preview_command("BURN", {
				"exec_t": state.tau() + 40.0, "dv_ms": 20.0, "brg": 90.0, "elev": 0.0,
			})
			state.cmd_model.selected_id = "CMD-01"
		print("DSH_CMD ", cmd_env, " commands=", state.commands().size(), " tau=", state.tau())
	state.refresh(state.clock)
	for c in state.commands():
		print("CMD ", c.get("id"), " ", c.get("action"), " ", c.get("status"), " tx=", c.get("tx_t"), " exec=", c.get("exec_t"), " done=", c.get("done_t"))
	print("SCENARIO ", state.scenario_source, " preview=", not state.cmd_model.preview_cmd.is_empty())
	# 截图/验证钩子：DSH_SIM=decision|fire|consequence|report|reportfake|done|end|endfake|restart
	var sim_env := OS.get_environment("DSH_SIM")
	if sim_env != "":
		state.clock = state.clock - state.tau() + maxf(76.0, state.decision_t + 1.0)
		state.exec_left = maxf(0.0, 360.0 - state.tau())
		state.refresh(state.clock)
		match sim_env:
			"decision":
				pass
			"fire", "consequence":
				state.authorize_fire()
			"report":
				state.choose_ending("HOLD")
			"reportfake":
				state.authorize_fire()
				state.finish_consequence()
				state.submit_report("FAKE")
			"done":
				state.choose_ending("EVACUATE")
				state.submit_report("TRUTH")
			"end":
				state.choose_ending("HOLD")
				state.submit_report("TRUTH")
			"endfake":
				state.authorize_fire()
				state.finish_consequence()
				state.submit_report("FAKE")
			"restart":
				state.choose_ending("HOLD")
				state.submit_report("TRUTH")
				state.restart_demo()
		state.refresh(state.clock)
		print("SIM ", sim_env, " phase=", state.tut_phase, " decision=", state.decision_open,
			" report=", state.report_open, " consequence=", state.consequence_open,
			" outcome=", state.outcome, " audit=", state.audit_flag,
			" perjury=", state.perjury_count, " frozen=", state.sim_frozen,
			" end=", state.end_open, " summary_keys=", state.end_summary.size(),
			" radio=", state.radio_feed.size(), " events=", state.event_feed.size())
	print("SCENE ", sc, " datum=", state.datum, " sensor=", state.sensor, " planar=", plot.ortho,
		" tau=", state.tau(), " cmds=", state.commands().size())

func _process(delta: float) -> void:
	if not state.capture and state.boot_t < 2.0:
		state.boot_t = minf(2.0, state.boot_t + delta)
	# 执行窗口：时标锁 1×（可暂停，不可加速）；开火后时间冻结
	if state.exec_locked:
		state.time_scale = 1.0
		if not state.paused and not state.sim_frozen:
			state.exec_left = maxf(0.0, state.exec_left - delta * state.time_scale)
	if not state.paused and not state.sim_frozen:
		state.clock += delta * state.time_scale
	state.elapsed += delta
	# 接触状态向量推进到当前时刻 + HUD 派生量保鲜
	state.refresh(state.clock)
	hud.queue_redraw()
	if end_panel != null:
		end_panel.queue_redraw()

	_frames += 1
	if _shot_path != "" and _frames >= 45:
		var img := vp.get_texture().get_image()
		var err := img.save_png(_shot_path)
		print("SHOT ", img.get_size(), " err=", err, " → ", _shot_path)
		get_tree().quit()

func _capture_gif(dir: String) -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	var n := 120
	var ns := OS.get_environment("DSH_GIF_N")
	if ns != "":
		n = int(ns)
	for i in range(n):
		_apply_demo(float(i) / 12.0)
		await get_tree().process_frame
		await get_tree().process_frame
		var img := vp.get_texture().get_image()
		img.save_png(dir + "/f%03d.png" % i)
	print("GIF FRAMES DONE ", dir)
	get_tree().quit()

func _apply_demo(t: float) -> void:
	state.boot_t = 2.0
	hud.menu_open = false
	var prev := int(state.sensor)
	state.sensor = 0
	if t < 1.6:
		state.boot_t = t
		return
	if t >= 3.6 and t < 4.5:
		hud.menu_open = true
		hud.menu_t = t - 3.6
	if t >= 4.5:
		state.sensor = 1
	if t >= 6.0:
		state.sensor = 2
	if t >= 7.5:
		state.sensor = 3
	if state.sensor != prev:
		state.sensor_fx_t = 0.0

func _mouse_to_base(p: Vector2) -> Vector2:
	if size.x <= 1.0:
		return p
	return p * (Vector2(BASE) / size)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var p := _mouse_to_base(event.position)
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				# 先让 HUD 吃掉（传感器条 / 下拉 / 列表 / 时标）；
				# 菜单开着时任何点击都交给 HUD，由它决定关闭。
				if hud.consumes(p) or hud.menu_open:
					hud.click(p)
					accept_event()
					return
				if state.boot_t >= 1.7 and PLOT_RECT.has_point(p):
					_drag = true
					accept_event()
					return
				hud.click(p)
				accept_event()
			else:
				if _drag:
					_drag = false
					accept_event()
		elif event.pressed and (event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_DOWN):
			if state.boot_t >= 1.7 and PLOT_RECT.has_point(p):
				plot.zoom_map(0.9 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.1)
				accept_event()
	elif event is InputEventMouseMotion and _drag:
		var rel: Vector2 = event.relative
		if size.x > 1.0:
			rel *= Vector2(BASE) / size
		plot.rotate_map(rel.x, rel.y)
		accept_event()

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if event.keycode == KEY_ESCAPE:
		get_tree().quit()
		return
	# P1g：END 页 —— R 重开 / Q 退出
	if state.end_open:
		if event.keycode == KEY_R:
			state.restart_demo()
		elif event.keycode == KEY_Q:
			get_tree().quit()
		return
	# P1f：决断 / 后果 / 报告面板优先吃键（1/2/3 与 F）
	if state.consequence_open:
		if event.keycode == KEY_E or event.keycode == KEY_ENTER:
			state.finish_consequence()
		return
	if state.decision_open:
		match event.keycode:
			KEY_1:
				state.choose_ending("HOLD")
			KEY_2:
				state.choose_ending("EVACUATE")
			KEY_3:
				state.choose_ending("EXPOSE")
			KEY_F:
				state.authorize_fire()
		return
	if state.report_open:
		if event.keycode == KEY_1:
			state.submit_report("TRUTH")
		elif event.keycode == KEY_2:
			state.submit_report("FAKE")
		return
	match event.keycode:
		KEY_SPACE:
			state.paused = not state.paused
		# P1d：1/2/3 预设命令，4 撤销最新待生效（时标锁 1×，时标键移到 5-8）
		KEY_1:
			state.issue_command("STATION", {})
		KEY_2:
			state.issue_command("SHADOW", {"hold_km": 60.0}, "谷神-2")
		KEY_3:
			state.issue_command("BURN", {
				"exec_t": state.tau() + 6.2, "dv_ms": 84.0, "brg": 340.0, "elev": 20.0,
			})
		KEY_4:
			state.abort_latest_command()
		KEY_5:
			state.time_scale = 1.0
			state.paused = false
		KEY_6:
			state.time_scale = 10.0
			state.paused = false
		KEY_7:
			state.time_scale = 60.0
			state.paused = false
		KEY_8:
			state.time_scale = 300.0
			state.paused = false
		KEY_R:
			plot.flip_map()
		KEY_D:
			var d: String = state.cycle_datum()
			print("DATUM → ", d)
		KEY_P:
			plot.set_planar(not plot.ortho)
		KEY_Z:
			var ru: bool = plot.toggle_roll_unlock()
			print("ROLL UNLOCK → ", ru)
		KEY_Q:
			plot.rotate_roll(deg_to_rad(-5.0))
		KEY_E:
			plot.rotate_roll(deg_to_rad(5.0))
		KEY_ESCAPE:
			get_tree().quit()


# ── P1g：END 归档页（只画 END；决断/报告仍由 HUD 覆盖层负责）──
class EndPanel extends Control:
	const P := preload("res://scripts/pal.gd")
	const F := preload("res://scripts/fonts.gd")
	var state

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		if state == null or not bool(state.end_open):
			return
		var r := Rect2(340.0, 276.0, 800.0, 470.0)
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.0, 0.0, 0.0, 0.42))
		draw_rect(r, P.a(P.PANEL, 0.97))
		draw_rect(r, P.a(P.PH, 0.55), false, 1.0)
		draw_rect(Rect2(r.position, Vector2(r.size.x, 2.0)), P.a(P.PH, 0.9))
		var cjk := F.cjk()
		var mono := F.mono()
		draw_string(cjk, r.position + Vector2(16.0, 24.0), "归档 / END — 第一关 · 监督交接（回执已归档）", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, P.PH)
		var es: Dictionary = state.end_summary if state.end_summary is Dictionary else {}
		var outcome := String(es.get("outcome", state.outcome))
		var ending := String(es.get("ending", state.ending_label(outcome)))
		var rep: Dictionary = es.get("reputation", {})
		var rep_txt := ""
		for k in rep.keys():
			rep_txt += "%s %+d  " % [String(k), int(rep[k])]
		var rep_s := "无变化" if rep_txt == "" else rep_txt
		var y := r.position.y + 58.0
		draw_string(mono, Vector2(r.position.x + 16.0, y), "OUTCOME %s / %s    REPORT %s    PERJURY %d    AUDIT %s" % [
			outcome, ending, String(es.get("report_choice", state.report_choice)),
			int(es.get("perjury_count", state.perjury_count)),
			"TRUE" if bool(es.get("audit_flag", state.audit_flag)) else "FALSE"],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 10, P.a(P.AMBER, 0.95))
		y += 20.0
		draw_string(mono, Vector2(r.position.x + 16.0, y), "声望 %s · 窗口消耗 %ds · FLAGS %s" % [
			rep_s, int(float(es.get("window_used_s", 0.0))), _flags_str(es)],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 9, P.a(P.FAINT, 0.95))
		y += 26.0
		var report := String(es.get("report_text", state.report_text))
		for line in _wrap(report, 46):
			draw_string(cjk, Vector2(r.position.x + 16.0, y), String(line), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, P.TXT)
			y += 18.0
		var fy := r.end.y - 52.0
		draw_string(cjk, Vector2(r.position.x + 16.0, fy), "R 重开演示 · ESC / Q 退出", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, P.a(P.PH, 0.85))
		draw_string(cjk, Vector2(r.position.x + 16.0, fy + 18.0), "报告文本 / flags 已写入 state.end_summary，供后续审裁与剧情读取。", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, P.a(P.FAINT, 0.9))

	func _wrap(s: String, n: int) -> Array:
		var out: Array = []
		var line := ""
		for i in s.length():
			line += s[i]
			if line.length() >= n:
				out.append(line)
				line = ""
		if line != "":
			out.append(line)
		return out

	func _flags_str(es: Dictionary) -> String:
		var fl: Dictionary = es.get("flags", {})
		var out := ""
		for k in fl.keys():
			out += "%s=%s " % [String(k), str(fl[k])]
		return out.strip_edges()

