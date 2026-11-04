class_name DeliveryZone
extends Area3D

signal delivery_progress_changed(progress_ratio: float, status_text: String)
signal cargo_delivered(cargo: CargoBody)

@export var required_cargo_type_id: String = "giant_sofa"
@export_range(0.3, 3.0, 0.1) var required_settle_seconds: float = 1.2
@export_range(0.05, 1.5, 0.05) var max_settled_speed: float = 0.45

var is_delivery_completed: bool = false
var current_settle_progress: float = 0.0
var current_zone_status: String = "Waiting for sofa"

var _overlapping_cargos: Array[CargoBody] = []
var _settle_timer: float = 0.0


func _ready() -> void:
	collision_layer = 0
	collision_mask = 8 # Layer 4: Cargo
	monitoring = true
	monitorable = false
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func reset_zone() -> void:
	is_delivery_completed = false
	_settle_timer = 0.0
	current_settle_progress = 0.0
	current_zone_status = "Waiting for sofa"
	delivery_progress_changed.emit(0.0, current_zone_status)


func step_zone_validation(delta: float, is_host: bool) -> void:
	if not is_host or is_delivery_completed:
		return

	var candidate: CargoBody = _find_matching_cargo()
	if candidate == null:
		if _settle_timer > 0.0 or current_zone_status != "Waiting for sofa":
			_settle_timer = 0.0
			current_settle_progress = 0.0
			current_zone_status = "Waiting for sofa"
			delivery_progress_changed.emit(0.0, current_zone_status)
		return

	# Must not count as delivered while still in the truck or still being held by a carrier
	if candidate.current_state in [CargoBody.CargoState.LOADED_UNSECURED, CargoBody.CargoState.SECURED]:
		_settle_timer = 0.0
		current_settle_progress = 0.0
		current_zone_status = "Unload sofa from truck first!"
		delivery_progress_changed.emit(0.0, current_zone_status)
		return

	if candidate.current_state == CargoBody.CargoState.CARRIED or candidate.get_carrier_count() > 0:
		_settle_timer = 0.0
		current_settle_progress = 0.0
		current_zone_status = "Sofa in zone — Press E to release handles!"
		delivery_progress_changed.emit(0.0, current_zone_status)
		return

	if candidate.current_state != CargoBody.CargoState.FREE:
		return

	var speed: float = candidate.linear_velocity.length()
	if speed > max_settled_speed:
		_settle_timer = maxf(0.0, _settle_timer - delta * 0.5)
		current_settle_progress = clampf(_settle_timer / maxf(required_settle_seconds, 0.1), 0.0, 1.0)
		current_zone_status = "Sofa settling... (%.1f m/s)" % speed
		delivery_progress_changed.emit(current_settle_progress, current_zone_status)
		return

	_settle_timer += delta
	current_settle_progress = clampf(_settle_timer / maxf(required_settle_seconds, 0.1), 0.0, 1.0)
	current_zone_status = "Verifying delivery... %.0f%%" % (current_settle_progress * 100.0)
	delivery_progress_changed.emit(current_settle_progress, current_zone_status)

	if _settle_timer >= required_settle_seconds:
		_finalize_delivery(candidate)


func _finalize_delivery(cargo: CargoBody) -> void:
	if is_delivery_completed or cargo == null:
		return
	is_delivery_completed = true
	current_settle_progress = 1.0
	current_zone_status = "DELIVERED!"
	cargo.transition_to(CargoBody.CargoState.DELIVERED)
	delivery_progress_changed.emit(1.0, current_zone_status)
	cargo_delivered.emit(cargo)


func _find_matching_cargo() -> CargoBody:
	for i in range(_overlapping_cargos.size() - 1, -1, -1):
		var cargo: CargoBody = _overlapping_cargos[i]
		if cargo == null or not is_instance_valid(cargo):
			_overlapping_cargos.remove_at(i)
			continue
		if required_cargo_type_id.is_empty():
			return cargo
		if cargo.cargo_data != null and cargo.cargo_data.cargo_type_id == required_cargo_type_id:
			return cargo
	return null


func _on_body_entered(body: Node3D) -> void:
	if body is CargoBody:
		var cargo: CargoBody = body as CargoBody
		if not _overlapping_cargos.has(cargo):
			_overlapping_cargos.append(cargo)


func _on_body_exited(body: Node3D) -> void:
	if body is CargoBody:
		var cargo: CargoBody = body as CargoBody
		_overlapping_cargos.erase(cargo)
