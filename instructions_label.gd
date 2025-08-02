extends CanvasLayer

@onready var label = $InstructionsLabel

func _ready():
	# Auto-hide after 8 seconds (adjust as needed)
	await get_tree().create_timer(8.0).timeout
	hide()
