extends Node2D

@onready var new_game_button = $Button
@onready var load_button = $Button3
@onready var delete_button = $Button2

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	new_game_button.pressed.connect(_on_new_game_pressed)
	load_button.pressed.connect(_on_load_pressed)
	delete_button.pressed.connect(_on_delete_button_pressed)
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass

# 一局的建立全在 GameState 里——GameScene 只负责显示，进来时数据都已就绪。
func _on_new_game_pressed():
	print("新档")
	GameState.new_game()
	get_tree().change_scene_to_file("res://scripts/scenes/GameScene/GameScene.tscn")

func _on_load_pressed():
	print("读取存档")
	if not GameState.load_game(0):
		print("没有可读取的存档")
		return
	get_tree().change_scene_to_file("res://scripts/scenes/GameScene/GameScene.tscn")

func _on_delete_button_pressed():
	print("存档删除")
	SaveManager.delete_game(0)
