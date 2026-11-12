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
   - Root git commits / `vendor/*` gitlink updates (Coordinator-only after verifying submodule clean state)
4. **Mandatory Worker Report & Verification**:
   - Every worker ends with exact changed paths, exported symbols, edge cases/caveats, and output of `dart analyze`, targeted `dart test <suite>`, and any compile/boundary check required by `DoneWhen`.
   - Subagents never run `git commit`. Coordinator validates integrated wave gates before advancing to Wave `N+1`.
