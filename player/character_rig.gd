@tool
class_name CharacterRig
extends Node3D

## Procedural low-poly delivery worker built from primitive meshes, with a fully procedural
## animation layer (walk/run cycle, idle breathing, jump/fall pose, landing squash, carry pose,
## strain shake, knockback tumble, blinking). Purely presentational: it never affects physics.

@export_group("Colors")
@export var uniform_color: Color = Color(0.95, 0.48, 0.16, 1.0):
	set(value):
		uniform_color = value
		if _uniform_mat != null:
			_uniform_mat.albedo_color = value
@export var skin_color: Color = Color(0.96, 0.77, 0.62, 1.0)
@export var pants_color: Color = Color(0.19, 0.24, 0.36, 1.0)
@export var cap_color: Color = Color(0.16, 0.2, 0.3, 1.0)

@export_group("Animation Tuning")
@export_range(0.6, 3.0, 0.05) var stride_length: float = 1.35
@export_range(5.0, 60.0, 1.0) var max_leg_swing_degrees: float = 36.0
@export_range(5.0, 60.0, 1.0) var max_arm_swing_degrees: float = 40.0
@export_range(0.0, 0.2, 0.005) var run_bob_height: float = 0.06
@export_range(0.0, 25.0, 0.5) var max_lean_degrees: float = 12.0
@export_range(1.0, 20.0, 0.5) var pose_blend_speed: float = 9.0

const HIP_HEIGHT: float = 0.92

var _uniform_mat: StandardMaterial3D = null
var _built: bool = false

var _body_pivot: Node3D = null
var _torso_pivot: Node3D = null
var _head_pivot: Node3D = null
var _shoulder_l: Node3D = null
var _shoulder_r: Node3D = null
var _elbow_l: Node3D = null
var _elbow_r: Node3D = null
var _hip_l: Node3D = null
var _hip_r: Node3D = null
var _knee_l: Node3D = null
var _knee_r: Node3D = null
var _eye_l: MeshInstance3D = null
var _eye_r: MeshInstance3D = null
var _dust: CPUParticles3D = null

var _phase: float = 0.0
var _speed_blend: float = 0.0
var _carry_blend: float = 0.0
var _air_blend: float = 0.0
var _tumble_blend: float = 0.0
var _lean: Vector2 = Vector2.ZERO
var _squash: float = 0.0
var _prev_velocity: Vector3 = Vector3.ZERO
var _was_airborne: bool = false
var _blink_timer: float = 2.5
var _blink_amount: float = 0.0
var _time: float = 0.0
var _last_step_sign: float = 1.0


func _ready() -> void:
	_build_rig()


func set_uniform_color(color: Color) -> void:
	uniform_color = color


## Called every frame by the owning PlayerController (host and clients).
## `world_velocity` is the body velocity; `facing_yaw` is the parent visual yaw.
func update_animation(
	delta: float,
	world_velocity: Vector3,
	on_floor: bool,
	carrying: bool,
	strain_ratio: float,
	sprinting: bool,
	stunned: bool
) -> void:
	if not _built or delta <= 0.0:
		return
	_time += delta

	var horiz: Vector3 = Vector3(world_velocity.x, 0.0, world_velocity.z)
	var speed: float = horiz.length()
	var accel: Vector3 = (world_velocity - _prev_velocity) / delta
	_prev_velocity = world_velocity

	# Landing squash (stronger for harder landings) + dust puff
	var airborne: bool = not on_floor
	if _was_airborne and not airborne:
		var impact: float = clampf(-_prev_velocity.y, 0.0, 12.0)
		_squash = maxf(_squash, clampf(0.12 + impact / 22.0, 0.0, 0.42))
		_emit_dust(10 + int(impact * 2.0))
	_was_airborne = airborne

	var blend_t: float = clampf(pose_blend_speed * delta, 0.0, 1.0)
	_speed_blend = lerpf(_speed_blend, clampf(speed / 7.0, 0.0, 1.0), blend_t)
	_carry_blend = lerpf(_carry_blend, 1.0 if carrying else 0.0, blend_t)
	_air_blend = lerpf(_air_blend, 1.0 if airborne and not stunned else 0.0, blend_t)
	_tumble_blend = lerpf(_tumble_blend, 1.0 if stunned else 0.0, clampf(delta * 6.0, 0.0, 1.0))

	# Walk / run cycle phase advances with distance travelled
	if on_floor and speed > 0.15:
		_phase = wrapf(_phase + (speed / maxf(stride_length, 0.2)) * TAU * 0.5 * delta, 0.0, TAU)
		var step_sign: float = signf(sin(_phase))
		if step_sign != _last_step_sign:
			_last_step_sign = step_sign
			if sprinting and speed > 5.5:
				_emit_dust(4)
	elif speed <= 0.15:
		_phase = lerpf(_phase, 0.0 if _phase < PI else TAU, clampf(delta * 6.0, 0.0, 1.0))

	var swing: float = sin(_phase)
	var gait_amp: float = clampf(speed / 5.0, 0.0, 1.25)
	var leg_amp: float = deg_to_rad(max_leg_swing_degrees) * gait_amp * (0.55 if carrying else 1.0)
	var arm_amp: float = deg_to_rad(max_arm_swing_degrees) * gait_amp

	# Local-space acceleration drives body lean (forward when speeding up, sideways in turns)
	var parent_basis: Basis = get_parent_node_3d().global_basis if get_parent_node_3d() != null else Basis.IDENTITY
	var local_accel: Vector3 = parent_basis.inverse() * Vector3(accel.x, 0.0, accel.z)
	var lean_target: Vector2 = Vector2(
		clampf(local_accel.z * 0.012, -0.5, 0.5),
		clampf(-local_accel.x * 0.010, -0.4, 0.4)
	)
	if sprinting and speed > 5.5:
		lean_target.x -= 0.12
	if carrying:
		lean_target.x += 0.06 + strain_ratio * 0.05
	var max_lean: float = deg_to_rad(max_lean_degrees)
	_lean = _lean.lerp(lean_target.clamp(Vector2(-max_lean, -max_lean), Vector2(max_lean, max_lean)), clampf(delta * 7.0, 0.0, 1.0))

	# --- Legs ---
	var leg_l: float = swing * leg_amp
	var leg_r: float = -swing * leg_amp
	var knee_l: float = -maxf(0.0, -cos(_phase)) * leg_amp * 1.4
	var knee_r: float = -maxf(0.0, cos(_phase)) * leg_amp * 1.4
	# Air pose: tuck legs
	leg_l = lerpf(leg_l, deg_to_rad(28.0), _air_blend)
	leg_r = lerpf(leg_r, deg_to_rad(-8.0), _air_blend)
	knee_l = lerpf(knee_l, deg_to_rad(-55.0), _air_blend)
	knee_r = lerpf(knee_r, deg_to_rad(-25.0), _air_blend)
	_hip_l.rotation = Vector3(leg_l, 0.0, 0.0)
	_hip_r.rotation = Vector3(leg_r, 0.0, 0.0)
	_knee_l.rotation = Vector3(knee_l, 0.0, 0.0)
	_knee_r.rotation = Vector3(knee_r, 0.0, 0.0)

	# --- Arms ---
	var idle_sway: float = sin(_time * 1.7) * 0.04
	var arm_l_x: float = -swing * arm_amp + idle_sway
	var arm_r_x: float = swing * arm_amp - idle_sway
	var arm_l_z: float = -0.08
	var arm_r_z: float = 0.08
	var elbow_l: float = deg_to_rad(12.0) + maxf(0.0, -swing) * arm_amp * 0.6
	var elbow_r: float = deg_to_rad(12.0) + maxf(0.0, swing) * arm_amp * 0.6

	# Carry pose: both arms reach forward/up to hold the handle, elbows bent
	var strain_shake: float = (sin(_time * 47.0) * 0.5 + sin(_time * 31.0) * 0.5) * clampf(strain_ratio - 0.35, 0.0, 1.0) * 0.08
	arm_l_x = lerpf(arm_l_x, deg_to_rad(68.0) + strain_shake, _carry_blend)
	arm_r_x = lerpf(arm_r_x, deg_to_rad(68.0) - strain_shake, _carry_blend)
	arm_l_z = lerpf(arm_l_z, deg_to_rad(-6.0), _carry_blend)
	arm_r_z = lerpf(arm_r_z, deg_to_rad(6.0), _carry_blend)
	elbow_l = lerpf(elbow_l, deg_to_rad(28.0), _carry_blend)
	elbow_r = lerpf(elbow_r, deg_to_rad(28.0), _carry_blend)

	# Air pose: arms flail up and out
	var flail: float = sin(_time * 14.0) * 0.25
	arm_l_x = lerpf(arm_l_x, deg_to_rad(40.0) + flail, _air_blend * (1.0 - _carry_blend))
	arm_r_x = lerpf(arm_r_x, deg_to_rad(40.0) - flail, _air_blend * (1.0 - _carry_blend))
	arm_l_z = lerpf(arm_l_z, deg_to_rad(-70.0), _air_blend * (1.0 - _carry_blend))
	arm_r_z = lerpf(arm_r_z, deg_to_rad(70.0), _air_blend * (1.0 - _carry_blend))

	_shoulder_l.rotation = Vector3(arm_l_x, 0.0, arm_l_z)
	_shoulder_r.rotation = Vector3(arm_r_x, 0.0, arm_r_z)
	_elbow_l.rotation = Vector3(elbow_l, 0.0, 0.0)
	_elbow_r.rotation = Vector3(elbow_r, 0.0, 0.0)

	# --- Torso, head, bob, breathing ---
	var bob: float = absf(cos(_phase)) * run_bob_height * gait_amp if on_floor else 0.0
	var breathe: float = sin(_time * 2.2) * 0.012 * (1.0 - _speed_blend)
	_squash = move_toward(_squash, 0.0, delta * 1.8)
	var squash_y: float = 1.0 - _squash * 0.55
	var squash_xz: float = 1.0 + _squash * 0.3

	_body_pivot.position = Vector3(0.0, HIP_HEIGHT - bob * 0.5 - _squash * 0.25, 0.0)
	_body_pivot.scale = Vector3(squash_xz, squash_y, squash_xz)
	_body_pivot.rotation = Vector3(-_lean.x, 0.0, _lean.y)

	_torso_pivot.rotation = Vector3(
		-_lean.x * 0.5 + strain_shake * 0.5,
		swing * 0.12 * gait_amp,
		strain_shake * 0.6
	)
	_torso_pivot.scale = Vector3(1.0 + breathe, 1.0 + breathe * 0.6, 1.0 + breathe)

	var head_look: float = sin(_time * 0.6) * 0.18 * (1.0 - _speed_blend) * (1.0 - _carry_blend)
	_head_pivot.rotation = Vector3(_lean.x * 0.6 - _carry_blend * 0.12, head_look, 0.0)

	# Knockback tumble: spin the whole rig around its local X axis
	if _tumble_blend > 0.01:
		rotation = Vector3(sin(_time * 9.0) * 0.6 * _tumble_blend, 0.0, cos(_time * 7.0) * 0.4 * _tumble_blend)
	elif rotation != Vector3.ZERO:
		rotation = rotation.lerp(Vector3.ZERO, clampf(delta * 8.0, 0.0, 1.0))

	_update_blink(delta)


func _update_blink(delta: float) -> void:
	_blink_timer -= delta
	if _blink_timer <= 0.0:
		_blink_amount = 1.0
		_blink_timer = randf_range(2.2, 5.0)
	_blink_amount = move_toward(_blink_amount, 0.0, delta * 9.0)
	var eye_scale_y: float = lerpf(1.0, 0.1, _blink_amount)
	if _eye_l != null:
		_eye_l.scale = Vector3(1.0, eye_scale_y, 1.0)
	if _eye_r != null:
		_eye_r.scale = Vector3(1.0, eye_scale_y, 1.0)


func _emit_dust(amount: int) -> void:
	if _dust == null or Engine.is_editor_hint():
		return
	_dust.amount = clampi(amount, 2, 32)
	_dust.restart()


# ---------------------------------------------------------------------------
# Rig construction (character faces -Z)
# ---------------------------------------------------------------------------

func _build_rig() -> void:
	if _built:
		return
	for child: Node in get_children():
		child.queue_free()

	_uniform_mat = _mat(uniform_color, 0.7)
	var skin_mat: StandardMaterial3D = _mat(skin_color, 0.65)
	var pants_mat: StandardMaterial3D = _mat(pants_color, 0.8)
	var cap_mat: StandardMaterial3D = _mat(cap_color, 0.6)
	var boot_mat: StandardMaterial3D = _mat(Color(0.24, 0.17, 0.12), 0.85)
	var belt_mat: StandardMaterial3D = _mat(Color(0.14, 0.12, 0.1), 0.7)
	var white_mat: StandardMaterial3D = _mat(Color(0.97, 0.97, 0.95), 0.4)
	var dark_mat: StandardMaterial3D = _mat(Color(0.08, 0.08, 0.1), 0.3)
	var badge_mat: StandardMaterial3D = _mat(Color(1.0, 0.86, 0.2), 0.35)
	var pack_mat: StandardMaterial3D = _mat(Color(0.3, 0.33, 0.38), 0.75)
	var glove_mat: StandardMaterial3D = _mat(Color(0.92, 0.82, 0.3), 0.7)

	_body_pivot = _pivot(self, "BodyPivot", Vector3(0.0, HIP_HEIGHT, 0.0))

	# Pelvis + belt
	_box(_body_pivot, "Pelvis", Vector3(0.0, 0.02, 0.0), Vector3(0.42, 0.2, 0.26), pants_mat)
	_box(_body_pivot, "Belt", Vector3(0.0, 0.12, 0.0), Vector3(0.44, 0.06, 0.28), belt_mat)
	_box(_body_pivot, "BeltBuckle", Vector3(0.0, 0.12, -0.145), Vector3(0.09, 0.06, 0.02), badge_mat)

	# Torso (uniform shirt with chest pocket, logo badge, collar)
	_torso_pivot = _pivot(_body_pivot, "TorsoPivot", Vector3(0.0, 0.14, 0.0))
	_box(_torso_pivot, "Chest", Vector3(0.0, 0.27, 0.0), Vector3(0.5, 0.52, 0.3), _uniform_mat)
	_box(_torso_pivot, "Collar", Vector3(0.0, 0.53, -0.02), Vector3(0.3, 0.06, 0.26), white_mat)
	_box(_torso_pivot, "LogoBadge", Vector3(-0.12, 0.36, -0.155), Vector3(0.11, 0.11, 0.015), badge_mat)
	_box(_torso_pivot, "Pocket", Vector3(0.12, 0.33, -0.155), Vector3(0.12, 0.1, 0.012), white_mat)
	_box(_torso_pivot, "Backpack", Vector3(0.0, 0.28, 0.21), Vector3(0.4, 0.42, 0.14), pack_mat)
	_box(_torso_pivot, "BackpackFlap", Vector3(0.0, 0.44, 0.215), Vector3(0.42, 0.1, 0.16), _uniform_mat)

	# Head (big cartoon head) with face, cap and brim
	_head_pivot = _pivot(_torso_pivot, "HeadPivot", Vector3(0.0, 0.58, 0.0))
	_box(_head_pivot, "Neck", Vector3(0.0, 0.03, 0.0), Vector3(0.13, 0.08, 0.13), skin_mat)
	_sphere(_head_pivot, "Head", Vector3(0.0, 0.2, 0.0), 0.2, skin_mat)
	_sphere(_head_pivot, "Nose", Vector3(0.0, 0.18, -0.2), 0.045, skin_mat)
	_sphere(_head_pivot, "EarL", Vector3(-0.2, 0.19, 0.0), 0.05, skin_mat)
	_sphere(_head_pivot, "EarR", Vector3(0.2, 0.19, 0.0), 0.05, skin_mat)
	_eye_l = _sphere(_head_pivot, "EyeL", Vector3(-0.075, 0.24, -0.172), 0.032, dark_mat)
	_eye_r = _sphere(_head_pivot, "EyeR", Vector3(0.075, 0.24, -0.172), 0.032, dark_mat)
	_box(_head_pivot, "BrowL", Vector3(-0.075, 0.295, -0.18), Vector3(0.07, 0.016, 0.02), dark_mat)
	_box(_head_pivot, "BrowR", Vector3(0.075, 0.295, -0.18), Vector3(0.07, 0.016, 0.02), dark_mat)
	_box(_head_pivot, "Mouth", Vector3(0.0, 0.11, -0.185), Vector3(0.08, 0.014, 0.02), dark_mat)
	_cylinder(_head_pivot, "CapCrown", Vector3(0.0, 0.33, 0.0), 0.205, 0.215, 0.13, cap_mat)
	_box(_head_pivot, "CapBrim", Vector3(0.0, 0.29, -0.22), Vector3(0.3, 0.025, 0.18), cap_mat)
	_box(_head_pivot, "CapLogo", Vector3(0.0, 0.34, -0.2), Vector3(0.09, 0.07, 0.012), badge_mat)
	_sphere(_head_pivot, "CapButton", Vector3(0.0, 0.4, 0.0), 0.03, _uniform_mat)

	# Arms (shoulder pivot -> upper arm -> elbow pivot -> forearm -> glove)
	_shoulder_l = _pivot(_torso_pivot, "ShoulderL", Vector3(-0.32, 0.47, 0.0))
	_shoulder_r = _pivot(_torso_pivot, "ShoulderR", Vector3(0.32, 0.47, 0.0))
	for side: int in [-1, 1]:
		var shoulder: Node3D = _shoulder_l if side < 0 else _shoulder_r
		_sphere(shoulder, "ShoulderCap", Vector3.ZERO, 0.085, _uniform_mat)
		_cylinder(shoulder, "UpperArm", Vector3(0.0, -0.15, 0.0), 0.07, 0.065, 0.28, _uniform_mat)
		var elbow: Node3D = _pivot(shoulder, "Elbow", Vector3(0.0, -0.29, 0.0))
		_cylinder(elbow, "Forearm", Vector3(0.0, -0.13, 0.0), 0.06, 0.055, 0.26, skin_mat)
		_sphere(elbow, "Glove", Vector3(0.0, -0.29, 0.0), 0.07, glove_mat)
		if side < 0:
			_elbow_l = elbow
		else:
			_elbow_r = elbow

	# Legs (hip pivot -> thigh -> knee pivot -> shin -> boot)
	_hip_l = _pivot(_body_pivot, "HipL", Vector3(-0.12, -0.02, 0.0))
	_hip_r = _pivot(_body_pivot, "HipR", Vector3(0.12, -0.02, 0.0))
	for side_l: int in [-1, 1]:
		var hip: Node3D = _hip_l if side_l < 0 else _hip_r
		_cylinder(hip, "Thigh", Vector3(0.0, -0.2, 0.0), 0.095, 0.085, 0.4, pants_mat)
		var knee: Node3D = _pivot(hip, "Knee", Vector3(0.0, -0.41, 0.0))
		_cylinder(knee, "Shin", Vector3(0.0, -0.19, 0.0), 0.08, 0.072, 0.38, pants_mat)
		_box(knee, "Boot", Vector3(0.0, -0.43, -0.05), Vector3(0.15, 0.12, 0.27), boot_mat)
		_box(knee, "BootSole", Vector3(0.0, -0.485, -0.05), Vector3(0.16, 0.03, 0.29), dark_mat)
		if side_l < 0:
			_knee_l = knee
		else:
			_knee_r = knee

	# Dust puff emitter at the feet
	_dust = CPUParticles3D.new()
	_dust.name = "DustPuff"
	_dust.emitting = false
	_dust.one_shot = true
	_dust.amount = 8
	_dust.lifetime = 0.55
	_dust.explosiveness = 0.9
	_dust.position = Vector3(0.0, 0.05, 0.0)
	_dust.direction = Vector3(0.0, 1.0, 0.0)
	_dust.spread = 80.0
	_dust.initial_velocity_min = 0.6
	_dust.initial_velocity_max = 1.6
	_dust.gravity = Vector3(0.0, -1.5, 0.0)
	_dust.scale_amount_min = 0.6
	_dust.scale_amount_max = 1.2
	var dust_mesh: SphereMesh = SphereMesh.new()
	dust_mesh.radius = 0.07
	dust_mesh.height = 0.14
	dust_mesh.radial_segments = 6
	dust_mesh.rings = 3
	var dust_mat: StandardMaterial3D = _mat(Color(0.86, 0.82, 0.74, 0.7), 1.0)
	dust_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dust_mesh.material = dust_mat
	_dust.mesh = dust_mesh
	add_child(_dust)

	_built = true


func _mat(color: Color, roughness: float) -> StandardMaterial3D:
	var m: StandardMaterial3D = StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	return m


func _pivot(parent: Node3D, node_name: String, pos: Vector3) -> Node3D:
	var n: Node3D = Node3D.new()
	n.name = node_name
	n.position = pos
	parent.add_child(n)
	return n


func _box(parent: Node3D, node_name: String, pos: Vector3, size: Vector3, material: Material) -> MeshInstance3D:
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.name = node_name
	mi.position = pos
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = size
	mesh.material = material
	mi.mesh = mesh
	parent.add_child(mi)
	return mi


func _sphere(parent: Node3D, node_name: String, pos: Vector3, radius: float, material: Material) -> MeshInstance3D:
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.name = node_name
	mi.position = pos
	var mesh: SphereMesh = SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 12
	mesh.rings = 6
	mesh.material = material
	mi.mesh = mesh
	parent.add_child(mi)
	return mi


func _cylinder(
	parent: Node3D,
	node_name: String,
	pos: Vector3,
	top_radius: float,
	bottom_radius: float,
	height: float,
	material: Material
) -> MeshInstance3D:
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.name = node_name
	mi.position = pos
	var mesh: CylinderMesh = CylinderMesh.new()
	mesh.top_radius = top_radius
	mesh.bottom_radius = bottom_radius
	mesh.height = height
	mesh.radial_segments = 10
	mesh.material = material
	mi.mesh = mesh
	parent.add_child(mi)
	return mi
