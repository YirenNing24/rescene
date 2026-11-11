class_name LegalPolicyView
extends Control
## Read-only policy modal; reading never changes registration agreement.
var host: ResceneAuthScreen
var kind: String = "terms"
var scroll: ActionListScroll

func _ready() -> void:
	name = "LegalPolicy"
	size = Vector2(2400, 1080)
	z_index = 100
	mouse_filter = Control.MOUSE_FILTER_STOP
	var scrim: ColorRect = ColorRect.new()
	scrim.color = Color(0.025,0.03,0.07,0.88)
	host._at(self, scrim, Rect2(0,0,2400,1080))
	var panel: Panel = Panel.new()
	panel.add_theme_stylebox_override("panel", host._style(Color("181a30"), Color("8c83bd"), 28))
	host._at(self, panel, Rect2(440,90,1520,900))
	var _eyebrow: Label = host._label(panel,"RESCENE / RHYTHM",Rect2(55,31,1000,30),17,host.MUTED)
	var _title: Label = host._label(panel,str(LegalPolicies.document(kind).get("title","")),Rect2(53,77,1080,65),44,host.WHITE,host.SERIF)
	var close: Button = host._button(panel,"CLOSE  ×",Rect2(1185,43,280,65),_dismiss)
	close.name = "ClosePolicy"
	close.grab_focus()
	scroll = ActionListScroll.new()
	scroll.name = "PolicyScroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	host._at(panel,scroll,Rect2(55,165,1410,635))
	var column: VBoxContainer = VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(column)
	var text: RichTextLabel = RichTextLabel.new()
	text.name = "PolicyText"
	text.bbcode_enabled = true
	text.fit_content = true
	text.scroll_active = false
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_theme_font_override("normal_font",host.FONT)
	text.add_theme_font_override("bold_font",host.BOLD)
	text.add_theme_font_size_override("normal_font_size",25)
	text.add_theme_font_size_override("bold_font_size",25)
	text.add_theme_color_override("default_color",host.WHITE)
	text.add_theme_constant_override("line_separation",9)
	column.add_child(text)
	text.text = LegalPolicies.bbcode(kind)
	var _hint: Label = host._label(panel,"Questions or data requests: " + str(LegalPolicies.data().contact),Rect2(55,837,1410,32),20,host.MUTED)

func _dismiss() -> void:
	hide()
	queue_free()
	if is_instance_valid(host._agreement) and host._agreement.is_visible_in_tree(): host._agreement.grab_focus()
	elif is_instance_valid(host._username): host._username.grab_focus()

func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_dismiss()
