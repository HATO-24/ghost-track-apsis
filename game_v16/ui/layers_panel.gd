extends Control

## V2-5 图层隐藏面板（战术图元素开关；HUD 面板不受影响）。
##
## 6 个图层：contacts / labels / predictions / radar / stations / grid。
## core V2-CORE-4 `world.set_layer(name, on)` / `vm_layers()` 可用时同步 core；
## 同时 UI 本地立刻生效（战术图按 _layers 绘制），不硬改 core。

signal layer_toggled(name: String, on: bool)

const T := preload("res://ui/theme.gd")

const LAYER_ORDER := ["contacts", "labels", "predictions", "radar", "stations", "grid"]
const LAYER_LABEL := {
	"contacts": "接触符号 / CONTACTS",
	"labels": "标签 / LABELS",
	"predictions": "预测线 / PREDICTIONS",
	"radar": "雷达球 / RADAR",
	"stations": "站体·储罐 / STATIONS",
	"grid": "网格 / GRID",
}

var data = null
var layers: Dictionary = {}
var _rows: Array = []
var _hover := -1


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	layers = _default_layers()


func _default_layers() -> Dictionary:
	var out: Dictionary = {}
	for k in LAYER_ORDER:
		out[k] = true
	return out


func bind(data_ref) -> void:
	data = data_ref
	var vm: Dictionary = data.layers_state()
	if not vm.is_empty():
		for k in LAYER_ORDER:
			if vm.has(k):
				layers[k] = bool(vm[k])
	queue_redraw()


func set_layers(dict: Dictionary) -> void:
	for k in LAYER_ORDER:
		if dict.has(k):
			layers[k] = bool(dict[k])
	queue_redraw()


func toggle(name: String) -> bool:
	if not layers.has(name):
		return false
	var on := not bool(layers[name])
	layers[name] = on
	if data != null:
		data.set_layer(name, on)
	layer_toggled.emit(name, on)
	queue_redraw()
	return on


func _draw() -> void:
	T.panel(self, Rect2(0.0, 0.0, size.x, size.y), 0.97, 0.85)
	T.text(self, 12.0, 8.0, "图层 / LAYERS", T.F9, T.TXT)
	T.text_r(self, size.x - 12.0, 8.0, "O 关闭", T.F7, T.a(T.FAINT, 0.85), false)
	T.hline(self, 10.0, 26.0, size.x - 10.0, T.a(T.LINE, 0.65))
	_rows.clear()
	var y := 34.0
	for name in LAYER_ORDER:
		var on := bool(layers.get(name, true))
		var row := Rect2(8.0, y - 3.0, size.x - 16.0, 18.0)
		_rows.append({"rect": row, "name": name})
		var hot := row.has_point(get_local_mouse_position())
		draw_rect(row, T.a(T.PANEL2, 0.85 if hot else 0.28))
		# 开关
		var sw := Rect2(row.position.x + 6.0, row.position.y + 4.0, 24.0, 10.0)
		draw_rect(sw, T.a(T.PH if on else T.LINE, 0.22 if on else 0.10))
		draw_rect(sw, T.a(T.PH if on else T.LINE, 0.85 if on else 0.45), false, 1.0)
		draw_circle(Vector2(sw.end.x - 4.0 if on else sw.position.x + 4.0, sw.get_center().y), 3.0,
			T.PH if on else T.FAINT)
		T.text_fit(self, row.position.x + 38.0, row.position.y + 3.0,
			String(LAYER_LABEL.get(name, name)), T.F8, T.a(T.TXT, 0.95 if on else 0.55), size.x - 76.0)
		T.text_r(self, row.end.x - 6.0, row.position.y + 3.0, "ON" if on else "OFF", T.F7,
			T.a(T.PH if on else T.FAINT, 0.9), false)
		y += 21.0
	# 注意：只隐藏战术图元素，HUD（左/右/底栏）不随图层隐藏
	T.text(self, 12.0, size.y - 32.0, "仅影响战术图绘制；HUD 面板不隐藏。", T.F7, T.a(T.FAINT, 0.85))
	T.text(self, 12.0, size.y - 18.0, "core: world.set_layer / vm_layers（local fallback）", T.F7,
		T.a(T.PH_DIM, 0.8))
	for i in range(_rows.size()):
		if i == _hover:
			var r: Rect2 = _rows[i]["rect"]
			draw_rect(r, T.a(T.PH, 0.10))


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var idx := _row_at((event as InputEventMouseMotion).position)
		if idx != _hover:
			_hover = idx
			queue_redraw()
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index != MOUSE_BUTTON_LEFT or not mb.pressed:
			return
		for i in range(_rows.size()):
			var row: Dictionary = _rows[i]
			if (row["rect"] as Rect2).has_point(mb.position):
				toggle(String(row["name"]))
				accept_event()
				return


func _row_at(pos: Vector2) -> int:
	for i in range(_rows.size()):
		if (_rows[i]["rect"] as Rect2).has_point(pos):
			return i
	return -1
