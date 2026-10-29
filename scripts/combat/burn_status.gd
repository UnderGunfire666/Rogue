class_name BurnStatus
extends Node

var target: Node2D
var damage := 0.0
var tick_timer: Timer
var expiry_timer: Timer

func _ready() -> void:
	tick_timer = Timer.new()
	tick_timer.wait_time = 1.0
	tick_timer.timeout.connect(_tick)
	add_child(tick_timer)
	expiry_timer = Timer.new()
	expiry_timer.one_shot = true
	expiry_timer.timeout.connect(queue_free)
	add_child(expiry_timer)

func apply(amount: float, duration: float) -> void:
	damage = maxf(damage, amount)
	expiry_timer.start(maxf(expiry_timer.time_left, duration))
	if tick_timer.is_stopped(): tick_timer.start()

func _tick() -> void:
	if is_instance_valid(target) and target.health.is_alive(): target.receive_damage(RunState.damage_against(target, damage))
