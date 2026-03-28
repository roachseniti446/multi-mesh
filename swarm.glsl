#[compute]
#version 450

// -----------------------------------------------------------------------------
// 1. DATA STRUCTURES
// -----------------------------------------------------------------------------
struct Entity {
    vec4 position; // xyz = pos, w = phase/random offset
    vec4 velocity; // xyz = velocity, w = speed multiplier
};
// The Godot MultiMesh 3D Transform format (12 floats, strict row-major)
// UPDATED: Now 64 bytes to match use_colors = true
struct MultiMeshTransform {
    vec4 row0; // basis.x.x, basis.y.x, basis.z.x, origin.x
    vec4 row1; // basis.x.y, basis.y.y, basis.z.y, origin.y
    vec4 row2; // basis.x.z, basis.y.z, basis.z.z, origin.z
    vec4 color;
};

// -----------------------------------------------------------------------------
// 2. BUFFERS
// -----------------------------------------------------------------------------
// Binding 0: Our custom physics state
layout(set = 0, binding = 0, std430) restrict buffer EntityBuffer {
    Entity entities[];
};

layout(set = 0, binding = 1, std430) writeonly buffer TransformOutput {
    MultiMeshTransform final_transforms[];
};
layout(set = 0, binding = 2, std430) restrict buffer CounterBuffer { uint visible_count; }; // Buffer B: Atomic Counter

// -----------------------------------------------------------------------------
// 3. PUSH CONSTANTS
// -----------------------------------------------------------------------------
layout(push_constant, std430) uniform Params {
	float time;
	float delta;
	uint total_instances;
	uint pad;               // 4 bytes (Explicit padding to hit the 16-byte boundary)
    // 6 planes * vec4 (16 bytes) = 96 bytes. Total block size = 112 bytes.
    vec4 planes[6]; 
} params;

// -----------------------------------------------------------------------------
// 4. THE KERNEL
// -----------------------------------------------------------------------------

// A 1x1x1 box has a bounding sphere radius of roughly 0.866. 
// We use 1.0 to give a tiny bit of safe padding.
bool is_visible(vec3 pos, float radius) {
    for (int i = 0; i < 6; i++) {
        // Godot's frustum planes face OUTWARD. 
        // If the distance along the normal is greater than 'd' + radius, it's off-screen.
        float dist = dot(params.planes[i].xyz, pos) - params.planes[i].w;
        if (dist > radius) return false;
    }
    return true;
}

layout(local_size_x = 64, local_size_y = 1, local_size_z = 1) in;

void main() {
	uint idx = gl_GlobalInvocationID.x;
	if (idx >= params.total_instances) { return; }

    // Read current state
    Entity e = entities[idx];
	// --- HARD-CODED MOVEMENT LOGIC ---
    // Make them swirl in a massive sine-wave tornado
    e.position.x += sin(params.time * e.velocity.w + e.position.w) * e.velocity.x * params.delta;
	e.position.y += e.velocity.y * params.delta;
	e.position.z += cos(params.time * e.velocity.w + e.position.w) * e.velocity.z * params.delta;

    // Wrap them around if they fly too high
    if (e.position.y > 100.0) {
		e.position.y = -100.0;
	}

    // Write state back to our physics buffer
    entities[idx] = e;

	// --- FRUSTUM CULLING (COMPACTION UPGRADE) ---
	if (is_visible(e.position.xyz, 1.0)) {
		// Grab the next available slot in the dense array
		uint dst = atomicAdd(visible_count, 1);

		float normalized_height = (e.position.y + 100.0) / 200.0;
		vec3 color_bottom = vec3(0.0, 0.2, 0.8);
		vec3 color_top = vec3(1.0, 0.1, 0.4);
		
		// Write exclusively to the compacted index!
		final_transforms[dst].row0 = vec4(1.0, 0.0, 0.0, e.position.x);
		final_transforms[dst].row1 = vec4(0.0, 1.0, 0.0, e.position.y);
		final_transforms[dst].row2 = vec4(0.0, 0.0, 1.0, e.position.z);
		final_transforms[dst].color = vec4(mix(color_bottom, color_top, normalized_height), 1.0);
	}
}