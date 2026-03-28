# Godot 4: High-Performance Swarm Rendering

This project is an educational exploration of rendering massive amounts of dynamic instances (100k - 1 Million+) in Godot 4. It documents the journey from standard high-level Nodes to bare-metal `RenderingDevice` compute shaders and GPU stream compaction.

If you are trying to understand how AAA games render massive swarms, flocks, or particle systems without melting the CPU, this repository is your roadmap.

## 🗺️ The Journey (Git Tags)

You can step through the commit history or check out the specific tags to see how the architecture evolved as we chased maximum performance.

### 1. `v0.1.0-MMI3D` : The Node Baseline
We started with Godot's high-level `MultiMeshInstance3D` node and a basic compute shader to handle movement. 
* **Pros:** Easy to set up, native Godot integration.
* **Cons:** Godot's high-level scene tree still tries to manage the node, and we are drawing everything, even if it's behind the camera.

### 2. `v0.2.0-rs-bypass-culling` : RenderingServer & Scale-to-Zero
We bypassed the Scene Tree entirely and talked directly to Godot's C++ `RenderingServer` via raw RIDs. We also introduced "Scale-to-Zero" frustum culling in the compute shader.
* **How it worked:** If an entity was outside the camera frustum, the compute shader collapsed its transform matrix to `vec4(0.0)`. 
* **The Bottleneck:** While zero-scale degenerate triangles successfully bypass the GPU's hardware rasterizer (saving fragment shader time), the GPU still executes a draw call for *all* instances. The Vertex Shader still spins up 1,000,000 times just to read the zeroed-out matrices and throw them away.

### 3. `v0.3.0-indirect-drawing` : GPU Stream Compaction
We completely eliminated the vertex shader bottleneck by preventing the GPU from drawing invisible objects in the first place.
* **How it worked:** Introduced a two-pass compute pipeline that uses an atomic counter to pack only visible instances into a dense array, followed by a command writer pass that formats an indirect draw call for the hardware.
* **The Bottleneck:** While incredibly fast, managing raw memory barriers and compute list state tracking (specifically regarding push constants) required strict, bare-metal synchronization.

---

## Indirect Drawing & Stream Compaction (Current)

To completely eliminate the vertex shader overhead, the current version of this project uses **GPU Stream Compaction and Indirect Drawing**.

Instead of passing a sparse list of 1,000,000 objects (many of which are zeroed out), the GPU actively packs only the *visible* objects into the front of the memory buffer. It then writes a hardware-level command to tell the graphics pipeline *exactly* how many objects to draw. 

### The Four-Buffer Architecture
We manage four distinct VRAM buffers using Godot's low-level `RenderingDevice`:

1. **Buffer A (Physics Source):** A custom Storage Buffer holding the unculled simulation state (Positions, Velocities) for all entities.
2. **Buffer B (Atomic Counter):** A tiny 4-byte Storage Buffer holding a single `uint`. It acts as a scratchpad for the GPU to count visible entities.
3. **Buffer C (Compacted MultiMesh):** The tightly packed array of visible instances mapped directly to the `RenderingServer` MultiMesh.
4. **Buffer D (Indirect Command):** A strict 5-integer format buffer that dictates the parameters of the draw call (Indices, Instance Count, Offsets).

### The Two-Pass Compute Pipeline
Every frame, we execute a heavily synchronized compute list:

1. **Pass 1: Culling & Compaction (`swarm.glsl`)**
   Thousands of threads calculate physics. If an entity is inside the camera frustum, the thread executes `atomicAdd()` on Buffer B to claim an index slot, then writes its transform data tightly into Buffer C.
2. **Barrier:** We insert a pipeline barrier to guarantee all transforms and the final atomic count are completely written to VRAM.
3. **Pass 2: Command Writer (`command_writer.glsl`)**
   A tiny 1-thread compute pass reads the final visible count from Buffer B and formats the 5 integers into Buffer D.
4. **Barrier:**
   A final barrier ensures the command buffer is ready before the hardware rasterizer attempts to read it.

### The Results
By guaranteeing the GPU only ever executes vertex shaders for geometry actually visible on screen, **GPU utilization drops massively**. In our testing with a 1-million entity swarm, GPU utilization plummeted from 54% (using the scale-to-zero method) down to just **14%** using stream compaction and indirect drawing!

---

## 🧠 Lessons Learned: The Push Constant State Leak

During development, we encountered a persistent C++ validation error from Godot's `RenderingDevice` during the frame's compute dispatch:

```text
E 0:00:00:892   mm_test.gd:217 @ _process(): This compute pipeline requires (0) bytes of push constant data, supplied: (112)
  <C++ Error>   Condition "p_data_size != compute_list.validation.pipeline_push_constant_size" is true.
  <C++ Source>  servers/rendering/rendering_device.cpp:5256 @ compute_list_set_push_constant()
```

### The Cause: "Sticky" State
Vulkan (and by extension, Godot's `RenderingDevice`) treats compute lists as state machines. Push constant payloads are "sticky"—they persist until explicitly overwritten or the list is closed.

Originally, we dispatched both our culling pass and our command writer pass inside a single `begin()` and `end()` block. **Crucially, the state does not reset between pipeline bindings within the same list.** 

We pushed 112 bytes for the culling pass, then immediately bound the command writer pipeline. Because our command writer expects `0` bytes, binding it while the 112-byte payload was still active triggered a strict state mismatch error. 

### The Fix: Splitting the Lists
To resolve this, you must isolate the state. We split the operation into two distinct compute lists per frame:

* **List 1:** `begin()` ➔ Bind Culling ➔ Push Constants ➔ Dispatch ➔ Barrier ➔ `end()`
* **List 2:** `begin()` ➔ Bind Command Writer ➔ Dispatch ➔ Barrier ➔ `end()`

By closing the first list and opening a completely fresh one for the second pass, the push constant state is wiped clean. The validation error vanished, leaving us with a pristine, high-performance 14% utilization swarm.
