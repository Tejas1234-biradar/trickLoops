extends CanvasLayer

var has_started := false

func _ready():
	set_process_input(true)

func _input(event):
	if has_started:
		return

	if event.is_pressed():
		has_started = true
		$Label.hide()
		$TextureRect.hide()
		get_parent().start_game()  # Calls function from Main to trigger animation
