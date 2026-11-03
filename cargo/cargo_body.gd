class_name CargoBody
extends RigidBody3D

enum CargoState {
	FREE,
	CARRIED,
	LOADED_UNSECURED,
	SECURED,
	UNLOADING,
	DELIVERED,
}

signal state_changed(old_state: CargoState, new_state: CargoState)
signal cargo_damaged(damage_amount: float, current_durability: float, max_durability: float, impact_speed: float)
signal carrier_status_changed(cargo: CargoBody, carrier_count: int, required_carriers: int)

@export var cargo_data: CargoData = null

var current_state: CargoState = CargoState.FREE
var _spawn_transform: Transform3D = Transform3D.IDENTITY
var _prev_linear_velocity: Vector3 = Vector3.ZERO
var _spawn_grace_timer: float = 0.35
var _damage_flash_timer: float = 0.0
var _handles: Array[CargoHandle] = []

@onready var cargo_damage: CargoDamage = $CargoDamage
@onready var carry_controller: CarryController = $CarryController
@onready var visual_root: Node3D = $VisualRoot


func _ready() -> void:
	_spawn_transform = global_transform
	collision_layer = 8 # Layer 4: Cargo (bitmask value 8)
	collision_mask = 1 | 2 | 8 | 16 # Environment (1) | Player (2) | Cargo (8) | Vehicle (16)
	contact_monitor = true
	max_contacts_reported = 4
	can_sleep = false

	if cargo_data == null:
		cargo_data = CargoData.new()

	mass = maxf(0.5, cargo_data.mass_kg)

	_collect_handles()

	if cargo_damage != null:
		cargo_damage.configure_from_data(cargo_data)
		cargo_damage.damage_taken.connect(_on_damage_taken)

	if carry_controller != null:
		carry_controller.setup(self, _handles, cargo_data)
		carry_controller.carrier_attached.connect(_on_carrier_attached)
		carry_controller.carrier_detached.connect(_on_carrier_detached)


func _physics_process(delta: float) -> void:
	if _spawn_grace_timer > 0.0:
		_spawn_grace_timer = maxf(0.0, _spawn_grace_timer - delta)

	if _damage_flash_timer > 0.0:
		_damage_flash_timer = maxf(0.0, _damage_flash_timer - delta)
		if _damage_flash_timer <= 0.0:
			_set_visual_flash(false)

	if current_state == CargoState.CARRIED and carry_controller != null:
		carry_controller.process_carry_physics(delta)

	_evaluate_collision_impacts()
	_prev_linear_velocity = linear_velocity


func get_display_name() -> String:
	if cargo_data != null and not cargo_data.display_name.is_empty():
		return cargo_data.display_name
	return name


func get_required_carriers() -> int:
	if cargo_data != null:
		return cargo_data.required_carriers
	return 1


func get_carrier_count() -> int:
	if carry_controller != null:
		return carry_controller.get_carrier_count()
	return 0


static func get_state_name(state_val: CargoState) -> String:
	match state_val:
		CargoState.FREE:
			return "FREE"
		CargoState.CARRIED:
			return "CARRIED"
		CargoState.LOADED_UNSECURED:
			return "LOADED_UNSECURED"
		CargoState.SECURED:
			return "SECURED"
		CargoState.UNLOADING:
			return "UNLOADING"
		CargoState.DELIVERED:
			return "DELIVERED"
	return "UNKNOWN"


func can_transition_to(new_state: CargoState) -> bool:
	if new_state == current_state:
		return true

	match current_state:
		CargoState.FREE:
			return new_state in [
				CargoState.CARRIED,
				CargoState.LOADED_UNSECURED,
				CargoState.DELIVERED,
			]
		CargoState.CARRIED:
			return new_state in [
				CargoState.FREE,
				CargoState.LOADED_UNSECURED,
				CargoState.DELIVERED,
			]
		CargoState.LOADED_UNSECURED:
			return new_state in [
				CargoState.CARRIED,
				CargoState.SECURED,
				CargoState.UNLOADING,
				CargoState.FREE,
			]
		CargoState.SECURED:
			return new_state in [
				CargoState.LOADED_UNSECURED,
				CargoState.UNLOADING,
			]
		CargoState.UNLOADING:
			return new_state in [
				CargoState.CARRIED,
				CargoState.FREE,
			]
		CargoState.DELIVERED:
			# Delivered is final unless reset_to_spawn() is invoked
			return false

	return false


func transition_to(new_state: CargoState) -> bool:
	if new_state == current_state:
		return true
	if not can_transition_to(new_state):
		return false

	var old_state: CargoState = current_state
	current_state = new_state

	match current_state:
		CargoState.FREE:
			freeze = false
			linear_damp = 0.2
			angular_damp = 0.6
		CargoState.CARRIED:
			freeze = false
			linear_damp = 1.5
			angular_damp = 3.0
		CargoState.SECURED:
			_spawn_grace_timer = 0.25
			linear_velocity = Vector3.ZERO
			angular_velocity = Vector3.ZERO
			freeze = true
		CargoState.DELIVERED:
			if carry_controller != null:
				carry_controller.detach_all("Delivered")
			linear_velocity = Vector3.ZERO
			angular_velocity = Vector3.ZERO
			freeze = true

	state_changed.emit(old_state, current_state)
	return true


func evaluate_handle_interaction(handle_id: int, origin: Vector3) -> Dictionary:
	if current_state == CargoState.DELIVERED:
		return {"allowed": false, "reason": "Cargo already delivered"}
	if current_state == CargoState.SECURED:
		return {"allowed": false, "reason": "Cargo is secured — unsecure first (F)"}

	var handle: CargoHandle = _find_handle(handle_id)
	if handle == null:
		return {"allowed": false, "reason": "Invalid handle"}

	var dist: float = handle.global_position.distance_to(origin)
	if dist > handle.max_interaction_distance:
		return {"allowed": false, "reason": "Too far from handle"}

	return {"allowed": true, "reason": ""}


func interact_with_handle(handle_id: int, actor: Node3D) -> String:
	if actor == null or carry_controller == null:
		return "Cannot interact"

	# If this actor is already holding this handle, release it
	var held_id: int = carry_controller.get_actor_handle_id(actor)
	if held_id == handle_id:
		carry_controller.detach_carrier_by_handle(handle_id, "Released")
		return "Released %s" % get_display_name()

	# Prevent grabbing multiple handles simultaneously
	if held_id != -1:
		return "Already holding another handle on this cargo"

	if actor.has_method("is_holding_any_cargo") and bool(actor.call("is_holding_any_cargo")):
		return "Hands full — release held cargo first"

	var handle: CargoHandle = _find_handle(handle_id)
	if handle != null and handle.is_occupied() and handle.occupying_actor != actor:
		return "Handle is already occupied"

	if not can_transition_to(CargoState.CARRIED) and current_state != CargoState.CARRIED:
		return "Cargo cannot be carried in state %s" % get_state_name(current_state)

	var attached: bool = carry_controller.attach_carrier(handle_id, actor)
	if not attached:
		return "Could not grab handle"

	if get_required_carriers() > 1 and get_carrier_count() < get_required_carriers():
		return "Grabbed %s (%d/%d carriers — need %d players to lift cleanly)" % [
			get_display_name(),
			get_carrier_count(),
			get_required_carriers(),
			get_required_carriers(),
		]
	return "Carrying %s (Q/R to rotate, E to drop)" % get_display_name()


func release_actor(actor: Node3D, reason: String = "Released") -> bool:
	if carry_controller == null:
		return false
	return carry_controller.detach_actor(actor, reason)


func reset_to_spawn() -> void:
	if carry_controller != null:
		carry_controller.detach_all("Reset to checkpoint")

	_spawn_grace_timer = 0.4
	freeze = false
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	_prev_linear_velocity = Vector3.ZERO
	global_transform = _spawn_transform

	var old_state: CargoState = current_state
	current_state = CargoState.FREE
	if old_state != current_state:
		state_changed.emit(old_state, current_state)


func _evaluate_collision_impacts() -> void:
	if _spawn_grace_timer > 0.0:
		return
	if current_state in [CargoState.SECURED, CargoState.DELIVERED]:
		return
	if get_contact_count() <= 0 or cargo_damage == null:
		return

	var velocity_change: float = (linear_velocity - _prev_linear_velocity).length()
	var impact_speed: float = maxf(velocity_change, _prev_linear_velocity.length() * 0.75)
	cargo_damage.process_impact(impact_speed, true)


func _on_carrier_attached(_handle_id: int, actor: Node3D) -> void:
	if actor is PhysicsBody3D:
		add_collision_exception_with(actor)
	if actor != null and actor.has_method("on_cargo_grabbed"):
		actor.call("on_cargo_grabbed", self)

	if current_state != CargoState.CARRIED:
		transition_to(CargoState.CARRIED)

	carrier_status_changed.emit(self, get_carrier_count(), get_required_carriers())


func _on_carrier_detached(_handle_id: int, actor: Node3D, _reason: String) -> void:
	if actor != null and is_instance_valid(actor):
		if actor is PhysicsBody3D:
			remove_collision_exception_with(actor)
		if actor.has_method("on_cargo_released"):
			actor.call("on_cargo_released", self)

	if get_carrier_count() == 0 and current_state == CargoState.CARRIED:
		transition_to(CargoState.FREE)

	carrier_status_changed.emit(self, get_carrier_count(), get_required_carriers())


func _on_damage_taken(damage_amount: float, current_dur: float, max_dur: float, impact_speed: float) -> void:
	_damage_flash_timer = 0.22
	_set_visual_flash(true)
	cargo_damaged.emit(damage_amount, current_dur, max_dur, impact_speed)


var _flash_material: StandardMaterial3D = null

func _set_visual_flash(flashing: bool) -> void:
	if visual_root == null:
		return
	if _flash_material == null:
		_flash_material = StandardMaterial3D.new()
		_flash_material.albedo_color = Color(1.0, 0.25, 0.2, 1.0)
		_flash_material.emission_enabled = true
		_flash_material.emission = Color(0.95, 0.2, 0.1, 1.0)
		_flash_material.emission_energy_multiplier = 1.6

	for child: Node in visual_root.get_children():
		if child is GeometryInstance3D:
			var geom: GeometryInstance3D = child as GeometryInstance3D
			geom.material_override = _flash_material if flashing else null


func _collect_handles() -> void:
	_handles.clear()
	var handles_root: Node = get_node_or_null("Handles")
	if handles_root == null:
		return
	for child: Node in handles_root.get_children():
		if child is CargoHandle:
			var handle: CargoHandle = child as CargoHandle
			handle.cargo_owner = self
			_handles.append(handle)


func _find_handle(handle_id: int) -> CargoHandle:
	for handle: CargoHandle in _handles:
		if handle != null and handle.handle_id == handle_id:
			return handle
	return null
