@tool
class_name TownEnvironmentBuilder
extends Node3D

@export var rebuild_town: bool = false:
	set(value):
		if value:
			_build_town()

var _mats: Dictionary = {}
var _physics_props: Array[Dictionary] = []
var _patrol_vans: Array[Dictionary] = []


func _ready() -> void:
	_build_town()


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint() or _patrol_vans.is_empty():
		return
	for van_rec: Dictionary in _patrol_vans:
		var body: AnimatableBody3D = van_rec.get("body") as AnimatableBody3D
		if body == null or not is_instance_valid(body):
			continue
		var p_start: Vector3 = van_rec.get("start", Vector3.ZERO)
		var p_end: Vector3 = van_rec.get("end", Vector3.ZERO)
		var spd: float = float(van_rec.get("speed", 5.5))
		var t_val: float = float(van_rec.get("t", 0.0))
		var dir_sign: float = float(van_rec.get("dir", 1.0))
		var seg_len: float = maxf(p_start.distance_to(p_end), 1.0)
		t_val += (spd / seg_len) * dir_sign * delta
		if t_val >= 1.0:
			t_val = 1.0
			dir_sign = -1.0
		elif t_val <= 0.0:
			t_val = 0.0
			dir_sign = 1.0
		van_rec["t"] = t_val
		van_rec["dir"] = dir_sign
		body.position = p_start.lerp(p_end, t_val)
		var travel_dir: Vector3 = (p_end - p_start).normalized() * dir_sign
		if travel_dir.length_squared() > 0.001:
			body.rotation.y = atan2(-travel_dir.x, -travel_dir.z)


func reset_dynamic_props() -> void:
	for rec: Dictionary in _physics_props:
		var rb: RigidBody3D = rec.get("body") as RigidBody3D
		if rb != null and is_instance_valid(rb):
			rb.linear_velocity = Vector3.ZERO
			rb.angular_velocity = Vector3.ZERO
			rb.transform = rec.get("spawn_tf", Transform3D.IDENTITY)


func _init_materials() -> void:
	if not _mats.is_empty():
		return
	_mats["asphalt"] = _make_mat(Color(0.21, 0.23, 0.26), 0.9)
	_mats["asphalt_dark"] = _make_mat(Color(0.16, 0.18, 0.20), 0.92)
	_mats["sidewalk"] = _make_mat(Color(0.76, 0.75, 0.72), 0.88)
	_mats["plaza"] = _make_mat(Color(0.68, 0.65, 0.60), 0.86)
	_mats["lane_white"] = _make_mat(Color(0.95, 0.95, 0.92), 0.7)
	_mats["lane_yellow"] = _make_mat(Color(0.96, 0.78, 0.16), 0.65)
	_mats["hazard_orange"] = _make_mat(Color(0.95, 0.42, 0.14), 0.65)
	_mats["water"] = _make_mat(Color(0.18, 0.58, 0.86), 0.2)
	_mats["river_bank"] = _make_mat(Color(0.52, 0.48, 0.42), 0.9)
	_mats["bridge_deck"] = _make_mat(Color(0.44, 0.44, 0.46), 0.85)
	_mats["bridge_red"] = _make_mat(Color(0.82, 0.24, 0.20), 0.55)
	_mats["wood_brown"] = _make_mat(Color(0.46, 0.31, 0.18), 0.85)
	_mats["fence_white"] = _make_mat(Color(0.93, 0.93, 0.90), 0.8)
	_mats["stone_wall"] = _make_mat(Color(0.55, 0.54, 0.52), 0.9)
	_mats["cliff_rock"] = _make_mat(Color(0.44, 0.42, 0.39), 0.95)
	_mats["hill_grass"] = _make_mat(Color(0.33, 0.58, 0.29), 0.95)
	_mats["foliage_light"] = _make_mat(Color(0.28, 0.65, 0.30), 0.85)
	_mats["foliage_dark"] = _make_mat(Color(0.18, 0.48, 0.23), 0.88)
	_mats["roof_red"] = _make_mat(Color(0.76, 0.27, 0.23), 0.75)
	_mats["roof_slate"] = _make_mat(Color(0.30, 0.35, 0.42), 0.75)
	_mats["roof_brown"] = _make_mat(Color(0.45, 0.29, 0.20), 0.78)
	_mats["roof_teal"] = _make_mat(Color(0.20, 0.52, 0.54), 0.72)
	_mats["wall_bakery"] = _make_mat(Color(0.94, 0.69, 0.55), 0.8)
	_mats["wall_blue"] = _make_mat(Color(0.54, 0.76, 0.92), 0.8)
	_mats["wall_yellow"] = _make_mat(Color(0.96, 0.85, 0.46), 0.8)
	_mats["wall_mint"] = _make_mat(Color(0.62, 0.86, 0.73), 0.8)
	_mats["wall_coral"] = _make_mat(Color(0.94, 0.62, 0.58), 0.8)
	_mats["wall_cream"] = _make_mat(Color(0.94, 0.90, 0.80), 0.8)
	_mats["wall_brick"] = _make_mat(Color(0.76, 0.36, 0.26), 0.82)
	_mats["wall_lavender"] = _make_mat(Color(0.78, 0.73, 0.90), 0.8)
	_mats["window_glass"] = _make_mat(Color(0.62, 0.84, 0.96), 0.2, 0.1, true, Color(0.18, 0.30, 0.42))
	_mats["lamp_metal"] = _make_mat(Color(0.22, 0.25, 0.28), 0.5, 0.4)
	_mats["lamp_glow"] = _make_mat(Color(1.0, 0.94, 0.72), 0.2, 0.0, true, Color(0.95, 0.82, 0.45))


func _make_mat(
	albedo: Color,
	rough: float = 0.8,
	metal: float = 0.0,
	emissive: bool = false,
	emit_col: Color = Color.BLACK
) -> StandardMaterial3D:
	var m: StandardMaterial3D = StandardMaterial3D.new()
	m.albedo_color = albedo
	m.roughness = rough
	m.metallic = metal
	if emissive:
		m.emission_enabled = true
		m.emission = emit_col
	return m


func _build_town() -> void:
	_init_materials()

	var existing: Node = get_node_or_null("GeneratedTown")
	if existing != null:
		remove_child(existing)
		existing.queue_free()

	_physics_props.clear()
	_patrol_vans.clear()

	var root_node: Node3D = Node3D.new()
	root_node.name = "GeneratedTown"
	add_child(root_node)

	_build_road_network(root_node)
	_build_river_and_bridge(root_node)
	_build_commerce_boulevard_district(root_node)
	_build_town_square_and_park(root_node)
	_build_maple_street_neighborhood(root_node)
	_build_streetlights_and_props(root_node)
	_build_dynamic_traffic_and_props(root_node)
	_build_map_perimeter_and_boundaries(root_node)


func _build_road_network(parent: Node3D) -> void:
	var roads: Node3D = Node3D.new()
	roads.name = "RoadNetworkVisuals"
	parent.add_child(roads)

	# 1. Loading Dock & Industrial Yard Apron (x = 0, z = 6..18)
	_add_visual_box(roads, Vector3(0.0, 0.01, 12.0), Vector3(16.0, 0.02, 12.0), "asphalt")
	_add_visual_box(roads, Vector3(-2.3, 0.02, 11.5), Vector3(0.18, 0.02, 6.8), "lane_yellow")
	_add_visual_box(roads, Vector3(2.3, 0.02, 11.5), Vector3(0.18, 0.02, 6.8), "lane_yellow")

	# 2. Commerce Boulevard (North-South Main Road: x = 0, z = 18..106, length = 88m, width = 10m)
	_add_visual_box(roads, Vector3(0.0, 0.01, 62.0), Vector3(10.0, 0.02, 88.0), "asphalt")
	_add_visual_box(roads, Vector3(-6.2, 0.015, 58.0), Vector3(2.4, 0.03, 80.0), "sidewalk")
	_add_visual_box(roads, Vector3(6.2, 0.015, 58.0), Vector3(2.4, 0.03, 80.0), "sidewalk")

	# Dashed centerline down Commerce Blvd
	for z_pos: int in range(20, 94, 6):
		_add_visual_box(roads, Vector3(0.0, 0.02, float(z_pos)), Vector3(0.22, 0.02, 3.0), "lane_white")

	# Crosswalks on Commerce Blvd (at z = 24 and z = 90)
	for cw_z: float in [24.0, 90.0]:
		for x_off: int in range(-4, 5, 1):
			_add_visual_box(roads, Vector3(float(x_off) * 1.0, 0.022, cw_z), Vector3(0.45, 0.02, 2.2), "lane_white")

	# 3. Central Town Square Plaza (x = 0, z = 106, size = 28m x 28m)
	_add_visual_box(roads, Vector3(0.0, 0.01, 106.0), Vector3(26.0, 0.02, 26.0), "asphalt")
	_add_visual_box(roads, Vector3(0.0, 0.008, 106.0), Vector3(31.0, 0.016, 31.0), "plaza")

	# West & South stub roads leading from Town Square to the County Line barricades
	_add_visual_box(roads, Vector3(-25.0, 0.01, 106.0), Vector3(24.0, 0.02, 9.0), "asphalt")
	_add_visual_box(roads, Vector3(0.0, 0.01, 128.0), Vector3(9.5, 0.02, 18.0), "asphalt")

	# 4. Riverview Avenue (East-West Avenue from Town Square x = 13 to Maple St x = 86 at z = 106)
	_add_visual_box(roads, Vector3(26.0, 0.01, 106.0), Vector3(26.0, 0.02, 10.0), "asphalt")
	_add_visual_box(roads, Vector3(26.0, 0.015, 99.8), Vector3(24.0, 0.03, 2.4), "sidewalk")
	_add_visual_box(roads, Vector3(26.0, 0.015, 112.2), Vector3(24.0, 0.03, 2.4), "sidewalk")
	for x_pos: int in range(16, 37, 6):
		_add_visual_box(roads, Vector3(float(x_pos), 0.02, 106.0), Vector3(3.0, 0.02, 0.22), "lane_white")

	# East of Bridge to Maple St Intersection (x = 61..92, z = 106)
	_add_visual_box(roads, Vector3(76.5, 0.01, 106.0), Vector3(31.0, 0.02, 10.0), "asphalt")
	_add_visual_box(roads, Vector3(72.0, 0.015, 99.8), Vector3(20.0, 0.03, 2.4), "sidewalk")
	_add_visual_box(roads, Vector3(76.5, 0.015, 112.2), Vector3(31.0, 0.03, 2.4), "sidewalk")
	for x_pos: int in range(64, 83, 6):
		_add_visual_box(roads, Vector3(float(x_pos), 0.02, 106.0), Vector3(3.0, 0.02, 0.22), "lane_white")

	# 5. Maple Street (Residential Street heading North from z = 106 to z = 44 at x = 86)
	_add_visual_box(roads, Vector3(86.0, 0.01, 72.0), Vector3(9.5, 0.02, 68.0), "asphalt")
	_add_visual_box(roads, Vector3(80.1, 0.015, 72.0), Vector3(2.2, 0.03, 60.0), "sidewalk")
	_add_visual_box(roads, Vector3(91.9, 0.015, 76.0), Vector3(2.2, 0.03, 50.0), "sidewalk")
	for z_pos: int in range(52, 100, 6):
		_add_visual_box(roads, Vector3(86.0, 0.02, float(z_pos)), Vector3(0.22, 0.02, 2.8), "lane_white")

	# 6. Maple Street Cul-de-Sac & 20 Maple St Driveway Apron (x = 86..98, z = 36..52)
	_add_visual_box(roads, Vector3(88.0, 0.01, 44.0), Vector3(16.0, 0.02, 15.0), "asphalt")
	_add_visual_box(roads, Vector3(95.5, 0.012, 44.0), Vector3(6.0, 0.024, 11.0), "sidewalk")


func _build_river_and_bridge(parent: Node3D) -> void:
	var river_node: Node3D = Node3D.new()
	river_node.name = "MapleCreekRiverAndBridge"
	parent.add_child(river_node)

	# Scenic North-South River ("Maple Creek") at x = 50, running z = -60 to z = +180
	_add_visual_box(river_node, Vector3(50.0, 0.006, 60.0), Vector3(11.0, 0.012, 240.0), "water")
	_add_visual_box(river_node, Vector3(44.0, 0.01, 60.0), Vector3(1.4, 0.02, 240.0), "river_bank")
	_add_visual_box(river_node, Vector3(56.0, 0.01, 60.0), Vector3(1.4, 0.02, 240.0), "river_bank")

	# River guard walls on North and South sides of the bridge so vehicles can't drive into the river
	_add_static_box(river_node, Vector3(44.0, 0.6, 46.0), Vector3(0.8, 1.2, 108.0), "stone_wall")
	_add_static_box(river_node, Vector3(44.0, 0.6, 146.0), Vector3(0.8, 1.2, 68.0), "stone_wall")
	_add_static_box(river_node, Vector3(56.0, 0.6, 46.0), Vector3(0.8, 1.2, 108.0), "stone_wall")
	_add_static_box(river_node, Vector3(56.0, 0.6, 146.0), Vector3(0.8, 1.2, 68.0), "stone_wall")

	# Maple Creek Bridge Overpass at x = 38..62, z = 106 (smooth 7.5° ramps + flat crown deck)
	# West Approach Ramp (tilted +7.5 deg around Z so bottom edge is sunken below y=0 -> zero bump)
	_add_static_box(
		river_node,
		Vector3(41.5, 0.28, 106.0),
		Vector3(7.4, 0.35, 9.6),
		"bridge_deck",
		Vector3(0.0, 0.0, 7.5)
	)
	# Center Bridge Deck
	_add_static_box(
		river_node,
		Vector3(50.0, 0.76, 106.0),
		Vector3(10.2, 0.35, 9.6),
		"bridge_deck"
	)
	# East Descent Ramp (tilted -7.5 deg around Z)
	_add_static_box(
		river_node,
		Vector3(58.5, 0.28, 106.0),
		Vector3(7.4, 0.35, 9.6),
		"bridge_deck",
		Vector3(0.0, 0.0, -7.5)
	)

	# Red Bridge Side Guardrails & Overhead Steel Truss Arches (high clearance y = 5.6m)
	_add_static_box(river_node, Vector3(50.0, 1.4, 101.0), Vector3(22.0, 1.2, 0.45), "bridge_red")
	_add_static_box(river_node, Vector3(50.0, 1.4, 111.0), Vector3(22.0, 1.2, 0.45), "bridge_red")

	for arch_x: float in [45.0, 50.0, 55.0]:
		_add_visual_box(river_node, Vector3(arch_x, 3.6, 101.0), Vector3(0.45, 4.2, 0.45), "bridge_red")
		_add_visual_box(river_node, Vector3(arch_x, 3.6, 111.0), Vector3(0.45, 4.2, 0.45), "bridge_red")
		_add_visual_box(river_node, Vector3(arch_x, 5.6, 106.0), Vector3(0.45, 0.45, 10.4), "bridge_red")


func _build_commerce_boulevard_district(parent: Node3D) -> void:
	var district: Node3D = Node3D.new()
	district.name = "CommerceBoulevardDistrict"
	parent.add_child(district)

	# Warehouse Yard Fences (leaving wide front exit at z = 16)
	_add_static_box(district, Vector3(-12.0, 0.9, 4.0), Vector3(0.35, 1.8, 24.0), "stone_wall")
	_add_static_box(district, Vector3(12.0, 0.9, 4.0), Vector3(0.35, 1.8, 24.0), "stone_wall")

	# WEST SIDE BUILDINGS along Commerce Blvd (facing East, +X)
	# 1. Luigi's Bakery & Cafe (z = 26)
	_build_detailed_building(district, Vector3(-13.5, 0.0, 26.0), Vector3(9.0, 5.5, 11.0), "wall_bakery", "roof_red", 1, true)
	# 2. Town Hardware & Paint Store (z = 44)
	_build_detailed_building(district, Vector3(-13.5, 0.0, 44.0), Vector3(9.5, 6.0, 12.0), "wall_blue", "roof_slate", 1, true)
	# 3. SunnySide Gas Station & Canopy (z = 64)
	_build_detailed_building(district, Vector3(-16.0, 0.0, 64.0), Vector3(7.5, 4.4, 10.0), "wall_cream", "roof_red", 1, false)
	_add_visual_box(district, Vector3(-10.5, 0.015, 64.0), Vector3(7.0, 0.03, 14.0), "plaza")
	_add_visual_box(district, Vector3(-10.5, 4.2, 64.0), Vector3(6.2, 0.4, 11.0), "wall_yellow")
	_add_static_box(district, Vector3(-10.5, 2.1, 60.5), Vector3(0.45, 4.2, 0.45), "bridge_red")
	_add_static_box(district, Vector3(-10.5, 2.1, 67.5), Vector3(0.45, 4.2, 0.45), "bridge_red")
	_add_static_box(district, Vector3(-10.5, 0.9, 64.0), Vector3(0.9, 1.8, 2.2), "bridge_red") # Fuel pump island
	# 4. Town Fire Station (z = 84)
	_build_detailed_building(district, Vector3(-14.0, 0.0, 84.0), Vector3(10.0, 6.8, 12.0), "wall_brick", "roof_slate", 1, false)
	_add_visual_box(district, Vector3(-16.5, 6.0, 80.0), Vector3(3.2, 12.0, 3.2), "wall_brick") # Fire hose tower

	# EAST SIDE BUILDINGS along Commerce Blvd (facing West, -X)
	# 5. Fresh Grocer Market (z = 26)
	_build_detailed_building(district, Vector3(13.5, 0.0, 26.0), Vector3(9.0, 5.2, 11.0), "wall_mint", "roof_teal", -1, true)
	# 6. Bookshop & Post Office (z = 46)
	_build_detailed_building(district, Vector3(13.5, 0.0, 46.0), Vector3(9.0, 6.4, 11.5), "wall_lavender", "roof_slate", -1, true)
	# 7. Diner 66 (z = 66)
	_build_detailed_building(district, Vector3(13.5, 0.0, 66.0), Vector3(8.5, 4.5, 12.0), "wall_coral", "roof_teal", -1, true)
	# 8. Town Hall & Clock Tower (z = 88)
	_build_detailed_building(district, Vector3(15.0, 0.0, 88.0), Vector3(11.0, 7.5, 14.0), "wall_cream", "roof_slate", -1, false)
	_add_visual_box(district, Vector3(15.0, 7.0, 88.0), Vector3(3.8, 14.0, 3.8), "wall_cream") # Clock tower
	_add_visual_box(district, Vector3(15.0, 14.6, 88.0), Vector3(4.2, 1.2, 4.2), "roof_slate")

	# DRIVING HAZARDS on Commerce Blvd
	# Speed Bump #1 (z = 28) & Speed Bump #2 (z = 82)
	_add_speed_bump(district, Vector3(0.0, -0.28, 28.0), 9.2)
	_add_speed_bump(district, Vector3(0.0, -0.28, 82.0), 9.2)

	# Roadwork S-Curve Chicane (z = 50..62)
	_add_static_box(district, Vector3(-2.3, 0.55, 51.0), Vector3(3.2, 1.1, 0.65), "hazard_orange")
	_add_visual_box(district, Vector3(-2.3, 0.85, 51.0), Vector3(3.25, 0.25, 0.7), "lane_white")
	_add_static_box(district, Vector3(2.3, 0.55, 60.0), Vector3(3.2, 1.1, 0.65), "hazard_orange")
	_add_visual_box(district, Vector3(2.3, 0.85, 60.0), Vector3(3.25, 0.25, 0.7), "lane_white")


func _build_town_square_and_park(parent: Node3D) -> void:
	var square: Node3D = Node3D.new()
	square.name = "TownSquareAndPark"
	parent.add_child(square)

	# Central Fountain Roundabout at (x = 0, z = 106)
	_add_static_cylinder(square, Vector3(0.0, 0.35, 106.0), 3.6, 0.7, "stone_wall")
	_add_visual_cylinder(square, Vector3(0.0, 0.65, 106.0), 3.1, 0.2, "water")
	_add_static_cylinder(square, Vector3(0.0, 1.2, 106.0), 0.85, 1.8, "stone_wall")
	_add_visual_cylinder(square, Vector3(0.0, 2.2, 106.0), 1.6, 0.3, "stone_wall")

	# Directional Signpost at South side of Town Square pointing EAST to 20 Maple St
	_add_directional_sign(square, Vector3(5.5, 0.0, 114.5), 0.0)
	# Directional Signpost at East side of Bridge (x = 92, z = 106) pointing NORTH to 20 Maple St
	_add_directional_sign(square, Vector3(92.5, 0.0, 106.0), 90.0)

	# Town Park North & South of Riverview Ave (x = 16..38)
	# Park Gazebo at (x = 26, z = 88)
	_add_static_cylinder(square, Vector3(26.0, 0.2, 88.0), 3.5, 0.4, "wood_brown")
	_add_visual_cylinder(square, Vector3(26.0, 3.4, 88.0), 3.8, 0.8, "roof_red")
	for angle_deg: int in [45, 135, 225, 315]:
		var rad: float = deg_to_rad(float(angle_deg))
		_add_static_box(
			square,
			Vector3(26.0 + cos(rad) * 2.6, 1.6, 88.0 + sin(rad) * 2.6),
			Vector3(0.3, 2.8, 0.3),
			"fence_white"
		)

	# Park Benches & Trees around Town Square and Riverview Ave
	var park_tree_positions: Array[Vector3] = [
		Vector3(18.0, 0.0, 94.0),
		Vector3(34.0, 0.0, 92.0),
		Vector3(22.0, 0.0, 118.0),
		Vector3(33.0, 0.0, 117.0),
		Vector3(-12.0, 0.0, 96.0),
		Vector3(-12.0, 0.0, 116.0),
		Vector3(12.0, 0.0, 116.0),
	]
	for t_pos: Vector3 in park_tree_positions:
		_add_broadleaf_tree(square, t_pos, 1.15)


func _build_maple_street_neighborhood(parent: Node3D) -> void:
	var maple: Node3D = Node3D.new()
	maple.name = "MapleStreetNeighborhood"
	parent.add_child(maple)

	# Suburban Houses along Maple Street (x = 86, z = 96..56)
	# West Side of Maple St (x = 71, facing East +X)
	# 12 Maple St (z = 90)
	_build_detailed_building(maple, Vector3(71.0, 0.0, 90.0), Vector3(8.5, 4.8, 9.5), "wall_blue", "roof_red", 1, false)
	_add_yard_fence(maple, Vector3(76.5, 0.0, 90.0), 9.5)
	# 16 Maple St (z = 70)
	_build_detailed_building(maple, Vector3(71.0, 0.0, 70.0), Vector3(8.5, 5.0, 9.5), "wall_yellow", "roof_brown", 1, false)
	_add_yard_fence(maple, Vector3(76.5, 0.0, 70.0), 9.5)
	# 19 Maple St (North-West corner of Cul-de-Sac, x = 71, z = 50)
	_build_detailed_building(maple, Vector3(71.0, 0.0, 50.0), Vector3(8.5, 4.8, 9.5), "wall_lavender", "roof_slate", 1, false)

	# East Side of Maple St (x = 101, facing West -X)
	# 14 Maple St (z = 90)
	_build_detailed_building(maple, Vector3(101.0, 0.0, 90.0), Vector3(8.5, 4.8, 9.5), "wall_coral", "roof_brown", -1, false)
	_add_yard_fence(maple, Vector3(95.5, 0.0, 90.0), 9.5)
	# 18 Maple St (z = 70, just South of the Customer House at 20 Maple St!)
	_build_detailed_building(maple, Vector3(101.0, 0.0, 70.0), Vector3(8.5, 4.8, 9.5), "wall_mint", "roof_red", -1, false)
	_add_yard_fence(maple, Vector3(95.5, 0.0, 70.0), 9.5)

	# Residential Speed Bump #3 on Maple St (z = 80) & Trash Bin Obstacle (z = 60)
	_add_speed_bump(maple, Vector3(86.0, -0.28, 80.0), 8.6)
	_add_static_box(maple, Vector3(88.6, 0.55, 61.0), Vector3(1.6, 1.1, 2.2), "hazard_orange")

	# Trees lining Maple Street and the Cul-de-Sac
	var maple_trees: Array[Vector3] = [
		Vector3(77.5, 0.0, 80.0),
		Vector3(94.5, 0.0, 80.0),
		Vector3(77.5, 0.0, 60.0),
		Vector3(94.5, 0.0, 58.0),
		Vector3(78.0, 0.0, 34.0),
		Vector3(92.0, 0.0, 32.0),
		Vector3(108.0, 0.0, 32.0),
		Vector3(108.0, 0.0, 56.0),
	]
	for mt_pos: Vector3 in maple_trees:
		_add_broadleaf_tree(maple, mt_pos, 1.0)


func _build_streetlights_and_props(parent: Node3D) -> void:
	var props: Node3D = Node3D.new()
	props.name = "StreetlightsAndTownProps"
	parent.add_child(props)

	# Streetlights along Commerce Blvd
	for z_lamp: int in [18, 36, 54, 72, 90]:
		_add_streetlight(props, Vector3(-5.5, 0.0, float(z_lamp)), 1.0)
		_add_streetlight(props, Vector3(5.5, 0.0, float(z_lamp)), -1.0)
		_add_broadleaf_tree(props, Vector3(-7.6, 0.0, float(z_lamp) + 8.0), 0.95)
		_add_broadleaf_tree(props, Vector3(7.6, 0.0, float(z_lamp) + 8.0), 0.95)

	# Streetlights along Riverview Ave & Maple St
	for x_lamp: int in [20, 34, 66, 78]:
		_add_streetlight(props, Vector3(float(x_lamp), 0.0, 100.2), 0.0)
		_add_streetlight(props, Vector3(float(x_lamp), 0.0, 111.8), 0.0)

	for z_maple: int in [96, 76, 56, 40]:
		_add_streetlight(props, Vector3(80.6, 0.0, float(z_maple)), 1.0)
		_add_streetlight(props, Vector3(91.4, 0.0, float(z_maple)), -1.0)


func _build_map_perimeter_and_boundaries(parent: Node3D) -> void:
	var perimeter: Node3D = Node3D.new()
	perimeter.name = "MapPerimeterAndHills"
	parent.add_child(perimeter)

	# 1. Out-of-Town Roadblock Barricades & Tunnel Portals where roads meet the town edge
	# West County Line Barricade (x = -36, z = 106)
	_add_roadblock_barricade(perimeter, Vector3(-34.0, 0.0, 106.0), true)
	# South County Line Barricade (x = 0, z = 135)
	_add_roadblock_barricade(perimeter, Vector3(0.0, 0.0, 134.0), false)
	# East Riverview T-End Wall (x = 93.5, z = 106)
	_add_static_box(perimeter, Vector3(95.0, 1.2, 106.0), Vector3(0.8, 2.4, 14.0), "stone_wall")
	# North Maple St Cul-de-Sac Boundary Fence (x = 88, z = 34)
	_add_static_box(perimeter, Vector3(88.0, 1.0, 34.0), Vector3(22.0, 2.0, 0.6), "stone_wall")

	# 2. Continuous Perimeter Boundary Walls (keeps vehicles & players inside the playable valley)
	# North Perimeter Wall (z = -24, x = -50..+130)
	_add_static_box(perimeter, Vector3(40.0, 3.0, -24.0), Vector3(180.0, 6.0, 2.0), "cliff_rock")
	# South Perimeter Wall (z = 142, x = -50..+130)
	_add_static_box(perimeter, Vector3(40.0, 3.0, 142.0), Vector3(180.0, 6.0, 2.0), "cliff_rock")
	# West Perimeter Wall (x = -42, z = -24..+142)
	_add_static_box(perimeter, Vector3(-42.0, 3.0, 59.0), Vector3(2.0, 6.0, 170.0), "cliff_rock")
	# East Perimeter Wall (x = 124, z = -24..+142)
	_add_static_box(perimeter, Vector3(124.0, 3.0, 59.0), Vector3(2.0, 6.0, 170.0), "cliff_rock")

	# 3. Scenic Low-Poly Valley Mountains & Rolling Hills framing all 4 horizons
	# North Mountain Ridge (z = -38)
	for i: int in range(-40, 130, 22):
		var h: float = 14.0 + float((absi(i * 7) % 12))
		_add_mountain_peak(perimeter, Vector3(float(i), 0.0, -38.0), 26.0, h)
	# South Mountain Ridge (z = 156)
	for i: int in range(-40, 130, 22):
		var h: float = 15.0 + float((absi(i * 11) % 14))
		_add_mountain_peak(perimeter, Vector3(float(i), 0.0, 156.0), 26.0, h)
	# West Mountain Ridge (x = -56)
	for z_i: int in range(-20, 150, 22):
		var h: float = 14.0 + float((absi(z_i * 5) % 12))
		_add_mountain_peak(perimeter, Vector3(-56.0, 0.0, float(z_i)), 26.0, h)
	# East Mountain Ridge (x = 138)
	for z_i: int in range(-20, 150, 22):
		var h: float = 15.0 + float((absi(z_i * 9) % 13))
		_add_mountain_peak(perimeter, Vector3(138.0, 0.0, float(z_i)), 26.0, h)

	# 4. Perimeter Pine Tree Forest Belt along the base of the hills
	for x_p: int in range(-36, 124, 14):
		_add_pine_tree(perimeter, Vector3(float(x_p), 0.0, -20.0), 1.3)
		_add_pine_tree(perimeter, Vector3(float(x_p), 0.0, 138.0), 1.3)
	for z_p: int in range(-14, 136, 14):
		_add_pine_tree(perimeter, Vector3(-38.0, 0.0, float(z_p)), 1.3)
		_add_pine_tree(perimeter, Vector3(120.0, 0.0, float(z_p)), 1.3)


func _build_detailed_building(
	parent: Node3D,
	base_pos: Vector3,
	size: Vector3,
	wall_mat_key: String,
	roof_mat_key: String,
	facing_x_sign: int,
	has_awning: bool
) -> void:
	# Main building body collider + mesh
	_add_static_box(
		parent,
		base_pos + Vector3(0.0, size.y * 0.5, 0.0),
		size,
		wall_mat_key
	)
	# Pitched / overhanging roof cap
	_add_visual_box(
		parent,
		base_pos + Vector3(0.0, size.y + 0.35, 0.0),
		Vector3(size.x + 0.8, 0.7, size.z + 0.8),
		roof_mat_key
	)
	_add_visual_box(
		parent,
		base_pos + Vector3(0.0, size.y + 0.95, 0.0),
		Vector3(size.x * 0.65, 0.6, size.z * 0.75),
		roof_mat_key
	)
	# Chimney
	_add_visual_box(
		parent,
		base_pos + Vector3(-size.x * 0.2, size.y + 1.4, -size.z * 0.25),
		Vector3(0.8, 1.4, 0.8),
		"wall_brick"
	)

	var front_x: float = base_pos.x + float(facing_x_sign) * (size.x * 0.5 + 0.06)
	# Front door & glowing windows
	_add_visual_box(
		parent,
		Vector3(front_x, 1.15, base_pos.z),
		Vector3(0.12, 2.2, 1.3),
		"wood_brown"
	)
	for z_win_off: float in [-size.z * 0.28, size.z * 0.28]:
		_add_visual_box(
			parent,
			Vector3(front_x, 1.6, base_pos.z + z_win_off),
			Vector3(0.12, 1.4, 1.8),
			"window_glass"
		)
		if size.y > 4.6:
			_add_visual_box(
				parent,
				Vector3(front_x, 3.6, base_pos.z + z_win_off),
				Vector3(0.12, 1.2, 1.6),
				"window_glass"
			)

	if has_awning:
		var awning_x: float = base_pos.x + float(facing_x_sign) * (size.x * 0.5 + 0.9)
		_add_visual_box(
			parent,
			Vector3(awning_x, 2.75, base_pos.z),
			Vector3(1.8, 0.3, size.z * 0.85),
			roof_mat_key
		)


func _add_speed_bump(parent: Node3D, pos: Vector3, width: float) -> void:
	var sb: StaticBody3D = StaticBody3D.new()
	sb.position = pos
	sb.rotation_degrees = Vector3(0.0, 0.0, 90.0)
	sb.collision_layer = 1
	sb.collision_mask = 0
	parent.add_child(sb)

	var col: CollisionShape3D = CollisionShape3D.new()
	var shape: CylinderShape3D = CylinderShape3D.new()
	shape.radius = 0.38
	shape.height = width
	col.shape = shape
	sb.add_child(col)

	var mi: MeshInstance3D = MeshInstance3D.new()
	var mesh: CylinderMesh = CylinderMesh.new()
	mesh.top_radius = 0.38
	mesh.bottom_radius = 0.38
	mesh.height = width
	mesh.radial_segments = 20
	mesh.material = _mats["lane_yellow"]
	mi.mesh = mesh
	sb.add_child(mi)


func _add_streetlight(parent: Node3D, base_pos: Vector3, arm_dir_x: float) -> void:
	_add_static_cylinder(parent, base_pos + Vector3(0.0, 2.4, 0.0), 0.12, 4.8, "lamp_metal")
	if not is_zero_approx(arm_dir_x):
		_add_visual_box(parent, base_pos + Vector3(arm_dir_x * 0.6, 4.7, 0.0), Vector3(1.3, 0.12, 0.12), "lamp_metal")
		_add_visual_box(parent, base_pos + Vector3(arm_dir_x * 1.1, 4.55, 0.0), Vector3(0.35, 0.2, 0.35), "lamp_glow")
	else:
		_add_visual_box(parent, base_pos + Vector3(0.0, 4.85, 0.0), Vector3(0.4, 0.3, 0.4), "lamp_glow")


func _add_broadleaf_tree(parent: Node3D, base_pos: Vector3, scale_factor: float = 1.0) -> void:
	_add_static_cylinder(
		parent,
		base_pos + Vector3(0.0, 1.2 * scale_factor, 0.0),
		0.32 * scale_factor,
		2.4 * scale_factor,
		"wood_brown"
	)
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.position = base_pos + Vector3(0.0, 3.3 * scale_factor, 0.0)
	var sph: SphereMesh = SphereMesh.new()
	sph.radius = 1.75 * scale_factor
	sph.height = 3.2 * scale_factor
	sph.radial_segments = 12
	sph.rings = 6
	sph.material = _mats["foliage_light"]
	mi.mesh = sph
	parent.add_child(mi)


func _add_pine_tree(parent: Node3D, base_pos: Vector3, scale_factor: float = 1.0) -> void:
	_add_static_cylinder(
		parent,
		base_pos + Vector3(0.0, 1.4 * scale_factor, 0.0),
		0.35 * scale_factor,
		2.8 * scale_factor,
		"wood_brown"
	)
	for tier: int in range(2):
		var cone_mi: MeshInstance3D = MeshInstance3D.new()
		cone_mi.position = base_pos + Vector3(0.0, (3.4 + float(tier) * 1.8) * scale_factor, 0.0)
		var cone: CylinderMesh = CylinderMesh.new()
		cone.top_radius = 0.05
		cone.bottom_radius = (2.1 - float(tier) * 0.5) * scale_factor
		cone.height = 3.2 * scale_factor
		cone.radial_segments = 10
		cone.material = _mats["foliage_dark"]
		cone_mi.mesh = cone
		parent.add_child(cone_mi)


func _add_mountain_peak(parent: Node3D, base_pos: Vector3, width: float, height: float) -> void:
	_add_visual_box(
		parent,
		base_pos + Vector3(0.0, height * 0.35, 0.0),
		Vector3(width, height * 0.7, width),
		"cliff_rock"
	)
	_add_visual_box(
		parent,
		base_pos + Vector3(0.0, height * 0.75, 0.0),
		Vector3(width * 0.72, height * 0.45, width * 0.72),
		"hill_grass"
	)


func _add_yard_fence(parent: Node3D, center_pos: Vector3, length_z: float) -> void:
	_add_static_box(
		parent,
		center_pos + Vector3(0.0, 0.5, 0.0),
		Vector3(0.2, 1.0, length_z),
		"fence_white"
	)


func _add_directional_sign(parent: Node3D, base_pos: Vector3, rot_y_deg: float) -> void:
	var sign_root: Node3D = Node3D.new()
	sign_root.position = base_pos
	sign_root.rotation_degrees = Vector3(0.0, rot_y_deg, 0.0)
	parent.add_child(sign_root)

	_add_static_cylinder(sign_root, Vector3(0.0, 1.4, 0.0), 0.12, 2.8, "lamp_metal")
	_add_visual_box(sign_root, Vector3(0.0, 2.5, 0.0), Vector3(2.4, 0.7, 0.18), "lane_yellow")
	_add_visual_box(sign_root, Vector3(0.85, 2.5, 0.0), Vector3(0.5, 0.4, 0.24), "hazard_orange")


func _add_roadblock_barricade(parent: Node3D, base_pos: Vector3, runs_along_z: bool) -> void:
	var b_size: Vector3 = Vector3(1.2, 1.4, 10.0) if runs_along_z else Vector3(10.0, 1.4, 1.2)
	_add_static_box(parent, base_pos + Vector3(0.0, 0.7, 0.0), b_size, "hazard_orange")
	var stripe_size: Vector3 = Vector3(1.25, 0.35, 9.6) if runs_along_z else Vector3(9.6, 0.35, 1.25)
	_add_visual_box(parent, base_pos + Vector3(0.0, 1.0, 0.0), stripe_size, "lane_white")


func _add_visual_box(
	parent: Node3D,
	pos: Vector3,
	size: Vector3,
	mat_key: String,
	rot_deg: Vector3 = Vector3.ZERO
) -> MeshInstance3D:
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.position = pos
	mi.rotation_degrees = rot_deg
	var bm: BoxMesh = BoxMesh.new()
	bm.size = size
	bm.material = _mats.get(mat_key, _mats["asphalt"])
	mi.mesh = bm
	parent.add_child(mi)
	return mi


func _add_visual_cylinder(
	parent: Node3D,
	pos: Vector3,
	radius: float,
	height: float,
	mat_key: String
) -> MeshInstance3D:
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.position = pos
	var cm: CylinderMesh = CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius
	cm.height = height
	cm.radial_segments = 18
	cm.material = _mats.get(mat_key, _mats["stone_wall"])
	mi.mesh = cm
	parent.add_child(mi)
	return mi


func _add_static_box(
	parent: Node3D,
	pos: Vector3,
	size: Vector3,
	mat_key: String,
	rot_deg: Vector3 = Vector3.ZERO
) -> StaticBody3D:
	var sb: StaticBody3D = StaticBody3D.new()
	sb.position = pos
	sb.rotation_degrees = rot_deg
	sb.collision_layer = 1
	sb.collision_mask = 0
	parent.add_child(sb)

	var col: CollisionShape3D = CollisionShape3D.new()
	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = size
	col.shape = shape
	sb.add_child(col)

	var mi: MeshInstance3D = MeshInstance3D.new()
	var bm: BoxMesh = BoxMesh.new()
	bm.size = size
	bm.material = _mats.get(mat_key, _mats["stone_wall"])
	mi.mesh = bm
	sb.add_child(mi)
	return sb


func _add_static_cylinder(
	parent: Node3D,
	pos: Vector3,
	radius: float,
	height: float,
	mat_key: String
) -> StaticBody3D:
	var sb: StaticBody3D = StaticBody3D.new()
	sb.position = pos
	sb.collision_layer = 1
	sb.collision_mask = 0
	parent.add_child(sb)

	var col: CollisionShape3D = CollisionShape3D.new()
	var shape: CylinderShape3D = CylinderShape3D.new()
	shape.radius = radius
	shape.height = height
	col.shape = shape
	sb.add_child(col)

	var mi: MeshInstance3D = MeshInstance3D.new()
	var cm: CylinderMesh = CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius
	cm.height = height
	cm.radial_segments = 16
	cm.material = _mats.get(mat_key, _mats["stone_wall"])
	mi.mesh = cm
	sb.add_child(mi)
	return sb


func _build_dynamic_traffic_and_props(parent: Node3D) -> void:
	var dyn_root: Node3D = Node3D.new()
	dyn_root.name = "DynamicTrafficAndProps"
	parent.add_child(dyn_root)

	# 1. Knockable Physics Traffic Cones & Barrels along Roadwork Chicane, Roundabout, and Maple St
	var cone_positions: Array[Vector3] = [
		Vector3(-3.8, 0.38, 48.0),
		Vector3(-1.0, 0.38, 49.5),
		Vector3(-0.6, 0.38, 52.5),
		Vector3(0.6, 0.38, 58.0),
		Vector3(1.2, 0.38, 61.5),
		Vector3(3.8, 0.38, 63.0),
		Vector3(-4.2, 0.38, 99.0),
		Vector3(4.2, 0.38, 99.0),
		Vector3(87.2, 0.38, 58.5),
		Vector3(87.2, 0.38, 63.5),
	]
	for cp: Vector3 in cone_positions:
		_add_physics_traffic_cone(dyn_root, cp)

	# 2. Moving Town Traffic Vans (cruising along outer lanes of Commerce Blvd & Riverview Ave)
	_add_patrol_van(
		dyn_root,
		"TownPostalVan",
		Vector3(3.1, 0.0, 76.0),
		Vector3(3.1, 0.0, 32.0),
		4.8,
		"wall_blue"
	)
	_add_patrol_van(
		dyn_root,
		"BakeryDeliveryVan",
		Vector3(18.0, 0.0, 102.8),
		Vector3(35.0, 0.0, 102.8),
		4.2,
		"wall_bakery"
	)


func _add_physics_traffic_cone(parent: Node3D, pos: Vector3) -> void:
	var rb: RigidBody3D = RigidBody3D.new()
	rb.position = pos
	rb.mass = 1.8
	rb.collision_layer = 1
	rb.collision_mask = 1 | 2 | 8 | 16
	parent.add_child(rb)

	var col: CollisionShape3D = CollisionShape3D.new()
	var shape: CylinderShape3D = CylinderShape3D.new()
	shape.radius = 0.28
	shape.height = 0.72
	col.shape = shape
	rb.add_child(col)

	var cone_mi: MeshInstance3D = MeshInstance3D.new()
	var cone_mesh: CylinderMesh = CylinderMesh.new()
	cone_mesh.top_radius = 0.06
	cone_mesh.bottom_radius = 0.28
	cone_mesh.height = 0.72
	cone_mesh.radial_segments = 12
	cone_mesh.material = _mats["hazard_orange"]
	cone_mi.mesh = cone_mesh
	rb.add_child(cone_mi)

	var stripe_mi: MeshInstance3D = MeshInstance3D.new()
	stripe_mi.position = Vector3(0.0, 0.08, 0.0)
	var stripe_mesh: CylinderMesh = CylinderMesh.new()
	stripe_mesh.top_radius = 0.11
	stripe_mesh.bottom_radius = 0.17
	stripe_mesh.height = 0.18
	stripe_mesh.radial_segments = 12
	stripe_mesh.material = _mats["lane_white"]
	stripe_mi.mesh = stripe_mesh
	rb.add_child(stripe_mi)

	_physics_props.append({
		"body": rb,
		"spawn_tf": rb.transform,
	})


func _add_patrol_van(
	parent: Node3D,
	van_name: String,
	start_pos: Vector3,
	end_pos: Vector3,
	speed: float,
	body_mat_key: String
) -> void:
	var van: AnimatableBody3D = AnimatableBody3D.new()
	van.name = van_name
	van.position = start_pos
	van.sync_to_physics = false
	van.collision_layer = 1
	van.collision_mask = 0
	parent.add_child(van)

	var col: CollisionShape3D = CollisionShape3D.new()
	col.position = Vector3(0.0, 1.0, 0.0)
	var box_sh: BoxShape3D = BoxShape3D.new()
	box_sh.size = Vector3(1.85, 1.8, 3.6)
	col.shape = box_sh
	van.add_child(col)

	_add_visual_box(van, Vector3(0.0, 1.05, 0.0), Vector3(1.85, 1.5, 3.5), body_mat_key)
	_add_visual_box(van, Vector3(0.0, 1.35, -1.76), Vector3(1.6, 0.55, 0.06), "window_glass")
	_add_visual_box(van, Vector3(0.0, 1.84, 0.1), Vector3(1.7, 0.12, 2.8), "lane_white")

	for wx: float in [-0.88, 0.88]:
		for wz: float in [-1.1, 1.1]:
			_add_visual_box(van, Vector3(wx, 0.35, wz), Vector3(0.22, 0.65, 0.65), "asphalt_dark")

	_patrol_vans.append({
		"body": van,
		"start": start_pos,
		"end": end_pos,
		"speed": speed,
		"t": 0.0,
		"dir": 1.0,
	})
