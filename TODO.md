# `gl_volition` Production Execution Backlog (Subagent-Optimized)

> **Master Plan:** See [PLAN.md](PLAN.md) for architectural rationale, post-`E106` baseline audit, and phase exit gates.
> **Rule:** Subagents receive exactly ONE task ID (`[Px-Wy-z]`). Do not modify any file outside your task's `Owns` list. Do not commit git changes or update submodule gitlinks inside worker tasks.

---

## Subagent Execution Protocol

1. **Wave Ordering**: Execute `[Px-Wy-0]` (Coordinator Freeze) first -> verify `dart analyze` -> dispatch `[Px-Wy-A..Z]` in parallel -> execute `[Px-Wy-M]` (Coordinator Merge & Verification) before starting Wave `y+1`.
2. **Pure-Dart Invariant**: `lib/src/engine/**`, `lib/gl_volition.dart`, and `lib/src/engine.dart` MUST NOT import `dart:io`, `dart:ffi`, `dart:isolate` (without conditional host abstraction), `package:web`, or `dart:js_interop`.
3. **Coordinator-Locked Files** (never edit inside `[Px-Wy-A..Z]` tasks unless explicitly listed in `Owns`):
   - `pubspec.yaml`, `.gitmodules`, `PLAN.md`, `TODO.md`, `ENGINE.md`
   - `lib/gl_volition.dart`, `lib/gl_volition_web.dart`, `lib/gl_volition_native.dart`
   - `lib/src/engine.dart`, `lib/src/engine/serialization/component_spec.dart`, `tool/generate_logos.dart`
4. **Standard Worker Verification**: Every worker must run `dart analyze`, targeted `dart test <suite>`, and any compile/boundary command specified in `DoneWhen`, reporting exact modified paths, exported symbols, caveats, and raw command results.

---

## Wave 8 (Phase 0) — Engineering Hygiene, CLI Fixes, Test Sharding & CI

**Wave Exit Gate:** `dart analyze`, `dart run tool/verify_all.dart`, `dart format --output=none --set-exit-if-changed .`, and green `.github/workflows/ci.yml` config.

- [x] **[P0-W8-A] Fix CLI `_runServe` bug, JS compiler `noSuchMethod` hint & README typo**
  - **Priority:** P0
  - **DependsOn:** none
  - **Owns:** `bin/volition.dart`, `README.md`, `lib/src/engine/serialization/component_spec_extra.dart`
  - **Reads:** `test/**`
  - **Scope:**
    - In `bin/volition.dart` (`_runServe`, around line 140), replace `Platform.resolvedExecutable` with `_dartExecutable` so `volition serve` succeeds when invoked from a compiled AOT `volition.exe` binary.
    - In `lib/src/engine/serialization/component_spec_extra.dart` (`_EmptySpecResources`, around line 15), remove `noSuchMethod(Object invocation)` or replace with explicit concrete no-op stubs so `dart compile js` emits zero hints.
    - In `README.md` (line 28), fix `-- target wasm` -> `--target wasm`.
  - **DoneWhen:** `dart analyze` reports 0 issues; `dart compile js example/prism_pulse/main.dart -o build/smoke.js` succeeds with zero `noSuchMethod` hints; `dart compile exe bin/volition.dart` runs `serve --help` / `serve` invoking `_dartExecutable`.

- [x] **[P0-W8-B] Add Static Boundary Linter, Unified Verification Script & GitHub Actions CI (`R6`)**
  - **Priority:** P0
  - **DependsOn:** none
  - **Owns:** `.github/workflows/ci.yml`, `tool/check_boundaries.dart`, `tool/verify_all.dart`
  - **Reads:** `pubspec.yaml`, `dist.ps1`, `vendor/pixeldart/tools/**`, `vendor/voxnet/pubspec.yaml`
  - **Scope:**
    - Create `tool/check_boundaries.dart` that scans `lib/src/engine/**` and `lib/gl_volition.dart` and fails non-zero if any file imports `dart:io`, `dart:ffi`, `dart:isolate`, `package:web`, `dart:js_interop`, or `dart:html`.
    - Create `tool/verify_all.dart` orchestrating: boundary check, `dart analyze`, `dart test`, `vendor/pixeldart` verification (`dart run tools/renderer/check_boundary.dart`, `dart run tools/renderer/shaders.dart --check`, `dart run tools/renderer/test_all.dart`), `vendor/voxnet` (`dart test`), `dart compile js example/prism_pulse/main.dart`, optional `dart compile wasm` smoke, and `dart compile exe bin/volition.dart` (cleaning temporary artifacts or writing under `.dart_tool/`).
    - Create `.github/workflows/ci.yml` running `dart format --output=none --set-exit-if-changed bin lib test tool example` + `dart run tool/verify_all.dart` on Windows and Linux runners (`ubuntu-latest`, `windows-latest`).
  - **DoneWhen:** `dart run tool/check_boundaries.dart` passes; `dart run tool/verify_all.dart` passes locally end-to-end.

- [x] **[P0-W8-C] Shard Monolithic `test/subsystems_test.dart` Into Domain Test Suites**
  - **Priority:** P0
  - **DependsOn:** none
  - **Owns:** `test/subsystems_test.dart`, `test/engine/**`, `test/physics/**`, `test/assets/**`, `test/network/**`, `test/serialization/**`, `test/native/**`
  - **Reads:** `lib/src/**`
  - **Scope:**
    - Split the 10,284-line `test/subsystems_test.dart` into fast, focused domain files (`test/engine/*_test.dart`, `test/physics/*_test.dart`, `test/assets/*_test.dart`, `test/network/*_test.dart`, `test/serialization/*_test.dart`, `test/native/*_test.dart`) without losing or weakening any single `test(...)` or assertion.
    - Convert `test/subsystems_test.dart` into a small verification/smoke index or clean removal once all extracted files execute via `dart test`.
  - **DoneWhen:** Exact total passed test count from `dart test` equals or exceeds pre-split count (`>= 200`, 0 skipped, 0 failures).

- [x] **[P0-W8-M] Coordinator Merge: Root Format & CI Gate Activation**
  - **Priority:** P0
  - **DependsOn:** `[P0-W8-A]`, `[P0-W8-B]`, `[P0-W8-C]`
  - **Owns:** Root Dart formatting (`bin lib test tool example`) + CI verification
  - **Scope:** Run `dart format bin lib test tool example` (keeping `vendor/*` submodules unmodified), apply `curly_braces_in_flow_control_structures` fixes triggered by wrapped lines, verify `dart analyze --fatal-infos` (0 issues), `dart test` (201/201 passed), and log the known `vendor/pixeldart/tools/renderer/test_rf11_runtime_reference_audit.dart` (`1 of 133` submodule `../..` path assumption) for `[P4-W12-B1]`.

---

## Wave 9 (Phase 1) — Native Desktop OS Backend (SDL3 + GLES3/ANGLE + Audio + AOT Packaging)

**Wave Exit Gate:** Native AOT executable opens a live OS window via SDL3 FFI, compiles/links real GLES3/ANGLE shaders, swaps frames on resize without errors, outputs hardware PCM audio, and keeps deterministic headless `RecordingGlesDevice` tests green.

- [x] **[P1-W9-0] Coordinator Freeze: Native FFI Service Contracts & Pluggable Host Injection**
  - **Priority:** P0
  - **DependsOn:** `[P0-W8-M]`
  - **Owns:** `lib/src/native/native_bindings.dart`, `lib/src/native/native_host.dart` (constructor injection only)
  - **Reads:** `lib/src/native/native_ffi_transport.dart`, `lib/src/engine/host.dart`
  - **Scope:**
    - Define abstract native contracts in `native_bindings.dart`: `NativeWindowBackend` (init, resize polling, swapBuffers, makeCurrent, shutdown), `GlProcBindings`, `NativeAudioConfig`, `NativeAudioSink`, and `DisposableNativeAudioDevice`.
    - Update `NativeEngineHost` constructor to accept optional injectable `AudioDevice?`, `GpuDevice?`, and `NativeWindowBackend?` so concurrent workers implement hardware modules cleanly against frozen types.
  - **DoneWhen:** `dart analyze` passes.

- [x] **[P1-W9-A] Real SDL3 `dart:ffi` Windowing, Context Creation & Live Event Pump**
  - **Priority:** P0
  - **DependsOn:** `[P1-W9-0]`
  - **Owns:** `lib/src/native/sdl3_bindings.dart`, `lib/src/native/native_ffi_transport.dart`, `test/native/sdl3_transport_test.dart`
  - **Reads:** `lib/src/native/native_bindings.dart`
  - **Scope:**
    - Implement `DynamicLibrary.lookupFunction` FFI bindings for SDL3 (`SDL_Init`, `SDL_CreateWindow`, `SDL_GL_CreateContext`, `SDL_GL_MakeCurrent`, `SDL_GL_SwapWindow`, `SDL_PollEvent`, `SDL_GetWindowSizeInPixels`, `SDL_DestroyWindow`, `SDL_Quit`) with clean missing-library diagnostic errors.
    - Replace stubbed queue-only behavior in `Sdl3EventPump` and `NativeDesktopBridge` with live SDL3 event decoding (keyboard up/down/repeat, mouse move/button/wheel, window resize/close/focus) while retaining a test-injectable queue adapter for deterministic VM tests.
  - **DoneWhen:** `dart test test/native/sdl3_transport_test.dart` passes; missing-DLL handling fails cleanly with actionable error messages rather than uncaught FFI segfaults.

- [x] **[P1-W9-B] Real GLES3 / ANGLE Hardware `GpuDevice` + Preserved `RecordingGlesDevice` for CI**
  - **Priority:** P0
  - **DependsOn:** `[P1-W9-0]`
  - **Owns:** `lib/src/native/gles3_bindings.dart`, `lib/src/native/gles3_ffi_device.dart`, `lib/src/native/native_host.dart`, `test/native/gles3_device_test.dart`
  - **Reads:** `vendor/pixeldart/lib/rendering/**`, `lib/src/native/native_bindings.dart`
  - **Scope:**
    - Extract current software recorder implementation in `native_host.dart` (`GlesDevice`) as `RecordingGlesDevice` AND preserve `typedef GlesDevice = RecordingGlesDevice;` so all existing VM tests, benchmarks, and examples compile and behave identically.
    - Create `Gles3Bindings` (EGL/ANGLE/GLES3 FFI function lookup via `GlProcBindings` / `DynamicLibrary`) and `Gles3FfiDevice implements GpuDevice, GpuContextGeneration` implementing real FBOs, VBOs/VAOs, textures, GLSL shader compile/link checks, uniform uploads, draw calls, readPixels, and genuine `GL_EXT_disjoint_timer_query` / timestamp polling (zero hardcoded timer values on `Gles3FfiDevice`).
  - **DoneWhen:** `dart test test/native/gles3_device_test.dart` passes against both `RecordingGlesDevice` and live FFI binding signature checks; zero hardcoded timer values on `Gles3FfiDevice`.

- [x] **[P1-W9-C] Native Hardware PCM Audio Device Replacing `SilentAudio`**
  - **Priority:** P1
  - **DependsOn:** `[P1-W9-0]`
  - **Owns:** `lib/src/native/native_audio_device.dart`, `test/native/native_audio_test.dart`
  - **Reads:** `lib/src/native/native_bindings.dart`, `lib/src/engine/host.dart`, `lib/src/engine/components/audio_source.dart`
  - **Scope:**
    - Implement `NativeAudioDevice` implementing `AudioDevice` using SDL3 audio stream / miniaudio C ABI callback or buffered PCM mixer in software + native audio stream output (`volume`, `playbackRate`, `loop`, WAV/OGG/PCM decoding).
    - Provide clean fallback/diagnostic mode when audio hardware is unavailable (headless CI without sound card).
  - **DoneWhen:** `dart test test/native/native_audio_test.dart` verifies mixing, looping, stop/pause, and PCM frame emission deterministically.

- [x] **[P1-W9-D] True Native AOT Desktop Build Targets (`--target windows|linux|macos`)**
  - **Priority:** P0
  - **DependsOn:** `[P1-W9-0]`
  - **Owns:** `bin/volition.dart`, `dist.ps1`, `tool/package_native.dart`, `example/native_smoke/main.dart`, `test/native/package_native_test.dart`
  - **Reads:** `vendor/pixeldart/examples/desktop_host/Program.cs`
  - **Scope:**
    - Change `bin/volition.dart` `_buildWindowsExecutable` (and add `linux`/`macos` native targets) to compile real Dart AOT executables importing `gl_volition_native.dart` + bundling SDL3/ANGLE dynamic libs and asset `.pak`/data folders.
    - Keep the existing `.NET 10` WinForms `WebView2` wrapper (`Program.cs`) available explicitly under `--target webview` for browser-embedded distribution.
    - Update `example/native_smoke/main.dart` to accept `--hardware` / `--headless` smoke mode flags and update `dist.ps1`.
  - **DoneWhen:** `dart test test/native/package_native_test.dart` and `dart run bin/volition.dart build example/native_smoke/main.dart --target windows --dry-run` (or full local AOT bundle build) pass cleanly.

- [x] **[P1-W9-M] Coordinator Merge: Default `NativeEngineHost` Hardware Wiring**
  - **Priority:** P0
  - **DependsOn:** `[P1-W9-A]`, `[P1-W9-B]`, `[P1-W9-C]`, `[P1-W9-D]`
  - **Owns:** `lib/gl_volition_native.dart`, `lib/src/native/native_host.dart`
  - **Scope:** Wire default windowed `NativeEngineHost.desktop(...)` factory using `Sdl3NativeBridge` + `Gles3FfiDevice` + `NativeAudioDevice`, while keeping `NativeEngineHost.recording(...)` / default test constructor safe for headless VM CI.

---

## Wave 10 (Phase 2) — Complete Host Contract (`Input`, Web Audio DSP, Multi-Camera, `visibilityMask`)

**Wave Exit Gate:** Feature parity across `HeadlessHost`, `WebEngineHost`, and `NativeEngineHost` for wheel/touch/pointer-lock/gamepad input, spatial Web Audio DSP, multi-camera viewports + render-to-texture, and Web `visibilityMask` culling.

- [x] **[P2-W10-0] Coordinator Freeze: Extend `host.dart` / `headless.dart`, Split `web_host.dart` & Patch `PixeldartApp._frame`**
  - **Priority:** P0
  - **DependsOn:** `[P1-W9-M]`
  - **Owns:** `lib/src/engine/host.dart`, `lib/src/engine/headless.dart`, `lib/src/web/web_host.dart`, `vendor/pixeldart/lib/rendering/webgl/pixeldart_app.dart`
  - **Scope:**
    - Extend `Input` (`wheelDeltaX/Y`, `pointerDeltaX/Y`, `pointerLocked`, `requestPointerLock()`, `touches`, `gamepadCount`, `gamepadAxis`, `gamepadButtonDown`, `textInputBuffer`).
    - Extend `AudioDevice` / `AudioChannel` (`setPan`, `setLowPass`, `setReverbSend`, listener orientation hooks).
    - Extend `Graphics` (`createRenderTarget`, `setViewport`, `renderFrameToTarget`, camera layer/target descriptor).
    - Implement matching inspectable mocks in `HeadlessInput`, `HeadlessAudio`, `HeadlessGraphics` (`headless.dart`).
    - Refactor `lib/src/web/web_host.dart` into delegating facade backed by separate files `web_input.dart`, `web_audio.dart`, `web_graphics.dart`.
    - Patch `PixeldartApp._frame` (`vendor/pixeldart/lib/rendering/webgl/pixeldart_app.dart:1194-1199`) to accept/apply `visibilityMask` into `sequencer.next(...)` (resolving Wave 7 Web caveat).
  - **DoneWhen:** `dart analyze` + `dart test` + `vendor/pixeldart` tests pass with zero warnings.

- [x] **[P2-W10-A] Web & Native Input Parity (Wheel, Multi-Touch, PointerLock, Gamepad) + `InputManagerComponent` Wiring**
  - **Priority:** P1
  - **DependsOn:** `[P2-W10-0]`
  - **Owns:** `lib/src/web/web_input.dart`, `lib/src/native/native_input.dart`, `lib/src/engine/components/input_manager.dart`, `test/engine/input_parity_test.dart`
  - **Reads:** `lib/src/engine/host.dart`, `lib/src/native/native_ffi_transport.dart`
  - **Scope:**
    - Wire DOM `wheel`, `touchstart/move/end`, `PointerLock` (`movementX/Y`), and `navigator.getGamepads()` in `web_input.dart`.
    - Wire SDL3 gamepad + wheel + relative mouse mode in `native_input.dart`.
    - Connect `InputManagerComponent` action maps, axis bindings, runtime rebinding persistence, and virtual touch overlays cleanly to live `Input`.
  - **DoneWhen:** `dart test test/engine/input_parity_test.dart` + `dart compile js example/prism_pulse/main.dart` pass.

- [x] **[P2-W10-B] Web Audio API `AudioContext` DSP Graph & Spatial Mixer Integration**
  - **Priority:** P1
  - **DependsOn:** `[P2-W10-0]`
  - **Owns:** `lib/src/web/web_audio.dart`, `lib/src/native/native_audio_device.dart`, `lib/src/engine/components/audio_dsp.dart`, `lib/src/engine/components/audio_source.dart`, `test/engine/audio_dsp_test.dart`
  - **Reads:** `lib/src/engine/host.dart`, `lib/src/engine/headless.dart`
  - **Scope:**
    - Replace `HTMLAudioElement`-only playback in `web_audio.dart` with Web Audio `AudioContext` + `AudioBufferSourceNode` + `StereoPannerNode` / `PannerNode` + `BiquadFilterNode` + `ConvolverNode` / wet-dry reverb bus (with clean autoplay-unlock policy).
    - Wire `AudioListener`, `AudioSource`, `AudioMixer`, `AudioReverbZone`, `AudioLowPassFilterComponent`, and `SpatialAudioDspExt` so zone proximity/occlusion parameters drive live `AudioChannel` pan, cutoff Hz, and reverb send on Web, Native, and Headless.
  - **DoneWhen:** `dart test test/engine/audio_dsp_test.dart` verifies gain attenuation, stereo pan, lowpass cutoff, and reverb send updates into `HeadlessAudio` & `NativeAudioDevice`, and `dart compile js` compiles cleanly.

- [x] **[P2-W10-C] Multi-Camera Viewport Sorting & Render-to-Texture Pipeline**
  - **Priority:** P1
  - **DependsOn:** `[P2-W10-0]`
  - **Owns:** `lib/src/web/web_graphics.dart`, `lib/src/native/native_host.dart`, `lib/src/engine/components/camera.dart`, `lib/src/engine/scene.dart`, `test/engine/multi_camera_test.dart`
  - **Reads:** `lib/src/engine/host.dart`, `vendor/pixeldart/lib/rendering/**`
  - **Scope:**
    - Update `Scene._syncToRenderer` and `Engine` frame submission to sort all enabled `Camera` components by `Camera.depth`, apply each camera's `cullingMask`/`visibilityMask`, `normalizedViewportRect`, clear flags, and optional offscreen `RenderTargetHandle`.
    - Implement multi-pass viewport/scissor & render-target switching in `web_graphics.dart` and `native_host.dart` (+ `RecordingGlesDevice` viewport command assertions).
  - **DoneWhen:** `dart test test/engine/multi_camera_test.dart` proves depth ordering (2+ active cameras + PIP minimap target) and per-camera `visibilityMask` isolation across Headless and Native recording hosts.

- [x] **[P2-W10-M] Coordinator Merge: Push `vendor/pixeldart` `visibilityMask` Submodule Commit & Verify Parity**
  - **Priority:** P0
  - **DependsOn:** `[P2-W10-A]`, `[P2-W10-B]`, `[P2-W10-C]`
  - **Owns:** Submodule gitlink sync + `tool/verify_all.dart` run
  - **Scope:** Commit/verify `vendor/pixeldart` `PixeldartApp._frame` fix, re-run full `verify_all.dart`.

---

## Wave 11 (Phase 3) — Production Asset Pipeline, `.pak` VFS Unification, Streaming & Scene Migrations

**Wave Exit Gate:** Scenes load `.glb`/`.qmesh`/textures/LUTs natively from `.pak` archives, `ModelRenderer` serializes real `AssetCatalog` keys, `v1` scenes migrate cleanly to current schema, and background async streaming passes memory/eviction tests.

- [x] **[P3-W11-0] Coordinator Freeze: Asset Handles, Ref-Counting & Migration Interfaces**
  - **Priority:** P0
  - **DependsOn:** `[P2-W10-M]`
  - **Owns:** `lib/src/engine/assets/asset_types.dart`, `lib/src/engine/serialization/scene_migration.dart`
  - **Reads:** `lib/src/engine/assets/asset_catalog.dart`, `lib/src/engine/assets/pak_vfs.dart`, `lib/src/engine/serialization/scene_serializer.dart`
  - **Scope:** Define `AssetHandle<T>` (`acquire`/`release`), eviction callback contracts, and `SceneMigrationStep` interface (`fromVersion`, `toVersion`, `migrate(Map<String, Object?>)`).
  - **DoneWhen:** `dart analyze` passes.

- [x] **[P3-W11-A] Direct `VfsAssetLoader.loadModel`, Ref-Counted `AssetCatalog` Unloading & `ModelRenderer` Spec Fix**
  - **Priority:** P0
  - **DependsOn:** `[P3-W11-0]`
  - **Owns:** `lib/src/engine/assets/pak_vfs.dart`, `lib/src/engine/assets/asset_catalog.dart`, `lib/src/engine/serialization/component_spec_extra.dart`, `test/assets/asset_catalog_vfs_test.dart`
  - **Reads:** `lib/src/engine/assets/asset_types.dart`, `vendor/pixeldart/lib/rendering/**`
  - **Scope:**
    - Implement `VfsAssetLoader.loadModel` directly from `VfsArchive` `.glb` / `.qmesh` byte entries (eliminating `UnimplementedError` when `fallback == null`).
    - Implement ref-counted `acquire(key)`, `release(key)`, explicit `unload(key)` / `unloadUnused()`, and GPU handle disposal notifications in `AssetCatalog`.
    - Fix `ModelRenderer` `ComponentSpec` (`component_spec_extra.dart:44-49`) so `assetId` / asset key serializes/deserializes against `AssetCatalog` instead of constructing an empty dummy `ModelAsset` with `const []` fields.
  - **DoneWhen:** `dart test test/assets/asset_catalog_vfs_test.dart` passes round-trip `.pak` model loads without fallback and verifies ref-count drops to 0 cleanly dispose resources.

- [x] **[P3-W11-B] `volition pack` CLI Bundler, `OBJ -> QMSH` Integration, Catalog Validator & LUT Asset Loader**
  - **Priority:** P1
  - **DependsOn:** `[P3-W11-0]`
  - **Owns:** `tool/asset_packer.dart`, `bin/volition.dart`, `vendor/pixeldart/lib/assets/**`, `vendor/pixeldart/tools/assets/**`, `test/assets/packer_qmesh_test.dart`
  - **Reads:** `vendor/pixeldart/lib/rendering/**`, `lib/src/engine/assets/pak_vfs.dart`
  - **Scope:**
    - Add `volition pack <dir> -o <bundle.pak>` CLI command compiling manifests, textures, audio, LUTs, and validated `.qmesh`/`.glb` models into indexed `.pak` files.
    - Wire `vendor/pixeldart`'s existing `ObjImporter` / `ObjModelPackageEmitter` / `GltfModelPackageEmitter` / `ModelPackageValidator` (`vendor/pixeldart/lib/assets/**`) directly into `volition pack` / converter CLI commands and close any missing sidecar validation edge cases.
    - Build a real color-grading `.cube`/image LUT asset + loader (`TODO.md` carry-over) usable by `pixeldart` post-processing & `.pak` archives.
  - **DoneWhen:** `dart test test/assets/packer_qmesh_test.dart` generates an OBJ -> QMSH package, packs a `.pak` archive, validates sidecars, and loads the LUT asset cleanly.

- [x] **[P3-W11-C] Versioned `SceneSerializer` & `Prefab` Schema Migration Pipeline**
  - **Priority:** P1
  - **DependsOn:** `[P3-W11-0]`
  - **Owns:** `lib/src/engine/serialization/scene_serializer.dart`, `lib/src/engine/serialization/scene_migration.dart`, `lib/src/engine/prefab.dart`, `test/serialization/scene_migration_test.dart`
  - **Reads:** `lib/src/engine/serialization/component_spec.dart`
  - **Scope:**
    - Bump scene schema version cleanly via `SceneMigrator` chain (`v1 -> v2 -> ...`) in `scene_serializer.dart` instead of immediately throwing `FormatException('Unsupported scene schemaVersion: $version')` on older saved scenes.
    - Add unknown-component preservation / warning diagnostics (`strictMode` toggle) and matching migration support in `Prefab`.
  - **DoneWhen:** `dart test test/serialization/scene_migration_test.dart` migrates recorded `v1` scene and prefab JSON fixtures forward cleanly and rejects only genuinely corrupted or future-unsupported schemas.

- [x] **[P3-W11-D] Background Isolate / Micro-Budgeted Streaming Asset Loader**
  - **Priority:** P1
  - **DependsOn:** `[P3-W11-0]`
  - **Owns:** `lib/src/engine/assets/streaming_loader.dart`, `lib/src/native/native_async_decode.dart`, `lib/src/web/web_async_decode.dart`, `test/assets/streaming_loader_test.dart`
  - **Reads:** `lib/src/engine/assets/asset_types.dart`, `lib/src/engine/assets/asset_catalog.dart`
  - **Scope:**
    - Build priority-queued `StreamingAssetLoader` with configurable per-frame upload millisecond budget and host-pluggable worker decoding (`Isolate.run` via `native_async_decode.dart` on Native, cooperative chunked async decode on Web/Headless so `lib/src/engine/**` stays pure Dart).
  - **DoneWhen:** `dart test test/assets/streaming_loader_test.dart` verifies cancellation, priority preemption, and bounded per-tick completion work under heavy queues.

- [x] **[P3-W11-M] Coordinator Merge: Wire `StreamingAssetLoader` Into `Scene` & Push `pixeldart` Tools**
  - **Priority:** P0
  - **DependsOn:** `[P3-W11-A]`, `[P3-W11-B]`, `[P3-W11-C]`, `[P3-W11-D]`
  - **Owns:** `lib/src/engine/scene.dart`, submodule gitlink check
  - **Scope:** Wire optional `StreamingAssetLoader` frame-budget step into `Engine`/`Scene`, test `dist.ps1` / `verify_all.dart`.

---

## Wave 12 (Phase 4) — Production Rendering, Skeletal Skinning & `pixeldart` Closure (`R1–R7`)

**Wave Exit Gate:** All remaining `pixeldart` `R1–R7` & renderer roadmap items verified in Browser Lab (golden PNG/SSIM, 180w/600m budget table, telemetry/no-black-frame gates), GPU skeletal animation deforms GLB characters, and CPU-only GI/2D-lighting/soft-body/batcher subsystems drive GPU output.

- [x] **[P4-W12-0] Coordinator Freeze: `R3` Declared Graph Pass API, `SkinData` & GI/2D Uniform Contracts**
  - **Priority:** P0
  - **DependsOn:** `[P3-W11-M]`
  - **Owns:** `vendor/pixeldart/lib/rendering/api/**`, `lib/src/engine/components/skinned_mesh.dart`
  - **Scope:**
    - Freeze `R3` host-declared graph-pass descriptor API (`RenderPassDecl`, transient target attachments, pass dependencies) and renderer diagnostic counters snapshot contract (`vendor/pixeldart` `TODO.md` carry-over).
    - Freeze bone palette / skin matrix capacity constants and `SkinData` / `JointNode` structures for GLB skinning.
    - Freeze shader slot/uniform names used by `LightProbeVolumeComponent` (SH3), `Lighting2DComponent` (2D lightmap overlay), and dynamic deformed mesh upload hooks.
  - **DoneWhen:** Both root `dart analyze` and `vendor/pixeldart` `dart analyze` pass.

- [x] **[P4-W12-A] `pixeldart` Browser Lab (`R7`), Golden + Perf Baseline Gates & `Procession` Dense Trees Fix**
  - **Priority:** P0
  - **DependsOn:** `[P4-W12-0]`
  - **Owns:** `vendor/pixeldart/web/renderer_test/**`, `vendor/pixeldart/.github/screenshots/**`, `vendor/pixeldart/tools/renderer/run_shader_lab.mjs`, `example/procession/**`, `tool/renderer_bench.dart`
  - **Reads:** `PLAN.md`, `vendor/pixeldart/lib/**`
  - **Scope:**
    - Extend `vendor/pixeldart/tools/renderer/run_shader_lab.mjs` + `web/renderer_test/` (`R7`) with automated golden PNG + SSIM comparison against `vendor/pixeldart/.github/screenshots/` and 180-warmup / 600-measured-frame telemetry (`no-black-frame` check, alloc counter, GPU/CPU frame timings, culling & instancing pixel acceptance verification).
    - Tune `example/procession/**` dense-tree framing/draw budgets (`R7` carry-over).
    - Author alpha-mask x affine interaction fixture and ratify the formal frame performance budget table (`TODO.md` carry-over).
    - Run `QMSH` geometry end-to-end through the live GPU WebGL path (`R1`/`R2` browser verification).
  - **DoneWhen:** Automated Browser Lab harness runs headless Chromium / WebGL2 checks, compares against golden references, prints ratified budget compliance table, and fails on black frame or >threshold SSIM drift.

- [x] **[P4-W12-B1] `pixeldart` Core Pipeline: `frame_arena`, `dynamic_batch`, Safe-Graph Reconcile & Diagnostics**
  - **Priority:** P0
  - **DependsOn:** `[P4-W12-0]`
  - **Owns:** `vendor/pixeldart/lib/rendering/core/**`, `vendor/pixeldart/tools/renderer/test_*_core*.dart`, `vendor/pixeldart/tools/renderer/test_render_graph*.dart`, `vendor/pixeldart/tools/renderer/test_no_allocation_trace.dart`, `vendor/pixeldart/tools/renderer/test_rf11_runtime_reference_audit.dart`
  - **Reads:** `vendor/pixeldart/lib/rendering/api/**`
  - **Scope:**
    - Close remaining `core/frame_arena` and `core/dynamic_batch` zero-allocation gaps beyond `frame_queue.dart`/`batching.dart`.
    - Reconcile safe-graph shape and implement `R3` host-declared custom graph passes cleanly.
    - Implement material table capacity splitting, per-draw light selection + diagnostics, debug visualization modes (albedo/normals/roughness/light-heatmap/overdraw), and full diagnostics snapshot export.
    - Fix `vendor/pixeldart/tools/renderer/test_rf11_runtime_reference_audit.dart` host-project detection so submodule checkouts inside `gl_volition/vendor/pixeldart` skip legacy `quarantine`-only `web/` checks cleanly rather than throwing `PathNotFoundException`.
  - **DoneWhen:** `dart run tools/renderer/test_all.dart` inside `vendor/pixeldart` passes all core, audit, & zero-allocation trace tests (133/133).

- [x] **[P4-W12-B2] `pixeldart` WebGL2 Passes: Instancing >16 Cap, Stencil, Decals, Shadows, MSAA & Linear/sRGB Audit**
  - **Priority:** P0
  - **DependsOn:** `[P4-W12-0]`
  - **Owns:** `vendor/pixeldart/lib/rendering/webgl/**`, `vendor/pixeldart/lib/rendering/passes/**`, `vendor/pixeldart/shaders/**`, `vendor/pixeldart/tools/renderer/test_webgl*.dart`, `vendor/pixeldart/tools/renderer/test_msaa*.dart`, `vendor/pixeldart/tools/renderer/test_directional_shadow.dart`
  - **Reads:** `vendor/pixeldart/lib/rendering/api/**`, `vendor/pixeldart/lib/rendering/core/**`
  - **Scope:**
    - Wire `InstanceBufferStream` end-to-end into live world/shadow passes & `webgl/frame_targets` to eliminate any remaining 16-instance uniform cap (`>1024` instances per draw via instanced attributes / UBO).
    - Expand `ShadowLightView` directional/multi-caster shadow support with capability-driven shadow resolution and front-face culling during shadow/depth pass.
    - Implement genuine stencil buffer state and decal rendering stage (currently `0` references in `lib/rendering/`), texture array groups, soft particles, fixed low internal resolution scaling, affine UV option in textured/safe world, vertex lighting fallback, `R4` anisotropy quality/cost benchmark, `R5` MSAA resize/restore correctness & cost, and a complete `Linear / sRGB` shader & render-target audit (`tools/renderer/shaders.dart` regenerated and `--check` clean).
  - **DoneWhen:** `dart run tools/renderer/shaders.dart --check` + `dart run tools/renderer/check_boundary.dart` + `dart run tools/renderer/test_all.dart` inside `vendor/pixeldart` pass cleanly.

- [x] **[P4-W12-C] Skeletal GPU Skinning Pipeline (`Animator` + `GlbSkinDecoder` + `SkinnedMeshRenderer`)**
  - **Priority:** P1
  - **DependsOn:** `[P4-W12-0]`
  - **Owns:** `lib/src/engine/assets/glb_skin_decoder.dart`, `lib/src/engine/components/animator.dart`, `lib/src/engine/components/skinned_mesh.dart`, `test/engine/skinning_test.dart`
  - **Reads:** `lib/src/engine/assets/pak_vfs.dart`, `vendor/pixeldart/lib/rendering/api/**`
  - **Scope:**
    - Parse GLB `skins`, `joints`, `inverseBindMatrices`, and `JOINTS_0`/`WEIGHTS_0` attributes cleanly in `glb_skin_decoder.dart`.
    - Extend `Animator` to evaluate hierarchical bone keyframe tracks, cross-fade blends, and joint palettes feeding `SkinnedMeshRenderer` GPU matrix uniforms/buffers.
  - **DoneWhen:** `dart test test/engine/skinning_test.dart` verifies known bone hierarchy FK + inverse-bind deformation accuracy against reference skinning math and `HeadlessGraphics` uniform palette uploads.

- [x] **[P4-W12-D] Wire Decoupled GPU Systems (`LightProbeGI`, `Lighting2D`, `SoftBodyXPbd`, `DrawBatcher`, `RenderGraph`)**
  - **Priority:** P1
  - **DependsOn:** `[P4-W12-0]`
  - **Owns:** `lib/src/engine/components/light_probe_gi.dart`, `lib/src/engine/components/lighting_2d.dart`, `lib/src/engine/components/soft_body_xpbd.dart`, `lib/src/engine/components/draw_batcher.dart`, `lib/src/engine/components/render_graph.dart`, `test/engine/render_wiring_test.dart`
  - **Reads:** `lib/src/engine/host.dart`, `vendor/pixeldart/lib/rendering/api/**`
  - **Scope:**
    - Wire `LightProbeVolumeComponent` baked/interpolated SH3 irradiance coefficients into `Graphics.setShaderUniform`.
    - Wire `Lighting2DComponent` + `ShadowCaster2DComponent` lightmap/shadow geometry into a declared `R3` 2D composition pass / overlay shader uniform+texture.
    - Wire `SoftBodyXpbdComponent` vertex solver positions/recomputed normals back into dynamic mesh buffer updates (not just `transform.position = centerOfMass`).
    - Connect `DrawBatcherComponent` (`IndirectDrawTable`) and `RenderGraphComponent` to declared renderer batching/pass execution.
  - **DoneWhen:** `dart test test/engine/render_wiring_test.dart` proves each subsystem modifies real `Graphics` shader uniforms, dynamic mesh vertex positions, or declared render passes.

- [x] **[P4-W12-M] Coordinator Merge: Integrate Wave 12 Into `Scene`, `ComponentSpec` & Submodule Commit**
  - **Priority:** P0
  - **DependsOn:** `[P4-W12-A]`, `[P4-W12-B1]`, `[P4-W12-B2]`, `[P4-W12-C]`, `[P4-W12-D]`
  - **Owns:** `lib/gl_volition.dart`, `lib/src/engine/scene.dart`, `lib/src/engine/serialization/component_spec.dart`
  - **Scope:** Register `SkinnedMeshRenderer` / wired components, commit/push `vendor/pixeldart`, update root gitlink reference, verify `dart run tool/verify_all.dart` + Browser Lab.

---

## Wave 13 (Phase 5) — Scalable 3D Physics, True Colliders & Runtime Determinism

**Wave Exit Gate:** `PhysicsWorld` steps 1,000+ colliders in sub-linear spatial broadphase, rotated `BoxCollider` uses true OBB SAT, `MeshCollider`/`HeightfieldCollider` + rotational dynamics/joints/CCD pass stress suites, and 600-frame deterministic + comfort tests are green.

- [x] **[P5-W13-0] Coordinator Pre-Split: Modularize `physics.dart` & Freeze Narrowphase/Broadphase Interfaces**
  - **Priority:** P0
  - **DependsOn:** `[P4-W12-M]`
  - **Owns:** `lib/src/engine/components/physics.dart` (barrel export), `lib/src/engine/components/physics_broadphase.dart`, `lib/src/engine/components/physics_colliders.dart`, `lib/src/engine/components/physics_solver.dart`, `lib/src/engine/components/physics_world.dart`
  - **Scope:** Split the single `physics.dart` file cleanly into modular collaborators while keeping all public symbol exports identical (`lib/src/engine/components/physics.dart` re-exports all split files) so existing callers suffer zero breakage.
  - **DoneWhen:** `dart analyze` + existing `test/physics/**` pass 100% unchanged after split.

- [x] **[P5-W13-A] Spatial Broadphase Acceleration Replacing `O(N^2)` `PhysicsWorld` Loops**
  - **Priority:** P1
  - **DependsOn:** `[P5-W13-0]`
  - **Owns:** `lib/src/engine/components/physics_broadphase.dart`, `lib/src/engine/components/broadphase_world.dart`, `test/physics/broadphase_test.dart`
  - **Scope:** Replace quadratic pairwise iteration and linear `raycast`/`raycastAll`/`overlapSphere`/`overlapBox`/`sphereCast` scans with uniform spatial hash / BVH broadphase backed cleanly by `BroadphaseWorldComponent`.
  - **DoneWhen:** `dart test test/physics/broadphase_test.dart` proves exact hit parity against brute-force reference plus benchmark speedups on 1,500+ colliders.

- [x] **[P5-W13-B] True SAT OBB `BoxCollider`, BVH `MeshCollider` & `HeightfieldCollider`**
  - **Priority:** P1
  - **DependsOn:** `[P5-W13-0]`
  - **Owns:** `lib/src/engine/components/physics_colliders.dart`, `test/physics/colliders_test.dart`
  - **Scope:**
    - Replace AABB `worldBounds` approximation on rotated `BoxCollider` with true 15-axis Separating Axis Theorem (SAT) OBB vs OBB / Sphere / Capsule / Ray intersection.
    - Add BVH-accelerated static concave `MeshCollider` and grid `HeightfieldCollider` for terrain.
  - **DoneWhen:** `dart test test/physics/colliders_test.dart` verifies rotated box edges/corners, triangle mesh raycasts, and terrain contacts accurately.

- [x] **[P5-W13-C] Rotational `RigidBody` Inertia, Torque/Friction, Joints, Sleeping & Swept CCD**
  - **Priority:** P1
  - **DependsOn:** `[P5-W13-0]`
  - **Owns:** `lib/src/engine/components/physics_solver.dart`, `lib/src/engine/components/constraints.dart`, `lib/src/engine/components/physics_world.dart`, `test/physics/solver_ccd_test.dart`
  - **Scope:**
    - Add inertia tensors, angular velocity/impulse, static/dynamic friction, restitution, warm-started sequential impulse solver iterations, island sleeping, hinge/ball/fixed joints, and swept TOI CCD in `RigidBody._step()` so high-velocity projectiles never tunnel thin walls.
  - **DoneWhen:** `dart test test/physics/solver_ccd_test.dart` verifies box stack stability, non-tunneling fast projectiles at >500 units/sec, angular toppling torque, and sleeping island wakeups.

- [x] **[P5-W13-D] 600-Frame Temporal Determinism, Live `reducedMotion` & Comfort Stability Gates**
  - **Priority:** P1
  - **DependsOn:** `[P5-W13-0]`
  - **Owns:** `test/determinism/temporal_determinism_test.dart`, `test/determinism/comfort_stability_test.dart`
  - **Reads:** `lib/src/engine/**`, `vendor/pixeldart/**`
  - **Scope:**
    - Author `TODO.md` carry-over tests: 600-frame fixed-step deterministic state-hash repeatability across physics/AI/animation, live runtime toggling of `reducedMotion`, automated luminance/photosensitivity flash-rate safety gate, and multi-frame visual-stability checks.
  - **DoneWhen:** `dart test test/determinism` passes repeatedly across isolated runs with bit-identical final state snapshots.

---

## Wave 14 (Phase 6) — Real Multiplayer Networking (`voxnet` Transports + Engine Tick Sync)

**Wave Exit Gate:** Cross-platform `WebSocket` + native UDP/reliable channels transport packets cleanly, and `Engine.step` drives live multi-client entity replication + rollback reconciliation under synthetic loss/jitter.

- [x] **[P6-W14-0] Coordinator Freeze: Production `NetTransport` TLS/Auth/Metrics & Engine Sync Hooks**
  - **Priority:** P1
  - **DependsOn:** `[P5-W13-D]`
  - **Owns:** `vendor/voxnet/lib/src/transport/transport.dart`, `lib/src/engine/network/network_config.dart`
  - **Reads:** `lib/src/engine/network/network_system.dart`
  - **Scope:** Extend `NetTransport` with connection states, TLS/token header options, RTT/loss telemetry counters, and `NetworkClockSync` / tick-hook config interfaces.
  - **DoneWhen:** `vendor/voxnet` and root `dart analyze` pass.

- [x] **[P6-W14-A] Cross-Platform `WebSocketNetTransport` (`dart:io` + `package:web`)**
  - **Priority:** P1
  - **DependsOn:** `[P6-W14-0]`
  - **Owns:** `vendor/voxnet/lib/src/transport/websocket_transport.dart`, `vendor/voxnet/lib/src/transport/websocket_transport_io.dart`, `vendor/voxnet/lib/src/transport/websocket_transport_web.dart`, `vendor/voxnet/test/websocket_transport_test.dart`
  - **Scope:** Implement WebSocket client/server (IO) + browser client (`package:web`) with binary framing, heartbeat pings, exponential reconnect backoff, and session token auth.
  - **DoneWhen:** `vendor/voxnet` WebSocket loopback integration tests pass on VM + compile cleanly to JS (`dart compile js`).

- [x] **[P6-W14-B] Native UDP / Reliable-Unreliable Channel Transport (`dart:io` `RawDatagramSocket` / FFI)**
  - **Priority:** P1
  - **DependsOn:** `[P6-W14-0]`
  - **Owns:** `vendor/voxnet/lib/src/transport/udp_transport.dart`, `vendor/voxnet/lib/src/transport/reliable_channel.dart`, `vendor/voxnet/test/udp_transport_test.dart`
  - **Scope:** Implement sequenced/acknowledged reliable + unreliable/unordered channels over UDP (`RawDatagramSocket` / FFI wrapper), congestion windowing, MTU fragmentation, and synthetic jitter/loss fault injector for tests.
  - **DoneWhen:** `vendor/voxnet` `dart test test/udp_transport_test.dart` passes under 10% simulated packet drop & reordering.

- [x] **[P6-W14-C] Automatic `NetworkManager` Tick/Replication Sync & Multi-Client Rollback Test Harness**
  - **Priority:** P1
  - **DependsOn:** `[P6-W14-0]`, `[P6-W14-A]`, `[P6-W14-B]`
  - **Owns:** `lib/src/engine/network/network_system.dart`, `test/network/multiplayer_sync_test.dart`
  - **Reads:** `lib/src/engine.dart`
  - **Scope:** Implement delta-compressed snapshot sync, client input prediction, rollback reconciliation hooks in `NetworkManager`, and an automated multi-process/multi-socket integration test over real `ws://` & UDP loopback.
  - **DoneWhen:** `dart test test/network/multiplayer_sync_test.dart` verifies converging multi-client state over real loopback sockets with synthetic latency.

- [x] **[P6-W14-M] Coordinator Merge: Hook `NetworkManager` Step Into `Engine.step` & Push `voxnet` Gitlink**
  - **Priority:** P0
  - **DependsOn:** `[P6-W14-A]`, `[P6-W14-B]`, `[P6-W14-C]`
  - **Owns:** `lib/src/engine.dart`, `vendor/voxnet` submodule commit/gitlink
  - **Scope:** Invoke `NetworkManager` fixed tick + post-step snapshot replication cleanly from `Engine.step`, verify full `verify_all.dart`.

---

## Wave 15 (Phase 7) — Production Editor UX, Diagnostics & Ship Tooling

**Wave Exit Gate:** Delta undo/redo handles 1,000+ object edits smoothly, 3D viewport gizmos pick/drag live transforms, full telemetry/transient stress checks pass, `volition doctor` + `volition create` + `--target server` work, and package publication strategy is finalized.

- [x] **[P7-W15-A] Compact `EditorCommand` Delta Undo/Redo Replacing Full-Scene JSON Snapshots**
  - **Priority:** P2
  - **DependsOn:** `[P6-W14-M]`
  - **Owns:** `lib/src/engine/editor_commands.dart`, `lib/src/engine/editor_session.dart`, `test/engine/editor_undo_delta_test.dart`
  - **Reads:** `lib/src/engine/serialization/scene_serializer.dart`
  - **Scope:** Replace `EditorSession._captureHistoryEntry` (`:80-94`) full-scene JSON dumps with composable reversible `EditorCommand` objects (property set, transform move, add/remove object/component, reparent, transaction batch).
  - **DoneWhen:** `dart test test/engine/editor_undo_delta_test.dart` demonstrates multi-step undo/redo memory/time scaling O(delta) vs O(scene) on a 1,000-entity scene.

- [x] **[P7-W15-B] Live 3D Viewport Gizmos, Unified Workbench/Inspector Picker & Prefab Variant UI**
  - **Priority:** P2
  - **DependsOn:** `[P6-W14-M]`
  - **Owns:** `lib/src/engine/gizmos/viewport_gizmos.dart`, `lib/src/engine/components/engine_workbench.dart`, `lib/src/web/inspector_overlay.dart`, `test/engine/gizmos_workbench_test.dart`
  - **Reads:** `lib/src/engine/editor_session.dart`, `lib/src/engine/prefab.dart`, `lib/src/engine/assets/asset_catalog.dart`
  - **Scope:**
    - Implement interactive 3D translate/rotate/scale gizmo axis raycasting and drag manipulation synchronized with `EditorSession`.
    - Add `AssetCatalog` visual resource picker and prefab-variant override badges/revert controls unified cleanly between `EngineWorkbenchComponent` (`voxui`) and `InspectorOverlay` (Web DOM).
  - **DoneWhen:** `dart test test/engine/gizmos_workbench_test.dart` verifies gizmo axis hit-testing, snapped dragging, and prefab override inspection; `dart compile js` builds cleanly.

- [x] **[P7-W15-C] CLI DX (`volition create`, `doctor`, `--target server`), Transient Stress, Telemetry & Package Split Decision**
  - **Priority:** P1
  - **DependsOn:** `[P6-W14-M]`
  - **Owns:** `bin/volition.dart`, `lib/src/engine/diagnostics/telemetry_snapshot.dart`, `lib/src/native/server_host.dart`, `test/engine/diagnostics_cli_test.dart`
  - **Reads:** `pubspec.yaml`, `lib/src/engine/headless.dart`
  - **Scope:**
    - Add `volition create <name> [--template 2d|3d|multiplayer]`, `volition doctor` (checks Dart SDK, Chrome/WebGL, MSVC/Clang, SDL3/GLES DLLs, shader toolchain), and `--target server` zero-GPU dedicated multiplayer server binary entrypoint (`server_host.dart`).
    - Implement full runtime diagnostics snapshot JSON + transient particle/VFX/decal stress suite + uncaught crash telemetry handler hook (`TODO.md` carry-over).
    - Document package publication architecture decision (`publish_to: none` monorepo vs split `pub.dev` releases for `gl_volition`, `pixeldart`, `vox*`) in a brief ADR section of `PLAN.md` during merge.
  - **DoneWhen:** `dart test test/engine/diagnostics_cli_test.dart` passes; `volition doctor` exits cleanly with accurate environment table; dedicated `--target server` AOT binary runs headless server tick loop.

- [x] **[P7-W15-M] Coordinator Final Sign-Off & Production Release Verification**
  - **Priority:** P0
  - **DependsOn:** `[P7-W15-A]`, `[P7-W15-B]`, `[P7-W15-C]`
  - **Owns:** `PLAN.md`, `ENGINE.md`, `TODO.md` status archive
  - **Scope:** Run complete `tool/verify_all.dart`, `tool/renderer_bench.dart`, Browser Lab, and native hardware smoke suite; record release tag readiness.

---

## Wave 16 (Phase 8) — Volition Studio GUI (`volition gui`)

**Wave Exit Gate:** `volition gui` launches a cross-platform Studio UI exposing `doctor`, `create`, `build`, `dist`, `pack`, `serve`, `test`, `verify_all`, and `renderer_bench` over a shared `VolitionCliService` + WebSocket RPC backend, with automated tests passing and `verify_all.dart` green.

- [x] **[P8-W16-0] Shared `VolitionCliService` Contract & Doctor/Entrypoint Discovery**
  - **Priority:** P1
  - **DependsOn:** `[P7-W15-M]`
  - **Owns:** `tool/cli_service.dart`
  - **Reads:** `bin/volition.dart`, `tool/asset_packer.dart`, `tool/package_native.dart`
  - **Scope:** Define `VolitionCliService`, `DoctorReport`, `DoctorCheckItem`, `CliTaskSession`, and `CliLogEvent` supporting `runDoctor()`, `discoverEntries()`, `runCommandStream()`, `startServe()`, `stopServe()`, and `cancelTask()`.
  - **DoneWhen:** `dart analyze` passes cleanly.

- [x] **[P8-W16-A] Local Studio HTTP + WebSocket RPC Server (`VolitionGuiServer`)**
  - **Priority:** P1
  - **DependsOn:** `[P8-W16-0]`
  - **Owns:** `tool/cli_gui_server.dart`
  - **Scope:** Serve the Studio SPA over localhost HTTP, bridge WebSocket JSON-RPC commands to `VolitionCliService`, stream real-time `stdout`/`stderr` task logs, and manage live `serve` process lifecycle with clean shutdown.
  - **DoneWhen:** `dart analyze` passes cleanly.

- [x] **[P8-W16-B] Embedded Studio Web UI (`tool/cli_gui_assets.dart`)**
  - **Priority:** P1
  - **DependsOn:** `[P8-W16-0]`
  - **Owns:** `tool/cli_gui_assets.dart`
  - **Scope:** Build self-contained, AOT-safe responsive Studio SPA with panels for Doctor, Create Project, Build & Dist, Asset Packer, Live Dev Server, and Tests & Gates, plus a cancelable streaming console.
  - **DoneWhen:** Embedded HTML/CSS/JS compiles cleanly with zero external runtime dependencies.

- [x] **[P8-W16-C] `volition gui` CLI Wiring, Docs & RPC Integration Tests**
  - **Priority:** P1
  - **DependsOn:** `[P8-W16-A]`, `[P8-W16-B]`
  - **Owns:** `bin/volition.dart`, `README.md`, `test/engine/cli_gui_test.dart`
  - **Scope:** Add `volition gui [--port 8090] [--no-open]` to `bin/volition.dart`, document `volition gui` in `README.md`, and verify service + HTTP/WebSocket RPC flows in `test/engine/cli_gui_test.dart`.
  - **DoneWhen:** `dart test test/engine/cli_gui_test.dart` and `dart run tool/verify_all.dart --check-format --skip-wasm` pass.

---

## Wave 17 (Phase 9) — Indexed Scene Queries, Replay Tapes, Multi-Selection Editor & Studio Inspector

**Wave Exit Gate:** Indexed `Scene` lookups and typed `query`/`query2`/`query3` archetypes operate without full-scene allocations, `InputTape` deterministically replays multi-modal inputs against 53-bit `SceneStateHasher` checkpoints, `EditorSession` multi-selection and batch undo commands pass regression suites, and Studio inspects `.pak` & `scene.json` artifacts cleanly with `verify_all.dart` green.

- [x] **[P9-W17-A] Indexed Scene Graph Lookups, Component Archetype Queries & Zero-Tree-Walk Renderer Sync**
  - **Priority:** P1
  - **DependsOn:** `[P8-W16-C]`
  - **Owns:** `lib/src/engine/game_object.dart`, `lib/src/engine/scene.dart`, `test/engine/scene_index_query_test.dart`
  - **Scope:** Maintain live `_objectsByTag`, `_nodeOwners`, and typed renderer component lists in `Scene`, reactively update `_objectsByTag` via `GameObject.tag` setter, eliminate full-scene tree walks in `_ownerOf` and `_behaviours` type checks in `_syncToRenderer`, and expose `query<A>`, `query2<A, B>`, `query3<A, B, C>`.
  - **DoneWhen:** `dart test test/engine/scene_index_query_test.dart` passes; `tool/check_boundaries.dart` reports 0 violations.

- [x] **[P9-W17-B] Deterministic Input Recorder, Frame Replay Tapes & Scene State Checksum Verifier (`InputTape`)**
  - **Priority:** P1
  - **DependsOn:** `[P8-W16-C]`
  - **Owns:** `lib/src/engine/replay/input_tape.dart`, `lib/src/engine.dart`, `test/engine/input_tape_replay_test.dart`
  - **Scope:** Implement pure-Dart `InputFrameSample`, `InputTape`, 53-bit cross-platform `SceneStateHasher`, `InputTapeRecorder`, `ReplayInputDriver`, and `EngineReplayHarness` for JSON-round-trippable deterministic gameplay verification.
  - **DoneWhen:** `dart test test/engine/input_tape_replay_test.dart` verifies bit-identical replay and tamper detection across 60 frames.

- [x] **[P9-W17-C] Multi-Selection Editor UX, Camera Framing (`focusSelection`), Hierarchy Search & Batch Commands**
  - **Priority:** P1
  - **DependsOn:** `[P8-W16-C]`
  - **Owns:** `lib/src/engine/editor_session.dart`, `lib/src/engine/editor_commands.dart`, `test/engine/editor_multiselection_test.dart`
  - **Scope:** Upgrade `EditorSession` to multi-selection (`select`, `selectAll`, `clearSelection`, `selectionCentroid`, `selectionWorldBounds`, `focusSelection`, `searchHierarchy`) while preserving single-selection compatibility, and add `BatchTransformDeltaCommand`, `BatchSetActiveCommand`, and `BatchDeleteCommand`.
  - **DoneWhen:** `dart test test/engine/editor_multiselection_test.dart` passes.

- [x] **[P9-W17-D] Studio Scene & `.pak` Archive Inspector Panel + Unified CLI `doctor --json` / `create` Web Template**
  - **Priority:** P1
  - **DependsOn:** `[P9-W17-A]`, `[P9-W17-B]`, `[P9-W17-C]`
  - **Owns:** `tool/cli_service.dart`, `tool/cli_gui_server.dart`, `tool/cli_gui_assets.dart`, `bin/volition.dart`, `test/engine/cli_gui_test.dart`, `test/engine/diagnostics_cli_test.dart`, `PLAN.md`, `TODO.md`
  - **Scope:** Add `discoverInspectableFiles` / `inspectArtifact` and WebSocket RPC (`inspector.list`, `inspector.inspect`) to Volition Studio, delegate `volition doctor [--json]` through `VolitionCliService`, and generate `index.html` in `volition create`.
  - **DoneWhen:** `dart test test/engine/cli_gui_test.dart test/engine/diagnostics_cli_test.dart` and `dart run tool/verify_all.dart --check-format --skip-wasm` pass.

---

## Wave 18 (Phase 10) — Advanced Gizmos, Additive Scenes, Integrity Save Bundles, Live Prefab Propagation & Replay CLI

**Wave Exit Gate:** Local/world planar 3D gizmos & multi-selection pivot drag pass `gizmos_workbench_test.dart`, additive scene loading & CRC32/bundle save system pass `scene_save_subsystems_test.dart`, prefab diffing/extraction/hot-propagation pass `prefab_live_propagation_test.dart`, and `volition replay` + Studio `tape.verify` RPC pass `cli_gui_test.dart` with `verify_all.dart` 10/10 green.

- [x] **[P10-W18-A] Advanced 3D Viewport Gizmos (Local/World Space, Planar Dual-Axis Handles & Multi-Selection Pivot Drag)**
  - **Priority:** P1
  - **DependsOn:** `[P9-W17-D]`
  - **Owns:** `lib/src/engine/gizmos/viewport_gizmos.dart`, `test/engine/gizmos_workbench_test.dart`
  - **Reads:** `lib/src/engine/editor_session.dart`, `lib/src/engine/editor_commands.dart`
  - **Scope:** Add `ViewportGizmoSpace.world`/`local`, planar `xy`/`xz`/`yz` handles with `intersectRayPlane` hit-testing & dragging, and `beginSelectionDrag`/`updateSelectionDrag`/`endSelectionDrag` returning reversible `CompoundCommand`.
  - **DoneWhen:** `dart test test/engine/gizmos_workbench_test.dart` and `dart analyze` pass cleanly.

- [x] **[P10-W18-B] Additive Multi-Scene Composition (`SceneManager`) & Integrity/Bundle Save System (`SaveSystem`)**
  - **Priority:** P1
  - **DependsOn:** `[P9-W17-D]`
  - **Owns:** `lib/src/engine/scene_manager.dart`, `lib/src/engine/save_system.dart`, `test/engine/scene_save_subsystems_test.dart`
  - **Reads:** `lib/src/engine/scene.dart`, `lib/src/engine/serialization/scene_serializer.dart`, `vendor/voxpack/lib/voxpack.dart`
  - **Scope:** Add `loadAdditive`, `unloadAdditive`, `isAdditiveLoaded`, `loadedAdditiveScenes` to `SceneManager`, and CRC32 `verifySlotIntegrity`, `loadDataMigrated`, `exportSlotBundle`, `importSlotBundle` to `SaveSystem`.
  - **DoneWhen:** `dart test test/engine/scene_save_subsystems_test.dart` and `dart analyze` pass cleanly.

- [x] **[P10-W18-C] Live Prefab Instance Diffing, Variant Extraction & Hot-Propagation (`PrefabRegistry`)**
  - **Priority:** P1
  - **DependsOn:** `[P9-W17-D]`
  - **Owns:** `lib/src/engine/prefab_registry.dart`, `test/engine/prefab_live_propagation_test.dart`
  - **Reads:** `lib/src/engine/prefab.dart`, `lib/src/engine/serialization/scene_serializer.dart`, `lib/src/engine/gizmos/viewport_gizmos.dart`
  - **Scope:** Ensure `PrefabRegistry.instantiate` attaches `PrefabInstanceComponent`, add `computeInstanceOverrides` and `extractVariantFromInstance`, and add live `propagatePrefabChanges` preserving transforms and overrides.
  - **DoneWhen:** `dart test test/engine/prefab_live_propagation_test.dart` and `dart analyze` pass cleanly.

- [x] **[P10-W18-D] Headless Replay CLI (`volition replay`) & Volition Studio Replay Verification Integration**
  - **Priority:** P1
  - **DependsOn:** `[P9-W17-D]`
  - **Owns:** `tool/cli_service.dart`, `tool/cli_gui_server.dart`, `tool/cli_gui_assets.dart`, `bin/volition.dart`, `test/engine/cli_gui_test.dart`
  - **Reads:** `lib/src/engine/replay/input_tape.dart`
  - **Scope:** Add `*tape*.json` discovery/inspection and `verifyInputTapeFile` to `VolitionCliService`, `tape.verify` RPC in `VolitionGuiServer`, "Verify Replay Tape" UI controls in `cli_gui_assets.dart`, and `volition replay <tape.json> [--json]` in `bin/volition.dart`.
  - **DoneWhen:** `dart test test/engine/cli_gui_test.dart` and `dart analyze` pass cleanly.

- [x] **[P10-W18-M] Coordinator Merge, Full Verification & Wave 18 Commit**
  - **Priority:** P0
  - **DependsOn:** `[P10-W18-A]`, `[P10-W18-B]`, `[P10-W18-C]`, `[P10-W18-D]`
  - **Owns:** `PLAN.md`, `TODO.md`, root formatting, full 10-gate verification, and git commit
  - **Scope:** Verify zero boundary violations, run `dart format`, `dart analyze`, full `verify_all.dart --check-format --skip-wasm`, mark Wave 18 complete, and commit.

---

## Wave 19 (Phase 11) — Input Rebinding Profiles, Prioritized Events & Coroutines, Runtime Dev Console & Scoped Profiler

**Wave Exit Gate:** Rebindable keyboard+gamepad `InputActions` profiles, prioritized/deferred `SceneEvents` & composable `Coroutine` instructions, `DebugConsole` commands/autocomplete, and `Stopwatch`-measured `FrameProfilerComponent` spans pass targeted tests and full 10-gate `verify_all.dart`.

- [x] **[P11-W19-A] Runtime Input Rebinding, Gamepad Button/Axis Integration & JSON Profile Persistence**
  - **Priority:** P1
  - **DependsOn:** `[P10-W18-M]`
  - **Owns:** `lib/src/engine/input_actions.dart`, `test/engine/wave19_runtime_ux_test.dart`
  - **Scope:** Add gamepad button/axis bindings, deadzone handling, `rebindButton`/`rebindAxis`, `exportBindingsJson`/`importBindingsJson`, and `saveToStore`/`loadFromStore` to `InputActions`.
  - **DoneWhen:** `dart test test/engine/wave19_runtime_ux_test.dart` passes cleanly.

- [x] **[P11-W19-B] Prioritized & Deferred `SceneEvents` + Composable `Coroutine` Instructions**
  - **Priority:** P1
  - **DependsOn:** `[P10-W18-M]`
  - **Owns:** `lib/src/engine/events_coroutines.dart`, `test/engine/wave19_runtime_ux_test.dart`
  - **Scope:** Add priority ordering, `once<E>`, `emitDeferred<E>`/`flushDeferred()`, and `listenerCount<E>()` to `SceneEvents`; add `WaitWhile`, `WaitForFrames`, and `WaitForCoroutine` yield instructions to `Coroutine`.
  - **DoneWhen:** `dart test test/engine/wave19_runtime_ux_test.dart` passes cleanly.

- [x] **[P11-W19-C] Runtime Developer Console & Built-In Command Registry (`DebugController`)**
  - **Priority:** P1
  - **DependsOn:** `[P10-W18-M]`
  - **Owns:** `lib/src/engine/debug_controller.dart`, `test/engine/wave19_runtime_ux_test.dart`
  - **Scope:** Add `DebugConsole` with quoted-argument parsing, history, prefix autocompletion, custom command registration, and built-in scene/time/entity commands on `DebugController`.
  - **DoneWhen:** `dart test test/engine/wave19_runtime_ux_test.dart` passes cleanly.

- [x] **[P11-W19-D] Scoped Sub-Frame `Stopwatch` Profiler Spans & JSON Telemetry Export**
  - **Priority:** P1
  - **DependsOn:** `[P10-W18-M]`
  - **Owns:** `lib/src/engine/components/frame_profiler.dart`, `test/engine/wave19_runtime_ux_test.dart`
  - **Scope:** Add `beginSpan`, `endSpan`, `measureSpan`, and `exportTelemetryJson()` to `FrameProfilerComponent`.
  - **DoneWhen:** `dart test test/engine/wave19_runtime_ux_test.dart` and `dart run tool/verify_all.dart --check-format --skip-wasm` pass.

---

## Wave 20 (Phase 12) — Hitstop Clock, Guarded/Triggered FSM, AudioMixer Snapshots/Ducking & Tween Sequences

**Wave Exit Gate:** Hitstop clock freeze/resume, guarded/timed/triggered `StateMachine`, `AudioMixer` snapshot transitions & bus ducking, and `tweenRotation`/`tweenColor`/`tweenSequence` pass `wave20_game_feel_test.dart` and full 10-gate `verify_all.dart`.

- [x] **[P12-W20-A] Hitstop / Freeze-Frame Clock (`Time`)**
  - **Priority:** P1
  - **DependsOn:** `[P11-W19-D]`
  - **Owns:** `lib/src/engine/time.dart`, `test/engine/wave20_game_feel_test.dart`
  - **Scope:** Add `triggerHitstop`, `cancelHitstop`, `isInHitstop`, and `hitstopRemaining` on `Time` without mutating user `timeScale`.
  - **DoneWhen:** `dart test test/engine/wave20_game_feel_test.dart` passes.

- [x] **[P12-W20-B] Guarded, Triggered & Timed `StateMachine<S>` Transitions**
  - **Priority:** P1
  - **DependsOn:** `[P11-W19-D]`
  - **Owns:** `lib/src/engine/state_machine.dart`, `test/engine/wave20_game_feel_test.dart`
  - **Scope:** Add `addTransition`, `addAnyTransition`, `addTrigger`, `fireTrigger`, and `revertToPreviousState`.
  - **DoneWhen:** `dart test test/engine/wave20_game_feel_test.dart` passes.

- [x] **[P12-W20-C] `AudioMixer` Snapshots, Smooth Blending & Bus Ducking**
  - **Priority:** P1
  - **DependsOn:** `[P11-W19-D]`
  - **Owns:** `lib/src/engine/components/audio_source.dart`, `lib/src/engine/scene.dart`, `test/engine/wave20_game_feel_test.dart`
  - **Scope:** Add `AudioMixerSnapshot`, `defineSnapshot`, `captureSnapshot`, `applySnapshot`, and `duckBus`, automatically stepped in `Scene._syncToRenderer`.
  - **DoneWhen:** `dart test test/engine/wave20_game_feel_test.dart` passes.

- [x] **[P12-W20-D] Rotation, Color & Sequence Tweens (`BehaviourTweenExt`)**
  - **Priority:** P1
  - **DependsOn:** `[P11-W19-D]`
  - **Owns:** `lib/src/engine/tween.dart`, `test/engine/wave20_game_feel_test.dart`
  - **Scope:** Add `tweenRotation`, `tweenColor`, and `tweenSequence` using `Quat.slerp` and `WaitForCoroutine`.
  - **DoneWhen:** `dart test test/engine/wave20_game_feel_test.dart` and `dart run tool/verify_all.dart --check-format --skip-wasm` pass.

---

## Wave 21 (Phase 13) — Platformer CharacterController, Exact SpatialGrid2D & Camera Frustum Batching

**Wave Exit Gate:** Coyote-time/jump-buffer/moving-platform `CharacterController`, exact circle/nearest/DDA-ray `SpatialGrid2D`, and single-pass `Camera.collectVisibleMeshes` pass `wave21_gameplay_spatial_test.dart` and full 10-gate `verify_all.dart`.

- [x] **[P13-W21-A] Platformer-Grade `CharacterController` (Coyote Time, Jump Buffering & Moving Platform Carry)**
  - **Priority:** P1
  - **DependsOn:** `[P12-W20-D]`
  - **Owns:** `lib/src/engine/components/character_controller.dart`, `test/engine/wave21_gameplay_spatial_test.dart`
  - **Scope:** Add `coyoteTime`, `jumpBufferTime`, `queueJump`, `consumeBufferedJump`, `groundNormal`, `groundObject`, and moving platform carry tracking.
  - **DoneWhen:** `dart test test/engine/wave21_gameplay_spatial_test.dart` passes.

- [x] **[P13-W21-B] Exact `SpatialGrid2D` Circle Queries, Nearest-Neighbor & DDA Ray Traversal**
  - **Priority:** P1
  - **DependsOn:** `[P12-W20-D]`
  - **Owns:** `lib/src/engine/spatial_grid_2d.dart`, `test/engine/wave21_gameplay_spatial_test.dart`
  - **Scope:** Add cell-coherent `update`, `queryCircleExact`, `findNearest`, and `queryRay`.
  - **DoneWhen:** `dart test test/engine/wave21_gameplay_spatial_test.dart` passes.

- [x] **[P13-W21-C] Camera Batch Frustum Culling (`collectVisibleMeshes`, `isPointVisible`, `isAabbVisible`)**
  - **Priority:** P1
  - **DependsOn:** `[P12-W20-D]`
  - **Owns:** `lib/src/engine/components/camera.dart`, `test/engine/wave21_gameplay_spatial_test.dart`
  - **Scope:** Add single-pass frustum culling batching and point/AABB visibility helpers respecting `cullingMask`.
  - **DoneWhen:** `dart test test/engine/wave21_gameplay_spatial_test.dart` and `dart run tool/verify_all.dart --check-format --skip-wasm` pass.

---

## Wave 22 (Phase 14) — Animation Event Markers, LOD Hysteresis & Timed Particle Burst Schedules

**Wave Exit Gate:** Skeletal animation event markers across looped & one-shot clips, anti-popping `LodGroup` hysteresis/bias/forced-override, and timed `ParticleBurstSchedule` schedules pass `wave22_animation_lod_particles_test.dart` and full 10-gate `verify_all.dart`.

- [x] **[P14-W22-A] Skeletal Animation Event Markers (`AnimationEventMarker` on `SkeletalClip` & `Animator`)**
  - **Priority:** P1
  - **DependsOn:** `[P13-W21-C]`
  - **Owns:** `lib/src/engine/components/animator.dart`, `test/engine/wave22_animation_lod_particles_test.dart`
  - **Scope:** Add `AnimationEventMarker`, `SkeletalClip.events`, `Animator.addClipEvent`, `Animator.onEvent`, and wrap-safe timestamp crossing dispatch.
  - **DoneWhen:** `dart test test/engine/wave22_animation_lod_particles_test.dart` passes.

- [x] **[P14-W22-B] Anti-Popping `LodGroup` Hysteresis, Quality `lodBias` & `forcedLevelIndex`**
  - **Priority:** P1
  - **DependsOn:** `[P13-W21-C]`
  - **Owns:** `lib/src/engine/components/lod_billboard.dart`, `test/engine/wave22_animation_lod_particles_test.dart`
  - **Scope:** Add `hysteresis`, `lodBias`, and `forcedLevelIndex` to `LodGroup` with `ComponentSpec` fields.
  - **DoneWhen:** `dart test test/engine/wave22_animation_lod_particles_test.dart` passes.

- [x] **[P14-W22-C] Timed `ParticleBurstSchedule` Schedules & Playback Controls on `ParticleSystem`**
  - **Priority:** P1
  - **DependsOn:** `[P13-W21-C]`
  - **Owns:** `lib/src/engine/components/particle_system.dart`, `lib/src/engine/scene.dart`, `test/engine/wave22_animation_lod_particles_test.dart`
  - **Scope:** Add `ParticleBurstSchedule`, `play`/`pause`/`stop`, and automatic burst timeline firing in `Scene._syncToRenderer`.
  - **DoneWhen:** `dart test test/engine/wave22_animation_lod_particles_test.dart` and `dart run tool/verify_all.dart --check-format --skip-wasm` pass.

---

## Volition Studio Track (`S1`–`S8`) — Unity-Class Engine & Renderer Upgrade

> **Plan:** [PLAN.md §13](PLAN.md#13-unity-class-engine-roadmap--volition-studio-track-phases-s1s8). **North star:** Volition Studio + the `volition` CLI is where every `vendor/*` submodule comes together.
> **IDs:** `[Sx-0]` Coordinator freeze → `[Sx-A..F]` parallel workers → `[Sx-M]` Coordinator merge. This track's IDs stay separate from the numbered `[Px-Wy-z]` waves; interleave only with disjoint `Owns`.
> **Track-wide DoneWhen rules (PLAN §13.3, Invariants 6–10):** `dart analyze`, `dart run tool/check_boundaries.dart` (now covering `lib/src/studio/**`), and targeted tests are always required. Renderer tasks also require `dart run tools/renderer/shaders.dart --check` and `dart run tools/renderer/test_all.dart` inside `vendor/pixeldart`, a Browser Lab golden for visual changes, and a native readback golden when a GPU is present (otherwise reported as **skipped**, never as passing). Every performance claim is a measured number.

---

## Phase S1 — Ground-Truth Debt Closure & Foundations (GPU Device v2, GUID Assets, Module Registry)

**Exit Gate:** No fixed `uniform mat4 …[N]` arrays in world/shadow/depth shaders; device API v2 is implemented on WebGL2, `Gles3FfiDevice` and `RecordingGlesDevice`; GUID references survive rename/move; the module registry inventories 74/74 packages; the boundary checker covers `lib/src/studio/**`.

- [x] **[S1-0] Coordinator Freeze: GPU Device API v2, Studio Protocol v2, Project FS & Editor Boundaries**
  - **Priority:** P0
  - **DependsOn:** none (current `main`)
  - **Owns:** `vendor/pixeldart/lib/rendering/webgl/device_api.dart`, `vendor/pixeldart/lib/rendering/api/capabilities.dart`, `lib/src/studio/protocol/**`, `lib/src/studio/project/project_fs.dart`, `lib/src/studio/studio.dart`, `tool/check_boundaries.dart`
  - **Scope:**
    - Device API v2 (signatures only plus capability bits): uniform buffers (`createUniformBuffer`, `updateUniformBuffer`, `bindUniformBufferBase`, `uniformBlockBinding`), cubemap textures (6 faces + mips), 2D texture arrays, half-float/float color targets (`EXT_color_buffer_float` / `EXT_color_buffer_half_float` capability), MRT `drawBuffers`, instanced attribute divisors, occlusion queries (`ANY_SAMPLES_PASSED_CONSERVATIVE`), and per-pass timer-query scopes.
    - Studio Protocol v2: versioned typed envelopes (`StudioRequest`, `StudioResponse`, `StudioEvent`), a method-id registry, error codes, and a JSON codec. Every method declares its CLI mapping, which the `[S2-M]` parity gate checks.
    - `ProjectFileSystem` interface (`read`, `write`, `list`, `stat`, `watch`, `move`, `delete`) so AssetDatabase logic stays pure Dart.
    - Extend `tool/check_boundaries.dart` so `lib/src/studio/**` gets the same import bans as `lib/src/engine/**`, and so `lib/src/engine/**` may not import `lib/src/studio/**`.
  - **DoneWhen:** Root and `vendor/pixeldart` `dart analyze` pass; `dart run tool/check_boundaries.dart` passes and has a test fixture proving a `dart:io` import under `lib/src/studio/` is rejected.

- [ ] **[S1-A] Device API v2 Implementations (WebGL2, `Gles3FfiDevice`, `RecordingGlesDevice`)**
  - **Priority:** P0
  - **DependsOn:** `[S1-0]`
  - **Owns:** `vendor/pixeldart/lib/rendering/webgl/webgl2_device.dart`, `vendor/pixeldart/lib/rendering/webgl/webgl2_device_*.dart`, `vendor/pixeldart/lib/rendering/webgl/state_cache.dart`, `vendor/pixeldart/tools/renderer/test_device_v2.dart`, `lib/src/native/gles3_bindings.dart`, `lib/src/native/gles3_ffi_device.dart`, `lib/src/native/native_host.dart` (`RecordingGlesDevice` only), `test/native/gles3_device_v2_test.dart`
  - **Scope:** Implement every `[S1-0]` op on all three devices, with state-cache awareness (UBO binding points, texture-array/cube units). Resolve the new GLES3 entry points via FFI with actionable missing-symbol diagnostics, and record commands deterministically for CI.
  - **DoneWhen:** `test_device_v2.dart` and `test/native/gles3_device_v2_test.dart` assert recorded command streams for each new op and an FFI symbol table containing `glBindBufferBase`, `glUniformBlockBinding`, `glTexImage3D`, `glDrawBuffers`, `glVertexAttribDivisor` and `glBeginQuery`. When hardware is present, a native readback renders a cubemap face and an RGBA16F target.

- [ ] **[S1-B] Uncapped Instancing, UBO Frame Data & 256-Joint Skinning (reopens `[P4-W12-B2]` / `[P4-W12-C]`)**
  - **Priority:** P0
  - **DependsOn:** `[S1-0]`
  - **Owns:** `vendor/pixeldart/shaders/rendering/world/**`, `vendor/pixeldart/shaders/rendering/shadow/**`, `vendor/pixeldart/shaders/rendering/depth/**`, `vendor/pixeldart/lib/rendering/passes/{world,textured_world,shadowed_world,shadow,depth_prepass}.dart`, `vendor/pixeldart/lib/rendering/webgl/instanced_stream.dart`, `vendor/pixeldart/lib/rendering/webgl/generated_shaders.dart`, `vendor/pixeldart/tools/renderer/test_no_fixed_uniform_caps.dart`, `vendor/pixeldart/tools/renderer/test_instancing_uncapped.dart`, `lib/src/engine/components/skinned_mesh.dart`, `test/engine/skinning_256_test.dart`
  - **Scope:**
    - Replace `uInstanceModels[16]` / `uInstanceNormalMatrices[16]` (`shadowed_world.vert:13-14`) with per-instance vertex attributes (divisor 1) fed by `InstanceBufferStream` in all world, shadow and depth passes, so the 16-per-draw split disappears.
    - Move camera/frame data (`uViewProjection`, `uView`, camera position, time, exposure placeholder) into a std140 `FrameBlock` UBO shared across passes.
    - Replace `uJointMatrices[64]` (`:25`) with a 256-joint std140 UBO palette, falling back to an RGBA32F joint texture when `MAX_UNIFORM_BLOCK_SIZE` is too small. Skin shadow-caster and depth-prepass vertices too. Raise `SkinnedMeshRenderer` capacity constants to match.
  - **DoneWhen:** `test_no_fixed_uniform_caps.dart` scans `shaders/rendering/{world,shadow,depth}/**` and fails on any `uniform mat4 \w+\[\d+\]`. `test_instancing_uncapped.dart` proves 4,096 instances go out in exactly one recorded `drawElementsInstanced`. `test/engine/skinning_256_test.dart` matches a 200-joint CPU reference within 1e-4. Browser Lab goldens of the instanced forest and skinned character are unchanged (SSIM ≥ 0.99).

- [x] **[S1-C] Project Format, `.vmeta` GUID Sidecars & `AssetDatabase` with Incremental Import Cache**
  - **Priority:** P0
  - **DependsOn:** `[S1-0]`
  - **Owns:** `lib/src/studio/project/**` (except `project_fs.dart`), `lib/src/studio/assets/**`, `tool/studio/io_project_fs.dart`, `test/studio/asset_database_test.dart`, `test/studio/project_format_test.dart`
  - **Reads:** `lib/src/engine/assets/**`, `vendor/pixeldart/lib/assets/**`, `tool/asset_packer.dart`
  - **Scope:**
    - `volition.project.json`: name, version, enabled modules, scenes in build, tags/layers, physics layer matrix, input actions asset, quality tiers, render pipeline settings asset, build profiles (filled later by `[S8-B]`).
    - `.vmeta`: GUID (128-bit, injectable RNG), importer id and version, import settings, source content hash, sub-asset ids (GLB meshes/materials/clips).
    - `AssetDatabase`: initial scan, GUID allocation, move/rename/delete keeping GUIDs, orphan-meta detection, dependency graph, importer registry (texture, glb/obj/qmesh model, audio, LUT, scene, prefab, material, data asset), and an incremental import cache under `.volition/library/` keyed by `(contentHash, importerVersion, settingsHash)`. Reimports are change-driven from `ProjectFileSystem.watch`. Add a `dart:io` adapter (`io_project_fs.dart`).
  - **DoneWhen:** Tests prove: renaming or moving keeps GUID resolution; unchanged assets are not reimported (counter assertion); changed settings invalidate dependents transitively; an in-memory FS and the IO FS behave identically on a fixture project; GUIDs are deterministic with a seeded RNG.

- [x] **[S1-D] Studio Module Registry, Maturity Levels & Coverage Gate (74 `vendor/*` Packages)**
  - **Priority:** P0
  - **DependsOn:** `[S1-0]`
  - **Owns:** `lib/src/studio/modules/module_descriptor.dart`, `lib/src/studio/modules/module_registry.dart`, `lib/src/studio/modules/module_inventory.g.dart`, `tool/check_module_coverage.dart`, `test/studio/module_registry_test.dart`
  - **Reads:** `vendor/*/pubspec.yaml`, `lib/src/engine/components/**`, `lib/src/engine/serialization/component_spec*.dart`
  - **Scope:**
    - `StudioModuleDescriptor`: package, version (from pubspec), family (PLAN §13.7), contributed `ComponentSpec` ids, importers, gizmo drawers, custom inspectors, create-menu entries, sample scenes, maturity (`runtime-only` | `inspectable` | `editor-tooled`), and a `requiredMaturity` target.
    - Generate an inventory of every `vendor/*` package, mapping each to the root component wrapper files that import it. That mapping becomes the `Owns` resolver for `[S6-*]`: `--owners <family>`.
    - `check_module_coverage.dart` takes `--report` (table + JSON), `--min-maturity <level>` and `--owners <family>`.
  - **DoneWhen:** `dart run tool/check_module_coverage.dart --report` lists 74/74 packages with family and current maturity; `--min-maturity runtime-only` exits 0; the test fails when a fixture vendor package has no descriptor.

- [ ] **[S1-M] Coordinator Merge: GUID Scene References, Gates in `verify_all`, Barrels & `pixeldart` Commit**
  - **Priority:** P0
  - **DependsOn:** `[S1-A]`, `[S1-B]`, `[S1-C]`, `[S1-D]`
  - **Owns:** `lib/src/engine/serialization/scene_serializer.dart`, `lib/src/engine/serialization/scene_migration.dart`, `lib/gl_volition.dart`, `lib/src/studio/studio.dart`, `tool/verify_all.dart`, `.gitignore` (`.volition/library/`), `vendor/pixeldart` gitlink
  - **Scope:** Add `AssetRef(guid)` serialization and bump the scene schema, adding a `SceneMigrationStep` that converts path/key references to GUIDs through an injectable resolver (the engine core stays independent of `lib/src/studio`). Add module coverage and the anti-cap test to `verify_all.dart`. Commit and push `vendor/pixeldart` first, then update the gitlink.
  - **DoneWhen:** `dart run tool/verify_all.dart --check-format --skip-wasm` passes with the new gates listed; old-schema scene fixtures migrate to GUID references.

---

## Phase S2 — Volition Studio Editor Shell (Scene · Game · Hierarchy · Inspector · Project · Console · Play Mode)

**Exit Gate:** The Studio e2e script passes in headless Chromium: open project → click-select → gizmo move → add component → drag material onto mesh → play/stop restores state → save → reload is byte-equal. A 1,000-object scene is interactive within 2 s and an inspector edit round-trips in under 16 ms (measured). Every RPC has a CLI path.

- [ ] **[S2-0] Coordinator Freeze: Panel/Docking Model, `EditorHostBridge`, Command & Menu Registry, `ComponentSpec` Field Metadata**
  - **Priority:** P0
  - **DependsOn:** `[S1-M]`
  - **Owns:** `lib/src/studio/shell/**`, `lib/src/studio/bridge/**`, `lib/src/studio/commands/menu_registry.dart`, `lib/src/engine/serialization/component_spec.dart`, `vendor/pixeldart/lib/rendering/api/editor_overlay.dart`
  - **Scope:**
    - Define `StudioPanel` (id, title, state save/restore) and a serializable docking layout tree.
    - Define `EditorHostBridge` between the in-page engine and the shell: selection, command dispatch, viewport picking, play state, and dirty tracking.
    - Define the menu/shortcut registry (`GameObject > Create > …`, `Assets > Create > …`, `Window > …`).
    - Extend `ComponentSpec` field metadata: type, range, step, enum values, tooltip, header, `AssetRef` asset-type filter, hidden flag, read-only flag.
    - Add a renderer `EditorOverlay` contract for grid, gizmo lines/icons, ID-pick target and selection set.
  - **DoneWhen:** `dart analyze` passes on root and `vendor/pixeldart`; existing `ComponentSpec` round-trip tests are unchanged.

- [ ] **[S2-A] Dart-Compiled Studio Shell, Bundle Embedding, Legacy Panels Migration & e2e Harness**
  - **Priority:** P0
  - **DependsOn:** `[S2-0]`
  - **Owns:** `lib/src/web/studio/shell/**`, `tool/studio/web/studio_main.dart`, `tool/studio/studio_bundle.dart`, `tool/studio/studio_bundle.g.dart`, `tool/cli_gui_server.dart`, `tool/cli_gui_assets.dart`, `tool/studio/e2e/run_studio_e2e.mjs`, `test/studio/studio_server_test.dart`
  - **Scope:**
    - Build a Dart web shell with docking, menu bar, toolbar (play/pause/step, gizmo mode, pivot/local-world, snap) and status bar, persisting layout in project user settings.
    - `studio_bundle.dart` compiles `studio_main.dart` (`dart compile js -O2`) and emits `studio_bundle.g.dart` so the AOT `volition` binary embeds Studio.
    - `VolitionGuiServer` serves the bundle and speaks Protocol v2, keeping v1 methods as aliases.
    - Port the Doctor, Create, Build & Dist, Pack, Tests & Gates, Inspector and Replay panels from `cli_gui_assets.dart` into Build/Tools panels, then reduce `cli_gui_assets.dart` to a no-JS fallback page.
    - The e2e runner (pattern of `run_shader_lab.mjs`) drives headless Chromium through scripted scenarios.
  - **DoneWhen:** `test/studio/studio_server_test.dart` passes; `node tool/studio/e2e/run_studio_e2e.mjs --scenario shell-smoke` passes; `dart compile exe bin/volition.dart` serves the embedded bundle with no network access.

- [ ] **[S2-B] Scene View & Game View: Editor Camera, Grid, Gizmo Overlay, ID-Buffer Picking, Selection Outline & Shading Modes**
  - **Priority:** P0
  - **DependsOn:** `[S2-0]`
  - **Owns:** `vendor/pixeldart/lib/rendering/passes/editor_*.dart`, `vendor/pixeldart/shaders/rendering/editor/**`, `vendor/pixeldart/tools/renderer/test_editor_passes.dart`, `lib/src/studio/viewport/**`, `lib/src/web/studio/viewport/**`, `test/studio/viewport_test.dart`
  - **Reads:** `lib/src/engine/gizmos/viewport_gizmos.dart`, `vendor/pixeldart/lib/rendering/core/debug_views.dart`
  - **Scope:**
    - Editor camera: orbit/pan/fly with WASD + RMB, frame-selected (`F`), ortho/2D toggle, and a view gizmo. It stays separate from game `Camera`s.
    - Infinite fade grid; gizmo/icon overlay pass rendering `ViewportGizmos` handles and component icons.
    - ID-buffer picking: an R32UI or RGBA8-packed object-id target, rendered on demand at the cursor.
    - Selection outline (id-edge or stencil).
    - Shading modes: lit, unlit, wireframe, overdraw, plus `debug_views` (normals, roughness, light heatmap).
    - Game view renders the scene's `Camera`s at chosen aspect/resolution presets.
  - **DoneWhen:** `test_editor_passes.dart` and `test/studio/viewport_test.dart` pass (pick ids match the object under the cursor in a recorded fixture); Browser Lab goldens exist for the grid, gizmos and selection outline.

- [ ] **[S2-C] Hierarchy & `ComponentSpec`-Driven Inspector (Multi-Edit, Add Component, Prefab Overrides)**
  - **Priority:** P0
  - **DependsOn:** `[S2-0]`
  - **Owns:** `lib/src/studio/hierarchy/**`, `lib/src/studio/inspector/**`, `lib/src/web/studio/panels/hierarchy_panel.dart`, `lib/src/web/studio/panels/inspector_panel.dart`, `test/studio/inspector_model_test.dart`
  - **Reads:** `lib/src/engine/editor_session.dart`, `lib/src/engine/editor_commands.dart`, `lib/src/engine/prefab_registry.dart`
  - **Scope:**
    - Hierarchy: tree with drag-reparent (undoable), sibling reorder, `searchHierarchy`, multi-select with shift/ctrl, active toggles, and a context menu (rename, duplicate, delete, create child).
    - Inspector: generic field editors driven by `ComponentSpec` metadata (int/double with range slider, bool, string, enum, Vec2/Vec3, Quat shown as euler, Color, curve, `AssetRef` GUID picker, lists, nested structs). Mixed-value display for multi-object editing, an add-component search menu (`@AddComponentMenu` paths once `[S5-0]` lands), remove/reorder/reset per component, and prefab override badges with apply/revert.
    - Every mutation goes through `EditorCommand`s, so undo/redo covers all of it.
  - **DoneWhen:** `test/studio/inspector_model_test.dart` covers each field type, multi-edit mixed values, undo of reparent and field edits, and prefab override apply/revert; the e2e scenario `inspector-edit` passes.

- [ ] **[S2-D] Project Window (GUID Asset Browser, Thumbnails, Drag & Drop, Import Settings) & Console**
  - **Priority:** P1
  - **DependsOn:** `[S2-0]`
  - **Owns:** `lib/src/studio/project_window/**`, `lib/src/studio/console/**`, `lib/src/web/studio/panels/project_panel.dart`, `lib/src/web/studio/panels/console_panel.dart`, `tool/studio/thumbnail_service.dart`, `tool/studio/open_in_editor.dart`, `test/studio/project_window_test.dart`
  - **Scope:**
    - Project window: folder tree + asset grid over `AssetDatabase` RPCs, search and type filters, and an `Assets > Create` menu (folder, scene, material, prefab, data asset).
    - Thumbnails for meshes, materials and textures are rendered offscreen to a render target and cached in `.volition/library/thumbnails/`.
    - Drag an asset into the Scene view to instantiate it, or onto an inspector `AssetRef` field. The import-settings inspector supports reimport.
    - Console: capture `voxlog` + `EngineHost.reportError` from the in-page player, with collapse, level filters and search. Clicking a stack frame opens `file:line` through a daemon call (`code -g`, or the configured editor).
  - **DoneWhen:** `test/studio/project_window_test.dart` passes (create/rename/move through the UI model keeps GUIDs, and the thumbnail cache is reused); the e2e scenario `drag-material` passes.

- [ ] **[S2-M] Coordinator Merge: Play Mode, Scene Save/Load via Daemon, Autosave & Studio ⇄ CLI Parity Gate**
  - **Priority:** P0
  - **DependsOn:** `[S2-A]`, `[S2-B]`, `[S2-C]`, `[S2-D]`
  - **Owns:** `lib/src/engine/editor_session.dart`, `tool/cli_service.dart`, `bin/volition.dart`, `tool/studio/studio_daemon.dart`, `test/studio/cli_parity_test.dart`, `test/studio/play_mode_test.dart`
  - **Scope:**
    - Enter/exit play mode using the `EditorSession` snapshot, with pause and single-step, play-mode tint, and Game-view input capture.
    - Save scenes and prefabs through the daemon as GUID-referenced JSON, with dirty markers, autosave and crash recovery.
    - Add `volition rpc <method> [--json]` for every Protocol v2 method.
    - Parity test enumerates the method registry and fails on any method without a CLI mapping.
  - **DoneWhen:** `test/studio/play_mode_test.dart` and `test/studio/cli_parity_test.dart` pass; the full S2 e2e script passes; `verify_all.dart` is green; the measured 1,000-object open time and inspector round-trip are recorded in the merge report.

---

## Phase S3 — VRP Lighting, Shadows & HDR

**Exit Gate:** The Browser Lab "VRP lights" scene (256 point lights, 4-cascade sun, 8 shadowed spots) matches its goldens; measured 1080p frame time on the `tool/renderer_bench.dart` reference machine is ≤ 16.6 ms on web and native; linear-audit readbacks are within tolerance on both quality tiers.

- [ ] **[S3-0] Coordinator Freeze: Render Pipeline Settings Asset, Light GPU Layout, Shader Keywords & `#include` Support**
  - **Priority:** P0
  - **DependsOn:** `[S1-M]`
  - **Owns:** `vendor/pixeldart/lib/rendering/api/settings.dart`, `vendor/pixeldart/lib/rendering/api/lights.dart`, `vendor/pixeldart/lib/rendering/api/shaders.dart`, `vendor/pixeldart/tools/renderer/shaders.dart`, `vendor/pixeldart/shaders/rendering/include/README.md`, `lib/src/engine/components/light.dart` (fields only)
  - **Scope:**
    - `RenderPipelineSettings`, serializable as a project asset: quality tiers; HDR on/off and format; MSAA; render scale; max visible lights; cluster dims; shadow distance, cascade count, split lambda, atlas size, and per-light resolution tiers.
    - Light data layout: a std140 punctual-light struct plus a directional struct.
    - Shader keyword/variant contract and `#include "include/…"` resolution in the shader generator (`--check` must cover includes).
    - Replace the `RuntimeLightBudget` constants with tier-derived limits.
    - `Light` component fields: range, inner/outer cone, shadows (none/hard/soft), shadow strength, bias, normal bias, culling layers, and intensity in lux/lumen units.
  - **DoneWhen:** `dart analyze` passes on root and `vendor/pixeldart`; `shaders.dart --check` passes with an include fixture.

- [ ] **[S3-A] Unified Lit Uber-Shader, PBR BRDF & Variant Cache/Warmup**
  - **Priority:** P0
  - **DependsOn:** `[S3-0]`
  - **Owns:** `vendor/pixeldart/shaders/rendering/world/**`, `vendor/pixeldart/shaders/rendering/include/{brdf,surface,lit_common}.glsl`, `vendor/pixeldart/lib/rendering/core/program_library.dart`, `vendor/pixeldart/lib/rendering/core/program_set_planner.dart`, `vendor/pixeldart/lib/rendering/core/program_source.dart`, `vendor/pixeldart/lib/rendering/passes/{world,textured_world,shadowed_world}.dart`, `vendor/pixeldart/tools/renderer/test_lit_variants.dart`
  - **Scope:**
    - Merge `safe_world`, `textured_world` and `shadowed_world` into `lit.vert`/`lit.frag` with keywords: `NORMAL_MAP`, `ORM_MAP`, `EMISSIVE`, `LIGHTMAP`, `SKINNED`, `INSTANCED`, `ALPHA_TEST`, `SHADOWS_{OFF,HARD,SOFT}`, `PS1_AFFINE`, `QUANTIZED`, `UNLIT`.
    - BRDF: GGX D, height-correlated Smith V, Schlick F, a multi-scatter energy compensation term, and clearcoat.
    - Program variant cache keyed by keyword bitset, with per-scene warmup lists; the legacy PS1/safe looks stay as keyword combinations.
  - **DoneWhen:** `test_lit_variants.dart` compiles every allowed variant on the recording device and asserts no keyword combination is missing; Browser Lab goldens of the legacy looks stay SSIM ≥ 0.98; furnace test (white env, roughness sweep) energy stays within ±3 %.

- [ ] **[S3-B] Clustered Forward+ Lighting (Froxel Grid, ≥256 Visible Lights, Heatmap)**
  - **Priority:** P0
  - **DependsOn:** `[S3-0]`
  - **Owns:** `vendor/pixeldart/lib/rendering/core/light_clusters.dart`, `vendor/pixeldart/lib/rendering/passes/light_cluster_upload.dart`, `vendor/pixeldart/shaders/rendering/include/clustered_lights.glsl`, `vendor/pixeldart/tools/renderer/test_light_clusters.dart`
  - **Scope:**
    - CPU froxel assignment (default 16×9×24, logarithmic depth slices) using sphere/cone vs. froxel-AABB tests, packed into a light-index texture plus a light UBO/texture.
    - `clustered_lights.glsl` loops over a cluster's lights, and the lit shader includes it.
    - Light-count heatmap debug view; zero per-frame allocations (frame arena).
  - **DoneWhen:** `test_light_clusters.dart` proves cluster assignment matches brute force on randomized scenes and that 256 lights stay allocation-free; the Browser Lab 256-light golden passes; the measured CPU cluster build time is recorded.

- [ ] **[S3-C] Shadows: Directional CSM, Spot/Point Shadow Atlas, PCF/PCSS & Priority Resolution**
  - **Priority:** P0
  - **DependsOn:** `[S3-0]`
  - **Owns:** `vendor/pixeldart/lib/rendering/passes/shadow*.dart`, `vendor/pixeldart/lib/rendering/core/shadow_atlas.dart`, `vendor/pixeldart/shaders/rendering/shadow/**`, `vendor/pixeldart/shaders/rendering/include/shadows.glsl`, `vendor/pixeldart/tools/renderer/test_shadow_atlas.dart`, `vendor/pixeldart/tools/renderer/test_directional_shadow.dart`, `lib/src/engine/components/cascaded_shadow_rig.dart`, `test/engine/cascaded_shadow_gpu_test.dart`
  - **Scope:**
    - Directional CSM with 2–4 cascades from `optics/cascade_splits.dart`: texel-snapped stable fitting, cascade blend band, per-cascade caster culling, and a cascade debug view.
    - Shadow atlas for spot lights and point lights (6 faces packed), with resolution chosen by screen-size priority and per-light tier.
    - Filtering: PCF 3×3/5×5, optional PCSS blocker search, normal-offset + slope bias.
    - `CascadedShadowRig` drives the GPU path.
  - **DoneWhen:** `test_shadow_atlas.dart` (packing, no overlap, stable reassignments) and `test/engine/cascaded_shadow_gpu_test.dart` (recorded passes per cascade) pass; Browser Lab goldens exist for the CSM sun, 8 shadowed spots and 2 shadowed points; `RuntimeLightBudget.shadowMaps = 1` has no remaining callers.

- [ ] **[S3-D] HDR Scene Color, Physical Exposure/Auto-Exposure, Tonemappers & HDR Bloom**
  - **Priority:** P0
  - **DependsOn:** `[S3-0]`
  - **Owns:** `vendor/pixeldart/lib/rendering/passes/{present,post_chain,bloom,bloom_resources,grade,grade_resources}.dart`, `vendor/pixeldart/lib/rendering/passes/exposure*.dart`, `vendor/pixeldart/shaders/rendering/post/**`, `vendor/pixeldart/shaders/rendering/bloom/**`, `vendor/pixeldart/shaders/rendering/grade/**`, `vendor/pixeldart/shaders/rendering/exposure/**`, `vendor/pixeldart/tools/renderer/test_hdr_pipeline.dart`
  - **Scope:**
    - RGBA16F scene color when capability bits allow it; otherwise RGBA8 with in-shader tonemap (documented tier behavior).
    - EV100 manual exposure plus auto-exposure (log-luminance downsample chain or histogram, with adaptation speed).
    - Tonemappers: ACES fitted, AgX, Khronos Neutral.
    - Bloom on HDR input with threshold/knee; LUT grading after tonemap; sRGB output.
    - End-to-end linear audit: known emissive patches read back at expected values.
  - **DoneWhen:** `test_hdr_pipeline.dart` passes on both tiers; Browser Lab linear-audit readback is within ±1/255 of expected; goldens exist for each tonemapper.

- [ ] **[S3-E] Studio Lighting & Quality Windows, Light Inspectors & Gizmos**
  - **Priority:** P1
  - **DependsOn:** `[S3-0]`, `[S2-M]`
  - **Owns:** `lib/src/studio/windows/lighting_window.dart`, `lib/src/studio/windows/quality_window.dart`, `lib/src/studio/gizmos/light_gizmos.dart`, `lib/src/web/studio/panels/lighting_panel.dart`, `test/studio/lighting_window_test.dart`
  - **Scope:** The Lighting window edits the `RenderPipelineSettings` asset and the environment (ambient, sky, exposure). The Quality window switches tiers live in the Scene and Game views. Light gizmos draw range spheres, spot cones, directional arrows and a cascade-split overlay toggle. The light inspector adds a unit helper (lux/lumen).
  - **DoneWhen:** `test/studio/lighting_window_test.dart` passes; the e2e scenario `lighting-tier-switch` passes with golden captures of both tiers.

- [ ] **[S3-M] Coordinator Merge: VRP Lighting Integration, `Scene._syncToRenderer` Light Upload & Bench Ratification**
  - **Priority:** P0
  - **DependsOn:** `[S3-A]`, `[S3-B]`, `[S3-C]`, `[S3-D]`, `[S3-E]`
  - **Owns:** `lib/src/engine/scene.dart`, `tool/renderer_bench.dart`, `vendor/pixeldart` gitlink
  - **Scope:** Route all scene `Light`s into cluster upload; add the "VRP lights" bench scene; record the reference machine (GPU, driver, browser) and measured web and native frame times; push `pixeldart`, then update the gitlink.
  - **DoneWhen:** Phase S3 exit gate is green and the measured numbers are in the merge report.

---

## Phase S4 — Environment, GI, Materials & Post-Processing v2

**Exit Gate:** Metallic sphere reflects its probe; the baked-lightmap scene golden matches; TAA golden is stable over 600 frames; editing a `.vmat` updates every user live in the Scene view.

- [ ] **[S4-0] Coordinator Freeze: `.vmat` Material Asset, `MaterialPropertyBlock`, Render Queues & Environment/Probe Blocks**
  - **Priority:** P0
  - **DependsOn:** `[S3-M]`
  - **Owns:** `vendor/pixeldart/lib/rendering/api/materials.dart`, `vendor/pixeldart/lib/rendering/api/effects.dart`, `vendor/pixeldart/lib/rendering/api/environment.dart`, `lib/src/engine/assets/asset_types.dart`
  - **Scope:** `.vmat` schema (shader id, keyword set, typed property values, GUID texture refs, render queue, sorting layer and order); `MaterialPropertyBlock` per renderer; queue ranges matching Unity (Background 1000, Geometry 2000, AlphaTest 2450, Transparent 3000, Overlay 4000); std140 environment block (SH9, exposure, sky) and probe binding contract; Volume profile schema.
  - **DoneWhen:** `dart analyze` passes on root and `vendor/pixeldart`.

- [ ] **[S4-A] Skybox & Image-Based Lighting (HDR Cubemaps, GGX Prefilter, BRDF LUT, SH9 Ambient)**
  - **Priority:** P0
  - **DependsOn:** `[S4-0]`
  - **Owns:** `vendor/pixeldart/lib/rendering/passes/{skybox,ibl_prefilter}*.dart`, `vendor/pixeldart/shaders/rendering/sky/**`, `vendor/pixeldart/shaders/rendering/include/ibl.glsl`, `vendor/pixeldart/lib/rendering/atmosphere/sky_atmosphere.dart`, `vendor/pixeldart/tools/renderer/test_ibl.dart`, `lib/src/studio/assets/importers/hdri_importer.dart`
  - **Scope:** Import equirect `.hdr` into a cubemap with mips. Bake the procedural sky (`sky_atmosphere`/`voxsky`) to a cubemap at runtime when the sun moves past a threshold. Add a GGX-prefiltered specular mip chain, a 2D split-sum BRDF LUT and SH9 projection for ambient, plus a skybox pass. Remove the `uReflectionColor` uniform.
  - **DoneWhen:** `test_ibl.dart` checks SH9 projection against an analytic reference and that the prefilter mip count matches cube size; Browser Lab roughness/metallic sphere-grid golden passes.

- [ ] **[S4-B] Reflection Probes & Per-Object Light-Probe SH**
  - **Priority:** P1
  - **DependsOn:** `[S4-0]`
  - **Owns:** `lib/src/engine/components/reflection_probe.dart`, `lib/src/engine/components/light_probe_gi.dart`, `vendor/pixeldart/lib/rendering/passes/reflection_probe*.dart`, `vendor/pixeldart/shaders/rendering/include/probes.glsl`, `lib/src/studio/gizmos/probe_gizmos.dart`, `test/engine/reflection_probe_test.dart`
  - **Scope:** `ReflectionProbe` component (baked / on-demand realtime, box projection, blend distance, importance), blending between the two nearest probes, and baked cubemaps stored as GUID assets. `LightProbeVolume` SH3/SH9 is interpolated per renderer and uploaded per object (no longer one global uniform). Studio probe gizmos and a "Bake Probes" command.
  - **DoneWhen:** `test/engine/reflection_probe_test.dart` covers probe selection, blend weights and box-projection math; the Browser Lab interior/exterior blend golden passes.

- [ ] **[S4-C] Progressive Lightmapper (UV2 Packing, Isolate Path Tracer, Denoise, Bake UI)**
  - **Priority:** P2
  - **DependsOn:** `[S4-0]`, `[S2-M]`
  - **Owns:** `lib/src/studio/baking/**`, `tool/studio/lightmap_baker_io.dart`, `test/studio/lightmapper_test.dart`
  - **Reads:** `lib/src/engine/components/spatial_bvh.dart`, `vendor/pixeldart/lib/rendering/api/materials.dart`
  - **Scope:** Generate UV2 charts and pack them (pure Dart), then path-trace direct and one-bounce indirect light over a BVH on isolates (daemon-side) with progressive passes. Denoise with an edge-aware À-trous filter and dilate charts. Write lightmap textures and per-renderer scale/offset that feed the existing `lightmapTexture` material slot. Lighting window gets "Bake / Cancel / Clear" with progress events over Protocol v2, plus CLI `volition bake`.
  - **DoneWhen:** `test/studio/lightmapper_test.dart` checks chart packing has no overlaps and that the Cornell-box bake matches its reference image within tolerance with deterministic seeds; the measured bake time is recorded.

- [ ] **[S4-D] Post-Processing v2: Motion Vectors, TAA, SSR, GTAO, Motion Blur & Volume Framework**
  - **Priority:** P1
  - **DependsOn:** `[S4-0]`
  - **Owns:** `vendor/pixeldart/lib/rendering/passes/{motion_vectors,taa,ssr,gtao,motion_blur}*.dart`, `vendor/pixeldart/lib/rendering/passes/ssao*.dart`, `vendor/pixeldart/shaders/rendering/{taa,ssr,gtao,motion}/**`, `lib/src/engine/components/post_process_volume.dart`, `vendor/pixeldart/tools/renderer/test_post_v2.dart`
  - **Scope:** Per-object motion-vector pass (MRT or separate pass, skinned + instanced aware). TAA uses Halton jitter, history reprojection, YCoCg neighborhood clamp and sharpening. SSR uses a Hi-Z trace and falls back to probes. GTAO replaces SSAO behind a setting. Camera and per-object motion blur. A Volume framework (global/local volumes, priority, blend distance, per-effect override flags) drives the whole post stack.
  - **DoneWhen:** `test_post_v2.dart` covers volume blending math and jitter-sequence determinism; Browser Lab TAA golden is stable across 600 frames (SSIM ≥ 0.99 between frames 300 and 600 on a static camera); SSR and GTAO goldens pass.

- [ ] **[S4-E] Material Assets, Material Inspector with Live Preview, Render Queues & Sorting Layers**
  - **Priority:** P0
  - **DependsOn:** `[S4-0]`, `[S2-M]`
  - **Owns:** `lib/src/studio/assets/importers/material_importer.dart`, `lib/src/studio/inspector/material_inspector.dart`, `lib/src/web/studio/panels/material_preview.dart`, `vendor/pixeldart/lib/rendering/core/material_table.dart`, `vendor/pixeldart/lib/rendering/core/sort_key.dart`, `lib/src/engine/components/renderers.dart`, `test/studio/material_asset_test.dart`
  - **Scope:** Import `.vmat` into `MaterialDefinition` and hot-update every user on change. The material inspector shows keyword toggles, typed properties and texture GUID pickers, with a live preview sphere/cube/plane rendered offscreen. `MaterialPropertyBlock` on `MeshRenderer`/`SkinnedMeshRenderer`. Render queues and sorting layers feed `sort_key.dart`; transparent objects sort back to front. Material UBOs are cached SRP-batcher style.
  - **DoneWhen:** `test/studio/material_asset_test.dart` covers hot-update fan-out, property-block override precedence and queue sort order; the e2e scenario `material-edit-live` passes.

- [ ] **[S4-M] Coordinator Merge: Environment/GI/Post Integration & `pixeldart` Commit**
  - **Priority:** P0
  - **DependsOn:** `[S4-A]`, `[S4-B]`, `[S4-C]`, `[S4-D]`, `[S4-E]`
  - **Owns:** `lib/src/engine/scene.dart`, `lib/src/engine/serialization/component_spec_extra.dart`, `lib/gl_volition.dart`, `vendor/pixeldart` gitlink
  - **Scope:** Register `ReflectionProbe` and Volume specs, route per-object SH and probe data in `_syncToRenderer`, update goldens, and push `pixeldart`.
  - **DoneWhen:** Phase S4 exit gate is green; `verify_all.dart` passes.

---

## Phase S5 — Scripting Workflow & Editor Extensibility

**Exit Gate:** `@Serialized @Range(0, 10) double speed` shows a slider with no hand-written spec; edit-to-visible reload time is measured and reported (target 3 s); scene, selection and camera survive reload; a nested-prefab edit propagates through two levels.

- [ ] **[S5-0] Coordinator Freeze: Serialization Annotations, `DataAsset` & EditorExtension API**
  - **Priority:** P0
  - **DependsOn:** `[S2-M]`
  - **Owns:** `lib/src/engine/serialization/annotations.dart`, `lib/src/engine/data_asset.dart`, `lib/src/studio/extensions/**`, `lib/gl_volition.dart`
  - **Scope:**
    - Annotations: `@Serialized`, `@HideInInspector`, `@Range`, `@Min`, `@Tooltip`, `@Header`, `@Space`, `@Multiline`, `@RequireComponent`, `@DisallowMultipleComponent`, `@ExecuteInEditMode`, `@AddComponentMenu`, `@CreateAssetMenu`.
    - `DataAsset` base class (ScriptableObject equivalent, `.vasset`, GUID-referenced).
    - Extension points: `CustomInspector<T>`, `GizmoDrawer<T>`, `MenuItem`, `EditorWindow`, `AssetImporter`, `ContextAction`, `ToolbarTool`.
  - **DoneWhen:** `dart analyze` passes; the boundary check keeps annotations and `DataAsset` free of platform imports.

- [ ] **[S5-A] `volition codegen`: Analyzer-Based `ComponentSpec` / `DataAsset` Spec Generation**
  - **Priority:** P0
  - **DependsOn:** `[S5-0]`
  - **Owns:** `tool/codegen/**`, `test/studio/codegen_test.dart`
  - **Scope:** Use `package:analyzer` to scan the project's `lib/` plus module wrappers and emit `*.spec.g.dart` (`ComponentSpec` with field metadata, `@RequireComponent` graph, menu paths). Watch mode with incremental regeneration. Diagnostics report `file:line` for unsupported field types. Generated files are deterministic, so they diff cleanly.
  - **DoneWhen:** `test/studio/codegen_test.dart` passes on golden source → spec fixtures (all annotation types, generics rejected with a clear diagnostic); regenerating unchanged input produces byte-identical output.

- [ ] **[S5-B] Hot-Reload Loop: In-Studio Player Recompile with State-Preserving Reload + Native VM-Service Reload**
  - **Priority:** P0
  - **DependsOn:** `[S5-0]`
  - **Owns:** `tool/studio/hot_reload/**`, `lib/src/studio/reload/**`, `test/studio/hot_reload_test.dart`
  - **Scope:**
    - First benchmark the web recompile strategies on the sample project and record the results: DDC via `build_web_compilers`, `dart compile js -O0`, and `-O1`.
    - Implement the fastest strategy that is correct, triggered by the project file watcher.
    - Before reload, serialize the editor state (scene incl. unsaved changes, selection, camera, layout) and restore it after.
    - Native: `volition run --native --hot` uses the VM service `reloadSources` while keeping engine state.
  - **DoneWhen:** `test/studio/hot_reload_test.dart` passes (the state snapshot round-trips byte-equal); the benchmark table of the strategies is recorded in the merge report with the chosen default.

- [ ] **[S5-C] Edit-Mode Execution & Extension Host (Discovery, Custom Inspectors, Gizmo Drawers, Menu Items)**
  - **Priority:** P1
  - **DependsOn:** `[S5-0]`
  - **Owns:** `lib/src/studio/extension_host/**`, `lib/src/engine/scene.dart` (edit-mode tick gate only), `example/studio_samples/extension_demo/**`, `test/studio/extension_host_test.dart`
  - **Scope:** `@ExecuteInEditMode` behaviours tick in edit mode with an `isPlaying` guard. Discover extensions from modules (descriptors) and from the project `editor/` folder. Custom inspectors replace or augment the generic one, gizmo drawers render through `EditorOverlay`, and menu items register in the menu registry. Add a sample extension.
  - **DoneWhen:** `test/studio/extension_host_test.dart` passes (custom inspector precedence, edit-mode tick, menu registration); the e2e scenario `extension-demo` passes.

- [ ] **[S5-D] Nested Prefabs, Prefab Mode (Isolation Stage) & Variant Chains**
  - **Priority:** P1
  - **DependsOn:** `[S5-0]`
  - **Owns:** `lib/src/engine/prefab.dart`, `lib/src/engine/prefab_registry.dart`, `lib/src/studio/prefab_mode/**`, `test/engine/nested_prefab_test.dart`
  - **Scope:** Nested prefab instances with layered overrides (outermost wins), variant chains, apply-to-specific-level, and Prefab Mode (open a prefab in an isolated stage with breadcrumbs, then save and propagate). Detect broken references and offer a repair UI model.
  - **DoneWhen:** `test/engine/nested_prefab_test.dart` covers 2-level propagation, override precedence, variant-of-variant and broken-reference repair.

- [ ] **[S5-M] Coordinator Merge: `volition codegen` / `run --hot` CLI Wiring, Studio "Recompile" & Parity**
  - **Priority:** P0
  - **DependsOn:** `[S5-A]`, `[S5-B]`, `[S5-C]`, `[S5-D]`
  - **Owns:** `bin/volition.dart`, `tool/cli_service.dart`, `lib/src/engine/serialization/component_spec_extra.dart`
  - **Scope:** Wire the `codegen [--watch]` and `run --native --hot` CLI commands, migrate hand-written specs to generated ones where equivalent, and extend the parity test.
  - **DoneWhen:** Phase S5 exit gate is green; `verify_all.dart` passes.

---

## Phase S6 — Module Integration Sweep (All 74 Submodules → Studio)

**Exit Gate:** `dart run tool/check_module_coverage.dart --min-maturity inspectable` reports 74/74; each family has a sample scene that opens and plays in Studio; headless smoke tests instantiate every registered component.

**Shared scope for `[S6-A..F]`:** For each package in the family (PLAN §13.7):
1. Register a `StudioModuleDescriptor`.
2. Annotate its root component wrapper(s) so `volition codegen` produces specs.
3. Add `GameObject > Create > <Family> > …` entries.
4. Add a `GizmoDrawer` for spatial components.
5. Add a `CustomInspector` where the generic one is inadequate (state it in the report).
6. Add one family sample scene under `example/studio_samples/<family>/` using GUID assets.
7. Add a headless smoke test that instantiates and serializes every registered component.

**Owns:** `lib/src/studio/modules/<family>/**`, `test/studio/modules/<family>_test.dart`, `example/studio_samples/<family>/**`, plus annotation-only edits to the wrapper files listed by `dart run tool/check_module_coverage.dart --owners <family>` (resolved in `[S1-D]`). Vendor packages themselves are not modified unless a bug blocks integration. That fix happens inside the submodule first (Invariant 4) and is reported.

- [ ] **[S6-A] Rendering & Visuals Family (17):** `pixeldart`, `voxvfx`, `voxribbon`, `voxdecal`, `voxlight`, `voxshadow`, `voxsky`, `voxcolor`, `voxlens`, `voxcam`, `voxprobe`, `voxatlas`, `voxbatch`, `voxoctree`, `voxsdf`, `voxgreedy`, `voxvox`
  - **Priority:** P1 · **DependsOn:** `[S5-M]`, `[S4-M]`
  - **DoneWhen:** `dart test test/studio/modules/rendering_test.dart`; coverage gate `inspectable` passes for this family; sample `example/studio_samples/rendering/` plays in Studio e2e (`module-rendering`).

- [ ] **[S6-B] Physics & Simulation Family (11):** `voxphys`, `voxbroad`, `voxcloth`, `voxfluid`, `voxfracture`, `voxragdoll`, `voxverlet`, `voxwheel`, `voxtraffic`, `voxcrowd`, `voxsteer`
  - **Priority:** P1 · **DependsOn:** `[S5-M]`
  - **Extra scope:** Collider gizmos (box/sphere/capsule/mesh/heightfield edit handles), Physics project settings panel (layer matrix, gravity, fixed step), joint gizmos.
  - **DoneWhen:** `dart test test/studio/modules/physics_test.dart`; gate passes for family; e2e `module-physics`.

- [ ] **[S6-C] Animation & Motion Family (9):** `voxanim`, `voxblend`, `voxik2d`, `voxgait`, `voxtween`, `voxcurve`, `voxseq`, `voxspline3d`, `voxextrude`
  - **Priority:** P1 · **DependsOn:** `[S5-M]`
  - **Extra scope:** Curve field editor for the generic inspector (reused by `[S7-A]`), spline point gizmos.
  - **DoneWhen:** `dart test test/studio/modules/animation_test.dart`; gate passes for family; e2e `module-animation`.

- [ ] **[S6-D] AI, Gameplay & Narrative Family (15):** `voxai`, `voxhtn`, `voxnav3d`, `voxpath`, `voxflow`, `voxgraph`, `voxcircuit`, `voxrule`, `voxitem`, `voxcraft`, `voxquest`, `voxtalk`, `voxstat`, `voxscore`, `voxloc`
  - **Priority:** P1 · **DependsOn:** `[S5-M]`
  - **Extra scope:** Convert item/quest/stat/craft/loc definitions to `DataAsset` types with `@CreateAssetMenu`; navmesh agent gizmos.
  - **DoneWhen:** `dart test test/studio/modules/gameplay_test.dart`; gate passes for family; e2e `module-gameplay`.

- [ ] **[S6-E] World & Procedural Family (10):** `voxbiome`, `voxnoise3d`, `voxproc`, `voxarch`, `voxbuild`, `voxgrid`, `voxhex`, `voxsnap`, `voxgeom`, `voxfoliage`
  - **Priority:** P1 · **DependsOn:** `[S5-M]`
  - **Extra scope:** "Generate / Regenerate with seed" context actions that produce undoable scene edits; grid/hex overlays.
  - **DoneWhen:** `dart test test/studio/modules/world_test.dart`; gate passes for family; e2e `module-world`.

- [ ] **[S6-F] Audio, Input, Net & Infrastructure Family (12):** `voxdsp`, `voxreverb`, `voxsynth`, `voxrhythm`, `voxpad`, `voxnet`, `voxrollback`, `voxecs`, `voxui`, `voxlog`, `voxpack`, `voxalloc`
  - **Priority:** P1 · **DependsOn:** `[S5-M]`
  - **Extra scope:** Audio Mixer window (buses, snapshots, ducking from Wave 20) with live meters; Input Actions asset editor (Wave 19 profiles); Network settings + "Play with N clients" launcher (local headless server + extra Studio game views); `voxlog` already feeds Console (verify).
  - **DoneWhen:** `dart test test/studio/modules/infra_test.dart`; gate passes for family; e2e `module-audio-input-net`.

- [ ] **[S6-M] Coordinator Merge: Raise Coverage Gate to `inspectable` in `verify_all` & Module Catalog**
  - **Priority:** P0
  - **DependsOn:** `[S6-A]`, `[S6-B]`, `[S6-C]`, `[S6-D]`, `[S6-E]`, `[S6-F]`
  - **Owns:** `tool/verify_all.dart`, `lib/src/studio/modules/module_registry.dart`, `lib/src/studio/studio.dart`
  - **Scope:** Register all family descriptor barrels, raise the gate to `--min-maturity inspectable`, and add a Studio "Modules" panel (package-manager view: enable/disable per project, version, maturity, samples).
  - **DoneWhen:** Phase S6 exit gate is green.

---

## Phase S7 — Specialized Editor Windows

**Exit Gate:** Each window has an e2e scenario that authors content, saves it as GUID assets, and plays it back in the Game view; the 22 `editor-tooled` modules (PLAN §13.7) pass `--min-maturity editor-tooled`.

- [ ] **[S7-0] Coordinator Freeze: Shared Node-Graph View Model & Timeline/Curve View Model**
  - **Priority:** P0
  - **DependsOn:** `[S6-M]`
  - **Owns:** `lib/src/studio/graph/**`, `lib/src/studio/timeline/**`, `lib/src/web/studio/widgets/{graph_canvas,timeline_canvas,curve_canvas}.dart`
  - **Scope:** Graph model (nodes, typed ports, edges, groups, comments, minimap, auto-layout, copy/paste, undo through `EditorCommand`s) and timeline model (tracks, clips, keys, tangents, snapping, scrubbing).
  - **DoneWhen:** `dart analyze` passes; model unit tests in `test/studio/graph_model_test.dart` and `test/studio/timeline_model_test.dart` pass.

- [ ] **[S7-A] Animation Window, Animator Controller Graph & Timeline**
  - **Priority:** P1 · **DependsOn:** `[S7-0]`
  - **Owns:** `lib/src/studio/windows/animation/**`, `lib/src/web/studio/panels/animation_*.dart`, `test/studio/animation_windows_test.dart`
  - **Modules:** `voxanim`, `voxblend`, `voxseq`, `voxcurve`, `voxtween`
  - **Scope:** Dopesheet and curve editor with record mode (inspector edits become keys). Animator Controller asset: states, transitions with conditions, parameters, layers with masks, and 1D/2D blend trees, compiled to `StateMachine`/`BlendTreeController`. Live state highlighting in play mode. Timeline over `CutsceneSequencer` tracks: animation, audio, activation, signal, camera.
  - **DoneWhen:** `test/studio/animation_windows_test.dart` passes; e2e `animator-author-play`.

- [ ] **[S7-B] Graph Editors: Flow Graph (Visual Scripting), Dialogue, HTN, Logic Circuits & Rules**
  - **Priority:** P1 · **DependsOn:** `[S7-0]`
  - **Owns:** `lib/src/studio/windows/graphs/**`, `lib/src/web/studio/panels/graph_*.dart`, `test/studio/graph_editors_test.dart`
  - **Modules:** `voxgraph`, `voxflow`, `voxtalk`, `voxhtn`, `voxcircuit`, `voxrule`
  - **Scope:** One graph canvas, many schemas. Each editor serializes to its module's runtime format as a GUID asset and supports live play-mode debugging (active node highlight, port values, breakpoints for the flow graph).
  - **DoneWhen:** `test/studio/graph_editors_test.dart` round-trips every schema; e2e `flowgraph-author-play`, `dialogue-author-play`.

- [ ] **[S7-C] World Tools: Terrain Sculpt/Paint, Foliage Brush, NavMesh Bake, Splines & Modular Building**
  - **Priority:** P1 · **DependsOn:** `[S7-0]`
  - **Owns:** `lib/src/studio/windows/world_tools/**`, `lib/src/studio/tools/{terrain,foliage,navmesh,spline,snap}_tool.dart`, `test/studio/world_tools_test.dart`
  - **Modules:** `voxbiome`, `voxfoliage`, `voxnav3d`, `voxspline3d`, `voxsnap`, `voxbuild`
  - **Scope:** Terrain brushes (raise/lower/smooth/flatten/holes) with splat-layer painting (heightfield and physics collider stay in sync). Foliage paint/erase with density. NavMesh bake settings, visualization and agent types (+ CLI `volition bake --navmesh`). Spline point/tangent editing. Snap/socket placement for modular building. All brush strokes are undoable as compact deltas.
  - **DoneWhen:** `test/studio/world_tools_test.dart` passes (stroke delta undo, navmesh bake determinism); e2e `terrain-paint-bake`.

- [ ] **[S7-D] 2D Tools: Sprite Editor, Tile Palette & Rule Tiles, 2D Lights/Colliders & Sorting Layers**
  - **Priority:** P1 · **DependsOn:** `[S7-0]`
  - **Owns:** `lib/src/studio/windows/tools_2d/**`, `lib/src/web/studio/panels/sprite_editor.dart`, `test/studio/tools_2d_test.dart`
  - **Modules:** `voxatlas` (+ engine `sprites_2d`, `tilemap`, `lighting_2d`, `physics_2d`)
  - **Scope:** Sprite slicing (grid/auto), pivots and 9-slice borders, with atlas packing at import. Tile palette with brush/fill/rect/picker and rule tiles. 2D light and shadow-caster shape editing. Physics 2D collider shape editing. Sorting layers UI.
  - **DoneWhen:** `test/studio/tools_2d_test.dart` passes; e2e `tilemap-author-play`.

- [ ] **[S7-E] UI Builder, Localization Tables & Data Tables (Items, Quests, Stats)**
  - **Priority:** P1 · **DependsOn:** `[S7-0]`
  - **Owns:** `lib/src/studio/windows/ui_builder/**`, `lib/src/studio/windows/data_tables/**`, `lib/src/web/studio/panels/{ui_builder,table_editor}.dart`, `test/studio/ui_data_tools_test.dart`
  - **Modules:** `voxui`, `voxloc`, `voxitem`, `voxquest`, `voxstat`
  - **Scope:** UI builder over `canvas_ui`/`voxui`: RectTransform anchors, pivots and offsets, layout groups, resolution preview, and event wiring to methods. Localization table editor with CSV import/export and a missing-key report. Spreadsheet-style editors for `DataAsset` collections with validation.
  - **DoneWhen:** `test/studio/ui_data_tools_test.dart` passes (anchor math across resolutions, CSV round-trip); e2e `ui-builder-play`.

- [ ] **[S7-M] Coordinator Merge: Window Registration, `editor-tooled` Gate & Docs Stubs**
  - **Priority:** P0
  - **DependsOn:** `[S7-A]`, `[S7-B]`, `[S7-C]`, `[S7-D]`, `[S7-E]`
  - **Owns:** `lib/src/studio/studio.dart`, `lib/src/studio/modules/module_registry.dart`, `tool/verify_all.dart`
  - **Scope:** Register windows under `Window > …`, raise the 22 listed modules' required maturity to `editor-tooled`, and run the full e2e suite.
  - **DoneWhen:** Phase S7 exit gate is green.

---

## Phase S8 — Player Link, Profiler, Build Profiles & Ship

**Exit Gate:** `volition build --profile web-release|windows-release` reproduces the Studio build byte-for-byte; the profiler shows live GPU pass timings from a native player; the showcase uses at least one module from every family; the release gate re-runs the PLAN §13.1 audit queries with zero reopened items.

- [ ] **[S8-0] Coordinator Freeze: Player Link Protocol**
  - **Priority:** P0
  - **DependsOn:** `[S7-M]`
  - **Owns:** `lib/src/studio/protocol/player_link.dart`, `lib/src/engine/diagnostics/player_link_client.dart`
  - **Scope:** Handshake (player id, target, build profile), telemetry frames (CPU spans from `FrameProfilerComponent`, GPU pass timings, memory and asset counts, draw/triangle/state-change stats), log stream, remote `DebugConsole` commands, and frame-capture requests and responses. The transport is a pluggable WebSocket via host adapters, so the engine core stays pure.
  - **DoneWhen:** `dart analyze` and the boundary check pass.

- [ ] **[S8-A] Profiler Window, GPU Per-Pass Timers & Frame Debugger**
  - **Priority:** P0 · **DependsOn:** `[S8-0]`
  - **Owns:** `lib/src/studio/windows/profiler/**`, `lib/src/web/studio/panels/profiler_*.dart`, `vendor/pixeldart/lib/rendering/core/frame_telemetry.dart`, `vendor/pixeldart/lib/rendering/core/scene_renderer_timing.dart`, `lib/src/web/player_link_web.dart`, `lib/src/native/player_link_native.dart`, `test/studio/profiler_test.dart`
  - **Scope:** Attach to the in-Studio player, an external browser tab, a native exe or a dedicated server. CPU timeline/hierarchy view, GPU timer-query scopes per declared render-graph pass (with the `RecordingGlesDevice` path marked as synthetic), memory/asset charts, and a draw-stats graph. Frame debugger: pass list → draw list → state → intermediate target readback thumbnails. Captures can be saved and loaded.
  - **DoneWhen:** `test/studio/profiler_test.dart` passes (protocol round-trip, capture save/load); a native player with a GPU shows non-synthetic GPU timings (otherwise reported as skipped); e2e `profiler-attach`.

- [ ] **[S8-B] Build Profiles, Reachability Stripping, Module Tree-Shaking & Build Report**
  - **Priority:** P0 · **DependsOn:** `[S8-0]`
  - **Owns:** `lib/src/studio/build/**`, `tool/studio/build_pipeline.dart`, `tool/package_native.dart`, `tool/asset_packer.dart`, `test/studio/build_profiles_test.dart`
  - **Scope:** Build profiles in `volition.project.json` (target `web|wasm|windows|linux|macos|server`, scenes in build, defines, quality tier, compression, dev/release). Build a GUID dependency closure from scenes in build into a per-profile `.pak` with unreferenced assets stripped. Generate a player entrypoint that imports only enabled modules. Emit a build report (size by asset, module and code) as JSON and in the Studio Build window. Builds are deterministic.
  - **DoneWhen:** `test/studio/build_profiles_test.dart` passes (stripping closure, deterministic `.pak` hash across two builds); `volition build --profile web-release` output hash matches the Studio-triggered build.

- [ ] **[S8-C] Standalone Studio App & Single Distributable**
  - **Priority:** P1 · **DependsOn:** `[S8-0]`
  - **Owns:** `bin/volition.dart` (`gui --app` only), `dist.ps1`, `tool/studio/app_window.dart`, `test/studio/app_mode_test.dart`
  - **Scope:** `volition gui --app` opens Studio in a native window, either through the existing `--target webview` wrapper or a browser in app mode, chosen by `volition doctor` capability. Add a first-run project picker, recent projects and new-from-template. `dist.ps1` emits one bundle: `volition.exe` + embedded Studio + SDL3/ANGLE runtimes.
  - **DoneWhen:** `test/studio/app_mode_test.dart` passes; `dist.ps1` output launches Studio offline on a clean machine (manual check recorded with screenshot).

- [ ] **[S8-D] Templates, Flagship Showcase & Generated Documentation**
  - **Priority:** P1 · **DependsOn:** `[S8-0]`
  - **Owns:** `tool/templates/**`, `example/showcase/**`, `doc/studio/**`, `tool/generate_module_catalog.dart`
  - **Scope:** Rebuild `volition create --template empty|2d|3d|multiplayer` on the project format with GUID assets. "Volition Showcase" uses VRP (CSM, clustered lights, IBL, TAA) and at least one module from each of the six families, and is built for web and windows. Docs: Studio manual, scripting guide (annotations, codegen, hot reload), VRP guide, and a module catalog generated from the registry.
  - **DoneWhen:** `volition create` → open in Studio → play → `volition build --profile web-release` passes in e2e `template-roundtrip` for each template; the showcase builds for both targets.

- [ ] **[S8-M] Coordinator Release Gate & Re-Audit**
  - **Priority:** P0
  - **DependsOn:** `[S8-A]`, `[S8-B]`, `[S8-C]`, `[S8-D]`
  - **Owns:** `PLAN.md`, `TODO.md`, `ENGINE.md`, `README.md`, root + submodule gitlinks
  - **Scope:** Run `verify_all.dart`, Browser Lab, the Studio e2e suite, the module coverage gate (`editor-tooled` for the 22 tooled modules, `inspectable` for all), the CLI parity test, and the native hardware smoke (or record it as skipped). Re-run every PLAN §13.1 audit query and record the results verbatim. Tag a release only if all are green.
  - **DoneWhen:** The release report lists each gate's raw output and zero reopened audit items.

---

## Carry-Over Index: Legacy `pixeldart` `PLAN.md` & `TODO.md` Traceability

Every open item from the prior `pixeldart`-only `PLAN.md` and `TODO.md` is tracked explicitly here so zero renderer debt is dropped:

| Legacy Open Item (Old `PLAN.md` / `TODO.md`) | Mapped Task ID | Wave |
| --- | --- | --- |
| `R1`/`R2` WebGL2 shader validation & `--check` | `[P0-W8-B]`, `[P4-W12-A]` | Wave 8 / 12 |
| `R3` Declared host graph-pass API & safe-graph reconcile | `[P4-W12-0]`, `[P4-W12-B1]` | Wave 12 |
| `R4` Anisotropy quality/cost benchmark | `[P4-W12-B2]` | Wave 12 |
| `R5` MSAA resize/restore correctness & cost | `[P4-W12-B2]` | Wave 12 |
| `R6` CI workflow gating format, analyze, shader check & tests | `[P0-W8-B]` | Wave 8 |
| `R7` Browser Lab golden baselines + `Procession` dense trees fix | `[P4-W12-A]` | Wave 12 |
| `core/frame_arena`, `core/dynamic_batch`, `webgl/frame_targets` | `[P4-W12-B1]`, `[P4-W12-B2]` | Wave 12 |
| Instance streaming beyond 16-instance uniform cap | `[P4-W12-B2]` | Wave 12 |
| Repo-wide `dart format` cleanliness | `[P0-W8-M]` | Wave 8 |
| Stencil state, Decal stage, Soft particles | `[P4-W12-B1]`, `[P4-W12-B2]` | Wave 12 |
| Directional-light shadows, Multiple casters + cap-driven res, Front-face depth culling | `[P4-W12-B2]` | Wave 12 |
| Per-draw light selection + diagnostics, Debug views, Full diagnostics snapshot | `[P4-W12-B1]`, `[P7-W15-C]` | Wave 12 / 15 |
| Material table capacity splitting, Texture array groups | `[P4-W12-B1]`, `[P4-W12-B2]` | Wave 12 |
| Real LUT asset + loader, `OBJ -> QMSH`, Model catalog/sidecar validation | `[P3-W11-B]` | Wave 11 |
| Run QMSH through real GPU path | `[P4-W12-A]`, `[P4-W12-B2]` | Wave 12 |
| Alpha-mask x affine fixture, Vertex lighting, Fixed low internal res, Affine UV, Linear/sRGB audit | `[P4-W12-A]`, `[P4-W12-B2]` | Wave 12 |
| Temporal-determinism, Live `reducedMotion`, Luminance/comfort gate, Visual-stability gates | `[P5-W13-D]` | Wave 13 |
| Performance budget ratification (180w/600m), Telemetry/alloc/no-black-frame, Culling/instancing pixels | `[P4-W12-A]` | Wave 12 |
| Transient stress story & Package publication decision (`publish_to`) | `[P7-W15-C]` | Wave 15 |
| **Reopened 2026-11-20:** 16-instance uniform arrays still in `shadowed_world.vert:13-14` | `[S1-B]` | Studio Track S1 |
| **Reopened 2026-11-20:** 64-joint uniform palette (`shadowed_world.vert:25`) | `[S1-B]` | Studio Track S1 |
| **Reopened 2026-11-20:** Single shadow map / no GPU CSM / no multi-caster atlas | `[S3-C]` | Studio Track S3 |
| **Reopened 2026-11-20:** Fixed 1+4+4 light budget, no clustering | `[S3-B]` | Studio Track S3 |
| **Reopened 2026-11-20:** No HDR targets, cubemaps, UBOs, texture-array shader consumers | `[S1-0]`, `[S1-A]`, `[S3-D]`, `[S4-A]` | Studio Track S1 / S3 / S4 |
| **Reopened 2026-11-20:** Studio is a CLI dashboard, not an editor | `[S2-*]` | Studio Track S2 |
