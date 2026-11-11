# Engine plan (`package:rocket`)

A Unity-style game engine (`GameObject`, `Component`, `Behaviour`, scenes, prefabs, pools, triggers/kinematics, 2D sprites/tilemaps/UI, 3D terrain/water/atmosphere, live inspector, and CLI) built in [`engine/`](engine/) on top of [`pixeldart`](pixeldart/)'s public facade.

---

## 0. Ground rules & frame architecture (optimized for fast iteration)

1. **VM-first inner loop (<0.5 s).** `package:rocket/rocket.dart` never imports `package:web` or `dart:io`. Every subsystem and every game's logic runs on the Dart VM against [`HeadlessHost`](engine/lib/src/engine/headless.dart) so `dart test` steps 1,000 frames of gameplay in <25 ms with zero browser startup.
2. **Zero `build_runner` in the edit-run cycle.** Scene/prefab serialization and the live inspector use explicit, strongly typed [`ComponentSpec<T>`](#e3-zero-codegen-scenes-prefabs-pools--assets) descriptors rather than AST code generation. Editing a `Behaviour` and running `dart test` or reloading the browser takes <1 s.
3. **Strict facade boundary.** `engine/lib/rocket.dart` imports only `package:pixeldart/pixeldart.dart` (and `pixeldart_advanced.dart` where needed). Browser bindings (`package:web`, `PixeldartApp`, `HTMLAudioElement`, `localStorage`) are isolated to `engine/lib/rocket_web.dart`.
4. **Two-phase frame contract (`step` + `encode`).**
   `PixeldartApp` splits each browser frame into `onBeforeFrame` (before `renderer.beginFrame`) and `onFrame(FrameContext)` (while `RenderEncoder` is open). `Engine` mirrors this split so retained 3D nodes and transient encoder draws (`SpriteBatch`, `AtmosphericParticleField`, `FlowParticleField`, gizmos, UI overlays) both work cleanly:

   ```text
   onBeforeFrame(t, dt) ──▶ Engine.step(dt)
     ├─ 1. Swap pending Scene (if loadScene was called mid-frame)
     ├─ 2. Time._beginFrame(dt)  [clamp to maximumDeltaTime, scale by timeScale]
     ├─ 3. Run due Engine.invoke / Behaviour.invoke timers
     ├─ 4. Fixed-step loop (while accumulator >= fixedDeltaTime, max 8 steps):
     │     ├─ Drain pending Behaviour.start() (sorted by executionOrder)
     │     ├─ Behaviour.fixedUpdate()         (sorted by executionOrder)
     │     └─ PhysicsWorld._step()            (kinematic integrate + trigger Enter/Stay/Exit)
     ├─ 5. Variable-step loop:
     │     ├─ Drain pending Behaviour.start()
     │     ├─ Behaviour.update()              (sorted by executionOrder)
     │     └─ Behaviour.lateUpdate()          (sorted by executionOrder)
     ├─ 6. Flush deferred GameObject.destroy() / Component.destroy()
     └─ 7. Scene._syncToRenderer(host.graphics)
           [SceneNode tree, Camera, Directional/Point/Spot lights, ParticleSystems, RenderSettings]

   renderer.beginFrame(world, frameInput)

   onFrame(FrameContext) ──▶ Engine.encodeFrame(RenderEncoder, FrameInput)
     ├─ 1. Submit active AtmosphericParticleFields & FlowParticleFields
     ├─ 2. Prepare & submit world-space 2D passes (TilemapRenderer, SpriteRenderer batches by layer)
     ├─ 3. Submit transient 3D gizmos / collider wireframes (when DebugHud or Editor is active)
     └─ 4. Prepare & submit SpriteStage.overlay passes (CanvasUI & DebugHud)

   renderer.endFrame()
   ```

5. **Definition of done per item.**
   - `dart analyze` reports 0 issues in both `pixeldart/` and `engine/`.
   - `dart test` passes in `engine/` (every item adds its own VM test).
   - `dart run tools/test_package_boundaries.dart` passes in `pixeldart/`.

---

## E0: Unblock & package boundary

- [x] **E0-1. Restore `pixeldart/lib`.** Moved `pixeldart/shaders/lib` back to `pixeldart/lib` so `package:pixeldart/...` resolves across examples, tools, and downstream packages.
- [x] **E0-2. Verify renderer & boundary suite.** `dart analyze` (0 issues), `tools/test_package_boundaries.dart` (14/14), `tools/test_plib01_facades.dart`, and `tools/renderer/check_boundary.dart` pass.
- [x] **E0-3. Create `engine/` (`package:rocket`).** Configured `engine/pubspec.yaml` with `lib/rocket.dart` (pure Dart) and `lib/rocket_web.dart` (browser host).

---

## E1: Runtime core & Pixel Rocket vertical slice

- [x] **E1-1. Platform host contract (`EngineHost`).**
  - _Files:_ `engine/lib/src/engine/host.dart`, `engine/lib/src/engine/headless.dart`.
  - _APIs:_ `EngineHost`, `Input`, `Graphics`, `AssetLoader`, `AudioDevice`, `AudioClip`, `AudioChannel`, `KeyValueStore`; plus `HeadlessHost`, `ScriptedInput`, `HeadlessGraphics`, `SilentAudio`, `MemoryStore`.
- [x] **E1-2. Fixed/variable loop, `Time`, and `invoke`.**
  - _Files:_ `engine/lib/src/engine/time.dart`, `engine/lib/src/engine/engine.dart`.
  - _APIs:_ `Time` (`deltaTime` auto-switches to `fixedDeltaTime` inside `fixedUpdate`, `time`, `unscaledTime`, `unscaledDeltaTime`, `fixedTime`, `timeScale`, `fixedInterpolation`, `maximumDeltaTime = 0.1`, `maxFixedStepsPerFrame = 8`), `Engine.step(rawDeltaSeconds)`, `Engine.invoke(delay, action, {repeatEvery, owner})`, `Invocation.cancel()`.
- [x] **E1-3. `InputActions`.**
  - _Files:_ `engine/lib/src/engine/input_actions.dart`.
  - _APIs:_ `button(name, keys)`, `axis(name, {negative, positive})`, `isDown`, `wasPressed`, `wasReleased`, `getAxis`; pre-bound `Horizontal`, `Vertical`, `Submit`, `Cancel`.
- [x] **E1-4. `GameObject`, `Component`, `Behaviour`, `TransformComponent`, `Scene`.**
  - _Files:_ `engine/lib/src/engine/component.dart`, `game_object.dart`, `transform.dart`, `scene.dart`.
  - _APIs:_ Unity lifecycle (`awake → onEnable → start → fixedUpdate → update → lateUpdate → onDisable → onDestroy`), `executionOrder`, `setActive`, `activeSelf`, `activeInHierarchy`, `setParent(parent, {worldPositionStays})`, `getComponent<T>()`, `getComponents<T>()`, `getComponentInChildren<T>()`, `getComponentInParent<T>()`, `find('A/B/C')`, `findWithTag`, `findObjectsOfType<T>()`, `raycastVisuals`, deferred `destroy()`.
- [x] **E1-5. Core 3D components & trigger physics.**
  - _Files:_ `engine/lib/src/engine/components/{camera,light,renderers,particle_system,audio_source,physics}.dart`.
  - _APIs:_ `Camera`, `Light` (`directional`, `point`, `spot`), `MeshRenderer`, `ModelRenderer` (`centerOrigin`, `boundingRadius`), `ParticleSystem`, `AudioSource`, `SphereCollider`, `BoxCollider`, `PhysicsWorld` (`onTriggerEnter`/`Stay`/`Exit`, `overlapSphere`, `raycast`, 32-bit `layer` + `collidesWithMask`).
- [x] **E1-6. Browser host (`WebEngineHost`).**
  - _Files:_ `engine/lib/rocket_web.dart`, `engine/lib/src/web/web_host.dart`.
  - _APIs:_ `WebEngineHost.mount(canvas, ...)`, `WebEngineRunner`, `WebAudioDevice` (pooled `HTMLAudioElement` voices + autoplay-rejection guard), `localStorage` `KeyValueStore`.
- [x] **E1-7. Port `example_1` (Pixel Rocket).**
  - _Files:_ `engine/example/pixel_rocket/{chase_camera,pixel_rocket_scene,main}.dart`, `engine/test/{engine_test,pixel_rocket_test}.dart`.
  - _Verified:_ 11/11 VM tests green (`dart test`) and `dart compile js -O2 --no-source-maps` builds cleanly (502 KB).

---

## E2: Sub-second dev loop, encoder hook & in-game diagnostics

Goal: edit a `Behaviour` or tweak a number → see the result in `dart test` (<0.4 s) or a live browser tab (<1.0 s), with an in-engine pause/step/timescale scrubber and live state retention.

- [x] **E2-1. Add `Engine.encodeFrame` & `Graphics` texture/encoder plumbing.**
  - _Scope:_
    - Add `void encodeFrame(RenderEncoder encoder, [FrameInput? frame])` to `Engine` and `void _encode(RenderEncoder encoder, FrameInput? frame)` to `Scene`.
    - Extend `Graphics` in `lib/src/engine/host.dart` with:
      - `int get viewportWidth; int get viewportHeight;`
      - `TextureHandle createTexture({required int width, required int height, Uint8List? pixels, GpuTextureFilter minFilter, GpuTextureFilter magFilter, GpuTextureWrap wrap, bool hasMips, double anisotropy, String? debugLabel});`
      - `void releaseMesh(MeshHandle handle); void releaseMaterial(MaterialHandle handle); void releaseTexture(TextureHandle handle);`
    - In `WebEngineHost._bind`: hook both `app.onBeforeFrame = (_, dt) => engine.step(dt)` and `app.onFrame = (ctx) => engine.encodeFrame(ctx.encoder)`.
  - _Touches:_ `lib/src/engine/{host,headless,engine,scene}.dart`, `lib/src/web/web_host.dart`.
  - _Verify:_ `test/subsystems_test.dart` verifying resource release tracking on `HeadlessGraphics`.

- [x] **E2-2. `volition` / `rocket` CLI (`bin/volition.dart`, `bin/rocket.dart`).**
  - _Scope:_ Single `dart:io` CLI executable registered under `executables: {volition: volition, rocket: volition}` in `pubspec.yaml`:
    - `dart run gl_volition:volition test [filter]` — runs `dart test`.
    - `dart run gl_volition:volition serve <entry.dart> [--port 8080] [--root <dir>]`:
      1. Serves static files from the target directory (with fallback to `pixeldart/web/`).
      2. Injects a `<script>` snippet before `</body>` on `index.html` that opens `new EventSource('/__rocket_events')` and calls `location.reload()` on `reload` events or renders a compiler error banner on `compile_error`.
      3. Watches `lib/**/*.dart` and the target directory's `.dart`/`.html` files (debounced 80 ms), compiles with `dart compile js -O0 --no-source-maps`, and broadcasts `reload` or `compile_error` SSE events.
    - `dart run gl_volition:volition build <entry.dart> [--target js|wasm|windows] [--out outDir]` — production build (`-O4 --no-source-maps`).
  - _Touches:_ `bin/volition.dart`, `bin/rocket.dart`, `pubspec.yaml`.

- [x] **E2-3. Hot-reload state snapshot (`captureSessionSnapshot` / `restoreSessionSnapshot`).**
  - _Scope:_
    - `Engine.captureSessionSnapshot()` and `Engine.restoreSessionSnapshot(Map<String, Object?>)` serialize and restore `timeScale`, `fixedDeltaTime`, `MemoryStore` entries, and `SceneSerializer.toJson(scene)`.
    - `WebEngineHost` saves to `sessionStorage['__rocket_hot_state']` on `beforeunload` when `enableHotState: true` and restores on mount via `tryRestoreHotState()`.
  - _Touches:_ `lib/src/engine/engine.dart`, `lib/src/web/web_host.dart`.
  - _Verify:_ Unit test in `test/subsystems_test.dart` round-tripping `captureSessionSnapshot()` / `restoreSessionSnapshot(snap)` on `HeadlessHost`.

- [x] **E2-4. In-game debug & time-control overlay (`DebugController`).**
  - _Scope:_ Built-in `Behaviour` toggled by `Backquote` (`` ` ``):
    - Keyboard shortcuts while open: `Space` pause/resume (`timeScale = 0` / `1`), `.` (Period) single-step one `fixedDeltaTime` while paused, `[` / `]` halve/double `timeScale` (`0.125×` .. `4×`).
    - Exposes `DebugMetrics` snapshot: rolling p50/p95 frame time, fixed steps taken last frame, active `GameObject` / `Behaviour` / `Collider` / `ParticleSystem` / `Light` counts.
  - _Touches:_ `lib/src/engine/debug_controller.dart`.
  - _Verify:_ `test/subsystems_test.dart` (pause, single-step advances `fixedUpdate`, resume restores prior `timeScale`, `metrics()`).

---

## E3: Zero-codegen scenes, prefabs, pools & assets

Goal: author scenes and prefabs in code or JSON, pool high-churn objects in 3 lines, and preload assets by logical ID so `awake`/`start` never `await`.

- [x] **E3-1. `ComponentSpec<T>` & `Field<T, V>` reflection-free descriptor table.**
  - _Touches:_ `lib/src/engine/serialization/component_spec.dart`.
  - _Verify:_ `test/subsystems_test.dart` reading/writing fields on built-in (`Camera`, `Light`, `SphereCollider`, `BoxCollider`, `AudioSource`) and custom `Behaviour` components by name and JSON value.

- [x] **E3-2. `Prefab`, `Scene.instantiate`, and `ObjectPool<T>`.**
  - _Touches:_ `lib/src/engine/prefab.dart`, `lib/src/engine/scene.dart`.
  - _Verify:_ `test/subsystems_test.dart` verifying `warmUp`, `acquire`/`release` reuse without allocations, and `onSpawned`/`onDespawned` callbacks.

- [x] **E3-3. `SceneSerializer` (JSON round-trip + prefab overrides).**
  - _Touches:_ `lib/src/engine/serialization/scene_serializer.dart`.
  - _Verify:_ `test/subsystems_test.dart` round-tripping a multi-level hierarchy with lights, camera, colliders, custom `Behaviour`s, and prefab overrides.

- [x] **E3-4. `AssetCatalog` (manifest preloading + synchronous handle lookup + release).**
  - _Touches:_ `lib/src/engine/assets/asset_catalog.dart`.
  - _Verify:_ `test/subsystems_test.dart` verifying progress ticks, sync lookup, and `clear()` GPU resource disposal.

---

## E4: 2D, sprites, tilemaps & in-canvas UI

Goal: expose both of pixeldart's 2D styles — **lit 3D-ortho dungeon** and **pure 2D `Camera2D` + `TileLayer` + y-sorted `SpriteBatch`** — plus a DOM-free `UICanvas` so games work unchanged on native builds.

- [x] **E4-1. Orthographic 3D camera support (`Camera.ortho` + `screenToGroundPlane`).**
  - _Touches:_ `lib/src/engine/components/camera.dart`.
  - _Verify:_ `test/subsystems_test.dart` checking orthographic projection raycasts onto `y == groundHeight`.

- [x] **E4-2. 2D rendering pipeline (`Camera2DComponent`, `SpriteRenderer`, `SpriteAnimator`).**
  - _Touches:_ `lib/src/engine/components/sprites_2d.dart`, `lib/src/engine/scene.dart`.
  - _Verify:_ `test/subsystems_test.dart` checking animation frame stepping and `SpriteRenderer` updates.

- [x] **E4-3. `TilemapComponent` & `moveAndSlideCircle`.**
  - _Touches:_ `lib/src/engine/components/tilemap.dart`.
  - _Verify:_ `test/subsystems_test.dart` testing corner sliding and solid-tile blocking.

- [x] **E4-4. `UICanvas` (in-canvas HUD on `SpriteStage.overlay`).**
  - _Touches:_ `lib/src/engine/ui/canvas_ui.dart`.
  - _Verify:_ `test/subsystems_test.dart` testing anchor layout and `UIButton` click dispatch via `ScriptedInput`.

- [x] **E4-5. 2D Dungeon validation scene (`example/dungeon_2d/game.dart`).**
  - _Touches:_ `example/dungeon_2d/game.dart`, `test/subsystems_test.dart`.
  - _Verify:_ `test/subsystems_test.dart` stepping `buildDungeon2DScene()` headlessly with `InputActions` movement and `TilemapComponent.moveAndSlideCircle`.

---

## E5: Rich 3D gameplay systems

Goal: wrap pixeldart's keyframe animation, splines, procedural terrain, Gerstner water, buoyancy, solar cycle, and volumetric atmosphere as components.

- [x] **E5-1. `Animator` component.**
  - _Touches:_ `lib/src/engine/components/animator.dart`.
  - _Verify:_ `test/subsystems_test.dart` sampling `Vector3Track` and `RotationTrack` keyframes.

- [x] **E5-2. `SplinePath` & `SplineFollower` components.**
  - _Touches:_ `lib/src/engine/components/spline.dart`.
  - _Verify:_ `test/subsystems_test.dart` verifying constant arc-length speed and arrival callback.

- [x] **E5-3. `TerrainComponent`, `WaterSurfaceComponent`, and `BuoyantBody`.**
  - _Touches:_ `lib/src/engine/components/terrain_water.dart`.
  - _Verify:_ `test/subsystems_test.dart` verifying `BuoyantBody` heave/roll on `GerstnerWaveEvaluator` and `TerrainComponent.sampleHeight`.

- [x] **E5-4. `AtmosphereVolume` (`SolarCycleEngine` + volumetric fog + weather fields).**
  - _Touches:_ `lib/src/engine/components/atmosphere_volume.dart`.
  - _Verify:_ `test/subsystems_test.dart` stepping `timeOfDayHours` and asserting sun intensity, skybox, and fog transitions.

- [x] **E5-5. 3D Island validation scene (`example/island_3d/game.dart`).**
  - _Touches:_ `example/island_3d/game.dart`, `test/subsystems_test.dart`.
  - _Verify:_ `test/subsystems_test.dart` stepping `buildIsland3DScene()` headlessly.

---

## E6: Build targets (JS, Wasm, Windows bundle)

- [x] **E6-1. WebAssembly & JS targets (`volition build --target js|wasm`).**
  - _Touches:_ `bin/volition.dart`.
- [x] **E6-2. Windows desktop bundler (`volition build --target windows`).**
  - _Touches:_ `bin/volition.dart`.
- [x] **E6-3. Native AOT backend (`GlesDevice` + `NativeEngineHost` via `DefaultSceneRendererFactory`).**
  - _Touches:_ `lib/src/native/native_host.dart`, `lib/gl_volition_native.dart`, `lib/rocket_native.dart`, `bin/volition.dart`, `test/subsystems_test.dart`.
  - _Verify:_ `test/subsystems_test.dart` (`NativeEngineHost.boot` over `GlesDevice`, full `SceneRenderer` 2D/3D frame execution, resize, and zero leaked GPU objects on `dispose`).

---

## E7: In-engine live inspector & scene editor

- [x] **E7-1. Hierarchy & `ComponentSpec` Inspector panel (`InspectorOverlay`).**
  - _Touches:_ `lib/src/web/inspector_overlay.dart`, `lib/src/web/web_host.dart`.
  - _APIs:_ Toggle with `F12` or `Alt+I`, viewport picking with `Alt + LeftClick`, live hierarchy tree with active checkboxes & search filter, live `Transform` + `ComponentSpec` field editors, and JSON scene export.
- [x] **E7-2. Free-look editor camera & 3D transform gizmo drag math (`EditorSession`).**
  - _Touches:_ `lib/src/engine/editor_session.dart`, `lib/src/web/inspector_overlay.dart`.
  - _Verify:_ `test/subsystems_test.dart` (`setFreeLook` camera override and `computeAxisDragPosition` along +X axis).
- [x] **E7-3. Play / Stop snapshot & save-to-disk via `volition serve`.**
  - _Touches:_ `lib/src/engine/editor_session.dart`, `lib/src/web/inspector_overlay.dart`, `bin/volition.dart`.
  - _Verify:_ `test/subsystems_test.dart` (`enterPlayMode` / `stopPlayMode` discarding runtime mutations and restoring destroyed objects).

---

## E8: Modularity, Events & Coroutines, Post-Process Volumes & UI/Inspector Authoring

- [x] **E8-1. Typed `SceneEvents` pub/sub bus & generator `Coroutine` scheduler (`NextFrame`, `WaitForSeconds`, `WaitForRealtime`, `WaitUntil`).**
  - _Touches:_ `lib/src/engine/events_coroutines.dart`, `lib/src/engine/component.dart`, `lib/src/engine/scene.dart`.
  - _Verify:_ `test/subsystems_test.dart` (`SceneEvents` lifecycle-scoped listeners and `Behaviour.startCoroutine`).
- [x] **E8-2. Spatial & global `PostProcessVolume` component.**
  - _Touches:_ `lib/src/engine/components/post_process_volume.dart`, `lib/src/engine/serialization/component_spec.dart`.
  - _Verify:_ `test/subsystems_test.dart` (`PostProcessVolume` feathering exposure, bloom, and vignette by camera distance).
- [x] **E8-3. Modular `UICanvas` widgets (`UIToggle`, `UISlider`, `UIStack`) & live `InspectorOverlay` scene authoring (`+ Object`, `+ Add Component`, `Delete`, `Vec3`/`Color` editors).**
  - _Touches:_ `lib/src/engine/ui/canvas_ui.dart`, `lib/src/web/inspector_overlay.dart`.
  - _Verify:_ `test/subsystems_test.dart` (`UIStack` layout and `UIToggle` / `UISlider` pointer dispatch).
- [x] **E8-4. 100% `ComponentSpec` inspector coverage across engine & example `Behaviour`s.**
  - _Touches:_ `lib/src/engine/serialization/component_spec.dart`, `example/pixel_rocket/game.dart`, `example/dungeon_2d/game.dart`, `example/procession/game.dart`, `example/island_3d/game.dart`.
  - _Verify:_ `volition_ux_debug.py audit-modularity` & `verify-render`.

---

## E9: GPU Instancing, Tweening, RigidBody Collision & Finite State Machines

- [x] **E9-1. `InstancedMeshRenderer` component (`InstancedMeshNode` wrapper with per-instance raycast picking).**
  - _Touches:_ `lib/src/engine/components/renderers.dart`.
  - _Verify:_ `test/subsystems_test.dart` (`InstancedMeshRenderer` batch submission and `RaycastHit.instanceIndex`).
- [x] **E9-2. Tweening & Easing Engine (`BehaviourTweenExt`: `tween`, `tweenVec3`, `tweenPosition`, `tweenScale`).**
  - _Touches:_ `lib/src/engine/tween.dart`, `lib/src/engine.dart`.
  - _Verify:_ `test/subsystems_test.dart` (`tweenPosition` and `tweenScale` with `Curves.easeOutCubic`).
- [x] **E9-3. `RigidBody` physics & solid sphere/AABB collision resolution (`onCollisionEnter`).**
  - _Touches:_ `lib/src/engine/components/physics.dart`, `lib/src/engine/component.dart`, `lib/src/engine/serialization/component_spec.dart`.
  - _Verify:_ `test/subsystems_test.dart` (`RigidBody` gravity, solid floor bounce, and `Collision` manifold).
- [x] **E9-4. Generic `StateMachine<S>` component.**
  - _Touches:_ `lib/src/engine/state_machine.dart`, `lib/src/engine.dart`.
  - _Verify:_ `test/subsystems_test.dart` (`StateMachine` lifecycle callbacks and `stateTime` tracking).

---

## E10: Spatial 3D Audio, 3D Character Controller & Line/Trail Renderers

- [x] **E10-1. Spatial 3D Audio (`AudioListener`, `AudioMixer`, `AudioBus`, `AudioSource`).**
  - _Touches:_ `lib/src/engine/components/audio_source.dart`, `lib/src/engine/scene.dart`.
  - _Verify:_ `test/subsystems_test.dart` (3D attenuation, stereo panning, and mixer bus volume/mute control).
- [x] **E10-2. Kinematic `CharacterController` 3D.**
  - _Touches:_ `lib/src/engine/components/character_controller.dart`.
  - _Verify:_ `test/subsystems_test.dart` (capsule hemisphere depenetration, wall sliding, gravity, and ground clamping).
- [x] **E10-3. `LineRenderer` & `TrailRenderer`.**
  - _Touches:_ `lib/src/engine/components/trail_renderer.dart`.
  - _Verify:_ `test/subsystems_test.dart` (ribbon MeshData dynamic vertex generation and length fading).

---

## E11: 2D Navigation, LOD/Billboards, UI Anchoring & Scene Management

- [x] **E11-1. `NavGrid2D` & `NavAgent`.**
  - _Touches:_ `lib/src/engine/navigation.dart`.
  - _Verify:_ `test/subsystems_test.dart` (A* pathfinding with corner prevention, tilemap extraction, and waypoint steering).
- [x] **E11-2. `LodGroup` & `Billboard`.**
  - _Touches:_ `lib/src/engine/components/lod_billboard.dart`.
  - _Verify:_ `test/subsystems_test.dart` (camera-distance child switching and spherical/cylindrical camera facing).
- [x] **E11-3. `Camera.worldToScreenPoint` & `UIWorldAnchor`.**
  - _Touches:_ `lib/src/engine/components/camera.dart`, `lib/src/engine/ui/canvas_ui.dart`.
  - _Verify:_ `test/subsystems_test.dart` (3D world position projection onto CanvasUI HUDs with behind-camera culling).
- [x] **E11-4. `SceneManager` (`engine.scenes`).**
  - _Touches:_ `lib/src/engine/scene_manager.dart`, `lib/src/engine/engine.dart`.
  - _Verify:_ `test/subsystems_test.dart` (named scene registration, loading, and `dontDestroyOnLoad` object migration).

---

## E12: Cinematic Cameras, Spatial Physics Queries, Save System & Editor Cloning

- [x] **E12-1. `SmoothFollowCamera`, `CinematicTourCamera`, and `CameraShakeEngine`.**
  - _Touches:_ `lib/src/engine/components/cinematic_camera.dart`, `lib/src/engine/components/camera.dart`.
  - _Verify:_ `test/subsystems_test.dart` (target follow smoothing, tour waypoint completion, and camera shake).
- [x] **E12-2. Spatial Physics Queries (`PhysicsWorld.overlapBox`, `raycastAll`, `sphereCast`).**
  - _Touches:_ `lib/src/engine/components/physics.dart`.
  - _Verify:_ `test/subsystems_test.dart` (overlapBox, sorted raycastAll, and sphereCast sweeps).
- [x] **E12-3. `SaveSystem` (`engine.saves`).**
  - _Touches:_ `lib/src/engine/save_system.dart`, `lib/src/engine/engine.dart`.
  - _Verify:_ `test/subsystems_test.dart` (named slot key-value persistence, full scene checkpointing, and slot listing).
- [x] **E12-4. `EditorSession.duplicate` & Scene JSON import/export.**
  - _Touches:_ `lib/src/engine/editor_session.dart`, `lib/src/web/inspector_overlay.dart`.
  - _Verify:_ `test/subsystems_test.dart` (subtree cloning, selected object duplicate, and JSON import/export).

---

## E13: Capsule Colliders, Volumetric/Thermal Lighting, Undo/Redo & Text Input

- [x] **E13-1. `CapsuleCollider` 3D.**
  - _Touches:_ `lib/src/engine/components/physics.dart`.
  - _Verify:_ `test/subsystems_test.dart` (capsule overlap, raycast, and SceneSerializer round-trip).
- [x] **E13-2. `VolumetricLightSource` & `ThermalSourceComponent`.**
  - _Touches:_ `lib/src/engine/components/atmosphere_volume.dart`, `lib/src/engine/scene.dart`.
  - _Verify:_ `test/subsystems_test.dart` (FrameEnvironment sync and `scene.sampleThermalDissolution`).
- [x] **E13-3. Bounded Undo/Redo stack in `EditorSession`.**
  - _Touches:_ `lib/src/engine/editor_session.dart`, `lib/src/web/inspector_overlay.dart`.
  - _Verify:_ `test/subsystems_test.dart` (undo/redo restoring scene hierarchy, selection, and component properties).
- [x] **E13-4. `UITextField` Canvas UI widget.**
  - _Touches:_ `lib/src/engine/ui/canvas_ui.dart`.
  - _Verify:_ `test/subsystems_test.dart` (focus on click, character typing, backspace, and submit on Enter).

---

## E14: Model Prefabs & Capsule Contact Manifolds

- [x] **E14-1. Model Prefabs (`Prefab.fromModelAsset`, `Prefab.fromGlbResult`, `Prefab.fromGlbBytes`).**
  - _Touches:_ `lib/src/engine/prefab.dart`.
  - _Verify:_ `test/subsystems_test.dart` (GLB hierarchy instantiation with MeshRenderers and shared GPU buffers).
- [x] **E14-2. Accurate Capsule Contact Manifolds.**
  - _Touches:_ `lib/src/engine/components/physics.dart`.
  - _Verify:_ `test/subsystems_test.dart` (capsule settling on solid box floor and axis-accurate normal restitution).

---

## E15: Immediate-Mode Gizmos, Auto-Gizmos & Catalog Shortcuts

- [x] **E15-1. `Gizmos` immediate-mode wireframe and debug visualizer.**
  - _Touches:_ `lib/src/engine/gizmos.dart`, `lib/src/engine/scene.dart`, `lib/src/web/inspector_overlay.dart`.
  - _Verify:_ `test/subsystems_test.dart` (wireBox, wireSphere, wireCapsule, contact normals, selection axes, and projection).
- [x] **E15-2. `AssetCatalog.prefab` & `catalog.spawn` shortcuts.**
  - _Touches:_ `lib/src/engine/assets/asset_catalog.dart`.
  - _Verify:_ `test/subsystems_test.dart` (lazy prefab caching and single-line GameObject spawning).

---

## E16: 3D PhysicsRaycaster Pointer Events, LayerMask & Gizmo Extensions

- [x] **E16-1. `PhysicsRaycaster` & 3D Pointer Events (`Behaviour.onPointerEnter/Down/Up/Click/Exit`).**
  - _Touches:_ `lib/src/engine/components/physics_raycaster.dart`, `lib/src/engine/component.dart`.
  - _Verify:_ `test/subsystems_test.dart` (pointer events dispatched to 3D colliders from mouse/touch input).
- [x] **E16-2. Type-safe `LayerMask` utility.**
  - _Touches:_ `lib/src/engine/game_object.dart`.
  - _Verify:_ `test/subsystems_test.dart` (bitmask composition, layer filtering in physics queries).
- [x] **E16-3. `Gizmos.arrow` and `Gizmos.wireDisc`.**
  - _Touches:_ `lib/src/engine/gizmos.dart`.
  - _Verify:_ `test/subsystems_test.dart` (vector and orientation wireframe projection).

---

## E17: Layer Collision Matrix, Radial Explosion Impulses & Spatial Camera Shake

- [x] **E17-1. Physics Layer Collision Matrix (`PhysicsWorld.setLayerCollision` / `getLayerCollision`).**
  - _Touches:_ `lib/src/engine/components/physics.dart`.
  - _Verify:_ `test/subsystems_test.dart` (selective layer collision disabling in fixed physics step).
- [x] **E17-2. Radial Explosion Impulse (`RigidBody.addExplosionForce` & `PhysicsWorld.addExplosionForce`).**
  - _Touches:_ `lib/src/engine/components/physics.dart`.
  - _Verify:_ `test/subsystems_test.dart` (distance-attenuated radial impulse and upwards modifier loft).
- [x] **E17-3. Spatial Camera Shake & `Scene.explode`.**
  - _Touches:_ `lib/src/engine/components/camera.dart`, `lib/src/engine/scene.dart`, `lib/src/engine/input_actions.dart`.
  - _Verify:_ `test/subsystems_test.dart` (distance-attenuated camera shake and unified `scene.explode(...)`).

---

## E18: Particle System Presets, Spatial Audio One-Shots & Transform Ergonomics

- [x] **E18-1. `ParticleSystem` Preset Factories (`campfire`, `explosion`, `smokePlume`, `bouncingSparks`, `fireflies`, `confetti`).**
  - _Touches:_ `lib/src/engine/components/particle_system.dart`.
  - _Verify:_ `test/subsystems_test.dart` (preset instantiation, emitter burst, active particle count tracking, and reset).
- [x] **E18-2. Spatial Audio One-Shots (`AudioSource.playClipAtPoint` & `Scene.playClipAt`).**
  - _Touches:_ `lib/src/engine/components/audio_source.dart`, `lib/src/engine/scene.dart`.
  - _Verify:_ `test/subsystems_test.dart` (transient spatial 3D audio GameObject creation, playback, and automatic destruction).
- [x] **E18-3. `TransformComponent` Directional Vectors & Euler Helpers.**
  - _Touches:_ `lib/src/engine/transform.dart`.
  - _Verify:_ `test/subsystems_test.dart` (`back`, `left`, `down`, `rotateX`, `rotateY`, `rotateZ`, and `resetLocal`).

---

## E19: 2D Spatial & Raycast Queries, UIImage, and Camera2D Follow/Clamp

- [x] **E19-1. `TilemapComponent` 2D Grid & Raycast Queries (`cellToWorld`, `raycast`, `hasLineOfSight`).**
  - _Touches:_ `lib/src/engine/components/tilemap.dart`.
  - _Verify:_ `test/subsystems_test.dart` (cell to world transform, obstacle line-of-sight raycasting).
- [x] **E19-2. `UIImage` UIElement in Canvas UI.**
  - _Touches:_ `lib/src/engine/ui/canvas_ui.dart`.
  - _Verify:_ `test/subsystems_test.dart` (textured sprite batch rendering in `UICanvas`).
- [x] **E19-3. `Camera2DComponent.smoothFollow` and `clampToBounds`.**
  - _Touches:_ `lib/src/engine/components/sprites_2d.dart`.
  - _Verify:_ `test/subsystems_test.dart` (exponential decay smooth follow and viewport bounding clamps).

---

## E20: Camera Viewport Projections & Culling, MeshRenderer Material Overrides, and NavGrid2D Line-of-Sight

- [x] **E20-1. Camera Viewport Projections & Culling Mask (`worldToViewportPoint`, `viewportToWorldPoint`, `cullingMask`).**
  - _Touches:_ `lib/src/engine/components/camera.dart`, `lib/src/engine/serialization/component_spec.dart`.
  - _Verify:_ `test/subsystems_test.dart` (viewport normalized coordinate projections and `SceneSerializer` culling mask round-trip).
- [x] **E20-2. `MeshRenderer` Tint Color & Material Override (`tintColor`, `materialOverride`, `setTint`).**
  - _Touches:_ `lib/src/engine/components/renderers.dart`.
  - _Verify:_ `test/subsystems_test.dart` (runtime tint and material override swapping).
- [x] **E20-3. `NavGrid2D` Straight-Line Line-of-Sight & Raycasting (`hasLineOfSight`, `raycast`).**
  - _Touches:_ `lib/src/engine/navigation.dart`.
  - _Verify:_ `test/subsystems_test.dart` (obstacle line-of-sight raycasts across navigation grids).

---

## E21: SpriteSheet Grid Slicing, UIDropdown, and Time.smoothDamp

- [x] **E21-1. `SpriteSheet` Grid Slicing & `SpriteRenderer.fromRegion`.**
  - _Touches:_ `lib/src/engine/assets/asset_catalog.dart`, `lib/src/engine/components/sprites_2d.dart`.
  - _Verify:_ `test/subsystems_test.dart` (grid UV cell slicing, sublist slice animation frames, and SpriteRenderer factory).
- [x] **E21-2. `UIDropdown` Multi-Option Menu Widget in Canvas UI.**
  - _Touches:_ `lib/src/engine/ui/canvas_ui.dart`.
  - _Verify:_ `test/subsystems_test.dart` (pointer toggle, popup item selection, and callback dispatch).
- [x] **E21-3. `Time.smoothDamp` and `smoothDampVec3` Critical Damping.**
  - _Touches:_ `lib/src/engine/time.dart`.
  - _Verify:_ `test/subsystems_test.dart` (smooth damping convergence without oscillation for double and Vec3).

---

## E22: SplineMeshRenderer, Stylized PostProcess Presets, and Multi-Camera Split-Screen Viewports

- [x] **E22-1. `SplineMeshRenderer` Dynamic Ribbon Mesh Generation.**
  - _Touches:_ `lib/src/engine/components/spline.dart`.
  - _Verify:_ `test/subsystems_test.dart` (spline point sampling and automated `LineRenderer` sync/rebuild).
- [x] **E22-2. Stylized `PostProcessVolume` Presets (`retro`, `cinematic`).**
  - _Touches:_ `lib/src/engine/components/post_process_volume.dart`.
  - _Verify:_ `test/subsystems_test.dart` (retro CRT/VHS dither, chromatic aberration, and cinematic contrast/bloom blending).
- [x] **E22-3. Multi-Camera Normalized Viewports & Depth Ordering (`normalizedViewportRect`, `depth`).**
  - _Touches:_ `lib/src/engine/components/camera.dart`, `lib/src/engine/serialization/component_spec.dart`.
  - _Verify:_ `test/subsystems_test.dart` (multi-viewport split-screen and depth serialization round-trip).

---

## E23: Scene.createPrimitive, UIButton Enabled State, and InputActions.getVector2

- [x] **E23-1. `Scene.createPrimitive` Factory Helper (`PrimitiveType.cube`, `sphere`, `capsule`, `cylinder`, `plane`, `quad`).**
  - _Touches:_ `lib/src/engine/scene.dart`, `lib/src/engine/components/renderers.dart`.
  - _Verify:_ `test/subsystems_test.dart` (instant instantiation of 3D primitive GameObjects with matching MeshRenderer and Colliders).
- [x] **E23-2. `UIButton` Enabled/Disabled Interactivity State.**
  - _Touches:_ `lib/src/engine/ui/canvas_ui.dart`.
  - _Verify:_ `test/subsystems_test.dart` (suppression of hover/pressed events and visual styling when disabled).
- [x] **E23-3. `InputActions.getVector2` Clamped & Normalized Directional Composition.**
  - _Touches:_ `lib/src/engine/input_actions.dart`.
  - _Verify:_ `test/subsystems_test.dart` (diagonal speed clamp / normalization of 2D directional axes).
