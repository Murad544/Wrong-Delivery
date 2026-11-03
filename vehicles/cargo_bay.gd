class_name CargoBay
extends Area3D

signal cargo_loaded(cargo: CargoBody)
signal cargo_unloaded(cargo: CargoBody)
signal cargo_secured_changed(cargo: CargoBody, is_secured: bool)
signal cargo_slide_impact(cargo: CargoBody, impact_speed: float)

@export_group("Bay Dimensions")
@export_range(0.4, 3.0, 0.05) var bay_half_width: float = 0.85
@export_range(0.6, 4.0, 0.05) var bay_half_length: float = 1.35
@export_range(0.0, 1.5, 0.05) var bed_floor_y: float = 0.42

@export_group("Unsecured Sliding Model")
@export_range(0.5, 8.0, 0.1) var slide_static_threshold_accel: float = 2.2
@export_range(0.5, 6.0, 0.1) var bed_friction_decel: float = 3.2
@export_range(0.2, 2.0, 0.05) var longitudinal_slide_scale: float = 0.65
@export_range(0.2, 2.0, 0.05) var lateral_slide_scale: float = 0.85
@export_range(0.5, 6.0, 0.1) var slide_wall_impact_threshold: float = 1.4
@export_range(0.5, 4.0, 0.1) var wall_impact_speed_multiplier: float = 1.85
@export_range(2.0, 20.0, 0.5) var max_tilt_degrees: float = 9.0

var truck_owner: Node3D = null
var current_stability_ratio: float = 1.0
var current_warning_text: String = ""

var _overlapping_cargos: Array[CargoBody] = []
# Maps CargoBody -> Dictionary { "local_pos": Vector3, "local_vel": Vector2, "local_yaw": float, "tilt": Vector2 }
var _loaded_records: Dictionary = {}

@onready var strap_visuals: Node3D = get_node_or_null("StrapVisuals") as Node3D


func _ready() -> void:
	collision_layer = 0
	collision_mask = 8 # Layer 4: Cargo
	monitoring = true
	monitorable = false
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	_update_strap_visuals()


func get_loaded_cargos() -> Array[CargoBody]:
	var result: Array[CargoBody] = []
	for cargo_key: Variant in _loaded_records.keys():
		var cargo: CargoBody = cargo_key as CargoBody
		if cargo != null and is_instance_valid(cargo):
			result.append(cargo)
	return result


func has_loaded_cargo() -> bool:
	return not _loaded_records.is_empty()


func is_any_cargo_secured() -> bool:
	for cargo: CargoBody in get_loaded_cargos():
		if cargo.current_state == CargoBody.CargoState.SECURED:
			return true
	return false


func are_all_cargos_secured() -> bool:
	var loaded: Array[CargoBody] = get_loaded_cargos()
	if loaded.is_empty():
		return false
	for cargo: CargoBody in loaded:
		if cargo.current_state != CargoBody.CargoState.SECURED:
			return false
	return true


func can_unload_cargo() -> Dictionary:
	if truck_owner != null and truck_owner.has_method("is_stationary_for_cargo"):
		if not bool(truck_owner.call("is_stationary_for_cargo")):
			return {
				"allowed": false,
				"reason": "Park the truck before unloading cargo"
			}
	return {"allowed": true, "reason": ""}


func evaluate_secure_action() -> Dictionary:
	if truck_owner != null and truck_owner.has_method("is_stationary_for_cargo"):
		if not bool(truck_owner.call("is_stationary_for_cargo")):
			return {
				"allowed": false,
				"reason": "Truck must be parked to secure/unsecure cargo"
			}
	if not has_loaded_cargo():
		return {
			"allowed": false,
			"reason": "No cargo loaded in the truck bay"
		}
	return {"allowed": true, "reason": ""}


func toggle_secure_loaded_cargo(actor: Node3D = null) -> Dictionary:
	if actor != null and actor.has_method("is_holding_any_cargo") and bool(actor.call("is_holding_any_cargo")):
		return {
			"success": false,
			"message": "Release held cargo before operating cargo straps"
		}

	var check: Dictionary = evaluate_secure_action()
	if not bool(check.get("allowed", false)):
		return {
			"success": false,
			"message": String(check.get("reason", "Cannot secure cargo"))
		}

	var should_secure: bool = not are_all_cargos_secured()
	var changed_count: int = 0

	for cargo: CargoBody in get_loaded_cargos():
		if should_secure:
			if cargo.current_state == CargoBody.CargoState.LOADED_UNSECURED:
				if cargo.transition_to(CargoBody.CargoState.SECURED):
					var rec: Dictionary = _loaded_records[cargo]
					rec["local_vel"] = Vector2.ZERO
					rec["tilt"] = Vector2.ZERO
					# Center slightly if near edges when strapped down
					var lp: Vector3 = rec["local_pos"]
					lp.x = clampf(lp.x, -bay_half_width * 0.5, bay_half_width * 0.5)
					lp.z = clampf(lp.z, -bay_half_length * 0.5, bay_half_length * 0.5)
					rec["local_pos"] = lp
					_loaded_records[cargo] = rec
					_apply_truck_local_transform(cargo, rec)
					cargo_secured_changed.emit(cargo, true)
					changed_count += 1
		else:
			if cargo.current_state == CargoBody.CargoState.SECURED:
				if cargo.transition_to(CargoBody.CargoState.LOADED_UNSECURED):
					cargo_secured_changed.emit(cargo, false)
					changed_count += 1

	_update_strap_visuals()

	if changed_count <= 0:
		return {
			"success": false,
			"message": "No cargo state changed"
		}

	if should_secure:
		current_stability_ratio = 1.0
		current_warning_text = "SECURED"
		return {
			"success": true,
			"message": "Cargo secured with heavy-duty straps!"
		}
	else:
		current_warning_text = "UNSECURED"
		return {
			"success": true,
			"message": "Cargo straps released (Cargo is now UNSECURED)"
		}


func step_bay_physics(
	delta: float,
	longitudinal_accel: float,
	lateral_accel: float,
	truck_stationary: bool
) -> void:
	_check_newly_settled_cargo(truck_stationary)

	if _loaded_records.is_empty():
		current_stability_ratio = 1.0
		current_warning_text = "EMPTY"
		return

	var worst_instability: float = 0.0
	var any_unsecured: bool = false

	var keys: Array = _loaded_records.keys()
	for key_val: Variant in keys:
		var cargo: CargoBody = key_val as CargoBody
		if cargo == null or not is_instance_valid(cargo):
			_loaded_records.erase(key_val)
			continue

		if cargo.current_state not in [CargoBody.CargoState.LOADED_UNSECURED, CargoBody.CargoState.SECURED]:
			_loaded_records.erase(cargo)
			continue

		var rec: Dictionary = _loaded_records[cargo]
		if cargo.current_state == CargoBody.CargoState.SECURED:
			rec["local_vel"] = Vector2.ZERO
			rec["tilt"] = Vector2.ZERO
			_apply_truck_local_transform(cargo, rec)
			continue

		any_unsecured = true
		var local_pos: Vector3 = rec["local_pos"]
		var local_vel: Vector2 = rec["local_vel"]

		# Inertial pseudo-acceleration in truck-local XZ plane:
		# Truck forward is -Z; accelerating forward (+longitudinal_accel) pushes cargo toward +Z (rear).
		# Turning left (+yaw_rate, +lateral_accel) pushes cargo toward +X (right wall).
		var inertial_x: float = lateral_accel * lateral_slide_scale
		var inertial_z: float = longitudinal_accel * longitudinal_slide_scale
		var inertial_vec: Vector2 = Vector2(inertial_x, inertial_z)

		if inertial_vec.length() > slide_static_threshold_accel or local_vel.length() > 0.05:
			local_vel += inertial_vec * delta

		# Apply bed friction opposing local slide velocity
		local_vel = local_vel.move_toward(Vector2.ZERO, bed_friction_decel * delta)

		local_pos.x += local_vel.x * delta
		local_pos.z += local_vel.y * delta

		# Check collisions with cargo bay side walls (-X / +X) and front/rear stops (-Z / +Z)
		var wall_hit_speed: float = 0.0
		if absf(local_pos.x) > bay_half_width:
			local_pos.x = signf(local_pos.x) * bay_half_width
			wall_hit_speed = maxf(wall_hit_speed, absf(local_vel.x))
			local_vel.x = -local_vel.x * 0.2

		if absf(local_pos.z) > bay_half_length:
			local_pos.z = signf(local_pos.z) * bay_half_length
			wall_hit_speed = maxf(wall_hit_speed, absf(local_vel.y))
			local_vel.y = -local_vel.y * 0.2

		if wall_hit_speed >= slide_wall_impact_threshold:
			var effective_impact: float = wall_hit_speed * wall_impact_speed_multiplier + 1.5
			var dmg: float = cargo.apply_external_impact(effective_impact)
			if dmg > 0.0:
				cargo_slide_impact.emit(cargo, effective_impact)

		# Visual tilt proportional to lateral & longitudinal acceleration
		var target_roll_deg: float = clampf(-inertial_x * 1.2, -max_tilt_degrees, max_tilt_degrees)
		var target_pitch_deg: float = clampf(inertial_z * 1.0, -max_tilt_degrees, max_tilt_degrees)
		var current_tilt: Vector2 = rec["tilt"]
		current_tilt.x = lerpf(current_tilt.x, deg_to_rad(target_pitch_deg), clampf(delta * 10.0, 0.0, 1.0))
		current_tilt.y = lerpf(current_tilt.y, deg_to_rad(target_roll_deg), clampf(delta * 10.0, 0.0, 1.0))

		rec["local_pos"] = local_pos
		rec["local_vel"] = local_vel
		rec["tilt"] = current_tilt
		_loaded_records[cargo] = rec

		_apply_truck_local_transform(cargo, rec)

		var slide_instability: float = clampf(local_vel.length() / 2.5 + inertial_vec.length() / 12.0, 0.0, 1.0)
		worst_instability = maxf(worst_instability, slide_instability)

	current_stability_ratio = clampf(1.0 - worst_instability, 0.0, 1.0)
	if not any_unsecured:
		current_warning_text = "SECURED"
	elif current_stability_ratio < 0.45:
		current_warning_text = "DANGER: CARGO SLIDING!"
	elif current_stability_ratio < 0.8:
		current_warning_text = "WARNING: UNSECURED SHIFTING"
	else:
		current_warning_text = "UNSECURED (Press F at bay to strap)"


func apply_vehicle_crash_impulse(crash_speed: float) -> void:
	for cargo: CargoBody in get_loaded_cargos():
		if cargo.current_state == CargoBody.CargoState.LOADED_UNSECURED:
			cargo.apply_external_impact(crash_speed * 1.1)
			if _loaded_records.has(cargo):
				var rec: Dictionary = _loaded_records[cargo]
				var lv: Vector2 = rec["local_vel"]
				lv.y -= crash_speed * 0.6
				rec["local_vel"] = lv
				_loaded_records[cargo] = rec
		elif cargo.current_state == CargoBody.CargoState.SECURED and crash_speed > 9.0:
			# Secured cargo is protected from normal bumps, only taking reduced damage on extreme crashes
			cargo.apply_external_impact(crash_speed * 0.45)


func load_cargo_immediately(cargo: CargoBody, make_secured: bool = false) -> bool:
	if cargo == null or not is_instance_valid(cargo):
		return false
	if cargo.current_state == CargoBody.CargoState.CARRIED:
		if cargo.carry_controller != null:
			cargo.carry_controller.detach_all("Loaded into truck bay")

	if not cargo.transition_to(CargoBody.CargoState.LOADED_UNSECURED):
		return false

	cargo.current_cargo_bay = self
	if truck_owner is PhysicsBody3D:
		(truck_owner as PhysicsBody3D).add_collision_exception_with(cargo)
		cargo.add_collision_exception_with(truck_owner)
	var local_tf: Transform3D = global_transform.affine_inverse() * cargo.global_transform
	var clamped_pos: Vector3 = Vector3(
		clampf(local_tf.origin.x, -bay_half_width, bay_half_width),
		bed_floor_y,
		clampf(local_tf.origin.z, -bay_half_length, bay_half_length)
	)
	var local_yaw: float = local_tf.basis.get_euler().y

	var rec: Dictionary = {
		"local_pos": clamped_pos,
		"local_vel": Vector2.ZERO,
		"local_yaw": local_yaw,
		"tilt": Vector2.ZERO,
	}
	_loaded_records[cargo] = rec
	_apply_truck_local_transform(cargo, rec)

	if make_secured:
		cargo.transition_to(CargoBody.CargoState.SECURED)

	_update_strap_visuals()
	cargo_loaded.emit(cargo)
	return true


func notify_cargo_unloaded(cargo: CargoBody) -> void:
	if _loaded_records.has(cargo):
		_loaded_records.erase(cargo)
		if cargo != null and is_instance_valid(cargo):
			if truck_owner is PhysicsBody3D:
				(truck_owner as PhysicsBody3D).remove_collision_exception_with(cargo)
				cargo.remove_collision_exception_with(truck_owner)
			if cargo.current_cargo_bay == self:
				cargo.current_cargo_bay = null
		_update_strap_visuals()
		cargo_unloaded.emit(cargo)


func _check_newly_settled_cargo(truck_stationary: bool) -> void:
	if not truck_stationary:
		return
	for i in range(_overlapping_cargos.size() - 1, -1, -1):
		var cargo: CargoBody = _overlapping_cargos[i]
		if cargo == null or not is_instance_valid(cargo):
			_overlapping_cargos.remove_at(i)
			continue
		if _loaded_records.has(cargo):
			continue
		if cargo.current_state == CargoBody.CargoState.FREE:
			load_cargo_immediately(cargo, false)


func _apply_truck_local_transform(cargo: CargoBody, rec: Dictionary) -> void:
	var lp: Vector3 = rec["local_pos"]
	var yaw: float = float(rec["local_yaw"])
	var tilt: Vector2 = rec["tilt"]
	var local_basis: Basis = Basis.from_euler(Vector3(tilt.x, yaw, tilt.y))
	var local_tf: Transform3D = Transform3D(local_basis, lp)
	cargo.global_transform = global_transform * local_tf


func _update_strap_visuals() -> void:
	if strap_visuals != null:
		strap_visuals.visible = is_any_cargo_secured()


func _on_body_entered(body: Node3D) -> void:
	if body is CargoBody:
		var cargo: CargoBody = body as CargoBody
		if not _overlapping_cargos.has(cargo):
			_overlapping_cargos.append(cargo)


func _on_body_exited(body: Node3D) -> void:
	if body is CargoBody:
		var cargo: CargoBody = body as CargoBody
		_overlapping_cargos.erase(cargo)
