extends Node3D

@export var swarm_count: int = 100000
@export var spawn_radius: float = 50.0

var enable_colors: bool = true
var enable_compute: bool = true

var cam: Camera3D

# --- Low-Level Rendering Variables ---
var base_mesh: BoxMesh         # MUST keep a reference so it isn't garbage collected.
var mm_rid: RID                # The raw MultiMesh RID
var rs_instance: RID           # The raw RenderingServer instance RID

# --- Compute Variables ---
var rd: RenderingDevice

var cull_shader: RID
var cull_pipeline: RID
var cull_uniform_set: RID

var cmd_shader: RID
var cmd_pipeline: RID
var cmd_uniform_set: RID

var entity_buffer: RID
var counter_buffer: RID # BUFFER B: Atomic Counter
var push_constant_bytes := PackedByteArray()
var time_elapsed: float = 0.0
var compute_initialized: bool = false

func _ready() -> void:
	# uncomment this line to check for bottlenecks. it will attempt to run its fps as high as it can.
	# DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	
	_setup_camera()
	_setup_server_swarm()
	
	if enable_compute:
		# Wait until the Render Thread has fully processed and drawn a frame.
		# This guarantees the hardware RenderingDevice buffers now exist in VRAM.
		await RenderingServer.frame_post_draw
		call_deferred("_init_compute")

func _setup_camera() -> void:
	cam = Camera3D.new()
	cam.name = "SwarmCamera"
	
	add_child(cam)
	
	cam.position = Vector3(0, 0, 120)
	cam.look_at(Vector3.ZERO)
	cam.make_current()

func _setup_server_swarm() -> void:
	# 1. Create and hold onto the base mesh
	base_mesh = BoxMesh.new()
	base_mesh.size = Vector3(1, 1, 1)
	
	if enable_colors:
		var mat = StandardMaterial3D.new()
		mat.vertex_color_use_as_albedo = true
		base_mesh.material = mat
	
	# 2. Create the MultiMesh completely on the RenderingServer
	mm_rid = RenderingServer.multimesh_create()
	
	# 3. Allocate the memory WITH the indirect flag (the 'true' at the end)
	RenderingServer.multimesh_allocate_data(
		mm_rid, 
		swarm_count, 
		RenderingServer.MULTIMESH_TRANSFORM_3D, 
		enable_colors, 
		false,         
		true           # use_indirect = true!
	)
	
	# 4. Assign the mesh
	RenderingServer.multimesh_set_mesh(mm_rid, base_mesh.get_rid())
	
	# 5. Populate initial zero-state data
	for i in swarm_count:
		var t = Transform3D(Basis(), Vector3.ZERO)
		RenderingServer.multimesh_instance_set_transform(mm_rid, i, t)
		if enable_colors:
			RenderingServer.multimesh_instance_set_color(mm_rid, i, Color(1, 1, 1, 1))

	# 6. Create the instance and attach to world
	rs_instance = RenderingServer.instance_create()
	RenderingServer.instance_set_base(rs_instance, mm_rid)
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

	# 1. Compile BOTH Shaders
	var cull_file = load("res://swarm.glsl")
	cull_shader = rd.shader_create_from_spirv(cull_file.get_spirv())
	cull_pipeline = rd.compute_pipeline_create(cull_shader)
	
	var cmd_file = load("res://command_writer.glsl")
	cmd_shader = rd.shader_create_from_spirv(cmd_file.get_spirv())
	cmd_pipeline = rd.compute_pipeline_create(cmd_shader)

	# 2. Setup Entity Buffer (Buffer A)
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

	# 3. Setup Atomic Counter Buffer (Buffer B)
	var counter_bytes := PackedByteArray()
	counter_bytes.resize(4) # 1 uint initialized to 0
	counter_buffer = rd.storage_buffer_create(counter_bytes.size(), counter_bytes)

	# 4. Grab MultiMesh Buffers (Buffers C & D)
	# Using the raw mm_rid from our pure server setup!
	var mm_output_buffer = RenderingServer.multimesh_get_buffer_rd_rid(mm_rid)
	var mm_cmd_buffer = RenderingServer.multimesh_get_command_buffer_rd_rid(mm_rid)

	# 5. Create Uniforms - CULLING PASS
	var u_entities = RDUniform.new()
	u_entities.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	u_entities.binding = 0
	u_entities.add_id(entity_buffer)

	var u_output = RDUniform.new()
	u_output.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	u_output.binding = 1
	u_output.add_id(mm_output_buffer)
	
	var u_counter_cull = RDUniform.new()
	u_counter_cull.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	u_counter_cull.binding = 2
	u_counter_cull.add_id(counter_buffer)

	cull_uniform_set = rd.uniform_set_create([u_entities, u_output, u_counter_cull], cull_shader, 0)
	
	# 6. Create Uniforms - COMMAND WRITER PASS
	var u_counter_cmd = RDUniform.new()
	u_counter_cmd.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	u_counter_cmd.binding = 0
	u_counter_cmd.add_id(counter_buffer)
	
	var u_cmd_output = RDUniform.new()
	u_cmd_output.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	u_cmd_output.binding = 1
	u_cmd_output.add_id(mm_cmd_buffer)
	
	cmd_uniform_set = rd.uniform_set_create([u_counter_cmd, u_cmd_output], cmd_shader, 0)
	
	push_constant_bytes.resize(112)
	compute_initialized = true

func _process(delta: float) -> void:
	if not compute_initialized: return
	
	time_elapsed += delta
	
	# Pack Push Constants
	push_constant_bytes.encode_float(0, time_elapsed)
	push_constant_bytes.encode_float(4, delta)
	push_constant_bytes.encode_u32(8, swarm_count)
	# bytes 12-15 are the padding
	
	# 2. Extract and Pack Camera Frustum Planes
	# get_frustum() returns an Array[Plane] of size 6
	var planes = cam.get_frustum()
	var offset = 16 
	
	for i in 6:
		var p: Plane = planes[i]
		# Plane normal (xyz) and distance (w)
		push_constant_bytes.encode_float(offset + 0, p.normal.x)
		push_constant_bytes.encode_float(offset + 4, p.normal.y)
		push_constant_bytes.encode_float(offset + 8, p.normal.z)
		push_constant_bytes.encode_float(offset + 12, p.d)
		offset += 16
		
	# 2. Reset the atomic counter BEFORE starting the compute list
	rd.buffer_clear(counter_buffer, 0, 4)
	
	#var _compute_list = rd.compute_list_begin()
	
	# --- PASS 1: Physics & Culling ---
	var cull_list = rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(cull_list, cull_pipeline)
	rd.compute_list_bind_uniform_set(cull_list, cull_uniform_set, 0)
	rd.compute_list_set_push_constant(cull_list, push_constant_bytes, push_constant_bytes.size())
	var workgroups_x = ceil(swarm_count / 64.0)
	rd.compute_list_dispatch(cull_list, workgroups_x, 1, 1)
	rd.compute_list_add_barrier(cull_list) # Wait for buffer B and C
	rd.compute_list_end()
	
	# --- PASS 2: Write Command Buffer ---
	# A brand new list. No push constant state carried over.
	var cmd_list = rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(cmd_list, cmd_pipeline)
	rd.compute_list_bind_uniform_set(cmd_list, cmd_uniform_set, 0)
	rd.compute_list_dispatch(cmd_list, 1, 1, 1)
	rd.compute_list_add_barrier(cmd_list) # Wait for buffer D
	rd.compute_list_end()

# --- CRITICAL: MANUAL MEMORY MANAGEMENT ---
func _exit_tree() -> void:
	# When bypassing the scene tree, we are responsible for cleaning up the RIDs
	if rs_instance.is_valid():
		RenderingServer.free_rid(rs_instance)
	if mm_rid.is_valid():
		RenderingServer.free_rid(mm_rid)
