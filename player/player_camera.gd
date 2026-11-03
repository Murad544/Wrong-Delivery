class_name PlayerCamera
extends Node3D

signal mouse_capture_changed(is_captured: bool)

@export_range(0.05, 1.0, 0.01) var mouse_sensitivity: float = 0.22
@export_range(-85.0, -10.0, 1.0) var min_pitch_degrees: float = -65.0
@export_range(10.0, 85.0, 1.0) var max_pitch_degrees: float = 60.0
@export_range(1.5, 10.0, 0.1) var spring_length: float = 4.2
@export var capture_mouse_on_ready: bool = true

var _yaw_degrees: float = 0.0
var _pitch_degrees: float = -18.0

@onready var spring_arm: SpringArm3D = $SpringArm3D
@onready var camera: Camera3D = $SpringArm3D/Camera3D


func _ready() -> void:
	_yaw_degrees = rotation_degrees.y
	if spring_arm != null:
		spring_arm.spring_length = spring_length
		spring_arm.collision_mask = 1 # Collide with Layer 1 (Environment) to prevent wall clipping
		spring_arm.rotation_degrees.x = _pitch_degrees

	if capture_mouse_on_ready and DisplayServer.get_name() != "headless":
		set_mouse_captured(true)


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
	_yaw_degrees -= relative_motion.x * mouse_sensitivity
	_pitch_degrees = clampf(
		_pitch_degrees - relative_motion.y * mouse_sensitivity,
		min_pitch_degrees,
		max_pitch_degrees
	)
	rotation_degrees.y = _yaw_degrees
	if spring_arm != null:
		spring_arm.rotation_degrees.x = _pitch_degrees


func set_mouse_captured(captured: bool) -> void:
	if DisplayServer.get_name() == "headless":
		return
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if captured else Input.MOUSE_MODE_VISIBLE
	mouse_capture_changed.emit(captured)


func get_horizontal_basis() -> Basis:
	return Basis(Vector3.UP, deg_to_rad(_yaw_degrees))


func get_forward_direction() -> Vector3:
	if camera != null:
		return -camera.global_transform.basis.z.normalized()
	return -global_transform.basis.z.normalized()


func get_camera_position() -> Vector3:
	if camera != null:
		return camera.global_position
	return global_position
