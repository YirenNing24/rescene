class_name InventoryView
extends MenuDestination

var _balance: Label
var _hint: Label
var _status: Label
var _use: Button
var _confirm: bool = false

func _ready() -> void:
	name = "InventoryView"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	body = Control.new(); body.mouse_filter = Control.MOUSE_FILTER_IGNORE; add_child(body)
	var shield: Panel = host._panel(body, Rect2(30, 155, host._width - 60, 885), Color("141529"), Color(host.LILAC, 0.32), 26)
	shield.mouse_filter = Control.MOUSE_FILTER_STOP
	var _back: Button = host._button(body, "←", Rect2(58, 184, 66, 64), go_back)
	var _title: Label = host._label(body, "INVENTORY", Rect2(150, 186, 730, 48), 34, host.WHITE, host.BOLD)
	var _subtitle: Label = host._label(body, "LITTLE BOOSTS FOR YOUR NEXT SCENE", Rect2(153, 244, 1100, 25), 13, host.LILAC)
	var _shop: Button = host._button(body, "MARKETPLACE  →", Rect2(host._width - 434, 184, 364, 64), host._open_marketplace)
	var _cards: Button = host._button(body, "COLLECTION", Rect2(host._width - 960, 184, 258, 64), host._open_collection)
	var _refresh: Button = host._button(body, "REFRESH", Rect2(host._width - 676, 184, 218, 64), func() -> void: GameServices.commerce().refresh.call_deferred())
	var width: float = host._width - 180
	var panel: Panel = host._panel(body, Rect2(90, 334, width, 550), Color("242039"), Color(host.LILAC, 0.32), 24)
	var art: MarketArtwork = MarketArtwork.new(); art.host = host; art.item = MarketCatalog.find_item("energy_drink")
	host._at(panel, art, Rect2(58, 42, 445, 440))
	var _tag: Label = host._label(panel, "CONSUMABLE  /  +5 ENERGY", Rect2(570, 58, 900, 28), 15, Color("b4ded4"), host.BOLD)
	var _name: Label = host._label(panel, "Energy Drink", Rect2(565, 110, 1100, 68), 48, host.WHITE, host.BOLD)
	_balance = host._label(panel, "Loading your items…", Rect2(572, 204, 900, 45), 29, host.LILAC, host.BOLD)
	_hint = host._label(panel, "Restore 5 energy, up to 15. One drink is used each time.\nKeep your drinks for later when your energy is full.", Rect2(574, 274, 1180, 80), 22, host.MUTED)
	_use = host._button(panel, "USE ENERGY DRINK", Rect2(574, 405, 680, 76), _use_pressed, true)
	_use.name = "UseEnergyDrink"
	_status = host._label(body, "", Rect2(100, 936, host._width - 210, 50), 22, host.LILAC)
	var _commerce_connection: int = GameServices.commerce().changed.connect(_render)
	var _progress_connection: int = GameServices.progression().changed.connect(_render)
	_render()
	GameServices.commerce().refresh.call_deferred()

func _render() -> void:
	if not is_instance_valid(_use): return
	var commerce: CommerceService = GameServices.commerce()
	var owned: int = commerce.owned("energy_drink")
	_balance.text = "%d OWNED" % owned
	var energy: int = StrictData.integer(StrictData.dictionary(GameServices.progression().state.get("energy")).get("current", 15))
	_use.disabled = owned < 1 or energy >= 15 or commerce.pending()
	_use.text = "PROCESSING…" if commerce.pending() else "ENERGY FULL" if energy >= 15 else "CONFIRM · USE 1 DRINK" if _confirm else "USE ENERGY DRINK"
	_status.text = commerce.message
	if _confirm: _status.text = "Use one Energy Drink to restore up to 5 energy?"

func _use_pressed() -> void:
	if _use.disabled: return
	if not _confirm: _confirm = true; _render(); return
	_confirm = false
	GameServices.commerce().consume.call_deferred("energy_drink")
