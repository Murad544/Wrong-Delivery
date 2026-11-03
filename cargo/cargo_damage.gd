class_name CargoDamage
extends Node

signal durability_changed(current_durability: float, max_durability: float)
signal damage_taken(damage_amount: float, current_durability: float, max_durability: float, impact_speed: float)

@export_range(10.0, 500.0, 5.0) var max_durability: float = 100.0
@export_range(0.5, 12.0, 0.1) var impact_speed_threshold: float = 2.6
@export_range(0.1, 5.0, 0.1) var fragility_multiplier: float = 1.0
@export_range(0.05, 2.0, 0.05) var damage_cooldown_sec: float = 0.35
@export_range(1.0, 30.0, 0.5) var base_damage_scale: float = 7.5

var current_durability: float = 100.0
var last_impact_speed: float = 0.0
var last_damage_amount: float = 0.0
var _cooldown_timer: float = 0.0


func _ready() -> void:
	current_durability = max_durability


func configure_from_data(data: CargoData) -> void:
	if data == null:
		return
	max_durability = data.max_durability
	impact_speed_threshold = data.impact_speed_threshold
	fragility_multiplier = data.fragility_multiplier
	damage_cooldown_sec = data.damage_cooldown_sec
	current_durability = max_durability
	durability_changed.emit(current_durability, max_durability)


func _physics_process(delta: float) -> void:
	if _cooldown_timer > 0.0:
		_cooldown_timer = maxf(0.0, _cooldown_timer - delta)


func reset_durability() -> void:
	current_durability = max_durability
	last_impact_speed = 0.0
	last_damage_amount = 0.0
	_cooldown_timer = 0.0
	durability_changed.emit(current_durability, max_durability)


func compute_potential_damage(impact_speed: float) -> float:
	if impact_speed < impact_speed_threshold:
		return 0.0
	var excess_speed: float = impact_speed - impact_speed_threshold
	return excess_speed * base_damage_scale * fragility_multiplier


func process_impact(impact_speed: float, allow_damage: bool = true) -> float:
	last_impact_speed = impact_speed
	if not allow_damage:
		return 0.0
	if _cooldown_timer > 0.0:
		return 0.0

	var raw_damage: float = compute_potential_damage(impact_speed)
	if raw_damage <= 0.01:
		return 0.0

	_cooldown_timer = damage_cooldown_sec
	var applied_damage: float = minf(current_durability, raw_damage)
	current_durability = clampf(current_durability - raw_damage, 0.0, max_durability)
	last_damage_amount = applied_damage

	durability_changed.emit(current_durability, max_durability)
	damage_taken.emit(applied_damage, current_durability, max_durability, impact_speed)
	return applied_damage


func get_durability_ratio() -> float:
	if max_durability <= 0.0:
		return 0.0
	return clampf(current_durability / max_durability, 0.0, 1.0)
