class_name PlayerCamera
extends Node3D

signal mouse_capture_changed(is_captured: bool)

@export_range(0.05, 1.0, 0.01) var mouse_sensitivity: float = 0.22
@export_range(-85.0, -10.0, 1.0) var min_pitch_degrees: float = -65.0
@export_range(10.0, 85.0, 1.0) var max_pitch_degrees: float = 60.0
@export_range(1.5, 10.0, 0.1) var spring_length: float = 4.2
@export_range(3.0, 14.0, 0.1) var vehicle_spring_length: float = 7.6
@export_range(0.0, 8.0, 0.2) var vehicle_auto_follow_speed: float = 3.2
@export var capture_mouse_on_ready: bool = true

var _yaw_degrees: float = 0.0
var _pitch_degrees: float = -18.0
var _in_vehicle: bool = false
var _tracked_vehicle: Node3D = null
var _manual_look_cooldown: float = 0.0

@onready var spring_arm: SpringArm3D = $SpringArm3D
@onready var camera: Camera3D = $SpringArm3D/Camera3D


func _ready() -> void:
	top_level = false
	_yaw_degrees = global_rotation_degrees.y
	_apply_rotations()

	if spring_arm != null:
		spring_arm.spring_length = spring_length
		spring_arm.collision_mask = 1 # Collide with Layer 1 (Environment) to prevent wall clipping

	if capture_mouse_on_ready and DisplayServer.get_name() != "headless":
		set_mouse_captured(true)


func _process(delta: float) -> void:
	if _manual_look_cooldown > 0.0:
		_manual_look_cooldown = maxf(0.0, _manual_look_cooldown - delta)

	if _in_vehicle and _tracked_vehicle != null and is_instance_valid(_tracked_vehicle):
		if _manual_look_cooldown <= 0.0 and vehicle_auto_follow_speed > 0.0:
			var spd: float = absf(float(_tracked_vehicle.get("forward_speed")))
			if spd > 0.8:
				var target_yaw_rad: float = _tracked_vehicle.global_rotation.y
				if float(_tracked_vehicle.get("forward_speed")) < -0.5:
					target_yaw_rad = wrapf(target_yaw_rad + PI, -PI, PI)
				var current_yaw_rad: float = deg_to_rad(_yaw_degrees)
				var new_yaw_rad: float = lerp_angle(
					current_yaw_rad,
					target_yaw_rad,
					clampf(vehicle_auto_follow_speed * delta, 0.0, 1.0)
				)
				_yaw_degrees = rad_to_deg(new_yaw_rad)
				_apply_rotations()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		set_mouse_captured(Input.mouse_mode != Input.MOUSE_MODE_CAPTURED)
		get_viewport().set_input_as_handled()
		return

	if event is InputEventMouseButton:
		var mouse_button: InputEventMouseButton = event as InputEventMouseButton
		if mouse_button.pressed and mouse_button.button_index == MOUSE_BUTTON_LEFT:
			if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and DisplayServer.get_name() != "headless":
				set_mouse_captured(true)
				get_viewport().set_input_as_handled()
				return

	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var mouse_motion: InputEventMouseMotion = event as InputEventMouseMotion
		apply_look_delta(mouse_motion.relative)


func apply_look_delta(relative_motion: Vector2) -> void:
	_manual_look_cooldown = 1.15
	_yaw_degrees = wrapf(_yaw_degrees - relative_motion.x * mouse_sensitivity, -180.0, 180.0)
	_pitch_degrees = clampf(
		_pitch_degrees - relative_motion.y * mouse_sensitivity,
		min_pitch_degrees,
		max_pitch_degrees
	)
	_apply_rotations()


func set_vehicle_camera_mode(in_vehicle: bool, vehicle: Node3D = null) -> void:
	_in_vehicle = in_vehicle
	_tracked_vehicle = vehicle
	if spring_arm != null:
		spring_arm.spring_length = vehicle_spring_length if in_vehicle else spring_length
	if in_vehicle and vehicle != null:
		_yaw_degrees = rad_to_deg(vehicle.global_rotation.y)
		_pitch_degrees = -16.0
		_manual_look_cooldown = 0.0
	_apply_rotations()


func align_yaw_to_world_angle(yaw_radians: float) -> void:
	_yaw_degrees = rad_to_deg(yaw_radians)
	_apply_rotations()


func set_mouse_captured(captured: bool) -> void:
	if DisplayServer.get_name() == "headless":
		return
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if captured else Input.MOUSE_MODE_VISIBLE
	mouse_capture_changed.emit(captured)


func get_horizontal_basis() -> Basis:
	# Derive horizontal basis directly from global yaw so parent rotation can never desync WASD controls
	return Basis(Vector3.UP, deg_to_rad(_yaw_degrees))


func get_forward_direction() -> Vector3:
	if camera != null:
		return -camera.global_transform.basis.z.normalized()
	return -global_transform.basis.z.normalized()


func get_camera_position() -> Vector3:
	if camera != null:
		return camera.global_position
	return global_position


func _apply_rotations() -> void:
	global_rotation_degrees = Vector3(0.0, _yaw_degrees, 0.0)
	if spring_arm != null:
		spring_arm.rotation_degrees = Vector3(_pitch_degrees, 0.0, 0.0)
