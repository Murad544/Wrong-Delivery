class_name CargoData
extends Resource

@export var cargo_type_id: String = "crate"
@export var display_name: String = "Delivery Crate"
@export_range(0.5, 200.0, 0.5) var mass_kg: float = 12.0
@export_range(10.0, 500.0, 5.0) var max_durability: float = 100.0
@export_range(1, 4, 1) var required_carriers: int = 1
@export_range(0.1, 5.0, 0.1) var fragility_multiplier: float = 1.0
@export_range(0.5, 12.0, 0.1) var impact_speed_threshold: float = 2.6
@export_range(0.05, 2.0, 0.05) var damage_cooldown_sec: float = 0.35
@export_range(1.2, 6.0, 0.1) var max_detach_distance: float = 3.2
@export_range(0.5, 2.5, 0.05) var hold_distance: float = 1.35
@export_range(0.4, 2.0, 0.05) var hold_height_offset: float = 0.95
