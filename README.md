<p align="center">
  <img src="assets/logo.svg" width="96" alt="glVolition logo"/>
</p>

# glVolition (`package:gl_volition`)

> **A high-performance, cross-platform 2D/3D game engine with a pure-Dart core, Forward+ WebGL2/GLES3 rendering, deterministic physics, networked rollback replication, and unified Native, Web, and Dedicated Server runtimes.**

glVolition is engineered around a strict architectural invariant: **a pure-Dart, host-agnostic engine core** (`lib/src/engine/**`) that has zero dependencies on `dart:io`, `dart:ffi`, or `package:web`. This enables complete deterministic game loops, physics simulations, state serialization, AI, and multiplayer replication suites to execute headlessly on the Dart VM in milliseconds, while compiling seamlessly to native AOT desktop binaries, WebGL2 browser applications, and lightweight headless servers.

---

## Engine Architecture & Pillars

```
                        +---------------------------------------+
                        |     Game / Application Logic          |
                        +-------------------+-------------------+
                                            |
                        +-------------------v-------------------+
                        |  Pure-Dart Core (`lib/src/engine/**`) |
                        |  ECS, Scene, Physics, Assets, Net, UI |
                        |  (100% Host-Agnostic, Zero IO/FFI/Web)|
                        +----+--------------+--------------+----+
                             |              |              |
          +------------------+     +--------+--------+     +------------------+
          |                        |                 |                        |
+---------v---------+    +---------v------+    +-----v------------+    +------v-----------+
| Dedicated Server  |    |  Web Runtime   |    |  Native Runtime  |    |  Forward+ 3D     |
| `DedicatedServer` |    | `src/web/**`   |    | `src/native/**`  |    | `vendor/pixeldart`
| Zero-GPU Headless |    | WebGL2 + Audio |    | SDL3 + GLES3 FFI |    | Graph, PBR, CSM, |
| Fixed Tick Loop   |    | Context + Pad  |    | + PCM Audio + IO |    | Skinning, Decals |
+-------------------+    +----------------+    +------------------+    +------------------+
```

### Core Subsystems
- **Pure-Dart Core Boundary (`lib/gl_volition.dart`)**: Complete ECS (`GameObject`, `Component`, `Behaviour`), hierarchy, `Time`, transform propagation, object pooling, and immediate `UICanvas`. 154 scanned engine files with 0 platform leaks enforced by static boundary tooling.
- **Hardware Forward+ 3D Renderer (`vendor/pixeldart`)**: Host-decoupled WebGL2 / GLES3 pipeline supporting GPU skeletal skinning, multi-caster cascaded directional shadows, projective surface decals, stencil buffer operations, soft particles, AgX/ACES tone mapping, and host-declared render passes.
- **Production Physics & Determinism**: Spatial broadphase acceleration (up to 127x faster than linear brute-force on 1,500+ colliders), 15-axis Separating Axis Theorem (SAT) oriented bounding boxes (`BoxCollider`), AABB-BVH triangle `MeshCollider`, bicubic `HeightfieldCollider`, rotational solver with inertia tensors and friction/torque, hinge/ball/fixed joints, island sleeping, swept TOI continuous collision detection (CCD), and 600-frame bit-identical temporal determinism gates.
- **Multiplayer Networking (`vendor/voxnet`)**: Cross-platform `WebSocketNetTransport` (`dart:io` server/client + `package:web` browser client), native UDP transport with sequenced reliable/unreliable channels (`RawDatagramSocket`), delta snapshot compression, client input prediction, and rollback reconciliation automatically synchronized with `Engine.step`.
- **Studio Editor & Live Tooling**: Compact reversible `EditorCommand` undo/redo operating in $O(\text{delta})$ memory/time, live 3D viewport transform gizmos (translate, rotate, scale with raycast snapping), prefab variant inheritance with live override inspection/revert, `AssetCatalog` resource pickers, and `EngineTelemetrySnapshot` runtime JSON diagnostics.
- **Native Desktop OS Runtime (`lib/gl_volition_native.dart`)**: SDL3 FFI window management, event pump, native audio sink with low-latency circular PCM buffers, dual-track graphics (hardware `RealGlesDevice` + deterministic `RecordingGlesDevice`), and `DedicatedServerHost`.
- **Modern Web Runtime (`lib/gl_volition_web.dart`)**: `WebEngineHost` driving WebGL2 canvas rendering, Web Audio API spatial DSP graph (`StereoPannerNode`, `BiquadFilterNode`, `ConvolverNode`), pointer lock, wheel, touch, and Gamepad API parity.

---

## Toolchain & Quick Start

### 1. Prerequisites
- **Dart SDK**: `^3.12.0` (Dart `3.14.0+` recommended)
- **Git**: Installed with submodule support
- *(Optional for Native Desktop)*: C/C++ compiler toolchain (MSVC on Windows, Clang/GCC on Linux/macOS) and SDL3 / ANGLE GLES shared libraries.

### 2. Clone Repository
Clone the repository and recursively pull all submodules (`vendor/pixeldart`, `vendor/voxnet`, etc.):
```bash
git clone --recurse-submodules https://github.com/soulwax/glVolition.git
cd glVolition
dart pub get
```

### 3. Verify Environment (`volition doctor`)
Check your toolchain, compilers, graphics devices, and runtime libraries using the engine CLI:
```bash
dart run gl_volition:volition doctor
```

### 4. Scaffold a Project (`volition create`)
Generate a complete, ready-to-build engine project using one of the built-in templates:
```bash
# Available templates: 2d | 3d | multiplayer
dart run gl_volition:volition create my_game --template 3d
cd my_game
dart pub get
```

---

## Building the Engine & Applications

The engine provides a unified CLI entrypoint via `bin/volition.dart` (`dart run gl_volition:volition <command>`).

### Compiling the Engine CLI Tool
You can compile the CLI into a standalone, native AOT binary for instant execution:
```bash
dart compile exe bin/volition.dart -o volition.exe
./volition.exe doctor
```

### Build Targets

```bash
# Web browser targets (emits minified bundle + HTML to ./dist/<version>/<name>/<target>/)
dart run gl_volition:volition build path/to/main.dart --target js
dart run gl_volition:volition build path/to/main.dart --target wasm

# Native Desktop AOT binary (bundles executable + SDL3/GLES DLLs + cooked assets)
dart run gl_volition:volition build path/to/main.dart --target windows
dart run gl_volition:volition build path/to/main.dart --target linux
dart run gl_volition:volition build path/to/main.dart --target macos

# Dedicated Headless Multiplayer Server (zero GPU, zero window, minimal headless tick loop)
dart run gl_volition:volition build path/to/server_main.dart --target server
```

### Asset Cooking & VFS Packaging (`volition pack`)
The engine uses an indexed, compressed virtual file system (`.pak`) with zero-allocation streaming decoders:
```bash
# Convert Wavefront OBJ + MTL + textures into binary QMSH model packages
dart run gl_volition:volition pack obj2qmesh --in assets/models --out assets/cooked

# Bake 3D Color Grading LUTs from .cube to raw volumetric textures
dart run gl_volition:volition pack cube2lut --in assets/luts --out assets/cooked

# Pack raw/cooked assets into a compressed .pak VFS archive with manifest
dart run gl_volition:volition pack pack --in assets --out build/game.pak

# Validate integrity of existing .pak bundles
dart run gl_volition:volition pack validate --in build/game.pak
```

### Live Development Server (`volition serve`)
Run applications in development mode with live HTTP serving, asset hot-state reloading, and the built-in diagnostic overlay:
```bash
dart run gl_volition:volition serve path/to/main.dart --port 8080
```
Open your browser to `http://localhost:8080` and press **F12** or **Alt+I** to toggle the live Web Inspector and 3D Viewport Gizmos.

### Studio GUI (`volition gui`)
Launch the graphical Studio frontend for `doctor`, `create`, `build`, `dist`, `pack`, `serve`, `test`, and verification gates:
```bash
dart run gl_volition:volition gui [--port 8090] [--no-open]
```

---

## Testing & Quality Gates

The engine enforces strict, automated verification across architecture, performance, determinism, and cross-platform compilation.

### 1. Root Test Suite
Execute the sharded engine test suite headlessly on the Dart VM:
```bash
dart test
# or via CLI:
dart run gl_volition:volition test
```
The test suite covers:
- `test/engine/`: Core ECS, transform hierarchy, `EditorCommand` delta undo/redo, 3D viewport gizmos, component serialization, and diagnostics.
- `test/physics/`: Spatial broadphase speedups, 15-axis SAT OBB collisions, BVH mesh tracing, heightfields, rotational solver, sleeping, and swept TOI CCD.
- `test/determinism/`: 600-frame temporal determinism, bit-identical state replay, live `reducedMotion` comfort gates, and luminance/flash safety.
- `test/assets/`: Direct `.pak` binary decoding, `.glb`/`.qmesh` parsing, ref-counted `AssetCatalog` acquire/release lifecycle.
- `test/network/`: Cross-platform `WebSocketNetTransport` and UDP multi-client snapshot sync, delta compression, prediction, and rollback reconciliation over real loopback sockets.

### 2. Pure-Dart Core Boundary Enforcement
Guarantee that engine core files under `lib/src/engine/**` remain free from platform leaks (`dart:io`, `dart:ffi`, `package:web`, `dart:js_interop`):
```bash
dart run tool/check_boundaries.dart
```
*Pass Criteria:* Scans 154 files across pure-dart-core (136), web-host (7), and native-host (11) with **0 violations**.

### 3. Unified 10-Step Verification Suite (`verify_all.dart`)
Run the complete release validation pipeline executed in CI:
```bash
dart run tool/verify_all.dart --check-format --skip-wasm
```
This single command validates:
1. **Format Check**: Enforces `dart format` across `bin/`, `lib/`, `test/`, and `tool/`.
2. **Boundary Check**: Verifies pure-Dart isolation of `lib/src/engine/**`.
3. **Static Analysis**: Runs `dart analyze` with zero errors, warnings, or hints.
4. **Root Test Suite**: Runs all 380+ headless unit, physics, and gameplay tests.
5. **Renderer Boundary Check**: Enforces boundary rules in `vendor/pixeldart`.
6. **Shader Sync Check**: Validates GLSL shader generator sources against compiled outputs (`shaders.dart --check`).
7. **Renderer Test Suite**: Runs 140 targeted rendering and math fixture test scripts in `vendor/pixeldart`.
8. **Networking Test Suite**: Runs all unit & loopback socket tests in `vendor/voxnet`.
9. **Web JS Compilation Smoke**: Compiles WebGL2 frontend to JavaScript with zero compilation errors.
10. **Native AOT Smoke**: Compiles `bin/volition.dart` to a native executable.

### 4. Renderer Performance & Budget Benchmark
Verify frame times, memory allocations, and visual stability under load:
```bash
dart run tool/renderer_bench.dart
```
*Performance Ratification Criteria:*
- **Frame Time**: CPU average $\le 16.67\text{ ms}$ (60 FPS budget; typically $\approx 0.2\text{ ms}$).
- **Steady-State Allocations**: Exactly $0\text{ B/frame}$ steady allocation.
- **Black Frames**: $0$ black or invalid frames.
- **Instancing**: Scales beyond the 16-instance uniform limit without draw call thrashing.
- **Visual Stability**: Structural SSIM $\ge 0.98$ compared against reference frames.

### 5. Static Analysis & Code Formatting
```bash
# Static analysis
dart analyze

# Format check
dart format --output=none --set-exit-if-changed bin lib test tool
```

---

## Package Structure & Public API

The engine provides three explicit entrypoint barrels:

```dart
// 1. Platform-neutral Core (Headless, Server, Web, Desktop)
import 'package:gl_volition/gl_volition.dart';

// 2. Web Runtime (WebGL2, Web Audio DSP, DOM Inspector)
import 'package:gl_volition/gl_volition_web.dart';

// 3. Native Desktop Runtime (SDL3 FFI, GLES3, Hardware PCM Audio, Server Host)
import 'package:gl_volition/gl_volition_native.dart';
```

### Minimal Headless Server Example
```dart
import 'package:gl_volition/gl_volition.dart';
import 'package:gl_volition/gl_volition_native.dart';

void main() async {
  final host = DedicatedServerHost(
    tickRateHz: 60,
    networkPort: 7777,
    bindAddress: '0.0.0.0',
    onTick: (engine, deltaSeconds) {
      // Gameplay logic runs deterministically without GPU or window handles
    },
  );

  await host.start();
}
```

---

## Submodule Architecture & Publication Strategy

glVolition operates as an integrated monorepo (`publish_to: none`) orchestrating a modular game development ecosystem:

- **`vendor/pixeldart`**: Standalone, host-decoupled WebGL2 / GLES3 3D renderer.
- **`vendor/voxnet`**: Standalone cross-platform networking library (WebSocket + UDP reliable channel transport).
- **`vendor/voxui`**: Standalone immediate/retained 2D GUI and layout library.
- **`vendor/vox*`**: Specialized pure-Dart libraries (`voxecs`, `voxai`, `voxaudio`, `voxphysics`, `voxbiome`, `voxcolor`, `voxcraft`, `voxfracture`, `voxdecal`, etc.).

Games created with glVolition are built and distributed directly into standalone AOT native binaries, web artifacts, or containerized server binaries using `volition build`, eliminating downstream package dependency friction for game developers and players.

---

## License

This project is licensed under the MIT License.
