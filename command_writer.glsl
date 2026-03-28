#[compute]
#version 450

layout(set = 0, binding = 0, std430) restrict readonly buffer CounterBuffer { uint visible_count; };
layout(set = 0, binding = 1, std430) writeonly buffer CommandBuffer {
	uint indexCount;    // Godot BoxMesh has 36 indices
	uint instanceCount; // The exact number of visible items!
	uint firstIndex;
	uint vertexOffset;
	uint firstInstance;
};

// -----------------------------------------------------------------------------
// FAKE PUSH CONSTANTS
// -----------------------------------------------------------------------------
// layout(push_constant, std430) uniform Params {
// 	float a;
// 	float b;
// 	uint c;
// 	uint d;               // 4 bytes (Explicit padding to hit the 16-byte boundary)
// 	vec4 e[6]; 
// } params;

// Run this exactly ONCE per frame
layout(local_size_x = 1, local_size_y = 1, local_size_z = 1) in;

void main() {
	// uint dummy = params.c; // Force the compiler to keep the struct!
	// if (dummy == 999999) { indexCount = 0; } // Use it in a way that will never trigger
	
	indexCount = 36; 
	instanceCount = visible_count;
	firstIndex = 0;
	vertexOffset = 0;
	firstInstance = 0;
}
