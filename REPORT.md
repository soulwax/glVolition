# Pixeldart ease-of-use report

This report comes from writing three games on Pixeldart from scratch: Pixel Rocket, Lantern and Tidewatch, now in `examples/`. It sets out what worked, what broke, what I had to hand-write that the renderer could own, and what I'd change first.

## Status update (2026-11-09)

The core API and correctness recommendations in section 7 have been implemented. Pixel-level acceptance for culling and instancing, along with the later renderer-library work, remains open in [PLAN.md](PLAN.md) and [TODO.md](TODO.md). This report keeps the original assessment below the line so the before-and-after stays readable; its descriptions of missing APIs and open bugs are historical, not current gaps.

### Renderer library follow-up

The later renderer phase added built-in shader overrides, typed host uniforms and textures, per-draw sprite and material shaders, host post effects, negotiated anisotropy, and capability-driven MSAA with an attachment-aware resolve. It also made identity post effects skip full-screen draws, rejected program-ID collisions, and corrected non-power-of-two mip allocation and invalid filter combinations. The latest local check passed all 132 renderer scripts, `dart analyze`, the rendering boundary check, and a minimal web compile.

Those checks do not complete browser color-space verification, anisotropy quality and GPU-time comparisons, MSAA resize/restore acceptance, or the planned CI and browser-baseline gates. [PLAN.md](PLAN.md) separates the implemented parts of R1–R5 from these remaining checks.

### Corrections to this report

Checking the claims against the code before implementing showed three were wrong:

- **`CatmullRomSpline3D` already had arc-length sampling.** `totalLength` and `sampleAtDistance` existed. Tidewatch's `Lane` class reimplemented them because I didn't look; only `tangentAtDistance` was missing.
- **`Ray.intersectPlane` already existed.** `intersectGround` now wraps it.
- **`SmoothFollowCameraController` already has `fovYRadians`.** The "no field-of-view hook" remark in section 4 is wrong; only per-axis damping is missing.

So discoverability is part of the ease-of-use story too. [docs/conventions.md](pixeldart/docs/conventions.md) now points at these APIs.

### Bugs found while implementing

These weren't in the original report:

| # | Bug | Effect | Fix |
| --- | --- | --- | --- |
| N1 | **Normals were rotated the wrong way.** `Mat4.inverse3x3` stored cofactors untransposed, so `normalMatrix()` returned the plain inverse. | Every rotated mesh was lit as if turned the opposite way. The existing test rotated about Y and probed +Y, which that rotation leaves fixed. | Fixed, and `test_math` now probes normals that the rotation actually moves (P0-8) |
| N2 | **31 test scripts never checked anything.** They use `assert`, but `test_all` ran without `--enable-asserts`. | Turning asserts on exposed three failures. `roundedBox` emitted zero-area triangles and `radialParticle`'s colour ramp ignored `innerRadius` (both code bugs, fixed); the water test lacked a Float32 tolerance (test fixed). | `test_all` runs with asserts (P0-7) |
| N3 | **Additive blending ignored alpha for colour too**, not just glow (`one, one`) | Soft additive sprites with white RGB drew as squares | New `additiveCoverage` state (`srcAlpha, one`) for additive world draws (P0-5) |
| N4 | **GLB material texture slots were treated as image indices.** They are glTF *texture* indices, and external images also shifted the image list. | Wrong maps on assets whose textures and images aren't one-to-one | `GlbResult.textureImages` / `imageForTexture`; image list index-aligned (P1-2) |
| N5 | **Orthographic picking rays all started at the eye** | Picking in any 2D or orthographic view was wrong | Rays start at the near plane under the pixel (P1-4) |
| N6 | **The decoder dropped `alphaMode`, `doubleSided`, `matrix` nodes and `data:` URIs** | Foliage and glass, and some exporters' assets, loaded wrong | All decoded (P1-2) |
| N7 | **Particle `fadeInFraction`, `fadeOutFraction` and `alphaCurve` were never applied**, the same kind of bug as `colorGradient` | Every preset's particles popped in and out | Applied as a size envelope (PLAN R-1) |
| N8 | **The showcase's island covered its hero exhibit**, and its buoy and vessel sat on dry land. The layout was authored while F1 culled the terrain and water. | The camera started inside a hill once F1 was fixed | Ocean diorama moved behind the stage (PLAN R-2) |
| N9 | **The committed `web/*/main.dart.js` bundles predated every fix** | The showcase as published still showed every bug | Rebuilt (PLAN R-3) |
| N10 | **A context restore between frames went unnoticed** | Black frames forever after a short GPU reset, in any `PixeldartApp` host | `GpuContextGeneration` (PLAN L-1) |
| N11 | **Extensions not re-enabled after a restore; dead handles still deleted** | Hundreds of WebGL errors per second; GPU timing broken | Fixed in `WebGl2Device` (PLAN L-1) |
| N12 | **A DPR change without a CSS resize was ignored** | Blurry or oversized rendering after moving to another monitor or zooming | `SurfaceMetrics.resized(devicePixelRatio:)` (PLAN L-2) |

### Where each finding landed

| Finding | Status |
| --- | --- |
| F1–F3 (`lookAt`, tangents) | Fixed earlier; F1 now has regression tests (P0-1) |
| O1 frame loop dies on an exception | Fixed: guarded tick, `abortFrame`, `onError` (P0-2) |
| O2 emissive needs a map | Fixed: neutral white fallback (P0-4). The showcase's conduit, beacon and VFX materials now glow as intended. |
| O3 glow ignores alpha | Fixed, together with N3 (P0-5) |
| O4 `removeChild` leaks draw items | Fixed: cleanup at the root's next sync (P0-6) |
| O5 degenerate scale throws | Fixed: cofactor fallback (P0-3) |
| O6 `loadGlb` mesh misassignment | Fixed: goes through `ModelAsset` (P1-3) |
| O7 `colorGradient` unused | Implemented as per-age materials, bound automatically by `addEmitter` (P1-8) |
| O8 point lights silently dropped | Ranked by influence; `FrameStats.pointLightsDropped` (P2-1) |
| O9 shake assumes perspective | Fixed: view-space perturbation, `rotationScale` (P1-5) |
| O10 volumetric banding | Fixed: jitter on by default, sample count floored by density (P2-2) |
| O11 validation doesn't name the field | Fixed for `SkyboxDeclaration` (P2-3) |
| O12 external URIs and non-uniform scale | Fixed: `loadModel` resolves URIs; leaf scale becomes `stretch` (P1-2, P1-3) |
| Section 4 boilerplate | Each row now has an API; see PLAN P1 and P2. The examples dropped `prefab.dart`, `model.dart` and `ortho_camera.dart`, plus every helper the appendix lists. |
| Section 5 papercuts | Handedness, primitive orientation and frame order documented (P2-6). Non-uniform scale via `stretch` (P2-4). `onBeforeFrame` (P2-5). |

### What the fixes show in the games

- **Pixel Rocket:** the crystals and fuel canisters glow for the first time, the meteors are shaded from the correct side, and the boosted flame lengthens instead of fattening.
- **Lantern:** with normals turned the right way, lit flagstones catch the light far more strongly.

---

## Summary

**Getting a first frame on screen is excellent. Getting a *correct* frame was the hard part.** `PixeldartApp.mount` plus `Primitives`, `ProceduralTextures` and the material presets put a lit, post-processed scene on screen in about twenty lines. The high-level systems are game-ready: terrain, Gerstner water, buoyant hulls, the solar cycle and volumetric fog. Tidewatch is mostly those built-ins wired together.

Almost all my debugging time went into **silent failures**: things that rendered wrong or not at all, with no error. The parameter validation is strict and loud, which is good, but the rendering path is quiet exactly where it matters. One bug, a mirrored `Mat4.lookAt`, caused most of it. It made camera-facing geometry disappear, and I spent two games working around its symptoms before I found the cause.

The second theme is **boilerplate**. Across the three games I wrote the same helpers three times: a model loader, a visibility toggle, a frame-error guard, a white emissive texture and particle streaming. Most of these belong in the library. Section 4 lists each one.

| Aspect | Verdict |
| --- | --- |
| Time to first frame | Excellent |
| API shape and naming | Good: consistent, discoverable, `copyWith` everywhere |
| Built-in game systems | Very good: terrain, water, buoyancy, sun, splines, animation |
| Correctness out of the box | Poor before the `lookAt` fix, good after |
| Failure visibility | Weak: wrong output is silent, and one exception stops rendering |
| Asset pipeline (GLB) | Fragile: decodes, but you can't instantiate a model more than once and it falls over on common real-world assets |
| Docs | Strong on architecture, thin on conventions (handedness, emissive, culling) |

## 1. What I built

| Example | Genre | Engine surface exercised | Game code |
| --- | --- | --- | --- |
| Pixel Rocket | 3D chase runner | `PixeldartApp`, GLB, particles, point lights, bloom, PS1 post, shake | ~1030 lines |
| Lantern | Pure 2D, top-down | Orthographic camera, normal-mapped procedural textures, the 4-light limit, emissive, VHS/PS1 post, exposure fades | ~1310 lines |
| Tidewatch | Inverted tower defense | Terrain, water, buoyancy, solar cycle, clouds, volumetric fog, shadows, rain field, splines, keyframe clips, picking, material presets, depth of field | ~1400 lines |

Of the roughly 3700 lines in total, I estimate **500–600 are infrastructure the renderer could provide** (section 4). The rest is game logic and HUD.

## 2. What worked well

- **`PixeldartApp.mount`** hides the bootstrap ladder, surface metrics, frame sequencing, the resize path and context loss. I never had to think about any of them.
- **`bootstrapRenderer` and `defaultProfileLadder`** let me request a high profile with a guaranteed fallback.
- **The retained `SceneNode` graph** is pleasant. `add(mesh:, meshData:, material:, transform:)` returns the node, the `position`/`rotation`/`scale` setters mark dirty automatically, and `traverse`/`findByName` cover the common needs.
- **`Primitives`** covers nearly everything a prototype needs: cylinder, cone, torus, rounded box, sphere, octahedron, `tubePath`.
- **`ProceduralTextures`** is a standout. `normalFromHeight` made Lantern's normal-mapped 2D floors trivial. `radialParticle(edgeColor:)` was the key to fixing glowing particles. `TerrainGenerator.generateBiomeTexture` gives a good-looking island for free.
- **Material presets** (`ceramic`, `chrome`, `copper`, `plastic`) were good enough to use as-is.
- **The game systems compose naturally.** One `GerstnerWaveEvaluator` drives the water mesh, `BuoyantVesselBody`, and my own buoy bobbing via `sampleHeight`. `BuoyantVesselBody` exposes mutable `position` and `yaw`, so steering a ship along a spline while it rolls on the waves took about ten lines.
- **`setSolarTime`** gives a full day/night cycle (sun, ambient, fog, sky) in one call.
- **Volumetric fog lit by point lights** is impressive: a lighthouse beam and lightning flashes became visible shafts with no extra work.
- **`AnimationClip` with `Vector3Track`/`RotationTrack`** made the sinking animation declarative and short.
- **Strict validation** (`CameraView.validate`, `SkyboxDeclaration`, mesh validation) catches nonsense early.
- **Everything outside the WebGL backend is pure Dart.** I ran `GlbDecoder` and the math types on the VM to debug assets and quaternions without a browser. That was invaluable.
- **The test suite** (115 scripts) is broad and fast enough to run in full after an engine change.

## 3. Bugs found

### Fixed during this work (committed in `1be1e4c`)

| # | Bug | Symptom in the games | Root cause | Fix |
| --- | --- | --- | --- | --- |
| F1 | **`Mat4.lookAt` was mirrored** | Terrain and ocean invisible; rocks and meteors shaded from inside; screen-right was −X looking down −Z, so steering was mirrored; billboard particles silently culled | `r = up × f` builds a determinant −1 basis, which flips on-screen winding. Standard CCW back-face culling then removes the camera-facing side. The doc comment already said "right-handed". | `r = f × up`, `u = r × f`. Related tests pass. |
| F2 | **GLB decoder fallback tangent** | Every Kenney Space Kit model failed with `surface-v2 tangent must be orthogonal` | A missing `TANGENT` was filled with a constant +X, which is not orthogonal to most normals | Project a reference axis onto the normal's plane |
| F3 | **GLB decoder trusted authored tangents** | Kenney Pirate Kit ships failed the same validation | Exporters emit degenerate tangents where palette UVs collapse (116 of 2158 on one ship) | Gram-Schmidt every tangent and fall back if degenerate |

**F1 needs a regression test that would have caught it.** Nothing in the suite failed before or after the fix. Two suggestions:

- assert `det(view) > 0`, and that `CameraView.look` maps world +X to screen-right when looking down −Z;
- a render-level fixture where a single-sided plane faces the camera and must produce pixels.

Also re-check the showcase and the README screenshots. Anything single-sided rendered before the fix was affected.

### Open, ordered by impact

| # | Issue | Evidence | Effect | Suggested fix |
| --- | --- | --- | --- | --- |
| O1 | **An exception in a frame stops rendering for good** | `PixeldartApp._tick` has no guard around `animations.update`, `syncToWorld`, emitters or `onFrame`. `requestAnimationFrame` is only re-requested at the end. | Lantern's game over froze the game: hiding the player with scale 0.0001 made `Mat4.inverse3x3` throw inside `syncToWorld`. Under dart2js `-O2` the error surfaces only as `Uncaught Error`. | Wrap the tick body, always re-request the next frame, expose `onError`, and rate-limit reporting. Every example now carries its own try/catch around `onFrame`, which doesn't cover `syncToWorld`. |
| O2 | **`emissiveStrength` does nothing without an `emissiveTexture`** | The emissive fallback is `FallbackPixels.blackEmissive`. The shader computes `texture(uEmissiveMap) * tint * strength`. | Emissive materials silently don't glow. **The showcase hits this too:** the conduit rail (`emissiveStrength: 1.8`), the buoy beacon and the VFX particle materials set a strength but no map. | Use a white fallback when `emissiveStrength > 0`, or treat a missing map as 1 in the shader. At minimum, warn on construction. |
| O3 | **The glow target ignores alpha** | `oGlow = vec4(emissive, 1.)` while `oColor` uses `vColor.a * tex.a` | Blended emissive particles bloom as hard squares. Workaround: an emissive map whose RGB falls off with alpha. | Multiply `oGlow` by `outAlpha` on the blended path |
| O4 | **`removeChild` leaves draw items in the world** | `removeChild` detaches the node; only `removeFromWorld` removes its retained items. `syncToWorld` only walks attached nodes. | Detached nodes keep rendering. Every example uses pools to avoid this. | Detach should enqueue world removal, or `syncToWorld` should diff the set of live instance IDs |
| O5 | **Degenerate scale throws instead of degrading** | `inverse3x3` throws on a singular matrix | Combined with O1, a legitimate "shrink to nothing" effect kills the app | Clamp, or skip drawing items whose scale is near zero |
| O6 | **`PixeldartApp.loadGlb` likely misassigns meshes on multi-node files** (from reading the code, not tested) | It assigns `meshHandles[cursor]` to every node with `sortTiebreaker >= 0`, but group nodes default to 0, and the flat mesh list is in glTF mesh order, not traversal order | Probably wrong parts on wrong nodes for any multi-mesh asset | Match by `node.meshData` identity, as `examples/*/src/model.dart` does. Stop overloading `sortTiebreaker` as a material index. |
| O7 | **`ParticleEmitter.colorGradient` is never applied** | It is only referenced by `validate()` | Dead API: the colors silently don't change | Implement it, or remove it |
| O8 | **Point lights above four are silently dropped** | The shader loops over four. The fifth and later lights are ignored without a warning. | Surprising, though Lantern turned it into a game rule | Warn in debug builds, or auto-rank by influence (volumetrics already ranks its sources) |
| O9 | **Camera shake assumes a perspective camera with +Y up** | `applyTo` rebuilds the view through `lookAt` with up = (0, 1, 0) | Degenerate for a top-down camera; rotates orthographic 2D views | Shake by perturbing the existing view matrix, with a translation-only option |
| O10 | **Volumetric banding at low sample counts** | A bright straight line across the sea at constant view depth in dense media with `sampleCount: 12`; gone at 24 | Visible artifact in storms | Jitter the steps per pixel per frame (the frame sequencer already has a noise seed), or scale the minimum sample count with density |
| O11 | **Validation errors don't name the field** | `SkyboxDeclaration contains invalid values` was caused by `cloudSampleCount: 1`. Clouds were off, yet the minimum of 4 is still enforced. | A guessing game | Name the field and its range; skip cloud validation when coverage is 0 |
| O12 | **The GLB decoder ignores external image URIs and non-uniform scale** | `images[].uri` is skipped silently; `scale` takes only `[0]` | Pirate Kit models load untextured, with no warning | Accept a `resolveUri` callback in `loadGlbFromUrl`; warn on non-uniform scale |

## 4. Boilerplate inventory: what I wrote that the renderer could do

For each item: where it lives, roughly how big it is, and what the library could provide instead.

### Assets and the scene graph

| What I wrote | Where | Size | What the renderer could do |
| --- | --- | --- | --- |
| **Model loaders**: decode once, register meshes and materials, instantiate many times, keep the node hierarchy, match meshes by identity, compute hierarchy bounds, re-key materials so keys are unique | `example_1/src/prefab.dart`, `example_3/src/model.dart` | ~240 lines, written twice | A `ModelAsset` type: `app.loadModel(url) → ModelAsset` with `instantiate()` and `bounds`. This was the single biggest gap. `loadGlb` attaches one copy to the scene, and every game needs many. |
| **External palette binding** (`Textures/colormap.png`, nearest filtering, no mipmaps) | `example_3/src/model.dart` | ~15 lines | Resolve relative `uri` images against the GLB's URL, with a `filter:` option or a palette heuristic |
| **Material overrides for unlit-authored assets** (`kenneySurface`) | `example_1/src/prefab.dart` | ~25 lines | Honor `KHR_materials_unlit` (Kenney's files declare it), and don't default `metallicFactor` to 1 when it's absent. A `materialOverride:` hook on load would cover the rest. |
| **`setVisible(node, bool)`**, which walks descendants, sets `visibilityMask` and calls `markDirty` | All three `main.dart` files | 7 lines ×3 | `node.visible = false`, inherited by children and dirty-tracked. Changing `visibilityMask` or `material` today doesn't mark the node dirty, so it doesn't reach the GPU unless you also move the node. |
| **Pooling to avoid `removeChild` leaks** | All three games | design constraint | Fix O4 |
| **Hiding via a tiny scale**, which then crashed | Lantern | — | Fix O1 and O5 |

### Materials and particles

| What I wrote | Where | Size | What the renderer could do |
| --- | --- | --- | --- |
| **A 2×2 white texture bound as the emissive map** | Lantern, Tidewatch | ~8 lines ×2 | Fix O2 |
| **A soft particle texture with black edges, also used as the emissive map** | All three | ~15 lines ×3 | Fix O3, and add a `ParticleMaterial.soft(color, glow)` preset. Every particle user writes this same material. |
| **`_stream()`: per-frame `burst()` with a fractional debt accumulator** | Lantern, Tidewatch | ~8 lines ×2 | `emitter.emitAt(position, perSecond, dt)`, so one emitter can feed many moving sources (braziers, flares). `rate` plus `transform` only supports one source per emitter. |

### Camera and input

| What I wrote | Where | Size | What the renderer could do |
| --- | --- | --- | --- |
| **An orthographic camera**: raw `CameraView` with `Mat4.orthographic`, fit-to-viewport, bounds clamping, translation-only shake | `example_2/src/ortho_camera.dart` | 96 lines | `CameraView.orthographic(...)` plus an `OrthoCameraController` with `fitBounds` |
| **A chase camera** with speed-driven field of view | `example_1/src/chase_camera.dart` | 57 lines | Partly my choice: `SmoothFollowCameraController` exists, but it lacks a field-of-view hook and lateral follow damping. Adding `fovYRadians` and per-axis damping would let games reuse it. |
| **Mouse ray against the sea plane** | Tidewatch `_aimBeam` | ~20 lines | `app.screenRay(clientX, clientY)` (`pick` builds this internally but doesn't expose it) and `Ray.intersectPlane(normal, d)` |
| **Telling a click from a drag** when the built-in orbit controls are on | Tidewatch `_installInput` | ~20 lines | An `app.onClick` / `onPointerTap` that ignores drags, since `app` already tracks the pointer |
| **Picking fallback** (nearest ship to the aim point) | Tidewatch `_clickAt` | ~15 lines | Triangle-level picking, or a pick filter (`pick(x, y, where: (node) => ...)`). AABB picking against a 520-unit ocean is risky. I added the fallback pre-emptively and didn't verify a failure. |

### Environment and sky

| What I wrote | Where | Size | What the renderer could do |
| --- | --- | --- | --- |
| **Keeping sky, fog and clear color coherent**: copy `SkyboxDeclaration` field by field, set `horizon = ground = fogColor`, set `clearColor = fogColor` | Tidewatch `_sun` | ~30 lines | `SkyboxDeclaration.copyWith`, plus a `coherentHorizon: true` option on `setSolarTime`. Today the fogged geometry's far edge shows as a seam against the background. |
| **Rebuilding the wave evaluator every frame for storms** | Tidewatch `_weather` | ~15 lines | `GerstnerWaveEvaluator.scaled(amplitude:, wavelength:, speed:)` that preserves steepness, or a `seaState` scalar on `.ocean()` |
| **Choosing at most four point lights** | Lantern | game rule | Automatic influence ranking (O8) |
| **Order-dependent solar calls** (set the skybox *before* `setSolarTime`, then override it again after) | Tidewatch | subtle | Document it, or make `setSolarTime` return the state and accept overrides |

### Splines and animation

| What I wrote | Where | Size | What the renderer could do |
| --- | --- | --- | --- |
| **Arc-length resampling of a spline** (`Lane`: `pointAt(distance)`, `tangentAt`, `length`) | Tidewatch | ~55 lines | Add `length`, `sampleAtDistance` and `tangentAtDistance` to `CatmullRomSpline3D`. Anything moving at constant speed along a spline needs these. |
| **Unique animation clip names per instance** (`sink$id`) | Tidewatch | small | `AnimationPlayer` keys by clip name, so playing one clip on two targets replaces the first. Return a playback handle instead. |

### App shell

| What I wrote | Where | Size | What the renderer could do |
| --- | --- | --- | --- |
| **A frame-error guard**: try/catch around `onFrame`, report once | All three | ~10 lines ×3 | Fix O1, and add `app.onError` |
| **Load-error and no-WebGL2 cards** | All three | ~10 lines ×3 | Optional: `mount(..., onUnavailable:)`. Mostly the host's job. |
| **Sound** (`HTMLAudioElement` voice pools) and **HUD** | All three | ~60 + ~70 lines ×3 | Out of scope for a renderer, but a tiny companion package (`pixeldart_audio`) would remove a copy-paste every host makes |

## 5. Papercuts and conventions

- **Handedness is undocumented**, and was inconsistent before F1. Document the world convention (right-handed, Y up, the camera looks down its −Z) and which way `Primitives.quad`, `cone` and `cylinder` face. I lost time finding that cylinders and tori are Y-axis and that the cone's apex is +Y.
- **`Transform` has uniform scale only.** A light beam that has to lengthen without widening, or a non-square slab, needs its own mesh, or a cone whose width grows with its length. Non-uniform scale (with a correct normal matrix) would remove those workarounds.
- **`app.onFrame` runs after emitters have updated and submitted.** Moving an emitter in `onFrame` therefore takes effect a frame late. A `beforeFrame` hook, or documenting the order, would help.
- **`PostProcessState` presets are factories.** Layering a temporary effect, such as a VHS hit glitch or an exposure fade, needs `copyWith` on every frame. That works, but a stack of named overrides would be cleaner.
- **`SceneNode.add(...)` takes `meshData`**, and bounds come from it. Easy to forget, and without it picking and culling quietly lose their bounds.
- **`sortTiebreaker` is overloaded** as "material index" in decoded GLB trees. That's surprising, and it collides with its real meaning.
- **`showStats: true`** draws an overlay I didn't think to use. If the README promoted it as the first debugging step, it might have shortened the F1 hunt, since draw counts would have shown the terrain being submitted.
- **README quickstart:** the example `forward: Vec3(0, 0, -1)` was mirrored before F1. It is correct now; it's worth saying explicitly what it produces.

## 6. Debuggability, in hindsight

Where my time went, roughly ordered by cost:

1. **F1 (mirrored `lookAt`), about 40% of all debugging.** It showed up as three unrelated mysteries in three games:
   - "rate-driven particle emitters don't render" in Pixel Rocket, which I wrongly blamed and worked around with a mesh flame;
   - "disc caps render their back side" in Lantern, which I worked around with a custom view matrix;
   - "terrain and water don't draw" in Tidewatch.

   Only the third was blatant enough to point at the camera. A single "back-facing triangles culled this frame" counter in `FrameStats`, or the regression test from section 3, would have caught it in minutes.
2. **The emissive and glow pair (O2, O3)**, about 15%. Silent: materials simply didn't glow, and particles bloomed square.
3. **GLB tangent validation (F2, F3)**, about 10%. This one was loud and well located. Strict validation earned its keep here; the decoder just needs to produce valid data.
4. **The frame-loop freeze (O1)**, about 10%. Intermittent, and invisible under `-O2`. It needed unminified builds and window error hooks to see the message.
5. Everything else (skybox validation, horizon seam, volumetric banding, removeChild leak, invisible-until-moved visibility changes) was minor once spotted.

**The pattern:** loud failures (validation) cost minutes, and silent failures (rendering) cost hours. The cheapest big win is to make the render path tell you when something you submitted didn't contribute pixels: culled, back-facing, zero alpha, zero emissive, over the light limit. Debug-build warnings, or counters in `FrameStats`, would do it.

## 7. Recommendations, prioritized

**P0: correctness and resilience**
1. Add the F1 regression tests (view determinant, screen-right axis, a single-sided camera-facing plane produces pixels). Re-verify the showcase and README captures.
2. Make `PixeldartApp` survive exceptions: guard the whole tick, always schedule the next frame, add `onError` (O1). Degrade on degenerate scale instead of throwing (O5).
3. Make emissive work without a map (O2), and multiply glow by alpha on blended draws (O3).
4. Make detaching a node remove its draw items (O4).

**P1: remove the boilerplate every game writes**
5. A reusable `ModelAsset` with `instantiate()`, resolution of external URIs, `KHR_materials_unlit`, and material override hooks. Fix `loadGlb` mesh assignment (O6).
6. Inherited, dirty-tracked visibility (`node.visible`). Mark the node dirty when its `material` or `visibilityMask` changes.
7. `CameraView.orthographic` and an ortho controller. A shake engine that works for any projection (O9).
8. `emitAt(position, perSecond, dt)` on emitters, and a `ParticleMaterial.soft` preset. Implement or remove `colorGradient` (O7).
9. Arc-length API on `CatmullRomSpline3D`. `app.screenRay` and `Ray.intersectPlane`. Click-versus-drag pointer events.
10. `SkyboxDeclaration.copyWith`, and a fog-coherent horizon option for `setSolarTime`.

**P2: polish**
11. Point-light overflow warning or auto-ranking (O8). Volumetric step jitter (O10).
12. Validation messages that name the field and its range (O11).
13. Non-uniform scale.
14. A conventions page (handedness, primitive orientation, the emissive model, culling, frame order) and a "debugging a blank or black frame" checklist that starts with `showStats`.

## Appendix: workarounds in `examples/` that can go once these are fixed

| Workaround | Where | Remove after |
| --- | --- | --- |
| White emissive texture | Lantern, Tidewatch | O2 |
| Black-edged particle texture used as the emissive map | All three | O3 (it's still a fine default) |
| `_stream()` burst accumulator | Lantern, Tidewatch | `emitAt` API (rate emitters do render correctly now that F1 is fixed) |
| `setVisible()` helper | All three | Inherited visibility |
| `prefab.dart` / `model.dart` | Pixel Rocket, Tidewatch | `ModelAsset` |
| `kenneySurface` material override | Pixel Rocket | `KHR_materials_unlit` support |
| try/catch around `onFrame` | All three | O1 |
| Mesh-cone engine flame instead of exhaust particles | Pixel Rocket | Nothing: F1 already fixed the real cause, so particles would work again |
| Sky, fog and clear color syncing | Tidewatch | Coherent-horizon option |
| `Lane` arc-length class | Tidewatch | Spline arc-length API |
| Custom orthographic camera | Lantern | `CameraView.orthographic` (keep it if you prefer explicit) |

## Addendum: performance and play-testing (round 4)

- **Performance was dominated by one renderer bug, not by game code.** Looking up uniform locations by name on every set cost a third of frame CPU in every game. With the cache, plus a fused wave pass, single-buffer model matrices and no per-frame forced layout, main-thread busy time fell:
  - Pixel Rocket: 43% → 24%;
  - Lantern: 17% → 10%;
  - Tidewatch: 68% → 23%.

  All three now hold a 60 Hz cadence with headroom.
- **Play-testing found what the fixtures could not.** The fallback sky shaded by screen position. A camera looking down at the sea therefore painted zenith colour over geometry the fog had already turned into "background", which left a hard band on the horizon. The night fog was also built from the sun's transmittance below the horizon. Neither shows in a unit test: both needed a person, or a screenshot, at 23:00. Pixel probes of the screenshot were essential. Hiding one node at a time (the sea, then the volumetrics) is what separated geometry from post-processing.
- **One more piece of boilerplate the renderer should own:** world-to-screen projection. `app.worldToClient` now exists. Without it, a game can't put a label over a ship, and a test can't click one.
