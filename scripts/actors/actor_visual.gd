class_name ActorVisual
extends Node2D

@onready var sprite: Sprite2D = $Sprite2D
@onready var animation: AnimationPlayer = $AnimationPlayer
var flash_tween: Tween

func set_actor_texture(value: Texture2D) -> void:
	sprite.texture = value

func update_motion(motion: Vector2) -> void:
	if absf(motion.x) > 0.1:
		sprite.flip_h = motion.x < 0.0
	if motion.length_squared() > 1.0:
		if animation.current_animation != "walk":
			animation.play("walk")
	else:
		animation.stop()
		sprite.position.y = 0.0

func flash() -> void:
	if flash_tween and flash_tween.is_valid():
		flash_tween.kill()
	sprite.modulate = Color(2.0, 1.4, 1.2)
	flash_tween = create_tween()
	flash_tween.tween_property(sprite, "modulate", Color.WHITE, 0.15)

func _draw() -> void:
	draw_ellipse_shadow()

func draw_ellipse_shadow() -> void:
	draw_set_transform(Vector2(0, 16), 0.0, Vector2(1.0, 0.32))
	draw_circle(Vector2.ZERO, 18.0, Color(0.02, 0.03, 0.04, 0.45))
