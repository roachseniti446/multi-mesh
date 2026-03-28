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

// Binding 1: Godot's MultiMesh VRAM
layout(set = 0, binding = 1, std430) writeonly buffer TransformOutput {
    MultiMeshTransform final_transforms[];
};

// -----------------------------------------------------------------------------
// 3. PUSH CONSTANTS
// -----------------------------------------------------------------------------
layout(push_constant, std430) uniform Params {
    float time;
    float delta;
    uint total_instances;
    uint pad;               // 4 bytes (Explicit padding to hit the 16-byte boundary)
} params;

// -----------------------------------------------------------------------------
// 4. THE KERNEL
// -----------------------------------------------------------------------------
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

    // --- DYNAMIC COLOR MATH ---
    // Map the Y position (-100 to 100) to a 0.0 to 1.0 range
    float normalized_height = (e.position.y + 100.0) / 200.0;
    
    // Mix between a deep blue at the bottom and a hot pink/red at the top
    vec3 color_bottom = vec3(0.0, 0.2, 0.8);
    vec3 color_top = vec3(1.0, 0.1, 0.4);
    vec3 final_color = mix(color_bottom, color_top, normalized_height);

    // --- WRITE TO MULTIMESH ---
    final_transforms[idx].row0 = vec4(1.0, 0.0, 0.0, e.position.x);
    final_transforms[idx].row1 = vec4(0.0, 1.0, 0.0, e.position.y);
    final_transforms[idx].row2 = vec4(0.0, 0.0, 1.0, e.position.z);
    
    // Write the calculated color
    final_transforms[idx].color = vec4(final_color, 1.0);
}