# Ease-of-use plan

This plan turns the findings in [REPORT.md](REPORT.md) into work items. Each item lists its scope, the files it touches and how it was verified. **Status: the original ease-of-use phase is complete.** The next phase is below; [TODO.md](TODO.md) tracks the full library gap list.

Two of the report's "missing API" claims were wrong when checked against the code. Only documentation was needed for them:

- `CatmullRomSpline3D.totalLength` / `sampleAtDistance` already existed. Only a tangent-at-distance call was added (P1-9).
- `Ray.intersectPlane` already existed (P1-9 builds on it).

Ground rules:

- The public API grows, but nothing existing is removed or changes meaning without a stated reason.
- After any shader edit, `dart run tools/renderer/shaders.dart` regenerates the shaders and `--check` must pass.
- Every item ends with `dart analyze` clean and the renderer suite passing. `test_rf11` is excluded, as are `plib00` and `plib04`, because they need the original host game repo.

## P0: correctness and resilience

- [x] **P0-1. Handedness regression tests.** New `test_view_handedness.dart`:
  - `lookAt` has determinant +1;
  - world +X maps to screen-right and +Y to screen-up looking down −Z;
  - camera-facing CCW triangles stay CCW from 64 random views;
  - the shaken view stays a rotation, keeps its winding, and reports an eye and forward that match;
  - a top-down camera can be shaken.
- [x] **P0-2. A frame loop that survives errors.**
  - `PixeldartApp._tick` wraps the whole frame and always schedules the next one.
  - A frame that failed after `beginFrame` is aborted with `abortFrame`.
  - `onError(error, stack)` receives the error; the default prints each distinct message once.
  - Taps that throw are reported the same way.
  - Verified in the browser: all three examples removed their own guards and run clean.
- [x] **P0-3. Degenerate scale degrades instead of throwing.** `normalMatrix()` falls back to the cofactor matrix, normalized, when the 3×3 is near-singular. That is the same normal direction, computed without dividing by the determinant. `inverse3x3()` keeps its strict contract. Covered by `test_degenerate_normals.dart`.
- [x] **P0-4. Emissive without a map.** The emissive fallback is now neutral white, like ORM and lightmap (`FallbackPixels.neutralEmissive`). `MaterialDefinition` documents the emission model.
- [x] **P0-5. Glow respects coverage.**
  - `oGlow` carries the fragment's output alpha.
  - Additive world draws use a new `DrawStateDescriptor.additiveCoverage` (`srcAlpha, one`). The old `one, one` state ignored alpha for colour as well as glow. `additiveDefault` is unchanged for full-screen composites.
  - Shaders regenerated.
- [x] **P0-6. Detaching a node removes its draw items.** `removeChild` queues the subtree on the tree root. The root's next `syncToWorld` (via `flushDetached`) removes the subtree's items unless it has been attached anywhere in the meantime; re-parenting keeps and moves them.
- [x] **P0-7. Make the suite's asserts count.**
  - `test_all.dart` now passes `--enable-asserts`. Without it, the 31 scripts that check with `assert(...)` verified nothing.
  - The three failures this exposed:
    - `roundedBox` corner patches emitted zero-area pole triangles: **code fixed**.
    - `radialParticle` started its colour ramp at the centre rather than at `innerRadius`, unlike its alpha: **code fixed**.
    - `test_water_surface` compared Float32 data with no tolerance: **test fixed**.
- [x] **P0-8. Normals were rotated the wrong way.** Found while doing P0-3.
  - `inverse3x3()` stored its cofactors untransposed, so `normalMatrix()` returned the plain inverse. Every rotated mesh was lit as if turned the opposite way.
  - The existing test rotated about Y and probed +Y, which that rotation leaves fixed, so it couldn't see the bug.
  - Fixed. `test_math` now probes normals that the rotation moves, and checks `inverse3x3` on a non-symmetric block.

## P1: remove the boilerplate every game writes

- [x] **P1-1. Inherited, dirty-tracked visibility.**
  - `SceneNode.visible` is inherited by the whole subtree.
  - Every draw-state field is a setter that marks the node world-dirty.
  - `effectiveVisibilityMask`, `hasPendingWorldChanges` and `markWorldSynced` let subclasses follow suit; `InstancedMeshNode` and `ParticleEmitterNode` do.
  - Covered by the new `test_scene_world_sync.dart`.
- [x] **P1-2. Decoder metadata.**
  - `GlbResult` gains:
    - `nodeMaterials` (`sortTiebreaker` is no longer overloaded);
    - `textureImages` plus `imageForTexture`. Material slots were glTF *texture* indices, which every consumer had been treating as image indices.
  - `GlbImage` is index-aligned with the asset's `images` array and carries `uri` for external images. `data:` URIs are decoded.
  - Materials: `KHR_materials_unlit` decodes as a matte dielectric, and `alphaMode`, `alphaCutoff` and `doubleSided` decode.
  - `matrix` nodes decompose into translation, rotation and scale.
  - Non-uniform scale on a leaf becomes `stretch`. When the node has children it is approximated, with a note in `warnings`.
- [x] **P1-3. `ModelAsset`.** In `assets/model_asset.dart` (pure Dart):
  - it registers meshes and materials once, keeps the node hierarchy, and looks meshes up by `MeshData` identity;
  - it exposes `bounds` and `warnings`, and takes `materialOverride` and a per-image texture table.
  - `app.loadModel(url, {materialOverride, textureFilter})` resolves external images relative to the GLB and caches each URL once.
  - `loadGlb`, `loadGlbAsync` and `loadGlbFromUrl` now go through it.
  - Covered by `test_model_asset.dart`, which uses the real Pirate Kit ship plus synthetic GLBs.
- [x] **P1-4. Orthographic camera.**
  - `CameraView.orthographic(...)`.
  - `screenPointToRay` starts orthographic rays at the near plane under the pixel (they all used to start at the eye).
  - `OrthoCameraController` provides following, `fitBounds`, `clampBounds` and damping for any view direction; `app.useOrthoCamera`.
  - Covered by `test_ortho_camera.dart`.
- [x] **P1-5. Shake for any projection.**
  - `applyTo` perturbs the existing view in view space.
  - `rotationScale` (0 means translation only).
  - `app.shakeCamera(trauma:, rotation:)`.
  - Covered by `test_view_handedness.dart`; the existing shake test still passes.
- [x] **P1-6. Particle streaming.** `ParticleEmitter.emitAt(position, perSecond, dt, {source})` and `resetStream`: one emitter streams at an exact rate from many sources.
- [x] **P1-7. Particle material preset.** `ParticleMaterials.soft` / `softDefinition` / `softTexture` (one shared texture per resource library); `app.createParticleMaterial`.
- [x] **P1-8. `colorGradient` works.** Design changed from the plan.
  - Failing `validate()` on an unbound gradient would have broken `ParticlePresets.campfire` and the showcase.
  - Instead, `emitter.bindColorGradient(resources, base, steps:)` builds per-age materials, and `submit` picks one by particle age.
  - `app.addEmitter` binds automatically when the emitter's material was created through the app, which now remembers material definitions.
  - `needsColorGradientBinding` reports an unbound gradient.
  - Covered by `test_particle_streaming.dart`.
- [x] **P1-9. Rays, taps and splines.**
  - `app.screenRay` and `app.currentCamera()`.
  - `Ray.intersectGround`.
  - `app.pick(x, y, where:, precise:)` and `SceneNode.raycast(ray, where:, precise:)`. `precise` tests mesh triangles, and hidden subtrees are skipped.
  - `app.onTap`, which ignores drags.
  - `CatmullRomSpline3D.tangentAtDistance`.
- [x] **P1-10. Coherent sky.**
  - `SkyboxDeclaration.copyWith`.
  - `setSolarTime(coherentHorizon:)` and `app.matchHorizonToFog()`.
  - `setSolarTime` now uses `copyWith` internally.

## P2: polish

- [x] **P2-1. Point-light overflow.** `selectPointLights` ranks lights by influence at the camera, deterministically by id on ties. The world pass uses it, and `FrameStats.pointLightsDropped` counts the rest. Covered by `test_point_light_selection.dart`.
- [x] **P2-2. Volumetric banding.** `enableVolumetricFog(jitter:)` defaults to the validated maximum of 0.5. The sample count is floored by density, within the validated 4–24.
- [x] **P2-3. Validation messages name the field.** `SkyboxDeclaration.validate` lists every bad field and its range. `cloudSampleCount` is only checked while `cloudCoverage > 0`, and the present pass clamps it when uploading.
- [x] **P2-4. Non-uniform scale.**
  - `Transform.stretch` and `SceneNode.stretch` give geometry-local, non-inherited scale.
  - `Transform.copyWith` exists, and the position/rotation/scale setters now preserve stretch.
  - Covered by `test_scene_world_sync.dart`.
- [x] **P2-5. `onBeforeFrame` hook.** It runs before animations, the scene sync, the camera and emitters.
- [x] **P2-6. Conventions document.** `docs/conventions.md`, linked from the README.

## Examples and report

- [x] **E-1. Examples migrated; workarounds deleted.**
  - `prefab.dart`, `model.dart` and `ortho_camera.dart` are gone.
  - Gone from the game code: every `setVisible` helper, the white emissive textures, the soft-texture boilerplate, the `_stream` accumulators and the per-game frame guards.
  - Pixel Rocket's flame now lengthens with `stretch`.
  - Tidewatch uses `loadModel`, `onTap`, precise `pick`, `screenRay`, spline arc length and `matchHorizonToFog`.
  - All three were compiled and played in the browser: Pixel Rocket to game over; Lantern through portal, death and restart; Tidewatch through dusk, a storm and game over, plus a tap test.
- [x] **E-2. REPORT.md updated** with corrections, new findings and the status of each item.
- [x] **V-1. Final verification.**
  - `dart analyze`: no issues in `lib` or `examples`. The 14 remaining notes are pre-existing style lints in untouched tests.
  - Shaders `--check` passes.
  - Renderer suite with asserts on: 121 of 122 scripts pass; `rf11` needs the host repo.
  - `plib` tests: all pass except `plib00` and `plib04`, which need the host repo.
  - Example builds use `--no-source-maps`, since `plib11` forbids generated maps in the package tree.

## Round 2: refinements (2026-11-09)

- [x] **R-1. Particle fades work.** `fadeInFraction`, `fadeOutFraction` and `alphaCurve` were validated but never applied, so every preset popped particles in and out. They now shape a `fadeEnvelope` applied as sprite scale: instances stream transforms only, so there's no per-instance alpha. Fully faded particles are no longer submitted. Fixture added to `test_particle_streaming`.
- [x] **R-2. Showcase layout.**
  - The island terrain sat on top of the hero exhibit, unnoticed while single-sided geometry was culled.
  - The island, water, buoy and vessel now form an `ocean_diorama` group behind the stage. The buoy and vessel were moved off the island into open water.
  - The terrain toggle hides the whole group through inherited `visible`.
  - The tour visits the diorama.
- [x] **R-3. Stale web bundles rebuilt.** The committed `web/minimal` and `web/showcase` `main.dart.js` predated every engine fix. They are rebuilt with `-O2 --csp --no-source-maps`; the showcase bundle went from 1.1 MB to 440 KB.
- [x] **R-4. The test suite is green in a standalone checkout.**
  - `rf11`, `plib00` and `plib04` run their package-side checks always, and their host-game checks only when a host project exists.
  - `plib00` also found the package root only when run from a host's `external/pixeldart` path with forward slashes.
  - Results: **all 122 renderer scripts and all 17 package checks pass.**
- [x] **R-5. Size budgets removed.** With `budgets.json` deleted, `check_sizes.dart`, its README lines and its TODO entries are gone.
- [x] **R-6. `dart analyze` reports no issues**, as the README promises. 3 warnings and 11 infos in older tests were fixed; the unused `leftArm` became an assertion.
- [x] **R-7. Docs.**
  - `examples/README.md` (index, build commands, assets) and `examples/example_1/README.md` were added, with a link from the main README.
  - The README's coordinate contract no longer claims non-uniform scale is rejected.

## Round 3: proving robustness live (2026-11-09)

- [x] **L-1. Context loss and restore, live.** 10 forced `WEBGL_lose_context` cycles on real hardware: minimal host, showcase, Tidewatch and Lantern. Three bugs found and fixed:
  - **Unobserved restore.** A loss and restore between frames was never noticed, because `PixeldartApp` skips frames while lost. The renderer kept drawing with dead objects, producing a black frame. Added the `GpuContextGeneration` optional interface and a renderer check, plus a pure fixture in `test_scene_renderer` (shown to fail without the fix).
  - **Extensions not re-enabled on restore**, which left every timer query with invalid enums.
  - **Stale deletes.** Handles from the lost context were still deleted. Objects now carry their generation.
  - Result: 0 WebGL errors after the cycles (was 760–866 per game), with full rendering including URL-loaded palette textures.
- [x] **L-2. Resize and DPR, live.** 100 cycles. 75/100 failed at first: a DPR change without a CSS resize was ignored (monitor change, zoom). `SurfaceMetrics.resized(devicePixelRatio:, maxDevicePixelRatio:)` was added, and `PixeldartApp` and the minimal host now follow it. Result: 0/100 mismatches. Resize failures are now reported rather than swallowed.
- [x] **L-3. Records.**
  - CHANGELOG has an `Unreleased` section covering all three rounds.
  - TODO: context loss, resize/DPR and per-instance transforms are ticked with evidence; the material item narrowed to `uvOffset`; README example snippets done.
  - `doubleSided` stays open: not yet verified under the corrected renderer.

## Round 4: optimise, then play all three games (2026-11-09)

- [x] **O-1. Profile.** CDP CPU profiles of 6 s of play per game, on -O1 builds. Hotspots:
  - `getUniformLocation`: 31–36% of busy time in every game;
  - `WaterSurfaceMesh.updateWaves`: 63% in Tidewatch;
  - smaller: `toMat4` allocations and a forced layout in `_resize`.
- [x] **O-2. Fixes.**
  - Uniform locations are cached per program. The table is fetched once per bind, and missing names are remembered.
  - The wave pass is fused: one pass yields displacement and normal, and each wave's phase is rotated along the grid row, so sin/cos run only at row starts. A test checks it against the evaluator on a 520 m, 112-subdivision grid.
  - `Mat4.compose` builds the model matrix in a single buffer.
  - A `ResizeObserver` gates canvas size reads.
- [x] **O-3. Result.** Main-thread busy time and p95 frame interval:

  | Game | Busy before → after | p95 frame interval now |
  | --- | --- | --- |
  | Pixel Rocket | 43% → 24% | 17.8 ms |
  | Lantern | 17% → 10% | 17.3 ms |
  | Tidewatch | 68% → 23% | 17.5 ms |

  Live context-loss and resize gates still pass: 10/10 restores and 0/100 resize mismatches.
- [x] **P-1. Play-throughs.** Every game reaches its end card and restarts:
  - **Pixel Rocket:** fly, boost, collect, die.
  - **Lantern:** motes, portal, room 2, death, restart.
  - **Tidewatch:** a full run from 17:00 into night, ships home, wrecks, harbour closes. A tapped ship gets a flare.
- [x] **P-2. Bugs found in play, fixed:**
  - **Night sky.** The night sky was bright mauve, and a hard band sat on the sea's horizon. Three causes:
    - **Night fog.** `SolarCycleEngine` used the sun's below-horizon transmittance for night fog. It now fades to a dark haze through twilight.
    - **Screen-space sky.** The fallback sky's bands followed the screen, not the horizon, so a downward camera got zenith colour over fully fogged sea. They now follow the view direction.
    - **Reflections.** Environment reflections ignored ambient intensity.
  - **Stars.** They were square blocks fixed to the screen. They are now round points fixed to the sky.
  - **End card.** Tidewatch's card said "through 0 nights".
- [x] **P-3. API gap found in play.** There was no world-to-screen projection: a test, or a HUD label over a ship, needs one. Added `CameraView.worldToScreenPoint` and `app.worldToClient`, with a round-trip test against `screenPointToRay` for perspective and orthographic cameras.
- [x] **P-4. Live material checks** (D3D11, a throwaway page outside the repo):
  - `uvOffset` swaps a checker's halves exactly.
  - A single-sided back face is culled and a double-sided one draws.
  - Found and fixed: `doubleSided` back faces were lit with the front normal (119 vs 173 on a matte quad; 172 vs 173 after). `test_lighting_shader_contract` guards it. Both TODO items are ticked.
- [x] **P-5. Pixel Rocket hit burst.** Emissive strength 7 tone-mapped the orange blast to cream-white discs that hid the ship for about 0.3 s. Lowered to 2.4 with a redder tint; it reads as fire and the ship stays visible.
- Not bugs:
  - Lantern's quick death while idle: 1.4 s of invulnerability per hit, by design.
  - Flare taps that miss: ships are a few pixels wide at that distance. The beam-proximity fallback covers this.

## Next phase: renderer library

Work through these in order. Built-in shaders are defaults for named pipeline slots; a host can supply replacements without taking ownership of WebGL objects or the render graph. Keep game rules in the examples.

Program registration now rejects duplicate IDs across passes and shader variants before compiling. `publish`/`tryReload` retain their explicit replacement behavior; a shared-library two-graph fixture guards the live program handle.

Current implementation: named shader overrides, typed host bindings, per-draw sprite and material shaders, host post effects, anisotropy negotiation, and MSAA negotiation/attachment-aware resolve are in place. R1–R5 remain open for the browser checks, hardware measurements, and declared host graph-pass API below; the unchecked boxes do not mean their existing APIs are absent. The latest local code check ran all 132 renderer scripts, `dart analyze`, the rendering boundary check, and a minimal web compile successfully. This is static/pure-fixture evidence, not a substitute for the remaining live checks.

- [ ] **R1. Complete the public shader contract.** `ShaderSlot` and `ShaderOverride` let hosts replace either GLSL stage through `PixeldartApp.mount`/`mount2d` or low-level `RendererConfiguration`; absent stages use the built-in defaults. The [slot contract](pixeldart/docs/shader_overrides.md) records default stages, vertex inputs, sampler units, outputs and links to each shader's typed uniform and varying declarations. Example API now implemented:

  ```dart
  final app = await PixeldartApp.mount(
    canvas,
    shaders: {
      ShaderSlot.sprites: ShaderOverride(
        fragment: await loadText('shaders/my_sprites.frag'),
      ),
    },
  );
  ```

  Typed slots reject unknown names. Duplicate program IDs, mismatched fragment outputs, attribute locations/types, engine uniform types and vertex-to-fragment varyings are rejected before drawing. The first [browser renderer lab](pixeldart/docs/browser_renderer_lab.md) fixtures compared built-in and overridden `present` on Edge 157 / Intel Iris Xe / D3D11: center RGBA `0,14,104,255` versus `64,128,191,255` for `vec4(0.25, 0.5, 0.75, 1)`, with 0 GL errors and no JavaScript exceptions. Other slots and color-space paths still need browser fixtures; the renderer cannot infer color-space semantics from GLSL declarations. A custom shader is bound to the same pass and resource contract as its default; adding new passes is a separate API.
- [ ] **R2. Finish safe shader changes.** Overrides resolve centrally; `setShader` changes them between frames, failed live compiles preserve the prior graph, startup failures use defaults with `shaderErrors`, and context restoration recompiles the override. Shader-only changes now compile affected programs in place without reallocating render targets or rebuilding passes. Typed host uniforms, including `int` and `mat4`, and texture bindings are done (`ShaderUniform`, `setShaderUniform`, `setShaderTexture`, `ShaderOverride.effect`, with no raw GL handles and engine-reserved names rejected). The float/vector/texture path was verified on D3D11; the new types have pure fixtures. Verify the slot contracts and visual output in a real browser fixture in addition to the pure tests.
- [ ] **R3. Extend shader choice to authored draws.** *Done (2026-11-09):* per-draw sprite shaders (`createSpriteShader`, `drawSprites(shader:)`) and host post-effect stacks (`postEffects`), verified on D3D11. Per-material world shaders (`createWorldShader`, `MaterialDefinition.worldShader`) now cover both `safeWorld` and `shadowedWorld`, restore frame uniforms on program switches, and survive context restore and profile round trips in pure fixtures. The default path avoids capture and selection work. The shadowed-world material path also caches alpha cutoff, coverage and affine warp values; a minimal-profile draw fixture guards the neutral SSAO fallback against feedback loops. *Remaining:* browser visual verification and a separately declared input/output API for arbitrary host graph passes. The latter must not treat a replaced built-in pass as an arbitrary new graph node.
- [ ] **R4. Finish anisotropic texture sampling.** The low-level request, extension negotiation and 1× fallback work. `ResourceLibrary.anisotropyOf(handle)` and `PixeldartApp.textureAnisotropy(handle)` report requested/effective sampling without GPU calls and refresh capability limits after context restoration. Texture descriptors now reject a mipmap magnification filter and minification mipmaps without storage before allocation; non-power-of-two images allocate the correct mip count. The README documents 1× nearest for pixel art and mipmapped anisotropy for oblique surfaces. *Remaining:* compare 1×, 4×, 8× and 16× on an oblique textured plane, recording image quality and GPU time before choosing a default cap.
- [ ] **R5. Make MSAA capability-driven and cheap.** *Done (2026-11-09):*
  - `MsaaStatus.negotiate` clamps to `maxSamples` and halves on an incomplete framebuffer, down to 1×. It runs on initialize, configure and context restore.
  - `renderer.msaa` / `app.msaa` report the result; `app.setSampleCount` changes it.
  - The resolve target is sized by its readers: color, plus glow only with bloom, and no depth. The WebGL resolve blits only attachments both sides own.
  - 1× stays free, and `mount2d` stays at 1×.
  - `test_msaa_negotiation` covers it.

  A 4× D3D11 smoke run with `ps1Full` and `clean` produced correct pixels and no GL errors. *Remaining:* cover resize and context restoration live, then measure 1×/2×/4× GPU time, memory, and edge quality on representative scenes before changing the high-profile `mount` default. The pixel-art 2D profile stays at 1×.
- [ ] **R6. Add a static CI gate.** Run `dart pub get`, `dart format --output=none --set-exit-if-changed .`, `dart analyze`, `dart run tools/renderer/test_all.dart`, `dart run tools/renderer/check_boundary.dart` and `dart run tools/renderer/shaders.dart --check` from `pixeldart` in GitHub Actions. The whole-package format gate is still pending; touched-file format checks do not satisfy it. Confirm the workflow passes on a clean checkout. Keep the desktop build as a separate Windows gate if needed.
- [ ] **R7. Build the browser renderer lab and baselines.** The first live fixtures and Node/CDP runner compare built-in versus overridden `present`, in-frame `readPixels`, JavaScript/WebGL error status, and hardware adapter identity. Add other slots, an oblique anisotropic texture, 1×/2×/4× MSAA edges and forced context loss. Add golden comparisons and the documented warm-up/measurement protocol; ratify performance budgets from real hardware evidence.

Example-specific acceptance, including Procession's dense trees and executable, remains tracked in [TODO.md](TODO.md) and is outside this renderer-focused sequence.

## Out of scope

- A frame counter for back-face-culled triangles: GPU culling isn't observable without queries. P0-1's tests guard the cause instead.
- An audio companion package: not renderer work.
- Named post-process override stacks: `copyWith` is adequate.
- `GerstnerWaveEvaluator.scaled(...)` for storms: one game needed it, and rebuilding the evaluator is cheap. Add it if a second user appears.
