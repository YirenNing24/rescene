class_name ResceneAuthScreen
extends Control
## Lightweight native form over the lobby artwork; no additional particle pass.

const FONT: FontFile = preload("res://assets/fonts/Montserrat-Medium.otf")
const BOLD: FontFile = preload("res://assets/fonts/Montserrat-SemiBold.otf")
const SERIF: FontFile = preload("res://assets/fonts/NimbusRoman-Regular.otf")
const ITALIC: FontFile = preload("res://assets/fonts/NimbusRoman-Italic.otf")
const WHITE: Color = Color("f4f1ff")
const MUTED: Color = Color("b7b9d5")
const LILAC: Color = Color("d8ceff")

var _canvas: Control
var _panel: Panel
var _username: LineEdit
var _password: LineEdit
var _confirm: LineEdit
var _confirm_group: VBoxContainer
var _status: Label
var _title: Label
var _subtitle: Label
var _submit: Button
var _login_tab: Button
var _register_tab: Button
var _show_password: Button
var _scroll: ScrollContainer
var _agreement_group: HBoxContainer
var _agreement: CheckBox
var _legal_view: LegalPolicyView
var _register: bool = false
var _pending: bool = false
var _submission_serial: int = 0
var _keyboard_height: int = 0
var _form: VBoxContainer
var _recovery_form: VBoxContainer
var _recovery_username: LineEdit
var _recovery_code: LineEdit
var _recovery_password: LineEdit
var _recovery_confirm: LineEdit
var _recovery_status: Label
var _recovery_submit: Button

func _ready() -> void:
	if GameServices.session().is_authenticated():
		_enter_menu.call_deferred()
		return
	_build()
	var _int_1: int = resized.connect(_layout)
	_layout()
	if not GameServices.session().notice.is_empty():
		_status.text = GameServices.session().notice
		GameServices.session().notice = ""
	elif FileAccess.file_exists(GameServices.session().session_file()):
		_set_pending(true)
		_status.text = "Restoring your session…"
		var result: Dictionary = await GameServices.session().restore_session()
		if not is_inside_tree(): return
		if result.ok:
			_enter_menu()
		else:
			_set_pending(false)
			_status.text = result.message

func _build() -> void:
	var art: TextureRect = TextureRect.new()
	art.texture = preload("res://assets/art/rescene-main-menu.png")
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	add_child(art)
	art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var shade: ColorRect = ColorRect.new()
	shade.color = Color(0.035, 0.04, 0.10, 0.37)
	add_child(shade)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas = Control.new()
	add_child(_canvas)
	var _label_2: Label = _label(_canvas, "R E S C É N E  /  R H Y T H M", Rect2(110, 70, 1100, 40), 19, MUTED)
	var _label_3: Label = _label(_canvas, "RESCÉNE", Rect2(110, 155, 1130, 140), 112, WHITE, SERIF)
	var _label_4: Label = _label(_canvas, "Rhythm", Rect2(116, 280, 900, 85), 58, LILAC, ITALIC)
	var _label_5: Label = _label(_canvas, "Your stage. Your scene.", Rect2(117, 390, 1050, 60), 35, WHITE)
	var _label_6: Label = _label(_canvas, "One account. Every beat.", Rect2(117, 455, 1050, 40), 22, MUTED)
	var _updates: Button = _button(_canvas, "CHECK FOR UPDATES", Rect2(117, 550, 440, 64), func() -> void:
		var _view: AppUpdateView = AppUpdateView.open(self)
	)
	var _terms_link: Button = _button(_canvas, "TERMS & CONDITIONS", Rect2(117,650,440,60), func() -> void: _show_policy("terms"))
	_terms_link.add_theme_font_size_override("font_size",19)
	var _privacy_link: Button = _button(_canvas, "PRIVACY POLICY", Rect2(580,650,370,60), func() -> void: _show_policy("privacy"))
	_privacy_link.add_theme_font_size_override("font_size",19)
	var fan_notice: Label = _label(_canvas,str(LegalPolicies.data().notice),Rect2(117,753,1050,78),23,MUTED,FONT,true)
	fan_notice.name = "FanNotice"
	var scam_notice: Label = _label(_canvas,"Anyone selling game items or accounts for real money is most likely a scammer. Never pay them or share your login details.",Rect2(117,858,1050,99),22,LILAC,FONT,true)
	scam_notice.name = "ScamNotice"
	var _label_7: Label = _label(_canvas, "01  /  YOUR BACKSTAGE PASS", Rect2(117, 985, 1100, 30), 16, MUTED)
	var panel: Panel = Panel.new()
	_panel = panel
	panel.add_theme_stylebox_override("panel", _style(Color(0.063, 0.068, 0.14, 0.94), Color(0.77, 0.73, 1, 0.48), 32))
	_at(_canvas, panel, Rect2(1390, 75, 890, 930))
	_login_tab = _button(panel, "LOG IN", Rect2(55, 40, 380, 64), func() -> void: _set_mode(false))
	_register_tab = _button(panel, "REGISTER", Rect2(455, 40, 380, 64), func() -> void: _set_mode(true))
	_title = _label(panel, "Welcome back.", Rect2(55, 141, 780, 64), 49, WHITE, SERIF)
	_subtitle = _label(panel, "Your next scene starts here.", Rect2(57, 213, 778, 35), 21, MUTED)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.follow_focus = true
	_at(_canvas, _scroll, Rect2(1445, 363, 780, 620))
	var form: VBoxContainer = VBoxContainer.new()
	_form = form
	form.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	form.add_theme_constant_override("separation", 15)
	var forms: VBoxContainer = VBoxContainer.new()
	forms.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(forms)
	forms.add_child(form)
	_username = _field(form, "USERNAME", "Your username", false)
	_username.name = "Username"
	_username.max_length = 24
	_username.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_DEFAULT
	_password = _field(form, "PASSWORD", "Your password", true)
	_password.name = "Password"
	_confirm_group = VBoxContainer.new()
	_confirm_group.add_theme_constant_override("separation", 12)
	form.add_child(_confirm_group)
	_confirm = _field(_confirm_group, "CONFIRM PASSWORD", "Repeat your password", true)
	_confirm.name = "ConfirmPassword"
	_show_password = Button.new()
	_show_password.text = "SHOW PASSWORD"
	_show_password.flat = true
	_show_password.toggle_mode = true
	_show_password.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_show_password.custom_minimum_size.y = 46
	_show_password.add_theme_font_override("font", FONT)
	_show_password.add_theme_font_size_override("font_size", 17)
	_show_password.add_theme_color_override("font_color", LILAC)
	var _int_8: int = _show_password.toggled.connect(func(show_text: bool) -> void:
		_show_password.text = "HIDE PASSWORD" if show_text else "SHOW PASSWORD"
		_password.secret = not show_text
		_confirm.secret = not show_text)
	form.add_child(_show_password)
	_agreement_group = HBoxContainer.new()
	_agreement_group.add_theme_constant_override("separation",16)
	form.add_child(_agreement_group)
	_agreement = CheckBox.new()
	_agreement.name = "AcceptPolicies"
	_agreement.tooltip_text = "I agree to the Terms & Conditions and acknowledge the Privacy Policy."
	_agreement.custom_minimum_size = Vector2(52,72)
	_agreement.add_theme_icon_override("unchecked",preload("res://assets/ui/consent-empty.svg"))
	_agreement.add_theme_icon_override("checked",preload("res://assets/ui/consent-checked.svg"))
	_agreement.add_theme_stylebox_override("focus",_style(Color.TRANSPARENT,LILAC,8))
	_agreement_group.add_child(_agreement)
	var agreement_text: RichTextLabel = RichTextLabel.new()
	agreement_text.name = "PolicyLinks"
	agreement_text.bbcode_enabled = true
	agreement_text.fit_content = true
	agreement_text.scroll_active = false
	agreement_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	agreement_text.add_theme_font_override("normal_font",FONT)
	agreement_text.add_theme_font_size_override("normal_font_size",22)
	agreement_text.add_theme_color_override("default_color",WHITE)
	agreement_text.text = "I agree to the [url=terms][color=#d8ceff]Terms & Conditions[/color][/url] and\nacknowledge the [url=privacy][color=#d8ceff]Privacy Policy[/color][/url]."
	var _policy_click: int = agreement_text.meta_clicked.connect(func(meta: Variant) -> void: _show_policy(str(meta)))
	_agreement_group.add_child(agreement_text)
	var _agreement_change: int = _agreement.toggled.connect(func(_accepted: bool) -> void: _sync_submit())
	_status = Label.new()
	_status.add_theme_font_override("font", FONT)
	_status.add_theme_font_size_override("font_size", 19)
	_status.add_theme_color_override("font_color", Color("f1bcca"))
	_status.custom_minimum_size.y = 44
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	form.add_child(_status)
	_submit = _button(form, "LOG IN  →", Rect2(), _submit_form, true)
	_submit.name = "Submit"
	_submit.custom_minimum_size.y = 74
	var hint: Label = Label.new()
	hint.text = "3–24 letters, numbers or underscores. Password: at least 8 characters. No special characters required."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_override("font", FONT)
	hint.add_theme_font_size_override("font_size", 16)
	hint.add_theme_color_override("font_color", MUTED)
	form.add_child(hint)
	var recover: Button = _button(form, "RECOVER ACCOUNT", Rect2(), func() -> void: _show_recovery(true))
	recover.name = "RecoverAccount"; recover.custom_minimum_size.y = 58
	_recovery_form = VBoxContainer.new(); _recovery_form.add_theme_constant_override("separation", 14); _recovery_form.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	forms.add_child(_recovery_form); _recovery_form.hide()
	_recovery_username = _field(_recovery_form, "USERNAME", "Your username", false); _recovery_username.max_length = 24
	_recovery_code = _field(_recovery_form, "ONE-TIME RECOVERY CODE", "Your saved recovery code", true)
	_recovery_password = _field(_recovery_form, "NEW PASSWORD", "8 or more characters", true)
	_recovery_confirm = _field(_recovery_form, "CONFIRM NEW PASSWORD", "Repeat your new password", true)
	_recovery_status = Label.new(); _recovery_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; _recovery_status.add_theme_font_override("font", FONT); _recovery_status.add_theme_font_size_override("font_size", 19); _recovery_status.add_theme_color_override("font_color", LILAC); _recovery_form.add_child(_recovery_status)
	_recovery_submit = _button(_recovery_form, "RESET PASSWORD", Rect2(), func() -> void: _recover_account.call_deferred(), true); _recovery_submit.custom_minimum_size.y = 70
	var back: Button = _button(_recovery_form, "BACK TO LOGIN", Rect2(), func() -> void: _show_recovery(false)); back.custom_minimum_size.y = 54
	var _int_9: int = _username.text_submitted.connect(func(_value: String) -> void: _password.grab_focus())
	var _int_10: int = _password.text_submitted.connect(func(_value: String) -> void:
		if _register: _confirm.grab_focus()
		else: _queue_submit())
	var _int_11: int = _confirm.text_submitted.connect(func(_value: String) -> void: _queue_submit())
	_set_mode(false, true)

func _layout() -> void:
	if _canvas == null: return
	var factor: float = minf(size.x / 2400.0, size.y / 1080.0)
	_canvas.scale = Vector2.ONE * factor
	_canvas.size = Vector2(2400, 1080)
	_canvas.position = (size - Vector2(2400, 1080) * factor) * 0.5
	_resize_for_keyboard()

func _process(_delta: float) -> void:
	if not DisplayServer.has_feature(DisplayServer.FEATURE_VIRTUAL_KEYBOARD): return
	var keyboard: int = DisplayServer.virtual_keyboard_get_height()
	if keyboard != _keyboard_height:
		_keyboard_height = keyboard
		_resize_for_keyboard()

func _resize_for_keyboard() -> void:
	if _scroll == null: return
	var screen_bottom: float = float(DisplayServer.window_get_size().y - _keyboard_height)
	var visible_bottom: float = (_canvas.get_screen_transform().affine_inverse() * Vector2(0.0, screen_bottom)).y
	_fit_keyboard(visible_bottom, _keyboard_height > 0)
	_reveal_focused_field.call_deferred()

func _fit_keyboard(visible_bottom: float, keyboard_open: bool) -> void:
	# Move the form itself above the IME: shrinking below the large title leaves
	# almost no room in landscape. Keep the native fields at their normal size.
	_title.visible = not keyboard_open
	_subtitle.visible = not keyboard_open
	_panel.position.y = 24.0 if keyboard_open else 75.0
	_panel.size.y = maxf(1.0, visible_bottom - 40.0) if keyboard_open else 930.0
	_login_tab.position.y = 16.0 if keyboard_open else 40.0
	_register_tab.position.y = _login_tab.position.y
	_scroll.position.y = 128.0 if keyboard_open else 363.0
	_scroll.size.y = maxf(1.0, minf(1080.0, visible_bottom) - _scroll.position.y - 24.0) if keyboard_open else 620.0

func _reveal_focused_field() -> void:
	# Containers settle on the next frame after resize/focus/IME changes.
	await get_tree().process_frame
	if not is_inside_tree(): return
	var focused: Control = get_viewport().gui_get_focus_owner()
	if focused != null and _scroll.is_ancestor_of(focused):
		_scroll.ensure_control_visible(focused)

func _set_mode(register: bool, force: bool = false) -> void:
	if _pending: return
	if not force and register == _register and _form.visible and not _recovery_form.visible: return
	_submission_serial += 1
	if is_instance_valid(_recovery_form): _recovery_form.hide(); _form.show()
	_register = register
	_form.add_theme_constant_override("separation",10 if register else 15)
	_confirm_group.visible = register
	_agreement_group.visible = register
	_agreement.button_pressed = false
	_sync_submit()
	_title.text = "Make it your scene." if register else "Welcome back."
	_subtitle.text = "Create your backstage pass." if register else "Your next scene starts here."
	_submit.text = "CREATE ACCOUNT  →" if register else "LOG IN  →"
	_password.clear()
	_confirm.clear()
	_status.text = ""
	_show_password.button_pressed = false
	_login_tab.modulate = Color(0.65, 0.64, 0.76) if register else WHITE
	_register_tab.modulate = WHITE if register else Color(0.65, 0.64, 0.76)
	_scroll.scroll_vertical = 0

func _show_policy(kind: String) -> void:
	if kind not in ["terms","privacy"] or is_instance_valid(_legal_view): return
	if DisplayServer.has_feature(DisplayServer.FEATURE_VIRTUAL_KEYBOARD): DisplayServer.virtual_keyboard_hide()
	_legal_view = LegalPolicyView.new()
	_legal_view.host = self
	_legal_view.kind = kind
	_canvas.add_child(_legal_view)

func _sync_submit() -> void:
	if is_instance_valid(_submit): _submit.disabled = _pending or (_register and not _agreement.button_pressed)

func _queue_submit() -> void:
	_submit_if_current.call_deferred(_submission_serial)

func _submit_if_current(serial: int) -> void:
	if serial == _submission_serial: await _submit_form()

func _submit_form() -> void:
	if _pending or is_instance_valid(_legal_view): return
	var username: String = _username.text.strip_edges()
	var pattern: RegEx = RegEx.create_from_string("^[A-Za-z0-9_]{3,24}$")
	if pattern.search(username) == null:
		_status.text = "Username must be 3–24 letters, numbers or underscores."
		_username.grab_focus()
		return
	var password: String = _password.text
	if password.is_empty():
		_status.text = "Enter your password."
		_password.grab_focus()
		return
	if password.length() < 8:
		_status.text = "Use at least 8 characters. You entered %d." % password.length()
		_password.grab_focus()
		return
	if password.to_utf8_buffer().size() > 72:
		_status.text = "That password is too long (maximum 72 UTF-8 bytes)."
		_password.grab_focus()
		return
	if _register and _confirm.text != _password.text:
		_status.text = "The passwords don't match."
		_confirm.grab_focus()
		return
	if _register and not _agreement.button_pressed:
		_status.text = "Please agree to the Terms & Conditions and acknowledge the Privacy Policy."
		_scroll.ensure_control_visible(_agreement_group)
		_agreement.grab_focus()
		return
	_submission_serial += 1
	_set_pending(true)
	_status.text = "Creating your account…" if _register else "Connecting…"
	_status.add_theme_color_override("font_color", MUTED)
	if DisplayServer.has_feature(DisplayServer.FEATURE_VIRTUAL_KEYBOARD):
		DisplayServer.virtual_keyboard_hide()
	var result: Dictionary = await GameServices.session().authenticate(username, password, _register, _agreement.button_pressed if _register else false)
	if not is_inside_tree(): return
	_set_pending(false)
	if result.ok:
		_password.clear()
		_confirm.clear()
		_enter_menu()
	else:
		_status.add_theme_color_override("font_color", Color("f1bcca"))
		_status.text = result.message

func _set_pending(value: bool) -> void:
	_pending = value
	_sync_submit()
	_agreement.disabled = value
	_login_tab.disabled = value
	_register_tab.disabled = value
	_username.editable = not value
	_password.editable = not value
	_confirm.editable = not value
	_show_password.disabled = value
	_submit.text = "PLEASE WAIT…" if value else ("CREATE ACCOUNT  →" if _register else "LOG IN  →")

func _enter_menu() -> void:
	var _error_12: Error = get_tree().change_scene_to_file("res://scenes/main_menu.tscn")

func _show_recovery(show_form: bool) -> void:
	if _pending: return
	_form.visible = not show_form; _recovery_form.visible = show_form
	_title.text = "Recover your account." if show_form else "Welcome back."
	_subtitle.text = "Use one of your saved one-time recovery codes." if show_form else "Your next scene starts here."
	_recovery_status.text = ""; _scroll.scroll_vertical = 0
	if not show_form: _recovery_code.clear(); _recovery_password.clear(); _recovery_confirm.clear(); _set_mode(false, true)

func _recover_account() -> void:
	if _pending: return
	if _recovery_password.text != _recovery_confirm.text: _recovery_status.text = "The passwords do not match."; return
	_set_pending(true); _recovery_submit.disabled = true
	var response: Dictionary = await GameServices.session()._send("/api/v1/auth/recover", HTTPClient.METHOD_POST, {"username":_recovery_username.text.strip_edges(),"recovery_code":_recovery_code.text,"new_password":_recovery_password.text})
	if not is_inside_tree(): return
	_set_pending(false); _recovery_submit.disabled = false
	_recovery_code.clear(); _recovery_password.clear(); _recovery_confirm.clear()
	if response.ok: _show_recovery(false); _status.text = "Password reset. Log in with your new password."
	else: _recovery_status.text = str(response.get("message", "Account recovery failed."))

func _style(fill: Color, border: Color, radius: int = 16) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(2)
	style.set_corner_radius_all(radius)
	style.corner_detail = 20
	style.anti_aliasing = true
	style.anti_aliasing_size = 1.5
	style.content_margin_left = 22
	style.content_margin_right = 22
	return style

func _at(parent: Node, control: Control, rect: Rect2) -> void:
	parent.add_child(control)
	control.position = rect.position
	control.size = rect.size

func _label(parent: Node, text: String, rect: Rect2, font_size: int, color: Color, font: Font = FONT, wrap_text: bool = false) -> Label:
	var label: Label = Label.new()
	if wrap_text: label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.text = text
	label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_at(parent, label, rect)
	return label

func _button(parent: Node, text: String, rect: Rect2, action: Callable, primary: bool = false) -> Button:
	var button: Button = Button.new()
	button.text = text
	button.add_theme_font_override("font", BOLD)
	button.add_theme_font_size_override("font_size", 24)
	button.add_theme_color_override("font_color", Color("202039") if primary else WHITE)
	button.add_theme_color_override("font_hover_color", Color("202039") if primary else WHITE)
	button.add_theme_color_override("font_pressed_color", Color("202039") if primary else WHITE)
	button.add_theme_stylebox_override("normal", _style(LILAC if primary else Color(0.15,0.14,0.26), Color(0.75,0.70,0.95,0.6)))
	button.add_theme_stylebox_override("hover", _style(Color("e9e2ff") if primary else Color(0.24,0.21,0.37), LILAC))
	button.add_theme_stylebox_override("pressed", _style(Color("b8a8eb") if primary else Color(0.30,0.25,0.43), LILAC))
	button.add_theme_stylebox_override("focus", _style(Color(0,0,0,0), WHITE))
	button.add_theme_stylebox_override("disabled", _style(Color(0.16,0.14,0.25),Color(0.65,0.60,0.8,0.35)))
	button.add_theme_color_override("font_disabled_color",MUTED)
	var _int_13: int = button.pressed.connect(action)
	_at(parent, button, rect)
	return button

func _field(parent: Node, title: String, placeholder: String, secret: bool) -> LineEdit:
	var group: VBoxContainer = VBoxContainer.new()
	group.add_theme_constant_override("separation", 12)
	parent.add_child(group)
	var label: Label = Label.new()
	label.text = title
	label.add_theme_font_override("font", BOLD)
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_color", MUTED)
	group.add_child(label)
	var input: LineEdit = LineEdit.new()
	input.placeholder_text = placeholder
	input.secret = secret
	if secret: input.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_PASSWORD
	input.max_length = 72
	input.custom_minimum_size.y = 72
	input.add_theme_font_override("font", FONT)
	input.add_theme_font_size_override("font_size", 25)
	input.add_theme_color_override("font_color", WHITE)
	input.add_theme_color_override("font_placeholder_color", MUTED)
	input.add_theme_stylebox_override("normal", _style(Color(0.10,0.10,0.19), Color(0.50,0.48,0.68)))
	input.add_theme_stylebox_override("focus", _style(Color(0.14,0.12,0.24), LILAC))
	group.add_child(input)
	var _focus_connection: int = input.focus_entered.connect(func() -> void: _reveal_focused_field.call_deferred())
	return input
