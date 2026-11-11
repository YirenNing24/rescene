class_name MenuDestination
extends Control

var host: ResceneMainMenu
var body: Control

func go_back() -> void:
	host._close_dialog()
