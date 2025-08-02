extends CanvasLayer

@onready var fog = $Fog  # The TextureRect node

var scroll_speed := Vector2(5, 0)  # Adjust to your liking
var offse2t := Vector2.ZERO

func _process(delta):
	offse2t += scroll_speed * delta
	fog.position = offset
