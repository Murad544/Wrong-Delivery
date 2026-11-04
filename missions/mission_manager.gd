class_name MissionManager
extends Node

signal mission_completed(score_summary: Dictionary)
signal mission_restarted()

@export var contract_name: String = "Contract #01: The Impossible Sofa"
@export_range(60.0, 900.0, 10.0) var target_time_seconds: float = 300.0
@export_range(5, 50, 5) var penalty_per_major_mistake: int = 15

var target_cargo: CargoBody = null
var delivery_truck: TruckController = null
var delivery_zone: DeliveryZone = null

var elapsed_seconds: float = 0.0
var major_mistakes_count: int = 0
var is_completed: bool = false
var current_objective_text: String = "Grab The Impossible Sofa inside the warehouse"
var last_score_summary: Dictionary = {}


func setup(
	primary_cargo: CargoBody,
	truck: TruckController,
	zone: DeliveryZone
) -> void:
	target_cargo = primary_cargo
	delivery_truck = truck
	delivery_zone = zone

	if delivery_zone != null and not delivery_zone.cargo_delivered.is_connected(_on_zone_cargo_delivered):
		delivery_zone.cargo_delivered.connect(_on_zone_cargo_delivered)


func step_mission(delta: float, is_host: bool) -> void:
	if not is_host:
		return

	if not is_completed:
		elapsed_seconds += delta
		_check_out_of_bounds_recovery()
		if delivery_zone != null:
			delivery_zone.step_zone_validation(delta, true)
		_update_objective_text()


func record_manual_reset_mistake() -> void:
	if is_completed:
		return
	# Only count as a mistake if the mission has been running and the sofa moved away from spawn
	if elapsed_seconds > 5.0 and target_cargo != null:
		if target_cargo.global_position.distance_to(target_cargo._spawn_transform.origin) > 1.5:
			major_mistakes_count += 1


func reset_mission_state() -> void:
	elapsed_seconds = 0.0
	major_mistakes_count = 0
	is_completed = false
	last_score_summary.clear()
	if delivery_zone != null:
		delivery_zone.reset_zone()
	_update_objective_text()
	mission_restarted.emit()


func apply_client_mission_snapshot(
	auth_elapsed: float,
	auth_mistakes: int,
	auth_completed: bool,
	auth_objective: String
) -> void:
	elapsed_seconds = auth_elapsed
	major_mistakes_count = auth_mistakes
	is_completed = auth_completed
	current_objective_text = auth_objective


func _on_zone_cargo_delivered(cargo: CargoBody) -> void:
	if is_completed:
		return
	is_completed = true
	current_objective_text = "COMPLETED — Delivery Finalized!"

	var cur_dur: float = 100.0
	var max_dur: float = 100.0
	if cargo != null and cargo.cargo_damage != null:
		cur_dur = cargo.cargo_damage.current_durability
		max_dur = cargo.cargo_damage.max_durability

	last_score_summary = ScoringSystem.calculate_mission_score(
		cur_dur,
		max_dur,
		elapsed_seconds,
		target_time_seconds,
		major_mistakes_count,
		penalty_per_major_mistake
	)
	last_score_summary["contract_name"] = contract_name
	last_score_summary["cargo_name"] = cargo.get_display_name() if cargo != null else "The Impossible Sofa"
	mission_completed.emit(last_score_summary)


func _check_out_of_bounds_recovery() -> void:
	if target_cargo != null and is_instance_valid(target_cargo):
		if target_cargo.global_position.y < -4.0:
			target_cargo.reset_to_spawn()
			major_mistakes_count += 1
	if delivery_truck != null and is_instance_valid(delivery_truck):
		if delivery_truck.global_position.y < -4.0:
			delivery_truck.reset_to_spawn()
			major_mistakes_count += 1


func _update_objective_text() -> void:
	if is_completed:
		current_objective_text = "COMPLETED — Delivery Finalized!"
		return

	if delivery_zone != null and delivery_zone.current_settle_progress > 0.01:
		current_objective_text = delivery_zone.current_zone_status
		return

	if target_cargo == null or not is_instance_valid(target_cargo):
		current_objective_text = "Locate the delivery cargo"
		return

	# Check if near the customer house at 20 Maple St (x >= 76, z <= 58)
	if target_cargo.global_position.x > 76.0 and target_cargo.global_position.z < 58.0:
		if target_cargo.current_state in [CargoBody.CargoState.LOADED_UNSECURED, CargoBody.CargoState.SECURED]:
			current_objective_text = "Step 4/5: Park in 20 Maple St driveway, unstrap (F), and unload the sofa"
		elif delivery_zone != null and delivery_zone.current_zone_status.begins_with("Sofa in zone"):
			current_objective_text = delivery_zone.current_zone_status
		else:
			current_objective_text = "Step 5/5: Pivot the sofa through the front door & hallway onto the green Delivery Zone!"
		return

	match target_cargo.current_state:
		CargoBody.CargoState.SECURED, CargoBody.CargoState.LOADED_UNSECURED:
			if target_cargo.current_state == CargoBody.CargoState.LOADED_UNSECURED and target_cargo.global_position.z < 18.0:
				current_objective_text = "Step 2/5: Press F at the yellow rear strap anchor to secure the sofa (or risk it sliding!)"
			elif target_cargo.global_position.x < 18.0 and target_cargo.global_position.z < 92.0:
				current_objective_text = "Step 3/5: Drive South down Commerce Blvd past the shops & roadwork toward Town Square!"
			elif target_cargo.global_position.x < 72.0:
				current_objective_text = "Step 3/5: Turn East at the Town Square fountain and cross the Maple Creek Bridge!"
			else:
				current_objective_text = "Step 3/5: Turn North onto Maple Street and follow it to 20 Maple St at the cul-de-sac!"
		CargoBody.CargoState.CARRIED:
			current_objective_text = "Step 2/5: Carry the sofa out the warehouse bay and up the truck's rear ramp (E to drop in bed)"
		_:
			current_objective_text = "Step 1/5: Grab The Impossible Sofa (E on Left & Right Handles) inside the warehouse"
