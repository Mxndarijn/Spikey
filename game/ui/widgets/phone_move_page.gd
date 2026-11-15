class_name PhoneMovePage
extends VBoxContainer
## Settings > Move to a new phone (docs/ACCOUNT_TRANSFER.md, the mockups on its
## page): one step at a time in the settings card.
##   Choose:  "This is my old phone" (Get a code) or "This is my new phone"
##            (Enter a code).
##   Code:    the old phone's code in three groups, how long it works, Copy
##            code, the two warnings and Cancel code.
##   Enter:   the new phone types the code; a refusal says why.
##   Confirm: this phone against what moves here (best, gold, diamonds,
##            items, name), the overwrite warning, Move progress here.
## A move that worked closes Settings (PhoneMove.moved shows Home).

## The move worked: the sheet closes.
signal finished

enum Step { CHOOSE, CODE, ENTER, CONFIRM }

const TEXT_WIDTH := 270.0
const CODE_SIZE := 30

var step := Step.CHOOSE
var _move: PhoneMove
var _boxes: Dictionary[Step, VBoxContainer] = {}
var _code := Label.new()
var _expires := Label.new()
var _expires_at := 0
var _code_problem: Label
var _field := LineEdit.new()
var _enter_problem: Label
var _continue: Button
var _this_phone: Label
var _moving_here: Label
var _confirm_problem: Label
var _move_button: Button
var _timer := Timer.new()


func _init(move: PhoneMove) -> void:
	_move = move
	add_theme_constant_override("separation", UiTokens.SPACE_3)
	for s: Step in Step.values():
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", UiTokens.SPACE_3)
		_boxes[s] = box
		add_child(box)
	_build_choose()
	_build_code()
	_build_enter()
	_build_confirm()
	_timer.wait_time = 30.0
	_timer.timeout.connect(_show_expiry)
	add_child(_timer)
	show_step(Step.CHOOSE)


func show_step(s: Step) -> void:
	step = s
	for k: Step in _boxes:
		_boxes[k].visible = k == s


func _heading(box: Control, text: String) -> void:
	var l := UiKit.label(text, &"InkLabel", false)
	l.add_theme_font_size_override("font_size", 19)
	box.add_child(l)


func _line(box: Control, text: String, variation: StringName = &"MutedLabel") -> Label:
	var l := UiKit.wrapped(text, variation, TEXT_WIDTH)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	box.add_child(l)
	return l


func _problem(box: Control) -> Label:
	var l := _line(box, "", &"CaptionLabel")
	l.add_theme_color_override("font_color", UiTokens.DANGER)
	l.visible = false
	return l


## A pill button on paper: the main one in ink, the others paper-raised.
static func _button(text: String, main: bool = false) -> Button:
	var b := UiKit.action_button(text) if main else Button.new()
	if not main:
		b.text = text
		b.focus_mode = Control.FOCUS_NONE
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.custom_minimum_size.y = UiTokens.SIZE_TAP_MIN + 8
	return b


func _build_choose() -> void:
	var box := _boxes[Step.CHOOSE]
	_heading(box, "This is my old phone")
	_line(box, "Get a code here, then type it on your new phone. Your progress moves there.")
	var get_code := _button("Get a code", true)
	get_code.name = "GetCode"
	get_code.pressed.connect(_on_get_code)
	box.add_child(get_code)
	_code_problem = _problem(box)
	box.add_child(UiKit.spacer(UiTokens.SPACE_3))
	_heading(box, "This is my new phone")
	_line(box, "Got a code from your old phone? Type it here.")
	var enter := _button("Enter a code")
	enter.name = "EnterCode"
	enter.pressed.connect(open_enter)
	box.add_child(enter)


func _build_code() -> void:
	var box := _boxes[Step.CODE]
	_line(box, "Type this on your new phone:", &"InkLabel")
	_code.theme_type_variation = &"NameLabel"
	_code.add_theme_font_size_override("font_size", CODE_SIZE)
	_code.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_code)
	_expires.theme_type_variation = &"MutedLabel"
	_expires.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_expires)
	var copy := _button("Copy code")
	copy.name = "Copy"
	copy.pressed.connect(func() -> void: DisplayServer.clipboard_set(_code.text))
	box.add_child(copy)
	_line(
		box,
		"Anyone with this code gets your progress. Flapjaw will never ask you for it.",
		&"CaptionLabel"
	)
	_line(box, "Once it is used, this phone starts over as a new player.", &"CaptionLabel")
	var cancel := _button("Cancel code")
	cancel.name = "CancelCode"
	cancel.pressed.connect(_on_cancel_code)
	box.add_child(cancel)


func _build_enter() -> void:
	var box := _boxes[Step.ENTER]
	_line(box, "The code from your old phone:", &"InkLabel")
	_field.placeholder_text = "XXXX-XXXX-XXXX"
	_field.max_length = 16
	_field.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_field.custom_minimum_size = Vector2(0, 52)
	_field.add_theme_font_override("font", GameFonts.display())
	_field.add_theme_font_size_override("font_size", 22)
	_field.text_changed.connect(_on_typed)
	_field.text_submitted.connect(func(_t: String) -> void: _on_continue())
	box.add_child(_field)
	_enter_problem = _problem(box)
	_continue = _button("Continue", true)
	_continue.name = "Continue"
	_continue.disabled = true
	_continue.pressed.connect(_on_continue)
	box.add_child(_continue)
	_line(box, "Letters and numbers only; O and 0, I and 1 count as the same.", &"CaptionLabel")


func _build_confirm() -> void:
	var box := _boxes[Step.CONFIRM]
	_heading(box, "Replace this phone's progress?")
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", UiTokens.SPACE_2)
	_this_phone = _column(cols, "THIS PHONE")
	_moving_here = _column(cols, "MOVING HERE")
	box.add_child(cols)
	var warn := _line(
		box, "This phone's own progress is lost, and your old phone is signed out.", &"CaptionLabel"
	)
	warn.add_theme_color_override("font_color", UiTokens.DANGER)
	_confirm_problem = _problem(box)
	_move_button = _button("Move progress here", true)
	_move_button.name = "MoveHere"
	var red := UiTheme.flat(UiTokens.DANGER, UiTokens.RADIUS_PILL, 10)
	for state in ["normal", "hover", "pressed", "hover_pressed"]:
		_move_button.add_theme_stylebox_override(state, red)
	_move_button.pressed.connect(_on_move)
	box.add_child(_move_button)
	var cancel := _button("Cancel")
	cancel.name = "CancelMove"
	cancel.pressed.connect(open_enter)
	box.add_child(cancel)


func _column(parent: Control, title: String) -> Label:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override(
		"panel", UiTheme.flat(UiTokens.PANEL_RAISED, UiTokens.RADIUS_S * 2, 12)
	)
	var col := VBoxContainer.new()
	var t := UiKit.label(title, &"MutedLabel", false)
	t.add_theme_font_size_override("font_size", UiTokens.FONT_SIZE_TAG)
	col.add_child(t)
	var body := UiKit.label("", &"CaptionLabel", false)
	col.add_child(body)
	panel.add_child(col)
	parent.add_child(panel)
	return body


## "Best 87", "2,310 gold", "45 diamonds", "18 items", the name.
static func summary_text(d: Variant) -> String:
	var s: Dictionary = d if d is Dictionary else {}
	var lines := [
		"Best %d" % int(s.get("best", 0)),
		"%s gold" % UiKit.thousands(int(s.get("gold", 0))),
		"%d diamonds" % int(s.get("diamonds", 0)),
		"%d items" % int(s.get("items", 0)),
	]
	if not str(s.get("name", "")).is_empty():
		lines.append(str(s.name))
	return "\n".join(lines)


func _on_get_code() -> void:
	_code_problem.visible = false
	var res: Dictionary = await _move.make_code()
	if not res.ok:
		_code_problem.text = str(res.problem)
		_code_problem.visible = true
		return
	_code.text = PhoneMove.grouped(str(res.code))
	_expires_at = int(res.expires_at)
	_show_expiry()
	_timer.start()
	show_step(Step.CODE)


## "Works once · expires in 23:58".
func _show_expiry() -> void:
	var left := maxi(_expires_at - int(Time.get_unix_time_from_system()), 0)
	var hours := floori(left / 3600.0)
	var minutes := floori((left % 3600) / 60.0)
	_expires.text = "Works once · expires in %d:%02d" % [hours, minutes]


func _on_cancel_code() -> void:
	_timer.stop()
	await _move.cancel_code()
	show_step(Step.CHOOSE)


func open_enter() -> void:
	_enter_problem.visible = false
	show_step(Step.ENTER)


func _on_typed(text: String) -> void:
	_continue.disabled = text.replace("-", "").replace(" ", "").length() != 12


func _on_continue() -> void:
	if _continue.disabled:
		return
	_enter_problem.visible = false
	_continue.disabled = true
	var res: Dictionary = await _move.preview(_field.text)
	_continue.disabled = false
	if not res.ok:
		_enter_problem.text = str(res.problem)
		_enter_problem.visible = true
		return
	_this_phone.text = summary_text(res.get("this_phone"))
	_moving_here.text = summary_text(res)
	_confirm_problem.visible = false
	show_step(Step.CONFIRM)


func _on_move() -> void:
	_move_button.disabled = true
	var res: Dictionary = await _move.redeem(_field.text)
	_move_button.disabled = false
	if not res.ok:
		_confirm_problem.text = str(res.problem)
		_confirm_problem.visible = true
		return
	finished.emit()


## For tests.
func code_text() -> String:
	return _code.text


func field() -> LineEdit:
	return _field


func problem_text() -> String:
	for l: Label in [_code_problem, _enter_problem, _confirm_problem]:
		if l.visible and l.is_visible_in_tree():
			return l.text
	return ""


func summary(this_phone: bool) -> String:
	return _this_phone.text if this_phone else _moving_here.text
