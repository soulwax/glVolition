# `gl_volition` Production Engine Master Plan

> **Supersedes:** Legacy `pixeldart`-only `PLAN.md` (`R1–R7`). Unclosed `pixeldart` renderer tasks are preserved and integrated into **Phase 4 (Wave 12)** and cross-referenced in [TODO.md](TODO.md).
> **Continues from:** [ENGINE.md](ENGINE.md) milestones `E0–E103` plus Wave 7 (`E104–E106`: typed shader/texture/visibilityMask contracts across `Graphics`, `HeadlessGraphics`, `NativeGraphics`, and `_WebGraphics`).

---

## 1. Executive Summary & Honest Baseline Audit

`gl_volition` (`pubspec.yaml`: `sdk: ^3.12.0`, `publish_to: none`, 74 local `vendor/*` dependencies including `pixeldart`, `voxecs`, `voxui`, `voxai`, `voxnet`, `voxlog`, and `voxgreedy`) has a clean architectural core: a pure-Dart ECS/component framework, three explicit platform entrypoints (`lib/gl_volition.dart`, `lib/gl_volition_web.dart`, `lib/gl_volition_native.dart`), deterministic headless execution (`dart test`: 200 passing tests; `dart analyze`: 0 issues; `dart compile js example/prism_pulse/main.dart`: exit 0), and an extensive component library.

However, **several critical runtime subsystems are still software recorders, CPU-only computations, or partial prototypes** rather than production hardware pipelines. Taking `gl_volition` to shippable production quality requires converting every simulated or decoupled boundary into real hardware-backed runtime behavior while preserving the host-agnostic pure-Dart core that enables instant headless testing and Web/Native parity.

### Verified Baseline Matrix (Post-E106)

| Pillar | What Is Solid & Verified Today | Verified Production Gaps & Blockers |
| --- | --- | --- |
| **Core Loop, ECS & Shaders** | Pure-Dart `Engine` / `Scene` / `GameObject` architecture (`lib/src/engine.dart`, `scene.dart`, `game_object.dart`), `ComponentSpec` metadata, `Graphics` visibility bitmask + shader uniform/texture/override contract (`lib/src/engine/host.dart`, `headless.dart`) | `Scene._syncToRenderer` syncs only a single `Camera.of(this)`; multiple components (`RenderGraphComponent`, `Lighting2DComponent`, `DrawBatcherComponent`, `SoftBodyXpbdComponent`) operate in CPU memory without driving live GPU passes/buffers |
| **Native Desktop Runtime** | `NativeEngineHost`, `NativeGraphics`, `FileAssetLoader`, `JsonFileStore` (`lib/src/native/native_host.dart`); FFI transport types (`DynamicLibraryGlLoader`, `NativeGlTransport`, `Sdl3EventPump`, `NativeDesktopBridge` in `native_ffi_transport.dart`) | `GlesDevice` is a software command/state recorder returning hardcoded `GpuTimerPoll(GpuTimerStatus.ready, 1250000)` (`native_host.dart:673`); `DynamicLibraryGlLoader` and `NativeGlTransport.dispatch` have zero GLES3/SDL3 `lookupFunction` bindings or OS window swap loop; `Sdl3EventPump` reads manually enqueued 24-byte `ByteData` packets; native host uses `SilentAudio` |
| **Web Runtime** | `WebEngineHost`, `_WebGraphics`, `_WebAssets` (`lib/src/web/web_host.dart`) backed by `PixeldartApp` (`vendor/pixeldart`) and compiling cleanly via `dart compile js` | `PixeldartApp._frame` (`pixeldart_app.dart:1194-1199`) does not forward `visibilityMask` to `sequencer.next(...)`; `_EmptySpecResources.noSuchMethod` (`component_spec_extra.dart:15`) triggers a `dart compile js` hint; Web lacks multi-touch, wheel, raw pointer-lock deltas, gamepad, and Web Audio DSP |
| **Renderer (`vendor/pixeldart`)** | WebGL2 Forward+ core, `InstanceBufferStream` & `ShadowLightView.fromDirectionalLight` & `MsaaResolveFeature` foundations, `RenderGraphBuilder` + `HostPost`, `tools/renderer/test_all.dart`, `tools/renderer/shaders.dart --check`, `tools/renderer/run_shader_lab.mjs` + `.github/screenshots/` goldens | Still needs end-to-end verification/closure: real stencil state & decal stage (`0` matches in `lib/`), GPU skeletal skinning (`0` matches), lifting any remaining 16-instance uniform path limits into `InstanceBufferStream` live draws, multi-caster shadows + capability-driven shadow resolution + front-face depth culling, linear/sRGB full audit, soft particles, `R3` host-declared graph passes, `R4` anisotropy perf proof, `R5` MSAA resize/restore browser cost, real LUT loader, `Procession` dense-tree tuning (`example/procession/`), Browser Lab 180w/600m budget ratification (`R7`) |
| **Animation & Characters** | Rigid-transform `Animator` keyframes and GLB asset loading support | No GPU skeletal skinning pipeline (joint hierarchy, inverse bind matrices, palette upload, vertex skinning) |
| **Audio** | Spatial math and DSP components (`AudioListener`, `AudioMixer`, `AudioReverbZone`, `AudioLowPassFilterComponent`, `SpatialAudioDspExt` in `audio_source.dart`, `audio_dsp.dart`) | DSP calculations remain CPU-only; `WebAudioDevice` wraps an `HTMLAudioElement` pool (`playbackRate`, `volume`, `loop` only) without Web Audio `AudioContext` filter/panner/reverb nodes; Native uses `SilentAudio` |
| **Physics** | `PhysicsWorld`, `RigidBody`, `SphereCollider`, `BoxCollider`, `CapsuleCollider`, `PhysicsHit` (`physics.dart`); separate `BroadphaseWorldComponent` (`broadphase_world.dart`) | `PhysicsWorld` runs `O(N^2)` `_colliders` loops and linear ray/overlap queries; `BoxCollider` uses axis-aligned `worldBounds` instead of true OBB; lacks `MeshCollider` / heightfield, rotational rigidbody inertia/torque, constraints/joints, and swept CCD in `RigidBody._step()` |
| **Assets & Serialization** | `AssetCatalog` (`asset_catalog.dart`), `.pak` VFS (`pak_vfs.dart`), `SceneSerializer` (`scene_serializer.dart`, `schemaVersion = 1`), plus `vendor/pixeldart` `ObjImporter` / `ObjModelPackageEmitter` / `GltfModelPackageEmitter` / `ModelPackageLoader` | `VfsAssetLoader.loadModel` (`pak_vfs.dart:55-60`) throws `UnimplementedError` without a fallback; `AssetCatalog` lacks ref-counted per-asset `unload` and async Isolate/frame-budgeted loading; `ModelRenderer` spec (`component_spec_extra.dart:44-49`) uses `const []` fields and dummy `ModelAsset`; `SceneSerializer` (`:98-100`) rejects unknown versions with no migration pipeline |
| **Networking (`voxnet`)** | `NetworkManager` (`network_system.dart`) and `LoopbackNetwork` (`vendor/voxnet/lib/src/transport/transport.dart`) | In-memory `LoopbackNetwork` only; no production `WebSocket` or reliable-UDP FFI transport; `Engine.step` does not automatically drive network tick/interpolation/rollback sync |
| **Editor & Tooling** | `EditorSession` (`editor_session.dart`), `InspectorOverlay` (`inspector_overlay.dart`), `EngineWorkbenchComponent` (`engine_workbench.dart`), `Prefab` (`prefab.dart`), CLI `bin/volition.dart` (`test`, `serve`, `build`, `dist`), `dist.ps1` | `EditorSession._captureHistoryEntry` (`:80-94`) snapshots full-scene JSON per undo step instead of deltas; split DOM/workbench UIs lack 3D gizmo drag-picking and asset browser wiring; `bin/volition.dart` `_runServe` (`:140`) invokes `Platform.resolvedExecutable` instead of `_dartExecutable`; `--target windows` (`:648-757`) packages a `.NET 10` WinForms + `WebView2` wrapper (`Program.cs`) rather than native AOT; `README.md:28` has `-- target wasm` typo; `.github/` CI does not exist; `test/subsystems_test.dart` is a 10,284-line monolith |

---

## 2. Production Architecture & Non-Negotiable Invariants

### 2.1 Architectural Target Topology

```
                        +---------------------------------------+
                        |     Game / Example / Application      |
                        +-------------------+-------------------+
                                            |
                        +-------------------v-------------------+
                        |  Pure-Dart Core (`lib/src/engine/**`) |
                        |  ECS, Scene, Physics, Assets, Net, UI |
                        |  (ZERO dart:io / dart:ffi / package:web)
                        +----+--------------+--------------+----+
                             |              |              |
          +------------------+     +--------+--------+     +------------------+
          |                        |                 |                        |
+---------v---------+    +---------v------+    +-----v------------+    +------v-----------+
| Headless & Server |    |  Web Runtime   |    |  Native Runtime  |    | Renderer Core    |
| `headless.dart`   |    | `src/web/**`   |    | `src/native/**`  |    | `vendor/pixeldart`|
| Software recorder |    | WebGL2 + Audio |    | SDL3 + GLES3 FFI |    | Graph, PBR, CSM, |
| + Dedicated Tick  |    | Context + Pad  |    | + PCM Audio + IO |    | Skinning, GI/2D  |
+-------------------+    +----------------+    +------------------+    +------------------+
```

### 2.2 Engineering Invariants Enforced on Every Phase

1. **Pure-Dart Core Boundary**: Files under `lib/src/engine/**` and `lib/gl_volition.dart` MUST NOT import `dart:io`, `dart:ffi`, `dart:isolate` (without conditional stub/adapter behind a host service), `package:web`, or `dart:js_interop`. This guarantees 100% deterministic VM unit tests, web portability, and headless server builds.
2. **Dual Native Parity (CI vs Hardware)**: Never delete software-recording graphics/device support when adding native FFI. Split clean adapters: a deterministic `RecordingGlesDevice` for VM/CI shader-command verification alongside hardware `RealGlesDevice` + SDL3 window/audio backends for desktop execution.
3. **Zero Silent Stubs in Ship Paths**: Any host or loader path that cannot operate on a given platform must either fail loudly at startup/init or advertise its exact capability bit cleanly in `DeviceCapabilities` / diagnostics — never silently drop audio, render frames, or return fabricated timer readings as production truth.
4. **Submodule Push Order**: `vendor/pixeldart`, `vendor/voxnet`, and sibling `vendor/*` packages are independent git submodules. Submodule changes must be tested inside the submodule first, committed/pushed upstream, and only then referenced by the root `gl_volition` superproject gitlink.
5. **Measurable Acceptance Gates**: Every phase completes with automated checks covering formatting, static analysis, boundary imports, VM tests, web compilation (`js` and `wasm` targets where applicable), native compilation, and runtime regression budgets.

---

## 3. Phased Continuation Roadmap (Phases 0–7 → Waves 8–15)

### Phase 0 (Wave 8) — Engineering Hygiene, CLI Fixes, Test Sharding & CI
- **Objective**: Establish fast, trustworthy automation before building new runtime backends.
- **Key Deliverables**:
  - Fix `bin/volition.dart` (`_runServe` using `_dartExecutable` instead of `Platform.resolvedExecutable`), remove `_EmptySpecResources.noSuchMethod` JS compiler hint in `component_spec_extra.dart:15`, and fix `README.md:28` (`--target wasm`).
  - Add static boundary checker (`tool/check_boundaries.dart`), unified verification script (`tool/verify_all.dart`), and `.github/workflows/ci.yml` running format checks, `dart analyze`, boundary verification, shader sync checks (`vendor/pixeldart/tools/renderer/shaders.dart --check`), root `dart test` + `vendor/pixeldart` (`tools/renderer/test_all.dart`, `tools/renderer/check_boundary.dart`, `tools/assets/*.dart`) + `vendor/voxnet` (`dart test`), and `dart compile js` / `dart compile exe` smoke builds.
  - Shard the 10,284-line `test/subsystems_test.dart` monolith by subsystem (`test/engine/`, `test/physics/`, `test/assets/`, `test/network/`, `test/serialization/`, `test/native/`) so workers and CI run targeted suites rapidly without merge conflicts.
- **Exit Criteria**: Green CI pipeline locally and in `.github/workflows/ci.yml`; repo formatted (`dart format --output=none --set-exit-if-changed .`); zero warnings/hints on `dart compile js`.

### Phase 1 (Wave 9) — Native Desktop OS Backend (SDL3 + GLES3/ANGLE + Audio + AOT Packaging)
- **Objective**: Turn native desktop builds from command-recording shells (and WinForms WebView2 wrappers) into genuine hardware-accelerated AOT executables while keeping software recording intact for VM tests.
- **Key Deliverables**:
  - Freeze native FFI service contracts (`SdlWindowBridge`, `GlProcBindings`, `NativeAudioSink`) before worker fan-out.
  - Implement real `dart:ffi` SDL3 bindings and event loop inside `native_ffi_transport.dart` (`window create/resize/destroy`, keyboard/mouse/gamepad/focus events, OpenGL/GLES3/ANGLE context creation and `swapBuffers`).
  - Implement hardware `RealGlesDevice` executing GL calls through resolved FFI pointers while renaming/retaining software `GlesDevice` / `RecordingGlesDevice` cleanly for headless VM assertions, removing hardcoded timer values on hardware paths in favor of real `GL_EXT_disjoint_timer_query` / timestamp polling.
  - Implement hardware PCM audio device replacing `SilentAudio` in native windowed runs (`NativeEngineHost` accepting pluggable audio backends: real hardware stream or headless `SilentAudio`).
  - Update `bin/volition.dart` and `dist.ps1` so `--target windows|linux|macos` builds standalone AOT native bundles (with SDL3/ANGLE runtime DLLs and `.pak`/assets) while moving the `.NET 10` `WebView2` wrapper (`Program.cs`) to an explicit `--target webview` mode.
- **Key Risks & Mitigations**: ANGLE / driver availability on Windows/Linux CI runners — mitigate by validating context probing in `volition doctor` / smoke harness and falling back cleanly or failing with actionable diagnostics on headless CI without GPU.
- **Exit Criteria**: `example/native_smoke/main.dart` opens a native window (when display available), compiles/links real shaders, renders frames > 0 FPS with real resize handling, and passes headless `RecordingGlesDevice` + hardware probe smoke checks.

### Phase 2 (Wave 10) — Complete Cross-Platform Host Contract (`Input`, Web Audio DSP, Multi-Camera, `visibilityMask`)
- **Objective**: Eliminate feature asymmetry across Headless, Web, and Native hosts and wire core camera/input/audio gameplay abstractions end-to-end.
- **Key Deliverables**:
  - **Pre-Wave Refactor/Freeze**: Split monolithic `lib/src/web/web_host.dart` into composable `web_input.dart`, `web_audio.dart`, and `web_graphics.dart` modules and extend `lib/src/engine/host.dart` (`Input` with wheel, multi-touch, pointer-lock deltas, gamepad axes/buttons, text input; `AudioDevice`/`AudioChannel` with spatial pan, lowpass cutoff, reverb send; `Graphics` with camera viewport rects & offscreen `RenderTargetHandle`). Patch `vendor/pixeldart` `PixeldartApp._frame` to forward `visibilityMask` to `sequencer.next(...)`.
  - **Input Parity**: Wire Web DOM wheel/touch/PointerLock/Gamepad APIs, Native SDL3 events, and `InputManagerComponent` virtual touch controls + action rebinding with cross-host parity tests.
  - **Live Spatial Audio & DSP**: Back `AudioReverbZone`, `AudioLowPassFilterComponent`, `AudioListener`, and `AudioMixer` with a real Web Audio API `AudioContext` graph (`StereoPannerNode`, `BiquadFilterNode`, `ConvolverNode`) on Web and real mixer filter/panning stages on Native.
  - **Multi-Camera & Viewport Pipeline**: Wire `Camera.normalizedViewportRect`, `Camera.depth`, clear flags, and render-to-texture through `Scene._syncToRenderer` and `Graphics` across Web and Native hosts (enabling minimaps, split-screen, and security cameras).
- **Exit Criteria**: Multi-camera split viewport, gamepad + pointer-lock input, layer visibility culling (`visibilityMask`), and spatial audio gain/pan/filter tests pass in Headless, Web compile, and Native VM parity suites.

### Phase 3 (Wave 11) — Production Asset Pipeline, `.pak` VFS Unification, Streaming & Scene Migrations
- **Objective**: Replace placeholder asset hooks and unversioned scene JSON with a unified, memory-bounded asset lifecycle and forward-compatible content serialization.
- **Key Deliverables**:
  - Implement binary `.glb` / `.qmesh` / image decoding directly from `VfsArchive` bytes inside `VfsAssetLoader.loadModel` (`pak_vfs.dart`), removing the `UnimplementedError` when `fallback == null`.
  - Add reference-counted asset lifetime management (`acquire`, `release`, `unload`, cache telemetry) to `AssetCatalog`, fix `ModelRenderer` spec registration (`component_spec_extra.dart:44-49`) to serialize/resolve real `AssetCatalog` asset IDs instead of dummy empty `ModelAsset`s, and bind `AudioSource` / `ParticleSystem` asset references cleanly.
  - Add `volition pack` bundling tool wired to `vendor/pixeldart`'s `ObjModelPackageEmitter` / `GltfModelPackageEmitter` / `ModelPackageValidator` / `ModelPackageLoader` (`vendor/pixeldart/lib/assets/**`), plus a real color-grading LUT asset loader (closing remaining asset tooling debt).
  - Introduce versioned `SceneMigrator` transformations in `scene_serializer.dart` (upgrading `schemaVersion = 1 -> N` cleanly instead of throwing `FormatException`), plus Isolate/async decode + frame-budgeted streaming queues so open worlds never hitch on asset loads.
- **Exit Criteria**: Scenes round-trip real model/audio/LUT asset references loaded strictly from `.pak` archives without loose disk files; `v1` fixture scenes migrate automatically to current schema; async asset stress test unloads and re-acquires assets without memory growth.

### Phase 4 (Wave 12) — Production Rendering Closure (`pixeldart` `R1–R7` + Skinning + GPU Component Wiring)
- **Objective**: Close every open renderer backlog item in `vendor/pixeldart`, ship GPU skeletal skinning, and connect existing CPU-only engine visual subsystems (`LightProbeGI`, `Lighting2D`, `SoftBodyXPbd`, `DrawBatcher`, `RenderGraph`) to real GPU execution.
- **Key Deliverables**:
  - **Renderer Core & Pipeline (`pixeldart`)**: Close remaining frame arena / batching / transient target gaps across `lib/rendering/core/**` and `webgl/**`; ensure all instanced draw paths leverage `InstanceBufferStream` beyond the 16-instance uniform cap; reconcile safe-graph shape; expose `R3` declared host graph-pass API cleanly; add stencil state, decal stage, vertex lighting, fixed low internal resolution, affine UV in textured/safe worlds, and soft particles.
  - **Shadows, Materials & Color (`pixeldart`)**: Expand directional-light & multi-caster shadow passes with capability-driven shadow resolution and front-face depth culling, material table capacity splitting, texture array groups, per-draw light selection & diagnostics, full `Linear / sRGB` audit, and alpha-mask x affine interaction fixture.
  - **Renderer Lab, Goldens & `Procession` Fix (`pixeldart` `R1–R7`)**: Extend `vendor/pixeldart/tools/renderer/run_shader_lab.mjs`, `vendor/pixeldart/web/renderer_test/`, and `vendor/pixeldart/.github/screenshots/` with 180-warmup / 600-measured frame telemetry (alloc, `no-black-frame`, culling/instancing pixel acceptance), fix dense-tree framing/draw budgets in root `example/procession/`, ratify performance budgets, validate `R4` anisotropy cost, `R5` MSAA resize/restore, and run `QMSH` through the real WebGL2 pipeline.
  - **GPU Skeletal Skinning (`gl_volition`)**: Parse GLB `skins` / `joints` / `inverseBindMatrices` / weights, extend `Animator` with bone-hierarchy blending + root motion, and upload skinning palettes to GPU shader attributes/uniforms.
  - **Wire Decoupled Render Components**: Feed `LightProbeVolumeComponent` SH3 irradiance into shader/renderer uniforms; render `Lighting2DComponent` / `ShadowCaster2DComponent` into 2D lightmap composition passes; upload `SoftBodyXpbdComponent` deformed vertex buffers dynamically; unify `DrawBatcherComponent` / `RenderGraphComponent` with live renderer submission.
- **Exit Criteria**: All `pixeldart` `R1–R7` and WebGL2 shader matrix checks pass in Browser Lab; rigged animated GLB character deforms on GPU; 2D lighting, soft-body mesh deformation, and GI probes visibly alter rendered frames.

### Phase 5 (Wave 13) — Scalable 3D Physics, True Colliders & Runtime Determinism
- **Objective**: Upgrade `PhysicsWorld` from an `O(N^2)` AABB/sphere toy solver into an authentic, broadphase-accelerated, deterministic rigidbody physics engine.
- **Key Deliverables**:
  - Refactor `lib/src/engine/components/physics.dart` cleanly across modular files (`physics_broadphase`, `physics_colliders`, `physics_solver`, `physics_world`) during pre-wave freeze.
  - Integrate spatial broadphase (`BroadphaseWorldComponent` / spatial hash / BVH) into `PhysicsWorld` step and `raycast` / `raycastAll` / `overlapSphere` / `overlapBox` / `sphereCast`.
  - Implement true SAT oriented bounding box (`BoxCollider` respecting rotation), BVH triangle `MeshCollider`, and grid `HeightfieldCollider` (terrain).
  - Add rotational `RigidBody` inertia tensors, angular velocity, torque/friction, body sleeping, mechanical joints/constraints, and swept continuous collision detection (CCD) inside `RigidBody._step()`.
  - Implement automated 600-frame deterministic fixed-step parity tests (`TODO.md` temporal determinism), live `reducedMotion` switching verification, photosensitivity/luminance flash gate, and visual-stability checks.
- **Exit Criteria**: 1,000+ static/dynamic colliders step comfortably within fixed-step budget; rotated boxes stack stably without AABB distortion; deterministic replay produces identical final state hashes across repeated headless runs.

### Phase 6 (Wave 14) — Real Multiplayer Networking (`voxnet` + Engine Sync)
- **Objective**: Enable genuine networked multiplayer across Web and Native targets with client prediction and rollback/reconciliation wired into `Engine.step`.
- **Key Deliverables**:
  - Add production `WebSocketNetTransport` (`package:web` WebSocket on Web, `dart:io` `WebSocket` on Native/Server) with TLS, session auth tokens, keepalive, and reconnect backoff inside `vendor/voxnet`.
  - Add native FFI UDP + sequenced reliable/unreliable multi-channel framing and packet-loss/latency simulation hooks inside `vendor/voxnet`.
  - Drive `NetworkManager` tick synchronization, state snapshot compression, entity interest/ownership, and rollback reconciliation automatically from `Engine.step`, proven via an automated multi-client networked test harness under synthetic jitter and 10% packet loss.
- **Exit Criteria**: Two independent client instances + headless server synchronize entity state over real loopback `ws://` and UDP sockets cleanly under simulated latency/loss without desync.

### Phase 7 (Wave 15) — Production Editor UX, Diagnostics & Ship Tooling
- **Objective**: Polish developer productivity, live debugging telemetry, and multi-target distribution into a cohesive studio toolset.
- **Key Deliverables**:
  - Replace full-scene JSON snapshots in `EditorSession._captureHistoryEntry` with compact reversible `EditorCommand` property/hierarchy deltas.
  - Unify editor interaction between `EngineWorkbenchComponent` (`voxui`) and `InspectorOverlay`: live 3D translate/rotate/scale viewport gizmos with raycast drag handles, `AssetCatalog` visual browser + drag/select assignment, and prefab variant override inspection.
  - Ship full frame/memory/transient diagnostics snapshot JSON, `volition create <template>` scaffolding, `volition doctor` toolchain/GPU capability verifier, dedicated `--target server` minimal runtime build, crash/panic reporting hook, and ratify standalone package publication (`publish_to` split if desired).
- **Exit Criteria**: Editing 1,000-object scenes with gizmos and undo/redo incurs sub-millisecond delta memory overhead; `volition doctor` accurately verifies SDK, SDL3/GLES, and build toolchains; `volition create && volition test && volition build` succeeds end-to-end.

---

## 4. Subagent Execution & Orchestration Protocol

`TODO.md` decomposes Phases 0–7 into **Waves 8–15** specifically structured for parallel multi-agent execution:

1. **Pre-Wave Interface Freeze (`[Px-Wy-0]`)**: Before launching parallel workers in a wave, the Coordinator edits shared hubs/interfaces (`host.dart`, `engine.dart`, module extraction splits, or contract header files), compiles `dart analyze`, and locks those interfaces.
2. **Strict Disjoint File Ownership (`Owns:`)**: Concurrent workers in the same wave NEVER touch overlapping files. Whenever two tasks need to wire into a shared file (such as `lib/gl_volition.dart`, `lib/src/engine.dart`, `pubspec.yaml`, or `native_host.dart`), the worker builds behind its owned file/adapter and the Coordinator performs the minimal barrel/wireup edit during post-wave merge.
3. **Coordinator-Locked Files (Do Not Touch Inside Worker Tasks)**:
   - `pubspec.yaml`, `.gitmodules`, `PLAN.md`, `TODO.md`, `ENGINE.md`
   - `lib/gl_volition.dart`, `lib/gl_volition_web.dart`, `lib/gl_volition_native.dart`
   - `lib/src/engine.dart`, `lib/src/engine/serialization/component_spec.dart`, `tool/generate_logos.dart`
   - `.github/workflows/*` (outside dedicated CI worker W8-B)
   - Studio Track hubs: `lib/src/studio/protocol/**`, `lib/src/studio/studio.dart` (barrel), `tool/studio/studio_bundle.g.dart`, `vendor/pixeldart/lib/rendering/webgl/device_api.dart` (outside `[Sx-0]` freezes)
   - Root git commits / `vendor/*` gitlink updates (Coordinator-only after verifying submodule clean state)
4. **Mandatory Worker Report & Verification**:
   - Every worker ends with exact changed paths, exported symbols, edge cases/caveats, and output of `dart analyze`, targeted `dart test <suite>`, and any compile/boundary check required by `DoneWhen`.
   - Subagents never run `git commit`. Coordinator validates integrated wave gates before advancing to Wave `N+1`.

---

## 5. Architecture Decision Record (ADR): Package Publication & Distribution Strategy

### Status
Accepted & Ratified (Wave 15)

### Context
`gl_volition` orchestrates a large ecosystem:
1. Core engine (`gl_volition`): Pure-Dart ECS, Scene, Physics, Assets, Prefabs, Editor commands, Viewport gizmos, UI, Diagnostics.
2. Platform hosts: Native desktop runtime (`NativeEngineHost`, SDL3/GLES3 FFI), Web runtime (`WebEngineHost`, WebGL2, Web Audio DSP), Headless/Server (`DedicatedServerHost`).
3. Core rendering engine (`vendor/pixeldart`): Host-decoupled Forward+ WebGL2/GLES renderer, GPU skinning, RenderGraph, shaders, shadows, decals, post-processing.
4. Modular sub-ecosystem (`vendor/vox*`): 74 focused libraries (`voxecs`, `voxui`, `voxnet`, `voxphysics`, `voxai`, `voxaudio`, `voxbiome`, etc.).

### Decision: Monorepo Orchestration with Independent Multi-Package Distribution (`publish_to: none` Root)
1. **Root Engine (`gl_volition`): `publish_to: none` Monorepo Aggregator**
   - The root repository remains an integrated game engine distribution, toolchain (`volition` CLI), workspace, and sample lab (`example/**`).
   - Retaining `publish_to: none` at the superproject root prevents accidental publishing of monolithic, non-portable workspace paths or local path dependencies.
2. **First-Class Sub-Packages for `pub.dev`**:
   - `pixeldart`: Published as a standalone, host-decoupled WebGL2 / GLES3 3D renderer for any Dart/Flutter application.
   - `voxnet`: Published as a standalone cross-platform transport & state replication engine (WebSocket, UDP, reliable sequencing, delta compression).
   - `voxui`: Published as a standalone immediate/retained-mode 2D GUI & layout library.
   - `voxecs` / `voxai` / `voxaudio`: Published independently as modular pure-Dart game development packages with zero external host dependencies.
3. **Application Distribution via `volition` CLI**:
   - Games built with `glVolition` distribute via `volition build --target <web|windows|linux|macos|server>`, emitting optimized AOT binaries or minified Web bundles without requiring individual sub-package pub dependencies for end players.

---

## 6. Production Milestone Completion & Release Sign-Off

> **2026-11-20 re-audit:** Several Wave 12 renderer claims below do not hold in the current tree (16-instance uniform arrays, 64-joint palette, single shadow map, no HDR targets/cubemaps/UBOs). See [§13.1](#131-ground-truth-re-audit-2026-11-20); the debt is reopened on the Studio Track as `[S1-B]` (instancing/skinning caps) and Phases `S3`–`S4` (lights, shadows, HDR, IBL).

All planned milestones across Phases 0 through 7 (Waves 8 through 15) are **100% Complete and Formally Verified**:
- **Phase 0 (Wave 8)**: Engineering hygiene, `tool/check_boundaries.dart`, test sharding, and CI verification pipeline.
- **Phase 1 (Wave 9)**: Native desktop OS runtime, SDL3/GLES3 FFI window/event pump, hardware PCM audio, and standalone AOT packaging.
- **Phase 2 (Wave 10)**: Cross-platform host contract parity (Web DOM wheel/touch/gamepad, Web Audio DSP graph, multi-camera split viewports, render-to-texture, and layer visibility masks).
- **Phase 3 (Wave 11)**: Production asset pipeline, `.pak` VFS direct binary decoders (.glb/.qmesh), ref-counted `AssetCatalog`, and versioned scene schema migration.
- **Phase 4 (Wave 12)**: PixelDart Forward+ WebGL2 hardware renderer, GPU joint skinning, stencil decals, multi-caster cascaded shadows, and Browser Lab golden budget ratification.
- **Phase 5 (Wave 13)**: Production physics engine (spatial broadphase, true SAT OBB, BVH triangle meshes, heightfields, rotational inertia solver, joints, sleeping, swept TOI CCD, and 600-frame temporal determinism).
- **Phase 6 (Wave 14)**: Cross-platform multiplayer networking (`voxnet` WebSocket + native UDP reliable transport channels, client prediction, delta compression, and rollback reconciliation).
- **Phase 7 (Wave 15)**: Production editor UX (compact `EditorCommand` delta undo/redo, 3D viewport transform gizmos, prefab variant UI), runtime telemetry & diagnostics snapshot, `DedicatedServerHost`, and `volition doctor`/`create`/`--target server` CLI.

Verified clean on Dart 3.14.0 across unified test suites (382 root tests, 140 pixeldart test scripts, 33 voxnet tests), 100% boundary compliance (0 violations on 154 scanned files), 0 analyzer issues, and 10/10 performance budget compliance on `tool/renderer_bench.dart`.

---

## 7. Phase 8 (Wave 16) — Volition Studio GUI (`volition gui`)

- **Objective**: Provide a cross-platform graphical Studio interface for the `volition` CLI (`doctor`, `create`, `build`, `dist`, `pack`, `serve`, `test`, `verify_all`, `renderer_bench`), backed by a shared service layer so CLI and GUI share 100% of build/pack/diagnostic logic.
- **Key Deliverables**:
  - Extract structured `VolitionCliService` (`tool/cli_service.dart`) returning typed reports (`DoctorReport`) and cancelable streaming task sessions (`CliTaskSession`).
  - Implement local HTTP + WebSocket RPC daemon (`tool/cli_gui_server.dart`) serving the embedded Studio SPA (`tool/cli_gui_assets.dart`) with real-time `stdout`/`stderr` streaming and live dev-server control.
  - Wire `volition gui [--port <p>] [--no-open]` into `bin/volition.dart` (launching browser app-mode or headless server).
  - Verify via automated unit/RPC integration tests (`test/engine/cli_gui_test.dart`) and `tool/verify_all.dart`.

---

## 8. Phase 9 (Wave 17) — Indexed Scene Queries, Deterministic Input Replay, Multi-Selection Editor & Studio Inspector

- **Objective**: Eliminate remaining $O(N)$ scene lookups during gameplay and rendering, establish bit-exact cross-platform input replay verification, upgrade `EditorSession` to full multi-object workflows, and expose live `.pak` / `scene.json` artifact inspection in Volition Studio and CLI tooling.
- **Key Deliverables**:
  - **Indexed Scene Graph & Archetype Queries (`[P9-W17-A]`)**: Maintain live `_objectsByTag` and `_nodeOwners` indexes on `Scene`, typed `query<A>`, `query2<A, B>`, `query3<A, B, C>` iterators with layer mask filtering, and direct typed component lists in `_syncToRenderer` avoiding full `_behaviours` walks.
  - **Deterministic Input Replay Tapes (`[P9-W17-B]`)**: Implement `InputFrameSample`, `InputTape`, `InputTapeRecorder`, `ReplayInputDriver`, 53-bit `SceneStateHasher`, and `EngineReplayHarness` in `lib/src/engine/replay/input_tape.dart` for zero-drift cross-platform regression verification.
  - **Multi-Selection Editor UX & Batch Commands (`[P9-W17-C]`)**: Upgrade `EditorSession` with `select` (additive/toggle), `selectAll`, `selectionCentroid`, `selectionWorldBounds`, `focusSelection`, and `searchHierarchy`, plus undoable `BatchTransformDeltaCommand`, `BatchSetActiveCommand`, and `BatchDeleteCommand`.
  - **Studio `.pak` / Scene Inspector & Unified CLI (`[P9-W17-D]`)**: Add `discoverInspectableFiles` / `inspectArtifact` and WebSocket RPC (`inspector.list`, `inspector.inspect`) to Volition Studio, route `volition doctor [--json]` through `VolitionCliService`, and generate ready-to-serve `index.html` shells in `volition create`.

---

## 9. Phase 10 (Wave 18) — Advanced 3D Viewport Gizmos, Additive Sub-Scenes & Integrity Save Bundles, Live Prefab Diff/Propagation & CLI/Studio Replay Runner

- **Objective**: Elevate editor, persistence, scene streaming, and regression-testing ergonomics across pure-Dart engine subsystems and CLI/Studio tooling via strictly disjoint parallel subagent execution.
- **Key Deliverables**:
  - **Advanced 3D Viewport Gizmos (`[P10-W18-A]`)**: Add `ViewportGizmoSpace` (`world`/`local`), planar dual-axis quad handles (`xy`/`xz`/`yz`), and multi-selection pivot drag (`beginSelectionDrag`/`updateSelectionDrag`/`endSelectionDrag` returning reversible `CompoundCommand`) to `ViewportGizmos`.
  - **Additive Sub-Scenes & Integrity Save Bundles (`[P10-W18-B]`)**: Extend `SceneManager` with `loadAdditive`/`unloadAdditive`/`isAdditiveLoaded` and `SaveSystem` with CRC32 integrity verification (`verifySlotIntegrity`), `loadDataMigrated`, and signed `exportSlotBundle`/`importSlotBundle`.
  - **Live Prefab Diffing & Hot-Propagation (`[P10-W18-C]`)**: Auto-attach `PrefabInstanceComponent` in `PrefabRegistry.instantiate`, implement `computeInstanceOverrides`/`extractVariantFromInstance`, and add live `propagatePrefabChanges` preserving per-instance transforms and field overrides.
  - **Headless Replay CLI & Studio Verification (`[P10-W18-D]`)**: Support `InputTape` inspection (`discoverInspectableFiles()['tapes']`), `verifyInputTapeFile`, WebSocket RPC `tape.verify`, Studio UI tape verification button, and `volition replay <tape.json> [--json]`.

---

## 10. Phase 11 (Wave 19) — Rebindable Input Profiles, Prioritized Events & Composable Coroutines, Runtime Dev Console & Scoped Frame Profiler

- **Objective**: Round out core gameplay-scripting and live-debugging ergonomics with customizable keyboard+gamepad input profiles, priority/deferred scene events, composable coroutines, an extensible developer command console, and real `Stopwatch`-measured sub-frame profiler spans.
- **Key Deliverables**:
  - **Input Rebinding & Gamepad Profiles (`[P11-W19-A]`)**: Extend `InputActions` (`lib/src/engine/input_actions.dart`) with gamepad button/axis bindings, configurable deadzones, runtime `rebindButton`/`rebindAxis`, and JSON / `KeyValueStore` profile persistence.
  - **Prioritized Events & Composable Coroutines (`[P11-W19-B]`)**: Extend `SceneEvents` with priority ordering, `once<E>`, `emitDeferred<E>`/`flushDeferred()`, and `listenerCount<E>()`; add `WaitWhile`, `WaitForFrames`, and `WaitForCoroutine` yield instructions (`lib/src/engine/events_coroutines.dart`).
  - **Runtime Developer Console (`[P11-W19-C]`)**: Add `DebugConsole` and built-in engine commands (`help`, `stats`, `pause`, `resume`, `timescale`, `entities`, `tp`, `active`, `clear`) with quoted-arg parsing, history, and prefix autocompletion on `DebugController` (`lib/src/engine/debug_controller.dart`).
  - **Scoped Sub-Frame Profiler Spans (`[P11-W19-D]`)**: Add real `Stopwatch`-backed `beginSpan`/`endSpan`/`measureSpan` and `exportTelemetryJson()` to `FrameProfilerComponent` (`lib/src/engine/components/frame_profiler.dart`).

---

## 11. Phase 12 (Wave 20) — Game-Feel & Core Runtime Ergonomics (Hitstop Clock, Guarded FSM, AudioMixer Snapshots/Ducking & Tween Sequences)

- **Objective**: Deliver high-leverage game-feel primitives across timing, state machines, audio mixing, and coroutine animation without adding platform dependencies.
- **Key Deliverables**:
  - **Hitstop / Freeze-Frame Clock (`[P12-W20-A]`)**: Add `triggerHitstop()`, `cancelHitstop()`, `isInHitstop`, and `hitstopRemaining` to `Time` (`lib/src/engine/time.dart`) preserving underlying `timeScale`.
  - **Guarded, Triggered & Timed `StateMachine<S>` (`[P12-W20-B]`)**: Add `addTransition`, `addAnyTransition`, `addTrigger`, `fireTrigger`, and `revertToPreviousState` (`lib/src/engine/state_machine.dart`).
  - **AudioMixer Snapshots & Bus Ducking (`[P12-W20-C]`)**: Add `AudioMixerSnapshot`, `defineSnapshot`, `captureSnapshot`, `applySnapshot` with smooth interpolation, and `duckBus` (`lib/src/engine/components/audio_source.dart`, stepped automatically in `Scene._syncToRenderer`).
  - **Rotation, Color & Sequence Tweens (`[P12-W20-D]`)**: Add `tweenRotation`, `tweenColor`, and `tweenSequence` on `BehaviourTweenExt` (`lib/src/engine/tween.dart`).

---

## 12. Phase 13 (Wave 21) — Platformer-Grade CharacterController, Exact 2D Spatial Queries & Camera Batch Frustum Culling

- **Objective**: Strengthen 3D character movement feel, 2D spatial query precision/performance, and single-pass camera frustum culling.
- **Key Deliverables**:
  - **Platformer-Grade `CharacterController` (`[P13-W21-A]`)**: Add `coyoteTime`, `jumpBufferTime`, `queueJump()`, `consumeBufferedJump()`, `groundNormal`, `groundObject`, and automatic moving-platform carry delta (`lib/src/engine/components/character_controller.dart`).
  - **Exact 2D Spatial Queries & Raycast (`[P13-W21-B]`)**: Add cell-coherent `update()`, `queryCircleExact()`, `findNearest()`, and DDA `queryRay()` to `SpatialGrid2D` (`lib/src/engine/spatial_grid_2d.dart`).
  - **Single-Pass Camera Frustum Batching (`[P13-W21-C]`)**: Add `isPointVisible()`, `isAabbVisible()`, and `collectVisibleMeshes()` honoring `cullingMask` with a single frustum extraction per frame (`lib/src/engine/components/camera.dart`).

---

## 13. Phase 14 (Wave 22) — Animation Event Markers, Anti-Popping LOD Hysteresis & Timed Particle Burst Schedules

- **Objective**: Complete key visual-gameplay synchronization features: timestamped animation events, hysteresis-stabilized LOD tiers, and scheduled particle burst timelines.
- **Key Deliverables**:
  - **Animation Event Markers (`[P14-W22-A]`)**: Add `AnimationEventMarker`, `SkeletalClip.events`, `Animator.addClipEvent()`, and `Animator.onEvent()` firing accurately across normal and looped playback (`lib/src/engine/components/animator.dart`).
  - **LOD Hysteresis, Quality Bias & Forced Override (`[P14-W22-B]`)**: Extend `LodGroup` with `hysteresis`, `lodBias`, and `forcedLevelIndex` (`lib/src/engine/components/lod_billboard.dart`).
  - **Timed Particle Burst Schedules (`[P14-W22-C]`)**: Add `ParticleBurst`, `play()`/`pause()`/`stop()`, and automatic burst timeline firing on `ParticleSystem` (`lib/src/engine/components/particle_system.dart`, stepped in `Scene._syncToRenderer`).

---

## 13. Phase 14 (Wave 22) — Animation Event Markers, Anti-Popping LOD Hysteresis & Timed Particle Burst Schedules

- **Objective**: Complete key visual-gameplay synchronization features: timestamped animation events, hysteresis-stabilized LOD tiers, and scheduled particle burst timelines.
- **Key Deliverables**:
  - **Animation Event Markers (`[P14-W22-A]`)**: Add `AnimationEventMarker`, `SkeletalClip.events`, `Animator.addClipEvent()`, and `Animator.onEvent()` firing accurately across normal and looped playback (`lib/src/engine/components/animator.dart`).
  - **LOD Hysteresis, Quality Bias & Forced Override (`[P14-W22-B]`)**: Extend `LodGroup` with `hysteresis`, `lodBias`, and `forcedLevelIndex` (`lib/src/engine/components/lod_billboard.dart`).
  - **Timed Particle Burst Schedules (`[P14-W22-C]`)**: Add `ParticleBurst`, `play()`/`pause()`/`stop()`, and automatic burst timeline firing on `ParticleSystem` (`lib/src/engine/components/particle_system.dart`, stepped in `Scene._syncToRenderer`).

---

## 13. Unity-Class Engine Roadmap — Volition Studio Track (Phases `S1`–`S8`)

> **North star:** *Volition Studio (`volition gui`) plus the `volition` CLI is the product.* It is where every `vendor/*` submodule comes together: each runtime module is authored, inspected, previewed, profiled, and shipped from Studio, and every Studio action has a headless CLI twin. The renderer (`vendor/pixeldart`) is upgraded in step to a URP-class pipeline so the Scene and Game views can show production lighting.
>
> **Track IDs:** This roadmap runs as its own wave sequence (`S1`…`S8`, task IDs `[Sx-y]`) so it does not collide with the numbered gameplay waves (`[Px-Wy-z]`). Numbered waves may run alongside it only when their `Owns` sets are disjoint; the Coordinator schedules the interleaving.

### 13.1 Ground-Truth Re-Audit (2026-11-20)

Before this roadmap was written, the tree was checked directly against the "100% complete" sign-off in §6. These claims do not hold and are reopened:

| Claim (task) | Evidence in tree | Consequence |
| --- | --- | --- |
| 16-instance uniform cap removed, `>1024` instances per draw (`[P4-W12-B2]`) | `vendor/pixeldart/shaders/rendering/world/shadowed_world.vert:13-14` declares `uniform mat4 uInstanceModels[16]` / `uInstanceNormalMatrices[16]`, indexed by `gl_InstanceID` at `:39` | Lit/shadowed instanced draws still cap at 16 per call |
| GPU skinning shipped (`[P4-W12-C]`) | `shadowed_world.vert:25` `uniform mat4 uJointMatrices[64]` | 64-joint ceiling and heavy uniform pressure; typical humanoid rigs with fingers exceed it |
| Multi-caster / cascaded shadows (`[P4-W12-B2]`, §6) | One `uShadowMap` sampler (`shadowed_world.frag:18`); `RuntimeLightBudget.shadowMaps = 1` (`lib/rendering/api/lights.dart:189`); `cascade` appears in no shader | One shadowed spot light; directional CSM exists only as CPU math (`cascaded_shadow_rig.dart`, `optics/cascade_splits.dart`) |
| "Forward+" lighting | `RuntimeLightBudget`: 1 directional, 4 point, 3 unshadowed + 1 shadowed spot; one named uniform per light (`shadowed_world.frag:28-70`) | Fixed per-object forward lighting, no clustering |
| HDR / IBL / modern GPU features | Zero hits in `lib/` or `shaders/` for `RGBA16F`, `samplerCube`/`TEXTURE_CUBE`, uniform blocks (`UNIFORM_BUFFER`/`bindBufferBase`), `sampler2DArray`, occlusion queries; reflections are the flat `uReflectionColor` uniform (`shadowed_world.frag:75-77`) | LDR pipeline with no environment lighting; `texture_array_group.dart` has no shader consumer |
| Studio = editor (`[P8-W16-*]`, `[P9-W17-D]`) | `tool/cli_gui_assets.dart` is a 717-line embedded HTML/JS SPA; RPC surface is task runners only (`doctor.run`, `build.run`, `pack.run`, `test.run`, `inspector.*`, `tape.verify`, `serve.*`) | No Scene view, Hierarchy, Inspector, Project window, or play-mode UI |
| Asset identity | No GUID or meta-sidecar concept anywhere in `lib/` | Scene/prefab references are path or key strings; renaming or moving an asset breaks scenes |
| Submodule integration | All 74 `vendor/*` packages are imported by about 2 root files each (component wrapper + barrel) | Every module is runtime-only; none has an inspector, gizmo, create-menu entry, sample, or editor window |

**Process fix (Invariant 10 below):** A Studio Track `DoneWhen` must be satisfiable only by the real behavior. Each removed limit gets a source-level anti-regression check (for example, a test that fails if any world/shadow/depth shader declares a fixed `uniform mat4 …[N]` array). Each visual feature gets a Browser Lab golden, plus a native readback golden where hardware is available.

### 13.2 Unity → glVolition Concept Map

| Unity | glVolition target | Status → Phase |
| --- | --- | --- |
| Unity Editor | **Volition Studio** (`volition gui`, Dart-compiled web shell, optional native window) | Dashboard only → `S2`, `S7`, `S8` |
| Batch mode / `-executeMethod` | `volition <cmd>` + `volition rpc <method>` (every Studio op) | Partial → `S2-M` parity gate |
| GameObject / Component / MonoBehaviour lifecycle | `GameObject` / `Component` / `Behaviour` (`awake`, `onEnable`, `start`, `fixedUpdate`, `update`, `lateUpdate`, triggers, pointer events) | ✅ exists |
| `[SerializeField]`, `[Range]`, `[Header]`, `[RequireComponent]` | `@Serialized`, `@Range`, `@Header`, `@RequireComponent` annotations + `volition codegen` → `ComponentSpec` | Hand-written specs → `S5` |
| Asset Database, `.meta`, Library | `AssetDatabase`, `.vmeta` GUID sidecars, `.volition/library/` import cache | Missing → `S1-C` |
| ScriptableObject | `DataAsset` (`.vasset`, GUID-referenced, inspector-editable) | Missing → `S5-0` |
| Prefabs, nested prefabs, variants, Prefab Mode | `Prefab`, `PrefabRegistry`, live propagation (exists) + nesting + isolation stage | Flat → `S5-D` |
| Package Manager | Studio Module Registry over `vendor/*` (enable/disable per project, version, maturity) | Missing → `S1-D`, `S6` |
| URP | **Volition Render Pipeline (VRP)** in `vendor/pixeldart`: clustered Forward+, CSM + shadow atlas, HDR, IBL, probes, lightmaps, post v2 | LDR fixed forward → `S1`, `S3`, `S4` |
| Animator / Animation / Timeline windows | Animator controller graph, dopesheet/curves, timeline over `voxanim`/`voxblend`/`voxseq` | Runtime only → `S7-A` |
| Visual scripting / graph tools | Node-graph framework over `voxgraph` (flow graph, dialogue, HTN, circuits, rules) | Runtime only → `S7-B` |
| Terrain, NavMesh, Tile Palette, Sprite Editor, UI Builder | `S7-C`/`S7-D`/`S7-E` world, 2D and UI tools | Runtime only → `S7` |
| Profiler, Frame Debugger, player connection | Player Link protocol + Studio Profiler/Frame Debugger | Local spans only → `S8-A` |
| Build Profiles, scenes in build, stripping | Build profiles in project, reachability-stripped `.pak`, module tree-shaking | Per-command flags → `S8-B` |

### 13.3 Additional Invariants (extending §2.2)

6. **Studio ⇄ CLI parity**: Every Studio action is a `VolitionCliService`/`StudioDaemon` operation, and every operation is reachable headlessly (`volition <cmd>` or `volition rpc <method> --json`). `test/studio/cli_parity_test.dart` enumerates the RPC registry and fails on any method without a CLI path.
7. **Module coverage**: Every `vendor/*` package registers a `StudioModuleDescriptor`. `tool/check_module_coverage.dart` (wired into `verify_all.dart`) fails if a package is missing or below its declared minimum maturity (`runtime-only` → `inspectable` → `editor-tooled`).
8. **Editor layering**: Editor models live in `lib/src/studio/**` (pure Dart, same import bans as `lib/src/engine/**`, enforced by `tool/check_boundaries.dart`). DOM UI lives in `lib/src/web/studio/**`. Disk, process, compiler and isolate work lives in `tool/studio/**`. The engine core never imports `lib/src/studio/**`.
9. **GUID references**: Serialized scenes, prefabs, materials and data assets reference assets by GUID. Paths appear only in `.vmeta` files and the database index. Schema bumps ship with a `SceneMigrationStep` that converts path keys to GUIDs.
10. **Evidence-based completion**: Renderer and editor tasks close only with (a) an anti-regression source or behavior check for each removed limit, (b) a Browser Lab golden (SSIM-gated) for visual changes, (c) a native `Gles3FfiDevice` readback golden when a GPU is available (otherwise reported as skipped, never as passing), and (d) a measured number, not an estimate, for any performance claim.

### 13.4 Target Topology

```
  volition CLI ────────────────┐            ┌──────── Volition Studio (browser / app window)
                               v            v
            VolitionCliService + StudioDaemon  (tool/studio/**, dart:io)
            project FS · AssetDatabase + importers · codegen · hot reload
            lightmap baker · builds · player link hub
                               │   Studio Protocol v2 (typed, versioned: lib/src/studio/protocol)
                               v
     Studio shell (lib/src/web/studio/**)   Scene · Game · Hierarchy · Inspector · Project
                                            Console · Lighting · Profiler · module windows
                               │   EditorHostBridge (selection, commands, picking, play state)
                               v
     Engine core (lib/src/engine/**) + editor models (lib/src/studio/**, pure Dart)
                               │   Graphics contract (host.dart)
                               v
     pixeldart VRP: lit uber-shader + variants · clustered Forward+ · CSM + shadow atlas
                    HDR + exposure + tonemap · IBL + reflection/light probes · lightmaps
                    TAA / SSR / GTAO / motion vectors · editor passes (grid, gizmos, ID pick)
                               │   device_api v2 (UBO, cubemap, tex arrays, float RT, MRT, queries)
                               v
              WebGL2 device   |   Gles3FfiDevice (SDL3/ANGLE)   |   RecordingGlesDevice (CI)
```

### 13.5 Renderer Upgrade Specification (VRP)

| Area | Today | VRP target | Phase |
| --- | --- | --- | --- |
| GPU data path | Per-draw named uniforms, 16-slot instance arrays | std140 UBOs (frame/camera/lights/material), instanced vertex attributes everywhere, material UBO caching | `S1-A`, `S1-B`, `S4-E` |
| Skinning | 64-joint uniform array | 256-joint UBO palette, float-texture fallback, skinned shadow/depth passes | `S1-B` |
| Shaders | 3 separate world shaders (`safe`/`textured`/`shadowed`) | One lit uber-shader with keyword variants (normal/ORM/emissive/skinned/instanced/alpha-test/shadow mode/PS1-affine), variant cache, warmup lists, `#include` support | `S3-0`, `S3-A` |
| BRDF | Ad-hoc | GGX + height-correlated Smith + Schlick, energy-conserving multi-scatter approximation, clearcoat | `S3-A` |
| Lights | 1 dir + 4 point + 4 spot | Clustered Forward+ (froxel grid, e.g. 16×9×24), ≥256 visible punctual lights, per-tier caps from settings | `S3-B` |
| Shadows | 1 spot map | Directional CSM (2–4 cascades, texel-snapped, blended), spot + point shadow atlas, priority-based resolution, PCF and optional PCSS, normal-offset bias | `S3-C` |
| Color | LDR + LUT grade | RGBA16F scene color (capability fallback), EV100 physical exposure + auto-exposure, ACES/AgX/Neutral tonemappers, HDR bloom, end-to-end linear audit | `S3-D` |
| Environment | Flat reflection color | Cubemap/procedural skybox, GGX-prefiltered specular, BRDF LUT, SH9 ambient | `S4-A` |
| GI | CPU SH probes wired as uniforms | Reflection probes (box-projected, blended), light-probe SH per object, progressive CPU lightmapper with UV2 packing and denoise | `S4-B`, `S4-C` |
| Post | Bloom, SSAO, DoF, LUT, PS1, VHS, volumetrics | Motion vectors, TAA, SSR (Hi-Z), GTAO, motion blur, Volume framework (global/local, priority, blend distance) | `S4-D` |
| Materials | `MaterialDefinition` in code | `.vmat` assets, `MaterialPropertyBlock`, render queues (2000/2450/3000), sorting layers, transparent sorting | `S4-0`, `S4-E` |
| Editor rendering | None | Scene-view camera, grid, gizmo/icon overlay, ID-buffer picking, selection outline, shading modes, offscreen thumbnails | `S2-B`, `S2-D` |
| Profiling | CPU spans | Per-declared-pass GPU timer queries, frame debugger with intermediate target readback | `S8-A` |

**Backend decision (ADR-3, §13.9):** Keep WebGL2/GLES 3.0 (one GLSL ES 3.00 source tree) as the baseline. Use clustered Forward+ rather than deferred, to keep MSAA, transparency, and web/mobile bandwidth friendly. WebGPU is a later `device_api` backend and is out of scope for `S1`–`S8`.

### 13.6 Phase Breakdown

#### Phase S1 — Ground-Truth Debt Closure & Foundations (GPU Device v2, GUID Assets, Module Registry)
- **Objective**: Close the reopened renderer debt and lay the three foundations everything else depends on: a modern GPU device API, GUID-based asset identity, and an inventory of all 74 modules.
- **Key Deliverables**: device API v2 (UBOs, cubemaps, texture arrays, half-float targets, MRT, instanced divisors, occlusion queries) on WebGL2, `Gles3FfiDevice` and `RecordingGlesDevice`; uncapped instancing and a 256-joint palette; `volition.project.json` + `.vmeta` + `AssetDatabase` with an incremental import cache; `StudioModuleDescriptor` registry and coverage gate; Studio Protocol v2 envelopes; boundary checker extended to `lib/src/studio/**`.
- **Exit Criteria**: Anti-cap test proves no fixed `uniform mat4 …[N]` in world/shadow/depth shaders; a 4,096-instance draw is one call; a 200-joint rig skins correctly; renaming an asset keeps every scene reference; the coverage report lists 74/74 modules.

#### Phase S2 — Volition Studio Editor Shell (Scene · Game · Hierarchy · Inspector · Project · Console · Play Mode)
- **Objective**: Turn Studio from a CLI dashboard into a real editor with the core Unity panels, running the actual engine in-page.
- **Key Deliverables**: Dart-compiled Studio shell (docking, menus, toolbar) embedded into the AOT `volition` binary; Scene view (editor camera, grid, gizmos, ID-buffer picking, selection outline, shading modes) and Game view; Hierarchy (reparent, search, multi-select); ComponentSpec-driven Inspector (typed field editors, add component, multi-edit, prefab overrides); Project window (GUID browser, thumbnails, drag-and-drop, import settings); Console (voxlog + errors, file:line click-through); play/pause/step with snapshot restore; GUID scene save; Studio e2e harness; CLI parity gate.
- **Exit Criteria**: The scripted Studio e2e flow passes in headless Chromium: open project → select via click → gizmo move → add component → drag material → play/stop restores state → save → reload is byte-equal. Opening a 1,000-object scene is interactive within 2 s, and an inspector edit round-trips in under 16 ms (measured).

#### Phase S3 — VRP Lighting, Shadows & HDR
- **Objective**: Replace fixed forward lighting with a URP-class lit pipeline.
- **Key Deliverables**: lit uber-shader with variants and `#include`; clustered Forward+ lights; directional CSM plus spot/point shadow atlas; HDR scene color, exposure and tonemapping; render pipeline settings asset with quality tiers; Studio Lighting/Quality windows and light gizmos.
- **Exit Criteria**: Browser Lab "VRP lights" scene (256 point lights, 4-cascade sun, 8 shadowed spots) matches goldens. Frame time at 1080p on the reference machine recorded in `tool/renderer_bench.dart` is ≤ 16.6 ms (measured, web and native). Linear audit readback values sit within tolerance.

#### Phase S4 — Environment, GI, Materials & Post-Processing v2
- **Objective**: Give scenes believable environment lighting, baked GI, and a modern post stack, all driven by assets authored in Studio.
- **Key Deliverables**: skybox and IBL (prefiltered specular, BRDF LUT, SH ambient); reflection probes and per-object light-probe SH; progressive lightmapper with UV2 packing (daemon-side, isolates); motion vectors, TAA, SSR, GTAO and motion blur under a Volume framework; `.vmat` materials, `MaterialPropertyBlock`, render queues and sorting layers; Material inspector with live preview.
- **Exit Criteria**: A metallic sphere reflects its environment probe; a baked lightmap scene matches its golden; TAA gives a stable golden across 600 frames; editing a `.vmat` updates every user live in the Scene view.

#### Phase S5 — Scripting Workflow & Editor Extensibility
- **Objective**: Make writing gameplay code feel like Unity: annotate a field, see it in the inspector, edit code, and see the change without losing editor state.
- **Key Deliverables**: serialization annotations and `volition codegen` (analyzer-based `ComponentSpec` generation, watch mode); hot-reload loop (in-Studio player recompile + state-preserving reload; native VM-service reload); `@ExecuteInEditMode`; EditorExtension API (custom inspectors, gizmo drawers, menu items, editor windows, importers); `DataAsset`; nested prefabs and Prefab Mode.
- **Exit Criteria**: Adding `@Serialized @Range(0, 10) double speed` shows a slider with no hand-written spec. Edit-to-visible time on the sample project is measured and reported, with a 3 s target. Editor state (scene, selection, camera) survives reload. A nested prefab edit propagates through two levels.

#### Phase S6 — Module Integration Sweep (All 74 Submodules → Studio)
- **Objective**: Make Studio the culmination of every submodule. Each `vendor/*` package becomes discoverable, inspectable, creatable, previewable and sampled in Studio.
- **Key Deliverables**: six family tasks (see §13.7). Each delivers descriptors, annotated component wrappers, `GameObject > Create` entries, gizmo drawers for spatial modules, custom inspectors where the generic one is not enough, one sample scene per family, and a headless smoke test that instantiates every registered component.
- **Exit Criteria**: `dart run tool/check_module_coverage.dart --min-maturity inspectable` reports 74/74. Modules flagged for `S7` windows report `editor-tooled` once `S7` merges.

#### Phase S7 — Specialized Editor Windows
- **Objective**: Ship the domain tools that make an engine productive.
- **Key Deliverables**: Animation window, Animator Controller graph and Timeline; shared node-graph framework with editors for flow graph, dialogue, HTN, circuits and rules (live play-mode debugging); terrain sculpt/paint/foliage, NavMesh bake, spline and modular-building tools; Sprite Editor, Tile Palette, 2D lights and colliders; UI Builder, localization tables, and table editors for items, quests and stats over `DataAsset`s.
- **Exit Criteria**: Each window has an e2e scenario that authors content, saves it as GUID-referenced assets, and plays it back in the Game view.

#### Phase S8 — Player Link, Profiler, Build Profiles & Ship
- **Objective**: Close the loop from authoring to a shipped, profiled player on every target.
- **Key Deliverables**: Player Link protocol (Studio attaches to the in-Studio player, an external browser tab, a native exe, or a dedicated server); Profiler (CPU spans, GPU per-pass timers, memory/assets, draw stats) and Frame Debugger; Build Profiles (scenes in build, reachability-stripped `.pak`, module tree-shaking, build size report); standalone Studio app window and single distributable; templates, a flagship showcase, and generated docs.
- **Exit Criteria**: `volition build --profile web-release` and `--profile windows-release` reproduce Studio builds byte-for-byte. The profiler shows live GPU pass timings from a native player. The showcase uses at least one module from every family, and the release gate is green.

### 13.7 Module Family Assignment (74 Packages → `S6` Tasks)

| Task | Family | Packages |
| --- | --- | --- |
| `[S6-A]` | Rendering & visuals (17) | `pixeldart`, `voxvfx`, `voxribbon`, `voxdecal`, `voxlight`, `voxshadow`, `voxsky`, `voxcolor`, `voxlens`, `voxcam`, `voxprobe`, `voxatlas`, `voxbatch`, `voxoctree`, `voxsdf`, `voxgreedy`, `voxvox` |
| `[S6-B]` | Physics & simulation (11) | `voxphys`, `voxbroad`, `voxcloth`, `voxfluid`, `voxfracture`, `voxragdoll`, `voxverlet`, `voxwheel`, `voxtraffic`, `voxcrowd`, `voxsteer` |
| `[S6-C]` | Animation & motion (9) | `voxanim`, `voxblend`, `voxik2d`, `voxgait`, `voxtween`, `voxcurve`, `voxseq`, `voxspline3d`, `voxextrude` |
| `[S6-D]` | AI, gameplay & narrative (15) | `voxai`, `voxhtn`, `voxnav3d`, `voxpath`, `voxflow`, `voxgraph`, `voxcircuit`, `voxrule`, `voxitem`, `voxcraft`, `voxquest`, `voxtalk`, `voxstat`, `voxscore`, `voxloc` |
| `[S6-E]` | World & procedural (10) | `voxbiome`, `voxnoise3d`, `voxproc`, `voxarch`, `voxbuild`, `voxgrid`, `voxhex`, `voxsnap`, `voxgeom`, `voxfoliage` |
| `[S6-F]` | Audio, input, net & infrastructure (12) | `voxdsp`, `voxreverb`, `voxsynth`, `voxrhythm`, `voxpad`, `voxnet`, `voxrollback`, `voxecs`, `voxui`, `voxlog`, `voxpack`, `voxalloc` |

Modules that also need an `S7` window (and therefore must reach `editor-tooled`) are `voxanim`, `voxblend`, `voxseq`, `voxcurve`, `voxgraph`, `voxflow`, `voxtalk`, `voxhtn`, `voxcircuit`, `voxrule`, `voxbiome`, `voxfoliage`, `voxnav3d`, `voxspline3d`, `voxsnap`, `voxbuild`, `voxatlas`, `voxui`, `voxloc`, `voxitem`, `voxquest` and `voxstat`.

### 13.8 Dependency Graph

```
S1 ──┬──> S2 ──┬──> S5 ──> S6 ──> S7 ──┐
     │         │                       ├──> S8
     └──> S3 ──┴──> S4 ────────────────┘
```

`S3` (renderer) can run alongside `S2` (editor shell) because their `Owns` sets are disjoint: `vendor/pixeldart/**` versus `lib/src/studio/**`, `lib/src/web/studio/**` and `tool/studio/**`. `S2-B` editor passes are the only shared renderer files and are frozen in `S2-0`.

### 13.9 Architecture Decision Records

**ADR-2 — Studio is a Dart-compiled web editor driving the real engine in-page.**
- *Context*: The current Studio is hand-written JS inside a Dart string, so it cannot share engine code or render scenes.
- *Decision*: The Studio shell is Dart (`lib/src/web/studio/**`) compiled to JS. It hosts `WebEngineHost` and `EditorSession` in-page for the Scene and Game views. The `dart:io` daemon (`tool/studio/**`) owns the disk, the AssetDatabase, compilation and builds. The compiled bundle is embedded into the AOT `volition` binary via a generated `tool/studio/studio_bundle.g.dart`, so Studio ships as one executable. The legacy dashboard panels (Doctor, Build, Pack, Tests, Inspector, Replay) move into Studio's Build/Tools panels in `S2-A` and keep their RPCs.
- *Consequences*: One rendering path for the editor and the web player, editor models testable headlessly, and native Studio windows via the existing webview target (`S8-C`).

**ADR-3 — VRP stays on WebGL2/GLES3 with clustered Forward+; WebGPU deferred.**
- *Context*: Both live backends share GLSL ES 3.00.
- *Decision*: Clustered Forward+ preserves MSAA, transparency and bandwidth on web/mobile GPUs better than deferred, and needs only UBOs and float or integer textures that WebGL2 already has.
- *Consequences*: Compute-dependent features (GPU-driven culling, compute light binning) stay on the CPU or use fragment-shader fallbacks until a WebGPU `device_api` backend is planned after `S8`.

**ADR-4 — GUID asset identity with sidecar metadata.**
- *Decision*: Adopt Unity-style `.vmeta` sidecars (GUID, importer id and version, import settings, content hash) committed next to each asset. A derived, git-ignored `.volition/library/` cache holds import outputs and thumbnails.
- *Consequences*: Rename-safe references, incremental reimport, and reproducible builds from source assets plus metas.

**ADR-5 — Dart is the scripting language (Unity's C# role); visual graphs for designers; no second runtime.**
- *Context*: A Unity-like engine needs a gameplay scripting story across web (JS/wasm), native AOT and server targets, while staying deterministic for input-tape replay and rollback netcode.
- *Decision*: Gameplay scripts are plain Dart `Behaviour`/`Component` subclasses, exposed to the editor via `@Serialized`-style annotations and `volition codegen` (`[S5-0]`, `[S5-A]`), with hot reload in development (`[S5-B]`). Designers use the `voxgraph`-based node editors (`[S7-B]`), which are data and therefore work in shipped builds. No Lua, JS or other embedded runtime is added.
- *Consequences*: No binding layer for the 74 modules and no marshalling cost; full analyzer and type support; one language and number model for determinism (scripts must respect dart2js 53-bit `int` semantics, as `SceneStateHasher` already does). Shipped AOT/dart2js builds cannot load new Dart code, so player modding is out of scope. If it is wanted later, the preferred route is a sandboxed `dart_eval` layer with a fixed exposed API (a future `[S5-E]`), not a second language.

### 13.10 Key Risks & Mitigations

| Risk | Mitigation |
| --- | --- |
| Hot-reload latency with `dart compile js` is too slow for a Unity-like loop | `S5-B` measures DDC/`build_web_compilers` incremental and `-O0` full builds first, and records the numbers; the fallback is state-preserving full reload, with the target and the actual time reported rather than assumed |
| WebGL2 uniform-block limits and missing `EXT_color_buffer_float` on low-end devices | Capability bits from `S1-0`; tiered settings (`S3-0`) select RGBA8 + in-shader tonemap and smaller light caps; Browser Lab runs both tiers |
| Shader variant explosion | Keyword whitelist per material/quality tier, offline variant enumeration in `tools/renderer/shaders.dart --check`, warmup lists per scene |
| Module sweep (74 packages) stalls | Maturity levels let `S6` land at `inspectable` quickly via codegen and generic inspectors; only the 22 listed modules need custom windows |
| Concurrent numbered waves editing the same hubs | Coordinator-locked file list (§4) also covers `lib/src/studio/protocol/**` and `tool/studio/studio_bundle.g.dart`; interleaving is scheduled by `Owns` disjointness |
| Claims drifting from reality again | Invariant 10: anti-regression checks and goldens are part of every `DoneWhen`; `[S8-M]` re-runs the §13.1 audit queries and must report zero reopened items |
