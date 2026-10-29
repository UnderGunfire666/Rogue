class_name LootPickup
extends Area2D

var experience_value: int = 4
var gold_value: int = 3
var fragment_value: int = 0
var collected: bool = false
var player: Node2D
var heal_value: float = 0.0
var is_relic_crate: bool = false
var is_boss_crate: bool = false

func _ready() -> void:
	add_to_group("pickups")
	player = get_tree().get_first_node_in_group("players")
	if heal_value > 0.0:
		$Sprite2D.texture = load("res://assets/art/health_drop.svg")
	elif is_relic_crate or is_boss_crate:
		$Sprite2D.texture = load("res://assets/art/relic_crate.svg")
		if is_boss_crate:
			$Sprite2D.scale *= 1.7
			$Sprite2D.modulate = Color("#ffdd77")
	body_entered.connect(func(body: Node2D):
		if body.is_in_group("players"):
			collect())

func _physics_process(delta: float) -> void:
	if is_instance_valid(player) and global_position.distance_to(player.global_position) < 85.0 * RunState.combat_rules().pickup_range_multiplier:
		global_position = global_position.move_toward(player.global_position, 220.0 * delta)

func collect() -> void:
	if collected:
		return
	collected = true
	if RunState.expedition != null and (experience_value != 0 or gold_value != 0 or fragment_value != 0):
		var frags: int = fragment_value if fragment_value > 0 else gold_value * 10
		if frags > 0:
			RunState.collect_combat_fragments(frags)
		RunState.trigger_character_event(CharacterEventEffect.Trigger.MATERIAL_PICKUP)
	elif experience_value != 0 or gold_value != 0:
		RunState.gain_loot(experience_value, gold_value)
		RunState.trigger_character_event(CharacterEventEffect.Trigger.MATERIAL_PICKUP)
	if heal_value > 0.0 and is_instance_valid(player):
		RunState.trigger_character_event(CharacterEventEffect.Trigger.CONSUMABLE_PICKUP)
		player.health.heal(maxf(0.0, heal_value + RunState.combat_rules().consumable_heal_bonus))
	if is_relic_crate or is_boss_crate:
		var rewards: PackedStringArray = RunState.roll_shop_items(ContentCatalog.relic_ids(), false, 1)
		if not rewards.is_empty() and RunState.add_relic(rewards[0]) and is_instance_valid(player):
			player.combat_effect.emit(global_position, 0.0, "loot", ("巨大宝箱：" if is_boss_crate else "获得 ") + ContentCatalog.relic(rewards[0]).display_name)
		elif rewards.is_empty() and is_boss_crate:
			RunState.gain_loot(0, 25)
	queue_free()
