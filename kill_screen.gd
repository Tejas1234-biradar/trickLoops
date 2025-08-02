extends CanvasLayer

signal retry_requested
signal menu_requested

func _ready():
	$Restart.pressed.connect(_on_retry_pressed)
	$MainMenu.pressed.connect(_on_menu_pressed)
	visible = false  # Hidden by default

func show_kill_screen():
	visible = true

func _on_retry_pressed():
	emit_signal("retry_requested")

func _on_menu_pressed():
	emit_signal("menu_requested")
