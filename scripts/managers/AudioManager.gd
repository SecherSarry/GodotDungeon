extends Node

var sound_players = []

func _ready():
	# 可以预创建多个播放器，避免并发冲突
	for i in range(8):
		var player = AudioStreamPlayer.new()
		add_child(player)
		sound_players.append(player)

func play_sound(sound: AudioStream, volume_db: float = 0.0, pitch_scale: float = 1.0):
	for player in sound_players:
		if not player.playing:
			player.stream = sound
			player.volume_db = volume_db
			player.pitch_scale = pitch_scale
			player.play()
			return
	# 若无空闲播放器，新创建一个（或忽略）
	var new_player = AudioStreamPlayer.new()
	add_child(new_player)
	new_player.stream = sound
	new_player.volume_db = volume_db
	new_player.pitch_scale = pitch_scale
	new_player.play()
	sound_players.append(new_player)
