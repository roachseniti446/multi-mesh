extends Node3D

@export var swarm_count: int = 10000
@export var spawn_radius: float = 50.0

var mmi: MultiMeshInstance3D
var cam: Camera3D

func _ready() -> void:
	# DISABLE VSYNC for true profiling data
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	
	_setup_camera()
	_setup_static_swarm()

func _setup_camera() -> void:
	cam = Camera3D.new()
	cam.name = "SwarmCamera"
	
	# 1. Add the camera to the SceneTree first!
	# This gives Godot the spatial context needed to calculate transforms.
	add_child(cam)
	
	# 2. Now we can safely position it...
	cam.position = Vector3(0, 0, 120)
	
	# 3. ...and orient it.
	cam.look_at(Vector3.ZERO)
	
	# 4. Make it the active camera
	cam.make_current()

func _setup_static_swarm() -> void:
	mmi = MultiMeshInstance3D.new()
	var swarm_multimesh = MultiMesh.new()
	
	# ==========================================
	# 1. BUFFER FORMAT SETUP
	# ==========================================
	swarm_multimesh.transform_format = MultiMesh.TRANSFORM_3D
	swarm_multimesh.use_colors = true       
	swarm_multimesh.use_custom_data = false 
	
	# ==========================================
	# 2. MESH AND MATERIAL SETUP
	# ==========================================
	var box_mesh = BoxMesh.new()
	box_mesh.size = Vector3(1, 1, 1)
	
	var mat = StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	box_mesh.material = mat
	
	swarm_multimesh.mesh = box_mesh
	
	# ==========================================
	# 3. ALLOCATE AND POPULATE
	# ==========================================
	swarm_multimesh.instance_count = swarm_count
	mmi.multimesh = swarm_multimesh
	
	# Populate the instances with random positions and colors
	for i in swarm_count:
		var random_pos = Vector3(
			randf_range(-spawn_radius, spawn_radius),
			randf_range(-spawn_radius, spawn_radius),
			randf_range(-spawn_radius, spawn_radius)
		)
		
		var t = Transform3D(Basis(), random_pos)
		swarm_multimesh.set_instance_transform(i, t)
		
		var random_color = Color(randf(), randf(), randf(), 1.0)
		swarm_multimesh.set_instance_color(i, random_color)
	
	# ==========================================
	# 4. SCENE INTEGRATION
	# ==========================================
	mmi.custom_aabb = AABB(Vector3(-10000, -10000, -10000), Vector3(20000, 20000, 20000))
	add_child(mmi)
