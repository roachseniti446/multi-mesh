extends Node3D

@export var swarm_count: int = 10000
@export var spawn_radius: float = 50.0

# Hardcoded now because we will always use compute and the shader expects color otherwise the stride will be off
var enable_colors: bool = true
var enable_compute: bool = true

var cam: Camera3D

# --- Low-Level Rendering Variables ---
var swarm_multimesh: MultiMesh # Keep a reference so it isn't garbage collected
var rs_instance: RID           # The raw RenderingServer instance RID

# --- Compute Variables ---
var rd: RenderingDevice
var shader: RID
var shader_pipeline: RID
var uniform_set: RID
var entity_buffer: RID
var push_constant_bytes := PackedByteArray()
var time_elapsed: float = 0.0
var compute_initialized: bool = false

func _ready() -> void:
	# uncomment this line to check for bottlenecks. it will attempt to run its fps as high as it can.
	# DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	
	_setup_camera()
	_setup_server_swarm()
	
	if enable_compute:
		call_deferred("_init_compute")

func _setup_camera() -> void:
	cam = Camera3D.new()
	cam.name = "SwarmCamera"
	
	add_child(cam)
	
	cam.position = Vector3(0, 0, 120)
	cam.look_at(Vector3.ZERO)
	cam.make_current()

func _setup_server_swarm() -> void:
	# ==========================================
	# 1. BUFFER FORMAT SETUP
	# ==========================================
	swarm_multimesh = MultiMesh.new()
	swarm_multimesh.transform_format = MultiMesh.TRANSFORM_3D
	swarm_multimesh.use_colors = enable_colors       
	swarm_multimesh.use_custom_data = false 
	
	var box_mesh = BoxMesh.new()
	box_mesh.size = Vector3(1, 1, 1)
	
	if enable_colors:
		var mat = StandardMaterial3D.new()
		mat.vertex_color_use_as_albedo = true
		box_mesh.material = mat
	
	swarm_multimesh.mesh = box_mesh
	
	# ==========================================
	# 3. ALLOCATE AND POPULATE
	# ==========================================
	swarm_multimesh.instance_count = swarm_count
	
	# Populate the initial positions (will be overwritten by compute, but good for setup)
	for i in swarm_count:
		var t = Transform3D(Basis(), Vector3.ZERO)
		swarm_multimesh.set_instance_transform(i, t)
		if enable_colors:
			swarm_multimesh.set_instance_color(i, Color(1, 1, 1, 1))

	# ==========================================
	# 4. CREATE THE SERVER INSTANCE
	# ==========================================
	rs_instance = RenderingServer.instance_create()
	
	# Attach the MultiMesh to the instance
	RenderingServer.instance_set_base(rs_instance, swarm_multimesh.get_rid())
	
	# Attach the instance to the current 3D world's scenario so it becomes visible
	var scenario = get_world_3d().scenario
	RenderingServer.instance_set_scenario(rs_instance, scenario)
	
	# Prevent Frustum Culling
	var massive_aabb = AABB(Vector3(-10000, -10000, -10000), Vector3(20000, 20000, 20000))
	RenderingServer.instance_set_custom_aabb(rs_instance, massive_aabb)

func _init_compute() -> void:
	rd = RenderingServer.get_rendering_device()
	if not rd:
		push_error("Compute unavailable.")
		return

	# 1. Compile Shader
	var shader_file = load("res://swarm.glsl")
	var shader_spirv: RDShaderSPIRV = shader_file.get_spirv()
	shader = rd.shader_create_from_spirv(shader_spirv)
	shader_pipeline = rd.compute_pipeline_create(shader)

	# 2. Setup our custom Entity Physics Buffer
	var entity_bytes := PackedByteArray()
	entity_bytes.resize(swarm_count * 32) # 32 bytes per struct (vec4 pos, vec4 vel)
	
	for i in swarm_count:
		var offset = i * 32
		# Position XYZ
		entity_bytes.encode_float(offset + 0, randf_range(-spawn_radius, spawn_radius))
		entity_bytes.encode_float(offset + 4, randf_range(-spawn_radius, spawn_radius))
		entity_bytes.encode_float(offset + 8, randf_range(-spawn_radius, spawn_radius))
		# Phase offset (w)
		entity_bytes.encode_float(offset + 12, randf() * PI * 2.0) 
		
		# Velocity XYZ
		entity_bytes.encode_float(offset + 16, randf_range(10.0, 30.0))
		entity_bytes.encode_float(offset + 20, randf_range(5.0, 15.0)) # Upward speed
		entity_bytes.encode_float(offset + 24, randf_range(10.0, 30.0))
		# Speed multiplier (w)
		entity_bytes.encode_float(offset + 28, randf_range(0.5, 2.0))

	entity_buffer = rd.storage_buffer_create(entity_bytes.size(), entity_bytes)

	# 3. Hijack Godot's MultiMesh Buffer
	var target_multimesh = swarm_multimesh.get_rid()
	var output_buffer = RenderingServer.multimesh_get_buffer_rd_rid(target_multimesh)

	# 4. Create Uniform Set
	var entity_uniform := RDUniform.new()
	entity_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	entity_uniform.binding = 0
	entity_uniform.add_id(entity_buffer)

	var output_uniform := RDUniform.new()
	output_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	output_uniform.binding = 1
	output_uniform.add_id(output_buffer)

	uniform_set = rd.uniform_set_create([entity_uniform, output_uniform], shader, 0)
	
	push_constant_bytes.resize(16) # float time, float delta, uint total_instances, padding
	compute_initialized = true

func _process(delta: float) -> void:
	if not compute_initialized: return
	
	time_elapsed += delta
	
	# Pack Push Constants
	push_constant_bytes.encode_float(0, time_elapsed)
	push_constant_bytes.encode_float(4, delta)
	push_constant_bytes.encode_u32(8, swarm_count)
	
	# Dispatch
	var compute_list = rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list, shader_pipeline)
	rd.compute_list_bind_uniform_set(compute_list, uniform_set, 0)
	rd.compute_list_set_push_constant(compute_list, push_constant_bytes, push_constant_bytes.size())
	
	var workgroups_x = ceil(swarm_count / 64.0)
	rd.compute_list_dispatch(compute_list, workgroups_x, 1, 1)
	
	rd.compute_list_end()

# --- CRITICAL: MANUAL MEMORY MANAGEMENT ---
func _exit_tree() -> void:
	# When bypassing the scene tree, we are responsible for cleaning up the RIDs
	if rs_instance.is_valid():
		RenderingServer.free_rid(rs_instance)
