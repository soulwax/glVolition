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

- [ ] **[P0-W8-A] Fix CLI `_runServe` bug, JS compiler `noSuchMethod` hint & README typo**
  - **Priority:** P0
  - **DependsOn:** none
  - **Owns:** `bin/volition.dart`, `README.md`, `lib/src/engine/serialization/component_spec_extra.dart`
  - **Reads:** `test/**`
  - **Scope:**
    - In `bin/volition.dart` (`_runServe`, around line 140), replace `Platform.resolvedExecutable` with `_dartExecutable` so `volition serve` succeeds when invoked from a compiled AOT `volition.exe` binary.
    - In `lib/src/engine/serialization/component_spec_extra.dart` (`_EmptySpecResources`, around line 15), remove `noSuchMethod(Object invocation)` or replace with explicit concrete no-op stubs so `dart compile js` emits zero hints.
    - In `README.md` (line 28), fix `-- target wasm` -> `--target wasm`.
  - **DoneWhen:** `dart analyze` reports 0 issues; `dart compile js example/prism_pulse/main.dart -o build/smoke.js` succeeds with zero `noSuchMethod` hints; `dart compile exe bin/volition.dart` runs `serve --help` / `serve` invoking `_dartExecutable`.

- [ ] **[P0-W8-B] Add Static Boundary Linter, Unified Verification Script & GitHub Actions CI (`R6`)**
  - **Priority:** P0
  - **DependsOn:** none
  - **Owns:** `.github/workflows/ci.yml`, `tool/check_boundaries.dart`, `tool/verify_all.dart`
  - **Reads:** `pubspec.yaml`, `dist.ps1`, `vendor/pixeldart/tools/**`, `vendor/voxnet/pubspec.yaml`
  - **Scope:**
    - Create `tool/check_boundaries.dart` that scans `lib/src/engine/**` and `lib/gl_volition.dart` and fails non-zero if any file imports `dart:io`, `dart:ffi`, `dart:isolate`, `package:web`, `dart:js_interop`, or `dart:html`.
    - Create `tool/verify_all.dart` orchestrating: boundary check, `dart analyze`, `dart test`, `vendor/pixeldart` verification (`dart run tools/renderer/check_boundary.dart`, `dart run tools/renderer/shaders.dart --check`, `dart run tools/renderer/test_all.dart`), `vendor/voxnet` (`dart test`), `dart compile js example/prism_pulse/main.dart`, optional `dart compile wasm` smoke, and `dart compile exe bin/volition.dart` (cleaning temporary artifacts or writing under `.dart_tool/`).
    - Create `.github/workflows/ci.yml` running `dart format --output=none --set-exit-if-changed .` + `dart run tool/verify_all.dart` on Windows and Linux runners (`ubuntu-latest`, `windows-latest`).
  - **DoneWhen:** `dart run tool/check_boundaries.dart` passes; `dart run tool/verify_all.dart` passes locally end-to-end.

- [ ] **[P0-W8-C] Shard Monolithic `test/subsystems_test.dart` Into Domain Test Suites**
  - **Priority:** P0
  - **DependsOn:** none
  - **Owns:** `test/subsystems_test.dart`, `test/engine/**`, `test/physics/**`, `test/assets/**`, `test/network/**`, `test/serialization/**`, `test/native/**`
  - **Reads:** `lib/src/**`
  - **Scope:**
    - Split the 10,284-line `test/subsystems_test.dart` into fast, focused domain files (`test/engine/*_test.dart`, `test/physics/*_test.dart`, `test/assets/*_test.dart`, `test/network/*_test.dart`, `test/serialization/*_test.dart`, `test/native/*_test.dart`) without losing or weakening any single `test(...)` or assertion.
    - Convert `test/subsystems_test.dart` into a small verification/smoke index or clean removal once all extracted files execute via `dart test`.
  - **DoneWhen:** Exact total passed test count from `dart test` equals or exceeds pre-split count (`>= 200`, 0 skipped, 0 failures).

- [ ] **[P0-W8-M] Coordinator Merge: Repo-Wide Format & CI Gate Activation**
  - **Priority:** P0
  - **DependsOn:** `[P0-W8-A]`, `[P0-W8-B]`, `[P0-W8-C]`
  - **Owns:** All workspace formatting (`dart format .`) + CI toggle verification
  - **Scope:** Run `dart format .`, confirm `dart format --output=none --set-exit-if-changed .` returns 0, run `dart run tool/verify_all.dart`.

---

## Wave 9 (Phase 1) — Native Desktop OS Backend (SDL3 + GLES3/ANGLE + Audio + AOT Packaging)

**Wave Exit Gate:** Native AOT executable opens a live OS window via SDL3 FFI, compiles/links real GLES3/ANGLE shaders, swaps frames on resize without errors, outputs hardware PCM audio, and keeps deterministic headless `RecordingGlesDevice` tests green.

- [ ] **[P1-W9-0] Coordinator Freeze: Native FFI Service Contracts & Pluggable Host Injection**
  - **Priority:** P0
  - **DependsOn:** `[P0-W8-M]`
  - **Owns:** `lib/src/native/native_bindings.dart`, `lib/src/native/native_host.dart` (constructor injection only)
  - **Reads:** `lib/src/native/native_ffi_transport.dart`, `lib/src/engine/host.dart`
  - **Scope:**
    - Define abstract native contracts in `native_bindings.dart`: `NativeWindowBackend` (init, resize polling, swapBuffers, makeCurrent, shutdown), `GlProcBindings`, and `NativeAudioSink`.
    - Update `NativeEngineHost` constructor to accept optional injectable `AudioDevice?`, `GpuDevice?`, and `NativeWindowBackend?` so concurrent workers implement hardware modules cleanly against frozen types.
  - **DoneWhen:** `dart analyze` passes.

- [ ] **[P1-W9-A] Real SDL3 `dart:ffi` Windowing, Context Creation & Live Event Pump**
  - **Priority:** P0
  - **DependsOn:** `[P1-W9-0]`
  - **Owns:** `lib/src/native/sdl3_bindings.dart`, `lib/src/native/native_ffi_transport.dart`, `test/native/sdl3_transport_test.dart`
  - **Reads:** `lib/src/native/native_bindings.dart`
  - **Scope:**
    - Implement `DynamicLibrary.lookupFunction` FFI bindings for SDL3 (`SDL_Init`, `SDL_CreateWindow`, `SDL_GL_CreateContext`, `SDL_GL_MakeCurrent`, `SDL_GL_SwapWindow`, `SDL_PollEvent`, `SDL_GetWindowSizeInPixels`, `SDL_DestroyWindow`, `SDL_Quit`) with clean missing-library diagnostic errors.
    - Replace stubbed queue-only behavior in `Sdl3EventPump` and `NativeDesktopBridge` with live SDL3 event decoding (keyboard up/down/repeat, mouse move/button/wheel, window resize/close/focus) while retaining a test-injectable queue adapter for deterministic VM tests.
  - **DoneWhen:** `dart test test/native/sdl3_transport_test.dart` passes; missing-DLL handling fails cleanly with actionable error messages rather than uncaught FFI segfaults.

- [ ] **[P1-W9-B] Real GLES3 / ANGLE Hardware `GpuDevice` + Preserved `RecordingGlesDevice` for CI**
  - **Priority:** P0
  - **DependsOn:** `[P1-W9-0]`
  - **Owns:** `lib/src/native/gles3_bindings.dart`, `lib/src/native/gles3_ffi_device.dart`, `lib/src/native/native_host.dart`, `test/native/gles3_device_test.dart`
  - **Reads:** `vendor/pixeldart/lib/rendering/**`, `lib/src/native/native_bindings.dart`
  - **Scope:**
    - Extract current software recorder implementation in `native_host.dart` (`GlesDevice`) as `RecordingGlesDevice` (retaining full VM CI inspection support).
    - Create `Gles3Bindings` (EGL/ANGLE/GLES3 FFI function lookup via `DynamicLibraryGlLoader`) and `Gles3FfiDevice` implementing real FBOs, VBOs/VAOs, textures, GLSL shader compile/link checks, uniform uploads, draw calls, readPixels, and genuine `GL_EXT_disjoint_timer_query` / timestamp polling (removing the hardcoded `1250000` constant on hardware devices).
  - **DoneWhen:** `dart test test/native/gles3_device_test.dart` passes against both `RecordingGlesDevice` and live FFI binding signature checks; zero hardcoded timer values on `Gles3FfiDevice`.

- [ ] **[P1-W9-C] Native Hardware PCM Audio Device Replacing `SilentAudio`**
  - **Priority:** P1
  - **DependsOn:** `[P1-W9-0]`
  - **Owns:** `lib/src/native/native_audio_device.dart`, `test/native/native_audio_test.dart`
  - **Reads:** `lib/src/native/native_bindings.dart`, `lib/src/engine/host.dart`, `lib/src/engine/components/audio_source.dart`
  - **Scope:**
    - Implement `NativeAudioDevice` implementing `AudioDevice` using SDL3 audio stream / miniaudio C ABI callback or buffered PCM mixer in software + native audio stream output (`volume`, `playbackRate`, `loop`, WAV/OGG/PCM decoding).
    - Provide clean fallback/diagnostic mode when audio hardware is unavailable (headless CI without sound card).
  - **DoneWhen:** `dart test test/native/native_audio_test.dart` verifies mixing, looping, stop/pause, and PCM frame emission deterministically.

- [ ] **[P1-W9-D] True Native AOT Desktop Build Targets (`--target windows|linux|macos`)**
  - **Priority:** P0
  - **DependsOn:** `[P1-W9-0]`
  - **Owns:** `bin/volition.dart`, `dist.ps1`, `tool/package_native.dart`, `example/native_smoke/main.dart`, `test/native/package_native_test.dart`
  - **Reads:** `vendor/pixeldart/examples/desktop_host/Program.cs`
  - **Scope:**
    - Change `bin/volition.dart` `_buildWindowsExecutable` (and add `linux`/`macos` native targets) to compile real Dart AOT executables importing `gl_volition_native.dart` + bundling SDL3/ANGLE dynamic libs and asset `.pak`/data folders.
    - Keep the existing `.NET 10` WinForms `WebView2` wrapper (`Program.cs`) available explicitly under `--target webview` for browser-embedded distribution.
    - Update `example/native_smoke/main.dart` to accept `--hardware` / `--headless` smoke mode flags and update `dist.ps1`.
  - **DoneWhen:** `dart test test/native/package_native_test.dart` and `dart run bin/volition.dart build example/native_smoke/main.dart --target windows --dry-run` (or full local AOT bundle build) pass cleanly.

- [ ] **[P1-W9-M] Coordinator Merge: Default `NativeEngineHost` Hardware Wiring**
  - **Priority:** P0
  - **DependsOn:** `[P1-W9-A]`, `[P1-W9-B]`, `[P1-W9-C]`, `[P1-W9-D]`
  - **Owns:** `lib/gl_volition_native.dart`, `lib/src/native/native_host.dart`
  - **Scope:** Wire default windowed `NativeEngineHost.desktop(...)` factory using `Sdl3NativeBridge` + `Gles3FfiDevice` + `NativeAudioDevice`, while keeping `NativeEngineHost.recording(...)` / default test constructor safe for headless VM CI.

---

## Wave 10 (Phase 2) — Complete Host Contract (`Input`, Web Audio DSP, Multi-Camera, `visibilityMask`)

**Wave Exit Gate:** Feature parity across `HeadlessHost`, `WebEngineHost`, and `NativeEngineHost` for wheel/touch/pointer-lock/gamepad input, spatial Web Audio DSP, multi-camera viewports + render-to-texture, and Web `visibilityMask` culling.

- [ ] **[P2-W10-0] Coordinator Freeze: Extend `host.dart` / `headless.dart`, Split `web_host.dart` & Patch `PixeldartApp._frame`**
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

- [ ] **[P2-W10-A] Web & Native Input Parity (Wheel, Multi-Touch, PointerLock, Gamepad) + `InputManagerComponent` Wiring**
  - **Priority:** P1
  - **DependsOn:** `[P2-W10-0]`
  - **Owns:** `lib/src/web/web_input.dart`, `lib/src/native/native_input.dart`, `lib/src/engine/components/input_manager.dart`, `test/engine/input_parity_test.dart`
  - **Reads:** `lib/src/engine/host.dart`, `lib/src/native/native_ffi_transport.dart`
  - **Scope:**
    - Wire DOM `wheel`, `touchstart/move/end`, `PointerLock` (`movementX/Y`), and `navigator.getGamepads()` in `web_input.dart`.
    - Wire SDL3 gamepad + wheel + relative mouse mode in `native_input.dart`.
    - Connect `InputManagerComponent` action maps, axis bindings, runtime rebinding persistence, and virtual touch overlays cleanly to live `Input`.
  - **DoneWhen:** `dart test test/engine/input_parity_test.dart` + `dart compile js example/prism_pulse/main.dart` pass.

- [ ] **[P2-W10-B] Web Audio API `AudioContext` DSP Graph & Spatial Mixer Integration**
  - **Priority:** P1
  - **DependsOn:** `[P2-W10-0]`
  - **Owns:** `lib/src/web/web_audio.dart`, `lib/src/native/native_audio_device.dart`, `lib/src/engine/components/audio_dsp.dart`, `lib/src/engine/components/audio_source.dart`, `test/engine/audio_dsp_test.dart`
  - **Reads:** `lib/src/engine/host.dart`, `lib/src/engine/headless.dart`
  - **Scope:**
    - Replace `HTMLAudioElement`-only playback in `web_audio.dart` with Web Audio `AudioContext` + `AudioBufferSourceNode` + `StereoPannerNode` / `PannerNode` + `BiquadFilterNode` + `ConvolverNode` / wet-dry reverb bus (with clean autoplay-unlock policy).
    - Wire `AudioListener`, `AudioSource`, `AudioMixer`, `AudioReverbZone`, `AudioLowPassFilterComponent`, and `SpatialAudioDspExt` so zone proximity/occlusion parameters drive live `AudioChannel` pan, cutoff Hz, and reverb send on Web, Native, and Headless.
  - **DoneWhen:** `dart test test/engine/audio_dsp_test.dart` verifies gain attenuation, stereo pan, lowpass cutoff, and reverb send updates into `HeadlessAudio` & `NativeAudioDevice`, and `dart compile js` compiles cleanly.

- [ ] **[P2-W10-C] Multi-Camera Viewport Sorting & Render-to-Texture Pipeline**
  - **Priority:** P1
  - **DependsOn:** `[P2-W10-0]`
  - **Owns:** `lib/src/web/web_graphics.dart`, `lib/src/native/native_host.dart`, `lib/src/engine/components/camera.dart`, `lib/src/engine/scene.dart`, `test/engine/multi_camera_test.dart`
  - **Reads:** `lib/src/engine/host.dart`, `vendor/pixeldart/lib/rendering/**`
  - **Scope:**
    - Update `Scene._syncToRenderer` and `Engine` frame submission to sort all enabled `Camera` components by `Camera.depth`, apply each camera's `cullingMask`/`visibilityMask`, `normalizedViewportRect`, clear flags, and optional offscreen `RenderTargetHandle`.
    - Implement multi-pass viewport/scissor & render-target switching in `web_graphics.dart` and `native_host.dart` (+ `RecordingGlesDevice` viewport command assertions).
  - **DoneWhen:** `dart test test/engine/multi_camera_test.dart` proves depth ordering (2+ active cameras + PIP minimap target) and per-camera `visibilityMask` isolation across Headless and Native recording hosts.

- [ ] **[P2-W10-M] Coordinator Merge: Push `vendor/pixeldart` `visibilityMask` Submodule Commit & Verify Parity**
  - **Priority:** P0
  - **DependsOn:** `[P2-W10-A]`, `[P2-W10-B]`, `[P2-W10-C]`
  - **Owns:** Submodule gitlink sync + `tool/verify_all.dart` run
  - **Scope:** Commit/verify `vendor/pixeldart` `PixeldartApp._frame` fix, re-run full `verify_all.dart`.

---

## Wave 11 (Phase 3) — Production Asset Pipeline, `.pak` VFS Unification, Streaming & Scene Migrations

**Wave Exit Gate:** Scenes load `.glb`/`.qmesh`/textures/LUTs natively from `.pak` archives, `ModelRenderer` serializes real `AssetCatalog` keys, `v1` scenes migrate cleanly to current schema, and background async streaming passes memory/eviction tests.

- [ ] **[P3-W11-0] Coordinator Freeze: Asset Handles, Ref-Counting & Migration Interfaces**
  - **Priority:** P0
  - **DependsOn:** `[P2-W10-M]`
  - **Owns:** `lib/src/engine/assets/asset_types.dart`, `lib/src/engine/serialization/scene_migration.dart`
  - **Reads:** `lib/src/engine/assets/asset_catalog.dart`, `lib/src/engine/assets/pak_vfs.dart`, `lib/src/engine/serialization/scene_serializer.dart`
  - **Scope:** Define `AssetHandle<T>` (`acquire`/`release`), eviction callback contracts, and `SceneMigrationStep` interface (`fromVersion`, `toVersion`, `migrate(Map<String, Object?>)`).
  - **DoneWhen:** `dart analyze` passes.

- [ ] **[P3-W11-A] Direct `VfsAssetLoader.loadModel`, Ref-Counted `AssetCatalog` Unloading & `ModelRenderer` Spec Fix**
  - **Priority:** P0
  - **DependsOn:** `[P3-W11-0]`
  - **Owns:** `lib/src/engine/assets/pak_vfs.dart`, `lib/src/engine/assets/asset_catalog.dart`, `lib/src/engine/serialization/component_spec_extra.dart`, `test/assets/asset_catalog_vfs_test.dart`
  - **Reads:** `lib/src/engine/assets/asset_types.dart`, `vendor/pixeldart/lib/rendering/**`
  - **Scope:**
    - Implement `VfsAssetLoader.loadModel` directly from `VfsArchive` `.glb` / `.qmesh` byte entries (eliminating `UnimplementedError` when `fallback == null`).
    - Implement ref-counted `acquire(key)`, `release(key)`, explicit `unload(key)` / `unloadUnused()`, and GPU handle disposal notifications in `AssetCatalog`.
    - Fix `ModelRenderer` `ComponentSpec` (`component_spec_extra.dart:44-49`) so `assetId` / asset key serializes/deserializes against `AssetCatalog` instead of constructing an empty dummy `ModelAsset` with `const []` fields.
  - **DoneWhen:** `dart test test/assets/asset_catalog_vfs_test.dart` passes round-trip `.pak` model loads without fallback and verifies ref-count drops to 0 cleanly dispose resources.

- [ ] **[P3-W11-B] `volition pack` CLI Bundler, `OBJ -> QMSH` Integration, Catalog Validator & LUT Asset Loader**
  - **Priority:** P1
  - **DependsOn:** `[P3-W11-0]`
  - **Owns:** `tool/asset_packer.dart`, `bin/volition.dart`, `vendor/pixeldart/lib/assets/**`, `vendor/pixeldart/tools/assets/**`, `test/assets/packer_qmesh_test.dart`
  - **Reads:** `vendor/pixeldart/lib/rendering/**`, `lib/src/engine/assets/pak_vfs.dart`
  - **Scope:**
    - Add `volition pack <dir> -o <bundle.pak>` CLI command compiling manifests, textures, audio, LUTs, and validated `.qmesh`/`.glb` models into indexed `.pak` files.
    - Wire `vendor/pixeldart`'s existing `ObjImporter` / `ObjModelPackageEmitter` / `GltfModelPackageEmitter` / `ModelPackageValidator` (`vendor/pixeldart/lib/assets/**`) directly into `volition pack` / converter CLI commands and close any missing sidecar validation edge cases.
    - Build a real color-grading `.cube`/image LUT asset + loader (`TODO.md` carry-over) usable by `pixeldart` post-processing & `.pak` archives.
  - **DoneWhen:** `dart test test/assets/packer_qmesh_test.dart` generates an OBJ -> QMSH package, packs a `.pak` archive, validates sidecars, and loads the LUT asset cleanly.

- [ ] **[P3-W11-C] Versioned `SceneSerializer` & `Prefab` Schema Migration Pipeline**
  - **Priority:** P1
  - **DependsOn:** `[P3-W11-0]`
  - **Owns:** `lib/src/engine/serialization/scene_serializer.dart`, `lib/src/engine/serialization/scene_migration.dart`, `lib/src/engine/prefab.dart`, `test/serialization/scene_migration_test.dart`
  - **Reads:** `lib/src/engine/serialization/component_spec.dart`
  - **Scope:**
    - Bump scene schema version cleanly via `SceneMigrator` chain (`v1 -> v2 -> ...`) in `scene_serializer.dart` instead of immediately throwing `FormatException('Unsupported scene schemaVersion: $version')` on older saved scenes.
    - Add unknown-component preservation / warning diagnostics (`strictMode` toggle) and matching migration support in `Prefab`.
  - **DoneWhen:** `dart test test/serialization/scene_migration_test.dart` migrates recorded `v1` scene and prefab JSON fixtures forward cleanly and rejects only genuinely corrupted or future-unsupported schemas.

- [ ] **[P3-W11-D] Background Isolate / Micro-Budgeted Streaming Asset Loader**
  - **Priority:** P1
  - **DependsOn:** `[P3-W11-0]`
  - **Owns:** `lib/src/engine/assets/streaming_loader.dart`, `lib/src/native/native_async_decode.dart`, `lib/src/web/web_async_decode.dart`, `test/assets/streaming_loader_test.dart`
  - **Reads:** `lib/src/engine/assets/asset_types.dart`, `lib/src/engine/assets/asset_catalog.dart`
  - **Scope:**
    - Build priority-queued `StreamingAssetLoader` with configurable per-frame upload millisecond budget and host-pluggable worker decoding (`Isolate.run` via `native_async_decode.dart` on Native, cooperative chunked async decode on Web/Headless so `lib/src/engine/**` stays pure Dart).
  - **DoneWhen:** `dart test test/assets/streaming_loader_test.dart` verifies cancellation, priority preemption, and bounded per-tick completion work under heavy queues.

- [ ] **[P3-W11-M] Coordinator Merge: Wire `StreamingAssetLoader` Into `Scene` & Push `pixeldart` Tools**
  - **Priority:** P0
  - **DependsOn:** `[P3-W11-A]`, `[P3-W11-B]`, `[P3-W11-C]`, `[P3-W11-D]`
  - **Owns:** `lib/src/engine/scene.dart`, submodule gitlink check
  - **Scope:** Wire optional `StreamingAssetLoader` frame-budget step into `Engine`/`Scene`, test `dist.ps1` / `verify_all.dart`.

---

## Wave 12 (Phase 4) — Production Rendering, Skeletal Skinning & `pixeldart` Closure (`R1–R7`)

**Wave Exit Gate:** All remaining `pixeldart` `R1–R7` & renderer roadmap items verified in Browser Lab (golden PNG/SSIM, 180w/600m budget table, telemetry/no-black-frame gates), GPU skeletal animation deforms GLB characters, and CPU-only GI/2D-lighting/soft-body/batcher subsystems drive GPU output.

- [ ] **[P4-W12-0] Coordinator Freeze: `R3` Declared Graph Pass API, `SkinData` & GI/2D Uniform Contracts**
  - **Priority:** P0
  - **DependsOn:** `[P3-W11-M]`
  - **Owns:** `vendor/pixeldart/lib/rendering/api/**`, `lib/src/engine/components/skinned_mesh.dart`
  - **Scope:**
    - Freeze `R3` host-declared graph-pass descriptor API (`RenderPassDecl`, transient target attachments, pass dependencies) and renderer diagnostic counters snapshot contract (`vendor/pixeldart` `TODO.md` carry-over).
    - Freeze bone palette / skin matrix capacity constants and `SkinData` / `JointNode` structures for GLB skinning.
    - Freeze shader slot/uniform names used by `LightProbeVolumeComponent` (SH3), `Lighting2DComponent` (2D lightmap overlay), and dynamic deformed mesh upload hooks.
  - **DoneWhen:** Both root `dart analyze` and `vendor/pixeldart` `dart analyze` pass.

- [ ] **[P4-W12-A] `pixeldart` Browser Lab (`R7`), Golden + Perf Baseline Gates & `Procession` Dense Trees Fix**
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

- [ ] **[P4-W12-B1] `pixeldart` Core Pipeline: `frame_arena`, `dynamic_batch`, Safe-Graph Reconcile & Diagnostics**
  - **Priority:** P0
  - **DependsOn:** `[P4-W12-0]`
  - **Owns:** `vendor/pixeldart/lib/rendering/core/**`, `vendor/pixeldart/tools/renderer/test_*_core*.dart`, `vendor/pixeldart/tools/renderer/test_render_graph*.dart`, `vendor/pixeldart/tools/renderer/test_no_allocation_trace.dart`
  - **Reads:** `vendor/pixeldart/lib/rendering/api/**`
  - **Scope:**
    - Close remaining `core/frame_arena` and `core/dynamic_batch` zero-allocation gaps beyond `frame_queue.dart`/`batching.dart`.
    - Reconcile safe-graph shape and implement `R3` host-declared custom graph passes cleanly.
    - Implement material table capacity splitting, per-draw light selection + diagnostics, debug visualization modes (albedo/normals/roughness/light-heatmap/overdraw), and full diagnostics snapshot export.
  - **DoneWhen:** `dart run tools/renderer/test_all.dart` inside `vendor/pixeldart` passes all core & zero-allocation trace tests.

- [ ] **[P4-W12-B2] `pixeldart` WebGL2 Passes: Instancing >16 Cap, Stencil, Decals, Shadows, MSAA & Linear/sRGB Audit**
  - **Priority:** P0
  - **DependsOn:** `[P4-W12-0]`
  - **Owns:** `vendor/pixeldart/lib/rendering/webgl/**`, `vendor/pixeldart/lib/rendering/passes/**`, `vendor/pixeldart/shaders/**`, `vendor/pixeldart/tools/renderer/test_webgl*.dart`, `vendor/pixeldart/tools/renderer/test_msaa*.dart`, `vendor/pixeldart/tools/renderer/test_directional_shadow.dart`
  - **Reads:** `vendor/pixeldart/lib/rendering/api/**`, `vendor/pixeldart/lib/rendering/core/**`
  - **Scope:**
    - Wire `InstanceBufferStream` end-to-end into live world/shadow passes & `webgl/frame_targets` to eliminate any remaining 16-instance uniform cap (`>1024` instances per draw via instanced attributes / UBO).
    - Expand `ShadowLightView` directional/multi-caster shadow support with capability-driven shadow resolution and front-face culling during shadow/depth pass.
    - Implement genuine stencil buffer state and decal rendering stage (currently `0` references in `lib/rendering/`), texture array groups, soft particles, fixed low internal resolution scaling, affine UV option in textured/safe world, vertex lighting fallback, `R4` anisotropy quality/cost benchmark, `R5` MSAA resize/restore correctness & cost, and a complete `Linear / sRGB` shader & render-target audit (`tools/renderer/shaders.dart` regenerated and `--check` clean).
  - **DoneWhen:** `dart run tools/renderer/shaders.dart --check` + `dart run tools/renderer/check_boundary.dart` + `dart run tools/renderer/test_all.dart` inside `vendor/pixeldart` pass cleanly.

- [ ] **[P4-W12-C] Skeletal GPU Skinning Pipeline (`Animator` + `GlbSkinDecoder` + `SkinnedMeshRenderer`)**
  - **Priority:** P1
  - **DependsOn:** `[P4-W12-0]`
  - **Owns:** `lib/src/engine/assets/glb_skin_decoder.dart`, `lib/src/engine/components/animator.dart`, `lib/src/engine/components/skinned_mesh.dart`, `test/engine/skinning_test.dart`
  - **Reads:** `lib/src/engine/assets/pak_vfs.dart`, `vendor/pixeldart/lib/rendering/api/**`
  - **Scope:**
    - Parse GLB `skins`, `joints`, `inverseBindMatrices`, and `JOINTS_0`/`WEIGHTS_0` attributes cleanly in `glb_skin_decoder.dart`.
    - Extend `Animator` to evaluate hierarchical bone keyframe tracks, cross-fade blends, and joint palettes feeding `SkinnedMeshRenderer` GPU matrix uniforms/buffers.
  - **DoneWhen:** `dart test test/engine/skinning_test.dart` verifies known bone hierarchy FK + inverse-bind deformation accuracy against reference skinning math and `HeadlessGraphics` uniform palette uploads.

- [ ] **[P4-W12-D] Wire Decoupled GPU Systems (`LightProbeGI`, `Lighting2D`, `SoftBodyXPbd`, `DrawBatcher`, `RenderGraph`)**
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

- [ ] **[P4-W12-M] Coordinator Merge: Integrate Wave 12 Into `Scene`, `ComponentSpec` & Submodule Commit**
  - **Priority:** P0
  - **DependsOn:** `[P4-W12-A]`, `[P4-W12-B1]`, `[P4-W12-B2]`, `[P4-W12-C]`, `[P4-W12-D]`
  - **Owns:** `lib/gl_volition.dart`, `lib/src/engine/scene.dart`, `lib/src/engine/serialization/component_spec.dart`
  - **Scope:** Register `SkinnedMeshRenderer` / wired components, commit/push `vendor/pixeldart`, update root gitlink reference, verify `dart run tool/verify_all.dart` + Browser Lab.

---

## Wave 13 (Phase 5) — Scalable 3D Physics, True Colliders & Runtime Determinism

**Wave Exit Gate:** `PhysicsWorld` steps 1,000+ colliders in sub-linear spatial broadphase, rotated `BoxCollider` uses true OBB SAT, `MeshCollider`/`HeightfieldCollider` + rotational dynamics/joints/CCD pass stress suites, and 600-frame deterministic + comfort tests are green.

- [ ] **[P5-W13-0] Coordinator Pre-Split: Modularize `physics.dart` & Freeze Narrowphase/Broadphase Interfaces**
  - **Priority:** P0
  - **DependsOn:** `[P4-W12-M]`
  - **Owns:** `lib/src/engine/components/physics.dart` (barrel export), `lib/src/engine/components/physics_broadphase.dart`, `lib/src/engine/components/physics_colliders.dart`, `lib/src/engine/components/physics_solver.dart`, `lib/src/engine/components/physics_world.dart`
  - **Scope:** Split the single `physics.dart` file cleanly into modular collaborators while keeping all public symbol exports identical (`lib/src/engine/components/physics.dart` re-exports all split files) so existing callers suffer zero breakage.
  - **DoneWhen:** `dart analyze` + existing `test/physics/**` pass 100% unchanged after split.

- [ ] **[P5-W13-A] Spatial Broadphase Acceleration Replacing `O(N^2)` `PhysicsWorld` Loops**
  - **Priority:** P1
  - **DependsOn:** `[P5-W13-0]`
  - **Owns:** `lib/src/engine/components/physics_broadphase.dart`, `lib/src/engine/components/broadphase_world.dart`, `test/physics/broadphase_test.dart`
  - **Scope:** Replace quadratic pairwise iteration and linear `raycast`/`raycastAll`/`overlapSphere`/`overlapBox`/`sphereCast` scans with uniform spatial hash / BVH broadphase backed cleanly by `BroadphaseWorldComponent`.
  - **DoneWhen:** `dart test test/physics/broadphase_test.dart` proves exact hit parity against brute-force reference plus benchmark speedups on 1,500+ colliders.

- [ ] **[P5-W13-B] True SAT OBB `BoxCollider`, BVH `MeshCollider` & `HeightfieldCollider`**
  - **Priority:** P1
  - **DependsOn:** `[P5-W13-0]`
  - **Owns:** `lib/src/engine/components/physics_colliders.dart`, `test/physics/colliders_test.dart`
  - **Scope:**
    - Replace AABB `worldBounds` approximation on rotated `BoxCollider` with true 15-axis Separating Axis Theorem (SAT) OBB vs OBB / Sphere / Capsule / Ray intersection.
    - Add BVH-accelerated static concave `MeshCollider` and grid `HeightfieldCollider` for terrain.
  - **DoneWhen:** `dart test test/physics/colliders_test.dart` verifies rotated box edges/corners, triangle mesh raycasts, and terrain contacts accurately.

- [ ] **[P5-W13-C] Rotational `RigidBody` Inertia, Torque/Friction, Joints, Sleeping & Swept CCD**
  - **Priority:** P1
  - **DependsOn:** `[P5-W13-0]`
  - **Owns:** `lib/src/engine/components/physics_solver.dart`, `lib/src/engine/components/constraints.dart`, `lib/src/engine/components/physics_world.dart`, `test/physics/solver_ccd_test.dart`
  - **Scope:**
    - Add inertia tensors, angular velocity/impulse, static/dynamic friction, restitution, warm-started sequential impulse solver iterations, island sleeping, hinge/ball/fixed joints, and swept TOI CCD in `RigidBody._step()` so high-velocity projectiles never tunnel thin walls.
  - **DoneWhen:** `dart test test/physics/solver_ccd_test.dart` verifies box stack stability, non-tunneling fast projectiles at >500 units/sec, angular toppling torque, and sleeping island wakeups.

- [ ] **[P5-W13-D] 600-Frame Temporal Determinism, Live `reducedMotion` & Comfort Stability Gates**
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

- [ ] **[P6-W14-0] Coordinator Freeze: Production `NetTransport` TLS/Auth/Metrics & Engine Sync Hooks**
  - **Priority:** P1
  - **DependsOn:** `[P5-W13-D]`
  - **Owns:** `vendor/voxnet/lib/src/transport/transport.dart`, `lib/src/engine/network/network_config.dart`
  - **Reads:** `lib/src/engine/network/network_system.dart`
  - **Scope:** Extend `NetTransport` with connection states, TLS/token header options, RTT/loss telemetry counters, and `NetworkClockSync` / tick-hook config interfaces.
  - **DoneWhen:** `vendor/voxnet` and root `dart analyze` pass.

- [ ] **[P6-W14-A] Cross-Platform `WebSocketNetTransport` (`dart:io` + `package:web`)**
  - **Priority:** P1
  - **DependsOn:** `[P6-W14-0]`
  - **Owns:** `vendor/voxnet/lib/src/transport/websocket_transport.dart`, `vendor/voxnet/lib/src/transport/websocket_transport_io.dart`, `vendor/voxnet/lib/src/transport/websocket_transport_web.dart`, `vendor/voxnet/test/websocket_transport_test.dart`
  - **Scope:** Implement WebSocket client/server (IO) + browser client (`package:web`) with binary framing, heartbeat pings, exponential reconnect backoff, and session token auth.
  - **DoneWhen:** `vendor/voxnet` WebSocket loopback integration tests pass on VM + compile cleanly to JS (`dart compile js`).

- [ ] **[P6-W14-B] Native UDP / Reliable-Unreliable Channel Transport (`dart:io` `RawDatagramSocket` / FFI)**
  - **Priority:** P1
  - **DependsOn:** `[P6-W14-0]`
  - **Owns:** `vendor/voxnet/lib/src/transport/udp_transport.dart`, `vendor/voxnet/lib/src/transport/reliable_channel.dart`, `vendor/voxnet/test/udp_transport_test.dart`
  - **Scope:** Implement sequenced/acknowledged reliable + unreliable/unordered channels over UDP (`RawDatagramSocket` / FFI wrapper), congestion windowing, MTU fragmentation, and synthetic jitter/loss fault injector for tests.
  - **DoneWhen:** `vendor/voxnet` `dart test test/udp_transport_test.dart` passes under 10% simulated packet drop & reordering.

- [ ] **[P6-W14-C] Automatic `NetworkManager` Tick/Replication Sync & Multi-Client Rollback Test Harness**
  - **Priority:** P1
  - **DependsOn:** `[P6-W14-0]`, `[P6-W14-A]`, `[P6-W14-B]`
  - **Owns:** `lib/src/engine/network/network_system.dart`, `test/network/multiplayer_sync_test.dart`
  - **Reads:** `lib/src/engine.dart`
  - **Scope:** Implement delta-compressed snapshot sync, client input prediction, rollback reconciliation hooks in `NetworkManager`, and an automated multi-process/multi-socket integration test over real `ws://` & UDP loopback.
  - **DoneWhen:** `dart test test/network/multiplayer_sync_test.dart` verifies converging multi-client state over real loopback sockets with synthetic latency.

- [ ] **[P6-W14-M] Coordinator Merge: Hook `NetworkManager` Step Into `Engine.step` & Push `voxnet` Gitlink**
  - **Priority:** P0
  - **DependsOn:** `[P6-W14-A]`, `[P6-W14-B]`, `[P6-W14-C]`
  - **Owns:** `lib/src/engine.dart`, `vendor/voxnet` submodule commit/gitlink
  - **Scope:** Invoke `NetworkManager` fixed tick + post-step snapshot replication cleanly from `Engine.step`, verify full `verify_all.dart`.

---

## Wave 15 (Phase 7) — Production Editor UX, Diagnostics & Ship Tooling

**Wave Exit Gate:** Delta undo/redo handles 1,000+ object edits smoothly, 3D viewport gizmos pick/drag live transforms, full telemetry/transient stress checks pass, `volition doctor` + `volition create` + `--target server` work, and package publication strategy is finalized.

- [ ] **[P7-W15-A] Compact `EditorCommand` Delta Undo/Redo Replacing Full-Scene JSON Snapshots**
  - **Priority:** P2
  - **DependsOn:** `[P6-W14-M]`
  - **Owns:** `lib/src/engine/editor_commands.dart`, `lib/src/engine/editor_session.dart`, `test/engine/editor_undo_delta_test.dart`
  - **Reads:** `lib/src/engine/serialization/scene_serializer.dart`
  - **Scope:** Replace `EditorSession._captureHistoryEntry` (`:80-94`) full-scene JSON dumps with composable reversible `EditorCommand` objects (property set, transform move, add/remove object/component, reparent, transaction batch).
  - **DoneWhen:** `dart test test/engine/editor_undo_delta_test.dart` demonstrates multi-step undo/redo memory/time scaling O(delta) vs O(scene) on a 1,000-entity scene.

- [ ] **[P7-W15-B] Live 3D Viewport Gizmos, Unified Workbench/Inspector Picker & Prefab Variant UI**
  - **Priority:** P2
  - **DependsOn:** `[P6-W14-M]`
  - **Owns:** `lib/src/engine/gizmos/viewport_gizmos.dart`, `lib/src/engine/components/engine_workbench.dart`, `lib/src/web/inspector_overlay.dart`, `test/engine/gizmos_workbench_test.dart`
  - **Reads:** `lib/src/engine/editor_session.dart`, `lib/src/engine/prefab.dart`, `lib/src/engine/assets/asset_catalog.dart`
  - **Scope:**
    - Implement interactive 3D translate/rotate/scale gizmo axis raycasting and drag manipulation synchronized with `EditorSession`.
    - Add `AssetCatalog` visual resource picker and prefab-variant override badges/revert controls unified cleanly between `EngineWorkbenchComponent` (`voxui`) and `InspectorOverlay` (Web DOM).
  - **DoneWhen:** `dart test test/engine/gizmos_workbench_test.dart` verifies gizmo axis hit-testing, snapped dragging, and prefab override inspection; `dart compile js` builds cleanly.

- [ ] **[P7-W15-C] CLI DX (`volition create`, `doctor`, `--target server`), Transient Stress, Telemetry & Package Split Decision**
  - **Priority:** P1
  - **DependsOn:** `[P6-W14-M]`
  - **Owns:** `bin/volition.dart`, `lib/src/engine/diagnostics/telemetry_snapshot.dart`, `lib/src/native/server_host.dart`, `test/engine/diagnostics_cli_test.dart`
  - **Reads:** `pubspec.yaml`, `lib/src/engine/headless.dart`
  - **Scope:**
    - Add `volition create <name> [--template 2d|3d|multiplayer]`, `volition doctor` (checks Dart SDK, Chrome/WebGL, MSVC/Clang, SDL3/GLES DLLs, shader toolchain), and `--target server` zero-GPU dedicated multiplayer server binary entrypoint (`server_host.dart`).
    - Implement full runtime diagnostics snapshot JSON + transient particle/VFX/decal stress suite + uncaught crash telemetry handler hook (`TODO.md` carry-over).
    - Document package publication architecture decision (`publish_to: none` monorepo vs split `pub.dev` releases for `gl_volition`, `pixeldart`, `vox*`) in a brief ADR section of `PLAN.md` during merge.
  - **DoneWhen:** `dart test test/engine/diagnostics_cli_test.dart` passes; `volition doctor` exits cleanly with accurate environment table; dedicated `--target server` AOT binary runs headless server tick loop.

- [ ] **[P7-W15-M] Coordinator Final Sign-Off & Production Release Verification**
  - **Priority:** P0
  - **DependsOn:** `[P7-W15-A]`, `[P7-W15-B]`, `[P7-W15-C]`
  - **Owns:** `PLAN.md`, `ENGINE.md`, `TODO.md` status archive
  - **Scope:** Run complete `tool/verify_all.dart`, `tool/renderer_bench.dart`, Browser Lab, and native hardware smoke suite; record release tag readiness.

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
