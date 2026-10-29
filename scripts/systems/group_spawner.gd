class_name GroupSpawner
extends Node

signal spawn_requested(definition: EnemyData, location: SpawnLocationData)
signal generation_finished
var schedule: GroupSpawnSchedule
var remaining: Array[EnemyData] = []
var timer: Timer

func _ready() -> void:
	for entry in schedule.group.entries:
		var expected := maxf(0.0, entry.count * RunState.combat_rules().enemy_count_multiplier)
		var count := floori(expected)
		if expected > count and RunState.rng.randf() < expected - count: count += 1
		for i in count:
			remaining.append(entry.enemy)
	timer = Timer.new()
	timer.one_shot = true
	timer.timeout.connect(_spawn_next)
	add_child(timer)
	_spawn_next.call_deferred()

func _spawn_next() -> void:
	if remaining.is_empty():
		generation_finished.emit()
		queue_free()
		return
	spawn_requested.emit(remaining.pop_front(), schedule.location)
	if remaining.is_empty():
		generation_finished.emit()
		queue_free()
	else:
		timer.start(schedule.group.entry_interval)
