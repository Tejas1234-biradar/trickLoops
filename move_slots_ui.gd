extends Control

@onready var anim_player = $AnimationPlayer

func play_slot_animation(slot_number):
	if slot_number < 1 or slot_number > 4:
		return
	
	var anim_name = "slot_%d" % slot_number
	if anim_player.has_animation(anim_name):
		anim_player.play(anim_name)
