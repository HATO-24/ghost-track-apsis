extends Node

# P6：录屏/回归用自动演示导演。
# 只由 main.gd 在 DSH_DEMO=1 时创建；不进入正常玩家流程。

const FPS := 30.0

var main_ref
var _caption_label: Label

func start() -> void:
	if main_ref == null:
		return
	_caption_label = main_ref._demo_caption
	await _wait(0.8)
	await _segment_prelude()
	await _segment_sensors_and_orders()
	await _segment_evidence()
	await _segment_decision_and_report()
	await _wait(4.0)
	get_tree().quit()

func _wait(sec: float) -> void:
	var frames := maxi(1, int(round(sec * FPS)))
	for i in frames:
		await get_tree().process_frame

func _caption(s: String) -> void:
	if _caption_label != null:
		_caption_label.text = s
	print("DEMO ", s)

func _st():
	return main_ref.state

func _hud():
	return main_ref.hud

func _segment_prelude() -> void:
	var st = _st()
	_caption("01 / 航行准备 · L4 HAMMER → L1 MERIDIAN")
	await _wait(1.4)
	st.prelude_choose_route("meridian")
	_caption("01 / 航行准备 · " + st.navigation_stage())
	await _wait(0.9)
	st.prelude_choose_window("t1800")
	_caption("01 / 航行准备 · " + st.navigation_stage())
	await _wait(0.9)
	st.prelude_confirm()
	await _wait(1.6)

func _segment_sensors_and_orders() -> void:
	var st = _st()
	var hu = _hud()
	st.selected = 1
	_caption("02 / 接触判读 · 按舰传感器架")
	await _wait(1.2)
	hu.menu_open = true
	await _wait(1.2)
	st.set_sensor("harmattan", 0, false)
	await _wait(1.0)
	st.set_sensor("harmattan", 0, true)
	await _wait(0.8)
	hu.menu_open = false
	_caption("02b / 传感器桅杆 · 收放（收起时整架不可用）")
	st.set_mast("harmattan", false)
	await _wait(1.4)
	st.set_mast("harmattan", true)
	await _wait(0.8)
	_caption("02c / 选中舰 · 三维方位 / 相对轨道读数")
	st.selected = 1
	await _wait(1.2)
	_caption("03 / 命令 · 站位 / 跟踪 / 点火")
	await _wait(0.8)
	st.issue_command("STATION", {}, "远地点号")
	st.issue_command("SHADOW", {"hold_km": 60.0}, "谷神-2")
	await _wait(2.0)

func _segment_evidence() -> void:
	var st = _st()
	_caption("04 / 副官申请 · 遥测与穿梭机任务可并行")
	st.clock = st.T0 + 21.0
	st.refresh(st.clock)
	await _wait(2.2)
	st.ack_adjutant("telemetry")
	await _wait(0.8)
	st.ack_adjutant("blackbox")
	_caption("04b / 遥测（远程）不占穿梭机 · 黑匣子已排队")
	await _wait(1.6)
	st.clock = st.T0 + 55.0
	st.refresh(st.clock)
	await _wait(1.0)
	st.start_evidence_task("inspection_blackbox")
	_caption("05 / 穿梭机取证 · 港务遥测 / 核查组黑匣子")
	await _wait(2.0)
	st.clock = st.T0 + 130.0
	st.refresh(st.clock)
	await _wait(1.0)
	st.start_evacuation()
	await _wait(1.8)
	st.clock = st.T0 + 195.0
	st.refresh(st.clock)
	_caption("06 / 证据 2/3 · 可走 EXPOSE")
	await _wait(2.0)

func _segment_decision_and_report() -> void:
	var st = _st()
	st.exec_left = 60.0
	st.clock = st.T0 + 301.0
	st.refresh(st.clock)
	_caption("07 / 指挥官决策 · HOLD / EVACUATE / EXPOSE")
	await _wait(3.0)
	var choose_ret = st.choose_ending("EXPOSE")
	_caption("08 / 内部报告 · 如实提交")
	await _wait(2.4)
	st.submit_report("TRUTH")
	_caption("09 / 归档 · END")
	await _wait(2.0)
