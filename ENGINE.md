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

---

## E24: Mathfx Utilities, ParallaxBackground2D Multi-Layer Scrolling, and SceneManager.fadeTo

- [x] **E24-1. `Mathfx` Engine Math Library.**
  - _Touches:_ `lib/src/engine/mathfx.dart`.
  - _APIs:_ `Mathfx.inverseLerp`, `Mathfx.pingPong`, `Mathfx.repeat`, `Mathfx.deltaAngle`, `Mathfx.deltaAngleDeg`, `Mathfx.moveTowards`, `Mathfx.moveTowardsVec3`, `Mathfx.damp`, `Mathfx.dampVec3`, `Mathfx.approximately`.
  - _Verify:_ `test/subsystems_test.dart` (interpolants, ping-pong bounces, shortest angular differences, step-towards without overshoot, exponential damping).
- [x] **E24-2. `ParallaxBackground2D` & `ParallaxLayer` Multi-Layered Scrolling.**
  - _Touches:_ `lib/src/engine/components/parallax_2d.dart`, `lib/src/engine/components/sprites_2d.dart`.
  - _APIs:_ `ParallaxLayer(factor, autoScroll, width, height, offset, region, repeatX, repeatY)`, `ParallaxBackground2D(layers, target)`.
  - _Verify:_ `test/subsystems_test.dart` (camera tracking, delta translation with relative factors, wrapping offsets, and ambient auto-scrolling).
- [x] **E24-3. `SceneManager.fadeTo` & `SceneTransition`.**
  - _Touches:_ `lib/src/engine/scene_manager.dart`, `lib/src/engine/engine.dart`.
  - _APIs:_ `SceneManager.fadeTo(target, duration, fadeColor)`, `SceneManager.isTransitioning`, `SceneManager.transitionAlpha`, `SceneTransition`.
  - _Verify:_ `test/subsystems_test.dart` (alpha opacity ramp up/down curve, seamless midpoint scene swapping, and transition completion).

---

## E25: AudioSource Fades & Cross-Fades, Constraints, and Scene.clone

- [x] **E25-1. `AudioSource` Volume Fade & Cross-Fade.**
  - _Touches:_ `lib/src/engine/components/audio_source.dart`, `lib/src/engine/scene.dart`.
  - _APIs:_ `AudioSource.fadeVolumeTo(targetVolume, {duration, onComplete})`, `AudioSource.crossFadeTo(nextClip, {duration, targetVolume, loop, onComplete})`, `AudioSource.isFading`.
  - _Verify:_ `test/subsystems_test.dart` (linear volume attenuation curves, callback dispatch, and midpoint clip swapping).
- [x] **E25-2. `LookAtConstraint` & `FollowConstraint` Components.**
  - _Touches:_ `lib/src/engine/components/constraints.dart`, `lib/src/engine/mathfx.dart`, `lib/src/engine/serialization/component_spec.dart`.
  - _APIs:_ `LookAtConstraint(target, upAxis, weight)`, `FollowConstraint(target, offset, smoothing, lockX, lockY, lockZ)`, `Mathfx.slerp`.
  - _Verify:_ `test/subsystems_test.dart` (spherical orientation tracking with slerp blending, spatial position follow, and individual axis constraints).
- [x] **E25-3. `Scene.clone` & `GameObject.clone` Runtime Duplication.**
  - _Touches:_ `lib/src/engine/scene.dart`, `lib/src/engine/game_object.dart`, `lib/src/engine/components/renderers.dart`, `lib/src/engine/serialization/component_spec.dart`.
  - _APIs:_ `Scene.clone(original, {parent, position, rotation, scale, name, active})`, `GameObject.clone(...)`, `MeshRenderer.spec`.
  - _Verify:_ `test/subsystems_test.dart` (deep entity duplication, independent component state, and nested child hierarchy cloning).

---

## E26: LinearColor Extensions, SpatialGrid2D, and UICanvas Focus Navigation

- [x] **E26-1. `UICanvas` Focus Navigation & Keyboard/Gamepad Tab Traversal.**
  - _Touches:_ `lib/src/engine/ui/canvas_ui.dart`.
  - _APIs:_ `UICanvas.focus(el)`, `UICanvas.focusNext()`, `UICanvas.focusPrevious()`, `UICanvas.submitFocused()`, `UIElement.isFocusable`, `UIElement.isFocused`, `UIElement.onSubmit()`.
  - _Verify:_ `test/subsystems_test.dart` (sequential tab focus traversal across focusable widgets, wrap-around navigation, and enter/submit triggering).
- [x] **E26-2. `LinearColor` Utility Extensions & HSV/Hex Parsing.**
  - _Touches:_ `lib/src/engine/color_ext.dart`.
  - _APIs:_ `LinearColorExt.lerp`, `withIntensity`, `toRgba`, `toArgb`, `toHex`, `toHsv`, `linearColorFromHex`, `linearColorFromHsv`.
  - _Verify:_ `test/subsystems_test.dart` (linear color interpolations, HSV conversions, 32-bit packing, and hex round-trips).
- [x] **E26-3. `SpatialGrid2D` Fast Broad-Phase Partitioning.**
  - _Touches:_ `lib/src/engine/spatial_grid_2d.dart`.
  - _APIs:_ `SpatialGrid2D<T>(cellSize)`, `insert(item, pos, radius)`, `insertAabb`, `remove(item)`, `querySphere(center, radius)`, `queryAabb`, `clear()`.
  - _Verify:_ `test/subsystems_test.dart` (spatial entity indexing, fast radius queries, entity removals, and clear).

---

## E27: Native Submodules Trilogy (voxlog, voxui, voxecs) & Immediate-Mode Diagnostics

- [x] **E27-1. `voxlog` Submodule: spdlog-Style Multi-Sink Logging.**
  - _Location:_ `./vendor/voxlog` (`https://github.com/soulwax/voxlog`).
  - _APIs:_ `Logger`, `LogLevel`, `LogRecord`, `ConsoleSink`, `FileSink`, `RingBufferSink`, `CallbackSink`, `PatternFormatter`, `voxlog.stdoutColor(...)`.
  - _Verify:_ `vendor/voxlog/test/voxlog_test.dart` & `test/subsystems_test.dart`.
- [x] **E27-2. `voxui` Submodule: Dear ImGui-Style Immediate Mode GUI.**
  - _Location:_ `./vendor/voxui` (`https://github.com/soulwax/voxui`).
  - _APIs:_ `VoxUiContext`, `VoxInput`, `DrawList`, `VoxRect`, `VoxColor`, `beginWindow`, `endWindow`, `button`, `checkbox`, `sliderDouble`, `sliderInt`, `collapsingHeader`, `progressBar`, `text`, `labelValue`.
  - _Verify:_ `vendor/voxui/test/voxui_test.dart` & `test/subsystems_test.dart`.
- [x] **E27-3. `voxecs` Submodule: EnTT-Style Sparse-Set Entity Component System.**
  - _Location:_ `./vendor/voxecs` (`https://github.com/soulwax/voxecs`).
  - _APIs:_ `Entity` (generational recycling), `SparseSet<T>` (contiguous dense arrays, $O(1)$ swap-and-pop), `Registry` (`create`, `destroy`, `assign`, `remove`, `has`, `get`, `tryGet`), `view<T>`, `view2<T1, T2>` ($O(\min(N_1, N_2))$ optimal joins), `view3<T1, T2, T3>`.
  - _Verify:_ `vendor/voxecs/test/voxecs_test.dart` & `test/subsystems_test.dart`.

---

## E28: Procedural Audio, AI Components, and Immediate-Mode Diagnostics Console

- [x] **E28-1. `voxsynth` Submodule & Procedural Audio One-Shots.**
  - _Location:_ `./vendor/voxsynth` (`https://github.com/soulwax/voxsynth`).
  - _APIs:_ `SynthParams`, `Waveform`, `AudioGenerator`, `PcmAudio`, `ProceduralAudioClip`, `AudioSource.playSynth(params)`, `Scene.playSynthAt(params, position)`.
  - _Verify:_ `vendor/voxsynth/test/voxsynth_test.dart` & `test/subsystems_test.dart` (chiptune synthesis, preset factories, PCM export, and audio source playback).
- [x] **E28-2. `voxai` Submodule & Engine AI Components (`BehaviorTreeComponent`, `AiFsmComponent`).**
  - _Location:_ `./vendor/voxai` (`https://github.com/soulwax/voxai`).
  - _APIs:_ `BehaviorTree`, `BtNode`, `BtSequence`, `BtSelector`, `BtAction`, `AiStateMachine`, `State`, `BehaviorTreeComponent`, `AiFsmComponent`.
  - _Verify:_ `vendor/voxai/test/voxai_test.dart` & `test/subsystems_test.dart` (AI state cycles, behavior tree ticks within engine game loop, and deferred start transitions).
- [x] **E28-3. `voxui` & `voxlog` Immediate-Mode Debug Console & Performance Metrics.**
  - _Touches:_ `lib/src/engine/debug_controller.dart`.
  - _APIs:_ `DebugController.renderDebugUi(ctx)`, displaying live FPS, delta time, total frames, active GameObjects, camera transforms, time scale sliders, and rolling `voxlog` logs.
  - _Verify:_ `test/subsystems_test.dart` (immediate-mode diagnostics window generation and rolling log sink verification).

---

## E29: Fluent Tweening Framework (voxtween), 3D Spatial Geometry & Frustum Culling (voxgeom)

- [x] **E29-1. `voxtween` Submodule: Fluent Interpolation, Sequences & Easing Curves.**
  - _Location:_ `./vendor/voxtween` (`https://github.com/soulwax/voxtween`).
  - _APIs:_ `Tween<T>`, `Sequence`, `Ease`, `EaseFunc`, `TweenManager`, `Interpolators`, `TransformComponent.tweenPosition`, `tweenLocalPosition`, `tweenScale`, `tweenRotation`, `GameObject.tweenScale`.
  - _Verify:_ `vendor/voxtween/test/voxtween_test.dart` & `test/subsystems_test.dart` (30+ easing equations, ping-pong, delay, target-based cancellation, and per-frame engine advancement).
- [x] **E29-2. `voxgeom` Submodule: 3D Geometric Testing, Raycasting & Dynamic AABB Tree.**
  - _Location:_ `./vendor/voxgeom` (`https://github.com/soulwax/voxgeom`).
  - _APIs:_ `GeomVec3`, `Plane3`, `Aabb3`, `Sphere3`, `Ray3` (Kay-Kajiya slab test, Möller-Trumbore ray-triangle, ray-sphere), `Frustum3` (Gribb-Hartmann extraction from 4x4 view-projection matrix), `FrustumIntersection`, `AabbTree<T>` (dynamic BVH with Surface Area Heuristic).
  - _Verify:_ `vendor/voxgeom/test/voxgeom_test.dart` & `test/subsystems_test.dart` (primitives arithmetic, ray-geometry hits, frustum plane containment, and dynamic tree queries).
- [x] **E29-3. Engine Integration: Camera Frustum Culling, Screen-to-World Raycasting & Scene Mesh Raycasts.**
  - _Touches:_ `lib/src/engine/components/camera.dart`, `lib/src/engine/components/renderers.dart`, `lib/src/engine/scene.dart`, `lib/src/engine/engine.dart`.
  - _APIs:_ `Camera.calculateFrustum([aspect])`, `Camera.screenPointToRay3(x, y)`, `Camera.isMeshVisible(renderer)`, `MeshRenderer.worldAabb`, `Scene.raycastMeshes(ray)`, `SceneMeshRayHit`.
  - _Verify:_ `test/subsystems_test.dart` (frustum camera culling, closest mesh renderer raycast hits, and automatic tween lifecycle cleanup on object destruction).

---

## E30: High-Performance Pathfinding Submodule (voxpath), Crowd Flow Fields, and Autonomous NavAgent2D

- [x] **E30-1. `voxpath` Submodule: Jump Point Search (JPS), Weighted A*, Flow Fields & Path Smoothing.**
  - _Location:_ `./vendor/voxpath` (`https://github.com/soulwax/voxpath`).
  - _APIs:_ `GridPoint`, `NavGrid`, `AStarFinder`, `JumpPointSearch`, `FlowField`, `PathSmoother`, `Heuristics` (`manhattan`, `euclidean`, `octile`, `chebyshev`).
  - _Verify:_ `vendor/voxpath/test/voxpath_test.dart` & `test/subsystems_test.dart` (Bresenham line-of-sight, obstacle avoidance, JPS open-field pruning, Dijkstra integration gradient vector field, and collinear waypoint reduction).
- [x] **E30-2. `NavAgent2D` Autonomous Agent Component.**
  - _Touches:_ `lib/src/engine/components/navigation_2d.dart`.
  - _APIs:_ `NavAgent2D(speed, stoppingDistance, acceleration, rotateTowardsTarget, grid)`, `setDestination(target, {navGrid, smooth, tileSize})`, `setWaypoints(points)`, `stop()`, `pause()`, `resume()`, `isMoving`, `hasPath`, `remainingWaypoints`, `currentWaypoint`, `onDestinationReached`, `onWaypointReached`.
  - _Verify:_ `test/subsystems_test.dart` (smooth steering along grid waypoints, obstacle navigation, and arrival callback triggers).
- [x] **E30-3. `FlowField2DComponent` Crowd Steering Field Component.**
  - _Touches:_ `lib/src/engine/components/navigation_2d.dart`.
  - _APIs:_ `FlowField2DComponent(grid, tileSize)`, `setTarget(tile)`, `setTargets(tiles)`, `getSteeringVector(worldPos)`.
  - _Verify:_ `test/subsystems_test.dart` (multi-agent normalized steering vectors in world coordinates around obstacles).

---

## E31: Procedural Generation Framework (voxproc), BSP Dungeons, Cellular Caves, Autotiling & Poisson Distribution

- [x] **E31-1. `voxproc` Submodule: Procedural Generation & Autotiling Toolkit.**
  - _Location:_ `./vendor/voxproc` (`https://github.com/soulwax/voxproc`).
  - _APIs:_ `ProcRect`, `BspDungeonGenerator`, `DungeonResult`, `CellularAutomata`, `PoissonDiskSampler2D`, `AutoTiler` (`cardinalMask`, `blob8Mask`, `autotileCardinal`).
  - _Verify:_ `vendor/voxproc/test/voxproc_test.dart` & `test/subsystems_test.dart` (BSP room and corridor carving, 4-5 cellular automata cave boundaries, Bridson blue-noise non-overlapping sampling, and adjacent tile bitmask lookups).
- [x] **E31-2. `ProceduralDungeonComponent` Engine Component.**
  - _Touches:_ `lib/src/engine/components/procedural_dungeon.dart`.
  - _APIs:_ `ProceduralDungeonComponent(width, height, minRoomSize, maxRoomSize, tileSize, seed)`, `generate({customSeed, targetTilemap})`, `dungeonResult`, `navGrid`, `rooms`, `roomCenters`, `playerSpawn`.
  - _Verify:_ `test/subsystems_test.dart` (procedural room generation, tilemap population, and matching `NavGrid` synchronization).
- [x] **E31-3. `PoissonScatterComponent` Blue-Noise Spatial Scatter Component.**
  - _Touches:_ `lib/src/engine/components/procedural_dungeon.dart`.
  - _APIs:_ `PoissonScatterComponent(areaWidth, areaHeight, minDistance, seed)`, `sampleWorldPositions({y, customSeed})`, `spawnPrefabs(prefab, {parent, y, customSeed})`.
  - _Verify:_ `test/subsystems_test.dart` (minimum distance clearance adherence and prefab hierarchy instantiation).

---

## E32: Rigid Body Dynamics, Sequential Impulse Solver & SAT Manifolds (voxphys)

- [x] **E32-1. `voxphys` Submodule: 2D Rigid Body Physics Engine.**
  - _Location:_ `./vendor/voxphys` (`https://github.com/soulwax/voxphys`).
  - _APIs:_ `PhysVec2`, `PhysMat2`, `PhysTransform`, `PhysAabb2`, `PhysShape`, `CircleShape` (`PhysCircle`), `PolygonShape` (`PhysPolygon`), `SegmentShape` (`PhysSegment`), `RigidBody` (`PhysBody`), `Fixture` (`PhysFixture`), `ContactManifold`, `CollisionDetector` (SAT edge-clipping convex polygon/box vs polygon, polygon vs circle, and circle vs circle), `ContactSolver` (sequential impulse velocity solver with warm-starting, Coulomb friction cone, restitution velocity bias, and Baumgarte position correction), `PhysJoint`, `DistanceJoint`, `RevoluteJoint` (pin/hinge with motor and angle limits), `PrismaticJoint` (slider with motor and translation limits), `SpringJoint`, `PhysWorld2D`, `PhysRaycastHit2D`.
  - _Verify:_ `vendor/voxphys/test/voxphys_test.dart` & `test/subsystems_test.dart` (15/15 unit tests: SAT manifolds, gravity fall, stacking rest, distance constraints, revolute pin anchors, prismatic rail slider, and raycasting).
- [x] **E32-2. `RigidBody2D` & `Collider2D` Engine Components.**
  - _Touches:_ `lib/src/engine/components/physics_2d.dart`.
  - _APIs:_ `RigidBody2D` (`bodyType`, `linearVelocity`, `angularVelocity`, `linearDamping`, `angularDamping`, `gravityScale`, `fixedRotation`, `bullet`, `applyForce`, `applyImpulse`, `applyTorque`, `getVelocityAtPoint`), `Collider2D`, `BoxCollider2D`, `CircleCollider2D`, `PolygonCollider2D`, `DistanceJoint2D`, `RevoluteJoint2D`, `PrismaticJoint2D`.
  - _Verify:_ `test/subsystems_test.dart` (gravity integration, resting on static ground, distance joint anchor maintenance, and pin hinge rotation).
- [x] **E32-3. `Physics2DWorld` Subsystem, Scene Raycasting & Collision Callbacks.**
  - _Touches:_ `lib/src/engine/components/physics_2d.dart`, `lib/src/engine/scene.dart`, `lib/src/engine/component.dart`.
  - _APIs:_ `scene.physics2D`, `scene.raycast2D(origin, direction, [maxDistance, mask])`, `RaycastHit2D`, `Collision2D`, `Behaviour.onCollisionEnter2D`, `onCollisionStay2D`, `onCollisionExit2D`, `onTriggerEnter2D`, `onTriggerStay2D`, `onTriggerExit2D`.
  - _Verify:_ `test/subsystems_test.dart` (automatic fixed-step synchronization with GameObject TransformComponent, continuous contact dispatch, trigger zones, and 2D scene raycasting).

---

## E33: Network Synchronization, Snapshot Interpolation & Rollback Prediction (voxnet)

- [x] **E33-1. `voxnet` Submodule: State Replication, Rollback & RPC Framework.**
  - _Location:_ `./vendor/voxnet` (`https://github.com/soulwax/voxnet`).
  - _APIs:_ `ByteWriter`, `ByteReader` (variable-length LEB128, float/int primitives), `FloatQuantizer`, `NetMessage`, `MessageRegistry`, `PingMsg`, `PongMsg`, `InputMsg`, `EntitySnapshotMsg`, `RpcMsg`, `NetTransport`, `LoopbackNetwork`, `LoopbackEndpoint` (latency, jitter, packet drop simulation), `SnapshotBuffer<T>`, `Snapshot<T>`, `PredictionHistory<TState, TInput>` (prediction frames, divergence detection, rollback, and intermediate tick re-simulation), `DeltaCompressor` (bitmask dirty field tracking), `RpcManager`.
  - _Verify:_ `vendor/voxnet/test/voxnet_test.dart` & `test/subsystems_test.dart` (11/11 unit tests: binary round-trip, loopback network delay delivery, snapshot sampling, rollback re-simulation, and RPC invocation).
- [x] **E33-2. `NetworkIdentity` & `NetworkTransform` Engine Components.**
  - _Touches:_ `lib/src/engine/network/network_system.dart`.
  - _APIs:_ `NetworkIdentity(netId, ownerPeerId)` (`isOwner`, `isServer`, `isClient`), `NetworkTransform(interpolationDelaySeconds, synchronizePosition, synchronizeRotation, enablePrediction)` (reconciles client-side prediction against authoritative server state, interpolates historical snapshot buffers for remote proxies).
  - _Verify:_ `test/subsystems_test.dart` (server authoritative entity position replication and remote client proxy smooth interpolation).
- [x] **E33-3. `NetworkManager` Subsystem & RPC Dispatch.**
  - _Touches:_ `lib/src/engine/network/network_system.dart`, `lib/src/engine/scene.dart`.
  - _APIs:_ `scene.network`, `NetworkManager.startServer()`, `startClient()`, `sendRpc()`, `rpc.register()`, `currentTick`, `currentNetworkTimeMs`.
  - _Verify:_ `test/subsystems_test.dart` (RPC packet broadcasting, payload deserialization, and multi-peer network manager execution).

---

## E34: Skeletal Animation Blend Trees & Inverse Kinematics (voxanim)

- [x] **E34-1. `voxanim` Submodule: Skeletal Animation, Blend Trees, FABRIK & Two-Bone IK.**
  - _Location:_ `./vendor/voxanim` (`https://github.com/soulwax/voxanim`).
  - _APIs:_ `AnimVec3`, `AnimQuat` (`lookRotation`, `fromToRotation`, `slerp`), `BoneTransform`, `Pose` (`lerp`, `blendAdditive`), `Skeleton` (forward kinematics hierarchy, global transforms), `BlendNode`, `ClipNode`, `Blend1DNode` (1D parameter interpolation), `Blend2DNode` (2D directional polar blending), `AdditiveBlendNode` (breathing, recoil, aim offsets), `TwoBoneIkSolver` (analytical law-of-cosines limb IK with pole target), `FabrikSolver` (Forwards and Backwards Reaching Inverse Kinematics multi-bone chains), `AimIkSolver` (cone-clamped look-at IK).
  - _Verify:_ `vendor/voxanim/test/voxanim_test.dart` & `test/subsystems_test.dart` (10/10 unit tests: pose blending, additive layering, FK propagation, FABRIK chain reaching, TwoBoneIk limb bending, and aim cone limits).
- [x] **E34-2. `TwoBoneIkComponent` & `AimIkComponent` Engine Components.**
  - _Touches:_ `lib/src/engine/components/ik_animation.dart`.
  - _APIs:_ `TwoBoneIkComponent(rootBone, midBone, endEffector, target, targetPosition, pole, polePosition, weight)`, `AimIkComponent(bone, target, targetPosition, localAimAxis, maxAngleRadians, weight)`.
  - _Verify:_ `test/subsystems_test.dart` (limb IK foot planting reaching targets within < 0.05 margin, pole knee direction, and aim look-at orientation alignment).
- [x] **E34-3. `BlendTreeComponent` Animation Graph Evaluator.**
  - _Touches:_ `lib/src/engine/components/ik_animation.dart`.
  - _APIs:_ `BlendTreeComponent(rootNode, initialParameters)`, `setFloat(name, value)`, `getFloat(name)`, `animationTime`.
  - _Verify:_ `test/subsystems_test.dart` (1D blend tree interpolation driving child bone GameObject local transforms during engine update loop).

---

## E35: 2D Dynamic Visibility, Shadows & Fog of War (voxlight)

- [x] **E35-1. `voxlight` Submodule: 2D Visibility Polygon, Shadow Casting & Fog of War.**
  - _Location:_ `./vendor/voxlight` (`https://github.com/soulwax/voxlight`).
  - _APIs:_ `LightVec2`, `Segment2D`, `VisibilityPolygon` (angular ray sweep, edge-intersection, sorted boundary polygon generation), `Light2D` (point light, spot/cone light, radius, attenuation falloff, illumination sampling), `ShadowCaster2D` (occlusion edge extraction, shadow volume extrusion), `FogOfWar` (grid exploration, visibility masking, sight radius revelation, smooth fade).
  - _Verify:_ `vendor/voxlight/test/voxlight_test.dart` & `test/subsystems_test.dart` (angular ray sweeps, occluded shadow cones, spot light directionality, and fog of war tile exploration).
- [x] **E35-2. `Light2DComponent` & `ShadowCaster2DComponent` Engine Components.**
  - _Touches:_ `lib/src/engine/components/lighting_2d.dart`.
  - _APIs:_ `Light2DComponent(type, color, intensity, radius, spotAngle, castsShadows)`, `ShadowCaster2DComponent(segments, shapeType, boxSize, radius)`.
  - _Verify:_ `test/subsystems_test.dart` (automatic collider occluder extraction, light boundary containment, and shadow casting).
- [x] **E35-3. `FogOfWar2DComponent` & Scene 2D Light Sampling.**
  - _Touches:_ `lib/src/engine/components/lighting_2d.dart`, `lib/src/engine/scene.dart`.
  - _APIs:_ `FogOfWar2DComponent(width, height, cellSize)`, `reveal(pos, radius)`, `isExplored(pos)`, `isVisible(pos)`, `scene.evaluateLight2D(pos)`.
  - _Verify:_ `test/subsystems_test.dart` (spatial 2D light evaluation with shadow obstruction, and player-centered fog of war revelation).

---

## E36: Audio DSP Effects, Spatial Audio 3D & Audio Mixer Graph (voxdsp)

- [x] **E36-1. `voxdsp` Submodule: Biquad Filters, Schroeder Reverb, Feedback Delay & Spatial 3D Audio.**
  - _Location:_ `./vendor/voxdsp` (`https://github.com/soulwax/voxdsp`).
  - _APIs:_ `BiquadFilter` (`lowpass`, `highpass`, `bandpass`, `notch`, `peakingEq`), `SchroederReverb` (comb/allpass filters, room size, dampening, wet/dry mix), `FeedbackDelay` (delay time, feedback gain, wet mix), `SpatialAudio3D` (inverse/linear/exponential distance attenuation, stereo equal-power panning, Doppler pitch factor), `AudioMixerGroup` (hierarchical bus routing, dB volume fader, mute/solo, DSP effect chain).
  - _Verify:_ `vendor/voxdsp/test/voxdsp_test.dart` & `test/subsystems_test.dart` (frequency response attenuation, algorithmic reverberation tail, stereo pan balance, and bus hierarchy volume propagation).
- [x] **E36-2. `AudioListener` & 3D Spatial Audio Integration in `AudioSource`.**
  - _Touches:_ `lib/src/engine/components/audio_source.dart`, `lib/src/engine/components/audio_dsp.dart`.
  - _APIs:_ `SpatialAudioDspExt.calculateSpatialDsp(listener, distanceModel, sourceVelocity, listenerVelocity)`, `SpatialAudioResult`.
  - _Verify:_ `test/subsystems_test.dart` (distance falloff curves, left/right stereo panning relative to listener head, and Doppler pitch shift).
- [x] **E36-3. `AudioReverbZone` & `AudioLowPassFilterComponent`.**
  - _Touches:_ `lib/src/engine/components/audio_dsp.dart`.
  - _APIs:_ `AudioReverbZone(minDistance, maxDistance, roomSize, damp, wet)`, `AudioLowPassFilterComponent(cutoffFrequency, q)`.
  - _Verify:_ `test/subsystems_test.dart` (distance-attenuated reverb wet mix and high-frequency buffer filtering).

---

## E37: Narrative Dialogue Graphs, Localization & Quest System (voxtalk)

- [x] **E37-1. `voxtalk` Submodule: Node-Based Dialogue Graphs, Branching Narratives & Quest State Tracking.**
  - _Location:_ `./vendor/voxtalk` (`https://github.com/soulwax/voxtalk`).
  - _APIs:_ `DialogueNode` (speaker, text, audioCue, choices, conditions, actions, nextNodeId), `DialogueChoice` (text, targetNodeId, condition), `DialogueGraph` (node lookup, entry point, validation), `DialogueRunner` (line advancement, typewriter pacing, choice selection, variable interpolation `{variable}`), `VariableStore` (blackboard flags, integers, strings), `LocalizationTable` (multi-language string dictionary, pluralization, formatting), `QuestTracker` (quest definitions, stages, objectives, completion callbacks).
  - _Verify:_ `vendor/voxtalk/test/voxtalk_test.dart` & `test/subsystems_test.dart` (branching choice pathing, conditional response filtering, variable string interpolation, and quest stage completions).
- [x] **E37-2. `DialogueComponent` & `DialogueUI` Integration.**
  - _Touches:_ `lib/src/engine/components/dialogue.dart`.
  - _APIs:_ `DialogueComponent(graph, autoStart, runner)`, `DialogueUI.render(ctx, runner)` (renders conversational speech bubble, choices, and skip/advance controls using `voxui`), `QuestManagerComponent`.
  - _Verify:_ `test/subsystems_test.dart` (gameplay conversation flow, choice dispatching, and immediate-mode dialogue rendering).

---

## E38: Particle Simulation, Force Fields & Visual Effects (voxvfx)

- [x] **E38-1. `voxvfx` Submodule: Particle Dynamics, Force Fields & Color/Size Gradients.**
  - _Location:_ `./vendor/voxvfx` (`https://github.com/soulwax/voxvfx`).
  - _APIs:_ `VfxParticle` (position, velocity, life, maxLife, size, color, rotation), `VfxEmitter` (burst, rate over time, shapes: sphere, cone, box, circle), `VfxColorGradient` (keyframe color/alpha lerp), `VfxCurve` (size/velocity multipliers over lifetime), `VfxForce` (`GravityForce`, `VortexForce`, `AttractorForce`, `TurbulenceForce`), `VfxSimulation`.
  - _Verify:_ `vendor/voxvfx/test/voxvfx_test.dart` & `test/subsystems_test.dart` (emitter lifetimes, force field acceleration, and color/size lifetime transitions).
- [x] **E38-2. `VisualEffectComponent` Engine Integration.**
  - _Touches:_ `lib/src/engine/components/vfx.dart`.
  - _APIs:_ `VisualEffectComponent(emitter, playOnAwake, looping)`, `play()`, `stop()`, `burst(count)`.
  - _Verify:_ `test/subsystems_test.dart` (scene lifecycle step, particle spawn, and world transform orientation sync).

---

## E39: Voxel Volume Chunks, Greedy Meshing, 3D DDA Raycasting & Destructible Terrain (voxvox)

- [x] **E39-1. `voxvox` Submodule: Voxel Volumes, Greedy Meshing & Fast 3D DDA Traversal.**
  - _Location:_ `./vendor/voxvox` (`https://github.com/soulwax/voxvox`).
  - _APIs:_ `VoxelChunk` (16x16x16 / 32x32x32 cubic voxel array, block palette, bit-packed storage), `VoxelWorld` (infinite/multi-chunk spatial hashing, coordinate translation), `GreedyMesher` (optimized quad merging reducing triangle count by 90%+, vertex ambient occlusion 0..3), `VoxelRaycaster` (fast 3D Amanatides-Woo DDA raymarching returning hit voxel, normal, adjacent empty block), `VoxelBrush` (box, sphere carve, cylinder carving and painting).
  - _Verify:_ `vendor/voxvox/test/voxvox_test.dart` & `test/subsystems_test.dart` (chunk coordinate lookups, greedy mesh optimization quad count reduction, 3D DDA ray intersection precision, and sphere carving).
- [x] **E39-2. `VoxelTerrainComponent` & `VoxelCollider` Engine Integration.**
  - _Touches:_ `lib/src/engine/components/voxel.dart`.
  - _APIs:_ `VoxelTerrainComponent` (chunk management, mesh generation, dynamic carving/building), `raycastVoxel(ray, maxDistance)`.
  - _Verify:_ `test/subsystems_test.dart` (scene integration, raycast hit verification, and terrain deformation).

---

## E40: Input Action Maps, Deadzones, Chord Combos, Rebinding & Virtual Gamepad (voxpad)

- [x] **E40-1. `voxpad` Submodule: Action Contexts, Deadzone Processors, Input Chords & Rebinding.**
  - _Location:_ `./vendor/voxpad` (`https://github.com/soulwax/voxpad`).
  - _APIs:_ `InputAction` (name, type: button/value1D/value2D, state: pressed, released, held duration, axis values, `consumeBufferedPress`), `ActionMap` (contextual bindings: "Gameplay", "Menu", "Vehicle", active enable/disable, priority control consumption), `InputBinding` (`KeyBinding`, `ChordBinding`, `Axis1DBinding`, `Vector2Binding`), `DeadzoneProcessor` (axial, radial, radialScaled thresholds with response curves), `InputRebinder` (interactive listen for next press, conflict policies, `InputProfileSerializer` JSON save/load).
  - _Verify:_ `vendor/voxpad/test/voxpad_test.dart` & `test/subsystems_test.dart` (action context priority, radial deadzone normalization, chord trigger logic, and profile serialization).
- [x] **E40-2. `InputManagerComponent` & Virtual Gamepad Overlay Integration.**
  - _Touches:_ `lib/src/engine/components/input_manager.dart`.
  - _APIs:_ `InputManagerComponent(actions, virtualGamepad)`, `VirtualGamepad` / `VirtualGamepadUI.render` (dual on-screen analog sticks, action buttons A/B, multi-touch pointer routing, storage profile save/load).
  - _Verify:_ `test/subsystems_test.dart` (engine input event ingestion, action map switching, interactive rebinding + storage profile, and virtual joystick vector calculations).

---

## E41: Spatial Grid Inventory, Weighted Loot Tables, Crafting & RPG Stat Modifiers (voxitem)

- [x] **E41-1. `voxitem` Submodule: 2D Grid Inventory, Stacking, Loot Tables, Crafting & Stat Pipeline.**
  - _Location:_ `./vendor/voxitem` (`https://github.com/soulwax/voxitem`).
  - _APIs:_ `ItemDefinition` (id, name, gridWidth, gridHeight, maxStack, tags, rarity), `ItemStack`, `GridInventory` (2D spatial occupancy matrix, rotation, auto-fit packing, splitting/merging, weight caps, JSON round-trip), `EquipmentSlots`, `StatBlock` (`StatModifier` flat / percentAdd / percentMult ordered evaluation pipeline), `LootTable` (weighted entries, conditions, luck scaling, guaranteed rolls, seeded RNG), `CraftingSystem` (atomic transaction crafting, ingredient consumption, tag-based substitutions).
  - _Verify:_ `vendor/voxitem/test/voxitem_test.dart` & `test/subsystems_test.dart` (2D grid placement & item rotation, stat multiplier ordering, weighted loot statistical distribution, and crafting validation).
- [x] **E41-2. `InventoryComponent` & `StatsComponent` Engine Integration.**
  - _Touches:_ `lib/src/engine/components/inventory.dart`.
  - _APIs:_ `InventoryComponent(gridWidth, gridHeight, slotNames)`, `StatsComponent(baseStats)`, `InventoryUI.render(ui, inventory)` (interactive spatial grid & rarity tint rendering via `voxui`).
  - _Verify:_ `test/subsystems_test.dart` (scene entity equipment stat buffs, equip/swap rollback safety, storage persistence, and `voxui` inventory grid rendering).

---

## E42: Deterministic State Snapshots, Time Rewind & Ghost Replays (voxsnap)

- [x] **E42-1. `voxsnap` Submodule: Ring-Buffer State Recording, Binary Delta Snapshots & Ghost Playback.**
  - _Location:_ `./vendor/voxsnap` (`https://github.com/soulwax/voxsnap`).
  - _APIs:_ `BinarySnapshotWriter` / `BinarySnapshotReader` (compact varint, quantized vec3 & smallest-three compressed quaternion, RLE byte diffing), `RewindBuffer<T>` (bounded O(1) ring buffer supporting scrubbing backwards/forwards across frames/seconds), `GhostTrack` / `GhostPlayer` (interpolated transform replay tracks, binary export/import).
  - _Verify:_ `vendor/voxsnap/test/voxsnap_test.dart` & `test/subsystems_test.dart` (bit-packed quantization error bounds, XOR/delta compression ratio, circular rewind buffer wrapping, and smooth interpolated ghost playback).
- [x] **E42-2. `TimeRewindComponent` & `GhostReplayComponent` Engine Integration.**
  - _Touches:_ `lib/src/engine/components/rewind.dart`.
  - _APIs:_ `TimeRewindComponent(maxSeconds, captureCustomState)`, `GhostRecorderComponent` / `GhostPlaybackComponent`.
  - _Verify:_ `test/subsystems_test.dart` (rewinding moving `GameObject` transforms through history and multi-frame ghost transform playback).

---

## E43: Visual Node Graphs, Reactive Dataflow & Logic Blueprints (voxflow)

- [x] **E43-1. `voxflow` Submodule: Typed Node Graphs, Dataflow Evaluation & Blueprint Exec Runtime.**
  - _Location:_ `./vendor/voxflow` (`https://github.com/soulwax/voxflow`).
  - _APIs:_ `PinType` (`exec`, `boolVal`, `intVal`, `floatVal`, `vec2Val`, `vec3Val`, `stringVal`, `colorVal`, `any`), `FlowNodeDef`, `FlowNodeRegistry`, `StandardNodes`, `FlowNodeInstance`, `FlowLink`, `FlowGraph` (topological sort, Kahn cycle detection, JSON round-trip), `DataflowEvaluator` (memoized pull execution), `FlowRunner` (`triggerEvent`, `step(dt)`, latent `Delay`, `Branch`, `Sequence`, `ForLoop`, `FlowBlackboard`).
  - _Verify:_ `vendor/voxflow/test/voxflow_test.dart` & `test/subsystems_test.dart` (cycle detection, implicit pin coercion, dirty pull evaluation, latent `Delay` coroutines, branching/looping blueprint execution, and JSON save/load).
- [x] **E43-2. `FlowGraphComponent` & Interactive ImGui Node Canvas (`FlowGraphUI`).**
  - _Touches:_ `lib/src/engine/components/flow_graph.dart`.
  - _APIs:_ `FlowGraphComponent(graph, autoRunOnUpdate)`, `triggerEvent(name, args)`, `setVariable(name, val)`, built-in scene/transform bindings, `FlowGraphUI.render(ui, graph, state)` rendering draggable node cards, colored sockets, Bezier wire links, and live pin values via `voxui`.
  - _Verify:_ `test/subsystems_test.dart` (blueprint graph mutating `GameObject` transforms over engine frames, custom trigger events, and `voxui` node canvas interactive dragging/wiring).

---

## E44: Hexagonal Grids, Wave-Function Collapse & Tactical Pathfinding (voxhex)

- [x] **E44-1. `voxhex` Submodule: Cube/Axial Hex Math, Hex FOV, Reachability & Wave-Function Collapse.**
  - _Location:_ `./vendor/voxhex` (`https://github.com/soulwax/voxhex`).
  - _APIs:_ `HexCoord` (cube/axial math, rounding, rings, spirals, line draw, pixel projection), `HexMap<T>`, `HexPathfinder` (`findPath`, `reachableTiles`), `HexFov` (shadowcast line-of-sight), `WfcSolver` (entropy-minimization constraint propagation with backtracking).
  - _Verify:_ `vendor/voxhex/test/voxhex_test.dart` & `test/subsystems_test.dart`.
- [x] **E44-2. `HexGridComponent`, `WfcTilemapGenerator` & `HexGridUI` Integration.**
  - _Touches:_ `lib/src/engine/components/hex_grid.dart`.
  - _APIs:_ `HexGridComponent`, `WfcTilemapGenerator`, `HexGridUI.render`.
  - _Verify:_ `test/subsystems_test.dart`.

---

## E45: Status Effects, Cooldowns, Initiative Turn Scheduler & Combat Resolver (`voxrule`)

- [x] **E45-1. `voxrule` Submodule: Buff/DoT Stacks, Cooldowns, Initiative Timeline & Damage Pipeline.**
  - _Location:_ `./vendor/voxrule` (`https://github.com/soulwax/voxrule`).
  - _APIs:_ `StatusEffectDef`, `StatusStackPolicy`, `StatusContainer` (tag dispel/immunity, periodic DoT/HoT ticks, stack decay), `CooldownTracker`, `TurnScheduler` (initiative & CT speed gauge), `DamagePacket` & `CombatResolver` (armor, resistances, crit rolls, shields).
  - _Verify:_ `vendor/voxrule/test/voxrule_test.dart` & `test/subsystems_test.dart`.
- [x] **E45-2. `StatusEffectComponent`, `TurnEncounterComponent` & `CombatHudUI` Integration.**
  - _Touches:_ `lib/src/engine/components/combat_rules.dart`.
  - _Verify:_ `test/subsystems_test.dart`.

---

## E46: Multi-Track Cutscene Timeline Sequencer & Keyframe Director (`voxseq`)

- [x] **E46-1. `voxseq` Submodule: Keyframe Property Tracks, Event Cues, Camera Cuts & Transport Scrubbing.**
  - _Location:_ `./vendor/voxseq` (`https://github.com/soulwax/voxseq`).
  - _APIs:_ `SeqKeyframe<T>` (`step`, `linear`, `smoothstep`, `cubic`), `ValueTrack<T>`, `EventTrack`, `AudioCueTrack`, `SubtitleTrack`, `CameraCutTrack`, `TimelineSequence` (`evaluateAt`, `play`, `pause`, `stop`, `scrubTo`, `speed`, `wrapMode`).
  - _Verify:_ `vendor/voxseq/test/voxseq_test.dart` & `test/subsystems_test.dart`.
- [x] **E46-2. `CutsceneDirectorComponent` & `TimelineSequencerUI` Engine Integration.**
  - _Touches:_ `lib/src/engine/components/cutscene_sequencer.dart`.
  - _APIs:_ `CutsceneDirectorComponent` (`bindPosition`, `bindRotation`, `bindScale`, `bindActive`, `bindColor`, `bindCameras`, `bindSubtitles`, `bindAudioCues`), `TimelineSequencerUI.render`.
  - _Verify:_ `test/subsystems_test.dart`.

---

## E47: Achievements, Telemetry Event Bus, Combo Multiplier & Leaderboards (`voxstat`)

- [x] **E47-1. `voxstat` Submodule: Typed Gameplay Telemetry, Achievement Conditions, Combos & Leaderboards.**
  - _Location:_ `./vendor/voxstat` (`https://github.com/soulwax/voxstat`).
  - _APIs:_ `TelemetryBus` (buffered typed event dispatch, frame counters, rolling rates & histograms), `MetricRegistry` (integer/float counters, min/max gauges, session vs lifetime rollups, JSON snapshot/restore), `AchievementDef` & `AchievementTracker` (threshold, compound `allOf`/`anyOf` rules, progressive unlock tiers, secret flags, unlock timestamps), `ComboTracker` (decay timer, multiplier curve, rank grades S/A/B/C/D), `Leaderboard` (ranked score entries with metadata, deterministic tie-breakers & JSON serialization).
  - _Verify:_ `vendor/voxstat/test/voxstat_test.dart` & `test/subsystems_test.dart`.
- [x] **E47-2. `ProgressionStatsComponent` & `AchievementsHudUI` Engine Integration.**
  - _Touches:_ `lib/src/engine/components/progression_stats.dart`.
  - _APIs:_ `ProgressionStatsComponent` (wires metrics, achievements, combos & leaderboards to `engine.host.storage` persistence), `AchievementsHudUI.render` (toast notifications, progress bars, combo badge, and leaderboard view via `voxui`).
  - _Verify:_ `test/subsystems_test.dart`.

---

## E48: Virtual File System, Binary Asset Bundles & Versioned Save Migrations (`voxpack`)

- [x] **E48-1. `voxpack` Submodule: Mounted VFS Layers, Chunked Binary Pak Reader/Writer, CRC32 & Migrations.**
  - _Location:_ `./vendor/voxpack` (`https://github.com/soulwax/voxpack`).
  - _APIs:_ `VfsMount` (`MemoryMount`, `PakMount`, priority overlay / DLC patch ordering), `VirtualFileSystem` (path normalization, glob search, readBytes/readText), `PakBuilder` & `PakArchive` (binary header, magic bytes, TOC offsets, CRC32 verification, RLE/XOR obfuscation & optional chunk compression), `SaveMigrator` (ordered schema version steps `v1 -> v2 -> ...`, atomic validation & rollback).
  - _Verify:_ `vendor/voxpack/test/voxpack_test.dart` & `test/subsystems_test.dart`.
- [x] **E48-2. `VfsAssetLoader`, `MigratedSaveStore` & `AssetBrowserUI` Engine Integration.**
  - _Touches:_ `lib/src/engine/assets/pak_vfs.dart`.
  - _Verify:_ `test/subsystems_test.dart`.

---

## E49: Multi-Locale Localization Tables, CLDR Plurals & Glyph Extraction (`voxloc`)

- [x] **E49-1. `voxloc` Submodule: CLDR Plurals, Fallback Chains, Interpolation, CSV/JSON & Glyph Prewarm.**
  - _Location:_ `./vendor/voxloc` (`https://github.com/soulwax/voxloc`).
  - _APIs:_ `LocaleCode` (fallback chains), `PluralRules` (`zero`/`one`/`two`/`few`/`many`/`other`, Slavic/Arabic/Romance/CJK rules + custom overrides), `LocalizationTable` (RFC-4180 CSV & nested JSON importers, `{nested.param:0.0}` formatter, Unicode glyph extraction), `LocalizationManager` (reactive listeners, missing key logging).
  - _Verify:_ `vendor/voxloc/test/voxloc_test.dart` & `test/subsystems_test.dart`.
- [x] **E49-2. `LocalizationComponent` & `LocalizationDebuggerUI` Engine Integration.**
  - _Touches:_ `lib/src/engine/localization/localization_system.dart`.
  - _APIs:_ `LocalizationComponent` (VFS/host asset loading + `engine.host.storage` preference persistence), `LocalizationDebuggerUI.render` (live locale switcher, fallback chain, glyph count & preview via `voxui`).
  - _Verify:_ `test/subsystems_test.dart`.

---

## E50: Cinemachine-Style Virtual Camera Brain, Priority Blending & Dead-Zone Framing (`voxcam`)

- [ ] **E50-1. `voxcam` Submodule: Virtual Camera Rig, Blend Curves, Dead-Zone Framing & Impulse Noise.**
  - _Location:_ `./vendor/voxcam` (`https://github.com/soulwax/voxcam`).
  - _APIs:_ `VirtualCameraRig`, `CameraBlendCurve` (cut, smoothstep, cubic ease-in-out), `CameraFramingComposer` (screen dead-zone, soft-zone clamping, look-ahead offset), `CameraOrbitRig` (yaw/pitch bounds, terrain raycast pull-in), `CameraImpulseSource` (2D/3D procedural trauma decay), `CameraDirectorBrain` (priority stack, smooth cross-blend across active virtual cameras, FOV & Dutch roll blending).
  - _Verify:_ `vendor/voxcam/test/voxcam_test.dart` & `test/subsystems_test.dart`.
- [ ] **E50-2. `CameraBrainComponent`, `VirtualCameraComponent` & `CameraDirectorUI` Engine Integration.**
  - _Touches:_ `lib/src/engine/components/camera_director.dart`.
  - _Verify:_ `test/subsystems_test.dart`.

---

## E51: Hierarchical Spatial Partitioning, Loose Octree & BVH Broadphase (`voxgrid`)

- [ ] **E51-1. `voxgrid` Submodule: Generic Dynamic BVH, Loose Quadtree/Octree & Closest-Hit Ray Queries.**
  - _Location:_ `./vendor/voxgrid` (`https://github.com/soulwax/voxgrid`).
  - _APIs:_ `GridAabb`, `GridRay`, `DynamicBvh<T>` (SAH surface-area heuristic insertion, fattened proxy AABBs, incremental tree updates, frustum/ray/sphere overlap queries), `LooseOctree<T>`.














