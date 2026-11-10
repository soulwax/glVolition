# TODO

The honest gap list between "the pipeline renders and is proven" and "a library
strangers can depend on." Ordered roughly by leverage. Items marked **(spec'd)**
have a detailed design already; they are unbuilt, not undesigned.

The renderer-focused sequence is in [PLAN.md](PLAN.md). Shader overrides,
per-draw shader selection, anisotropy negotiation, and capability-driven MSAA
have working APIs and pure fixtures. The open work includes a declared host
graph-pass API, browser color-space verification, texture quality and GPU-time
comparisons, MSAA resize/restore coverage, CI, and browser baselines.
Example-specific acceptance is tracked below.

## Example follow-up

- [ ] **Procession dense trees.** Reproduce the reported chopped/fragmented
      grove, correct the overlap or clipping issue, and visually verify a dense
      layout in both browser and Windows builds. Rebuild the canonical
      `pixeldart/examples/example_4/build/Procession.exe` and run its `--self-test`.

## Public API surface

- [x] **Built-in shader overrides.** Named `ShaderSlot`s accept host vertex or
      fragment GLSL through `PixeldartApp.mount`/`mount2d` and low-level
      `RendererConfiguration`; missing stages use defaults. `setShader` keeps
      the old graph on compile failure, startup falls back with `shaderErrors`,
      and context restoration recompiles the override. Pure tests cover these.
- [ ] **Complete host shader API.** The [slot contract](pixeldart/docs/shader_overrides.md)
      documents default stages, vertex inputs, sampler units and outputs;
      duplicate program IDs, mismatched fragment outputs, attribute layouts,
      uniform types and stage varyings are rejected. Typed host uniforms and
      textures, `ShaderOverride.effect` and `pdTime`/`pdResolution` are done
      and verified on D3D11 (generated GLSL, live uniforms, host textures,
      snippet line numbers, 0 GL errors). A `present` override now has a
      browser readback against the built-in control on Edge/D3D11 (RGBA
      `0,14,104,255` versus `64,128,191,255`, 0 GL errors);
      other slots and color-space paths still need live fixtures. Per-material
      world shaders, per-draw sprite shaders and host
      post-effect stacks are implemented; the sprite and post paths were
      verified on D3D11, while the world shader path has pure fixtures.
- [x] **Shader-only reload without target churn.** A valid between-frame
      override compiles only changed installed programs and updates pass-owned
      references in place. Failures preserve the live handles and graph.
- [x] **Anisotropy result by texture handle.** Requests, clamping and the
      portable 1× fallback are reported through the public resource API;
      context restoration refreshes the effective value.
- [ ] **Anisotropy quality/cost evidence.** Benchmark an oblique mipmapped
      surface before raising any default above 1× for perspective textures.
- [x] **Capability-driven MSAA policy.** `MsaaStatus`, `renderer.msaa`, and
      `app.setSampleCount` report and change the sample request. The renderer
      clamps to `maxSamples`, steps down on incomplete framebuffers, and
      renegotiates on restore. 1× allocates no multisample target or resolve.
- [ ] **MSAA acceptance and default.** The 4× `ps1Full` and `clean` D3D11
      smoke check produced correct pixels and no GL errors. Check resize and
      context restoration live, then measure 1×/2×/4× before changing the
      high-profile default.

The facade and safe/minimal/clean profile transitions below are implemented;
the remaining unchecked items are the next capability and acceptance gaps.

- [x] **Implement `SceneRenderer`.** The interface exists (`initialize` /
      `configure` / `resize` / `beginFrame` / `endFrame` / `abortFrame` /
      `dispose`) and the concrete facade now owns the reusable lifecycle; the
      feature graph and passes directly. The standalone graph remains useful
      for feature-level fixtures.
      **(spec'd)**
- [x] **`configure()` as an atomic between-frame graph rebuild** — prepare a
      full replacement feature set, swap between frames, reset temporal
      history; never compile or allocate from `beginFrame`. **(spec'd)**
- [x] **`dispose()` with exact accounting** — releasing every owned CPU and GPU
      resource, provable by diagnostics returning to the pre-renderer
      baseline.
- [x] **Enforce the `RenderEncoder` lifecycle at runtime** — both transient
      encoder implementations now reject stale submissions after `endFrame` /
      `abortFrame`, with focused active/end/abort coverage.
- [x] **`TextureStore`.** The store now owns declared textures, fallback
      resolution, pixel uploads, and context-restore rehydration. Descriptor
      validation rejects invalid mip filters before allocation, and
      non-power-of-two textures use the correct mip count.
- [x] **Per-instance transforms.** Each member of an instanced batch draws
      with its own model and normal matrix (`uInstanceModels` /
      `uInstanceNormalMatrices`, indexed by `gl_InstanceID`; see
      `core/instance_transforms.dart`). Batches cap at
      `InstanceBatch.maxInstanceCount` (16) uniforms.
- [ ] **Instance streaming beyond the uniform cap.** Stream per-instance
      attributes from a persistent buffer, so large batches don't split
      every 16 members.
- [ ] **Optional module work still unbuilt:** `core/frame_arena`,
      `core/dynamic_batch`, and `webgl/frame_targets`. Resource-library and
      texture-store ownership already exist as `core/resource_library_impl.dart`
      and `assets/texture_store.dart`; the original proposed file paths are
      no longer a gap.

## Graph and pass system

- [x] **Express MSAA resolve as a graph stage.** `MsaaResolveFeature` declares
      `isResolve: true` and has graph ordering tests.
- [x] **Attachment-aware MSAA resolve.** The resolve target
      holds color, glow only when bloom is installed, and never depth; the
      WebGL resolve blits only attachments both sides own. The fake device
      fixtures cover it, and a D3D11 run at 4× with `ps1Full` and `clean`
      gave correct pixels and 0 GL errors. Resize and restore acceptance is
      tracked above.
- [x] **Profile exclusion ("owns zero targets").** safe/minimal/clean install
      only selected features. An excluded feature compiles no program,
      allocates no target, and adds no pass. `test_profile_resources` covers
      this ownership boundary. **(spec'd)**
- [x] **Extend zero-cost-off to grade, PS1 quantize, and VHS.** At identity
      weights they forward their input through a per-graph `PostChain`
      instead of drawing. No copy path was needed. `test_post_chain` covers
      it. The work also fixed VHS through `SceneRenderer`: it failed graph
      validation, and it sampled its own render target. It now ping-pongs
      `vhsOutput`/`vhsHistory`.
- [x] **Skippable DOF composite.** Same `PostChain` mechanism: at strength
      ≤ 0.0001 the sharp input is forwarded.
- [ ] **Repo-wide `dart format`.** The planned whole-package formatting gate
      has not been run cleanly. Do it as one formatting-only commit while no
      parallel branch is editing those files.
- [x] **Guard against program-id collisions.** Passes use `publishNew`, which
      rejects an installed ID before compiling; `publishVariant` does the same
      and rejects a reused shader target. Intentional `publish`/`tryReload`
      replacements remain available. A two-graph fixture proves the first
      program stays live when a second graph shares its library.
- [ ] **Reconcile the safe-graph shape.** Spec says three passes
      (opaque → transparent → present); the built graph validates with two,
      handling blended items inside the world pass. Decide which is canonical.
- [ ] **Stencil state** — absent from `DrawStateDescriptor` entirely.
- [ ] **Decal stage** between world-opaque and transparents. **(spec'd)**

## Lighting and shadows

- [x] **Bounded direct lights.** The shadowed world uses up to four point
      lights, three non-casting spot lights, and one shadow-casting spot light.
      Overflow selection ranks by influence with stable-ID tie-breaking.
- [ ] **Per-draw light selection and diagnostics.** Choose a bounded subset
      for each draw and report submitted, selected, and rejected lights;
      selection is currently frame/camera based. **(spec'd)**
- [ ] **Multiple shadow casters + capability-driven shadow resolution**
      (512²/two casters standard, 256²/three casters fallback), with caster
      priority/influence selection surfaced in diagnostics. **(spec'd)**
- [ ] **Directional-light shadows** (spot-only today; point-light cube shadows
      are explicitly out of scope for v1).
- [x] **Static shadow caching** — done: the whole map is reused while the
      light and its draw list match the previous frame exactly; verified on
      D3D11. Partial caching (static casters only, with movers redrawn on
      top) is still open. Original: cache static casters, invalidate on
      moving caster/light or changed geometry.
- [ ] **Front-face culling during the shadow/depth pass.**
- [ ] **Debug views** beyond linearized depth: normals, direct, ambient,
      shadow factor, material, fog factor, light volumes.

## Materials and textures

- [x] **Verify `uvOffset` live.** On real hardware (D3D11), shifting U by
      half a repeat swaps the halves of a 2×2 nearest-filtered checker
      exactly. The other material slots are verified in the examples:
      tiled normal-mapped floors in Lantern and palette-textured GLBs in
      Tidewatch.
- [ ] **Material table capacity splitting** — deterministic per-batch material
      tables that split a batch at UBO/texture-table capacity instead of
      dropping materials. **(spec'd)**
- [ ] **Texture array groups** — device support exists, but no array-group
      aggregation, layer-order validation, or catalog.
- [ ] **A real LUT asset + loader** — only a procedurally built demo LUT
      exists.
- [x] **Visually confirm `doubleSided`.** Live, on D3D11, with a quad turned
      away from the camera: the single-sided one is culled and the
      double-sided one draws. The check found a bug, now fixed: back faces
      were lit with the front normal, so a matte back face rendered at 119
      against the front's 173. The world shaders now reverse the normal on
      back faces (normal map included), giving 172 vs 173.
      `test_lighting_shader_contract` guards the fix.
- [ ] **Alpha-mask × affine interaction fixture** — masking cuts out against
      the prepass while affine warps the world-pass UVs; add a fixture proving
      the two gates compose without cutout/shading divergence.

## PS1 treatment (remaining pieces)

- [ ] **Vertex lighting** — move N·L/shadow/ambient to per-vertex under the
      PS1 profile. Riskiest remaining piece: must be gated so the confirmed
      per-fragment look is untouched when off.
- [ ] **Fixed low internal resolution** — internal resolution currently tracks
      the canvas; fixing it (e.g. 384×216 + NEAREST upscale) touches sizing on
      nearly every target. Deserves a dedicated pass.
- [ ] **Affine UV in the textured/safe world programs** (currently only the
      shadowed world path), and decide what affine means for mip selection.

## Color

- [ ] **Linear/sRGB audit.** The renderer shades and grades in display-referred
      values with no explicit final encode — documented as the de facto
      convention rather than reworked. Needed before PBR or HDR-authored
      assets make sense.

## Determinism, comfort, accessibility

- [ ] **Temporal-determinism tests** — pin time/seed/input-sequence/epoch and
      prove byte-identical RGBA across 120 frames with temporal effects off.
      VHS noise is currently seeded by raw `uTime`/`gl_FragCoord`, un-pinned.
- [ ] **Exercise `reducedMotion` live** — implemented, but no demo toggle
      flips it.
- [ ] **A real photosensitivity/luminance comfort gate** — current comfort
      clamps (DOF focus range, VHS tracking ceiling, fog onset) are hand-picked
      magnitudes, not tested against a documented contract.
- [ ] **Visual-stability gates** — no mostly-black frames over 600 frames, no
      NaN/inf reaching a uniform or target, no full-frame luminance collapse.

## Robustness (proven pure, not yet proven live)

- [x] **Real context loss/restore in a browser.** 10 forced
      `WEBGL_lose_context` cycles on real hardware (D3D11), on the minimal
      host, the showcase and two examples, end with no WebGL errors and a
      fully rendered frame. The first run found three bugs, all fixed:
      - a loss and restore between frames was never noticed, so the renderer
        drew with dead objects (now `GpuContextGeneration`);
      - extensions weren't re-enabled, which broke the timer queries;
      - handles from the lost context were still being deleted.

      The pure fixture in `test_scene_renderer` covers the unobserved case.
- [x] **Real canvas resize/DPR change.** 100 live cycles over sizes from
      320 to 1420 px and DPR 1 to 2 keep the backing store exact
      (`css × min(dpr, cap)`), on the minimal host and the showcase. The first
      run found that a DPR change without a CSS resize was ignored; that is
      fixed (`SurfaceMetrics.resized(devicePixelRatio:)`).
- [x] **Steady-state no-allocation assertion.**
      `tools/renderer/test_no_allocation_trace.dart` checks 100 warm frames for
      stable GPU/resource counts and balanced delayed timer samples.
- [x] **Draw-count assertions for skip paths.** `test_zero_cost` checks that
      SSAO, bloom, and DOF blur skip at zero strength. `test_post_chain`
      checks that the integrated graph forwards identity DOF composite,
      grade, PS1, and VHS inputs without drawing. Standalone passes with no
      `PostChain` still draw because they have no forwarding context.

## Verification infrastructure

- [ ] **Renderer lab** — a browser verification runner: URL-selected fixtures
      and profiles, final offscreen `readPixels` evidence (never OS
      screenshots — a recorded incident showed a false cyan capture while the
      framebuffer readback was neutral), golden/diff artifacts, console and
      WebGL error capture, adapter proof that rejects software renderers,
      built from Node built-ins only. The first built-in/overridden `present`
      fixtures and Node/CDP runner record pixels, GL/JavaScript errors and
      adapter identity; other slots, goldens and performance
      protocol remain. Twenty fixtures are already enumerated, from an unlit
      triangle through forced context loss. **(spec'd)**
- [ ] **Golden + perf baseline system** — keyed by fixture/browser/adapter/
      profile/resolution; SSIM ≥ 0.995 for shaded goldens on a pinned
      adapter, semantic probes across vendors.
- [ ] **Ratify the performance budget table.** Proposed and never measured:
      60 Hz; CPU submit p95 ≤ 4 ms; GPU p95 ≤ 12 ms; ≤ 40 draws for a
      representative two-room scene; ≤ 64 MiB GPU resources. Measure on real
      hardware (180 warm-up frames, ≥ 600 measured, three runs, medians),
      then change numbers only with recorded evidence.
- [ ] **Full diagnostics snapshot** — per-pass CPU time, GPU timer queries
      (async, keyed to source frame, disjoint results discarded), draw/
      triangle/cull/batch counts, target formats and completeness, live+peak
      bytes by kind, context-loss counts, offscreen readback hook. **(spec'd)**
- [ ] **Culling and instancing acceptance by pixels** — both are proven at the
      visible-list level; the metamorphic contract (identical pixels with
      culling on/off, individual vs. instanced) has never run as a pixel
      comparison, and culling's net CPU value has never been measured.
- [ ] **CI** — GitHub Actions running the static gate: `dart format
      --set-exit-if-changed`, `dart analyze`, `test_all`, `check_boundary`,
      `shaders.dart --check`.

## Asset pipeline

- [ ] **Run QMSH through the real GPU path** — the decoder is proven against
      all corruption fixtures, but the demo builds `MeshData` in Dart; no real
      QMSH bytes have ever reached a live draw.
- [ ] **An OBJ → QMSH producer** (none exists here, by prior design).
- [ ] **Model catalog / sidecar validation** — schema, provenance and license
      checks, deterministic source hashing, turntable capture. **(spec'd)**
- [ ] **Soft particles** — depth-fade blended particles against scene depth.
- [ ] **Transient stress story** — six motes is not a stress test; no culling
      or instancing path exists for large transient counts, and transient
      bounds are a fixed radius, not mesh-accurate.

## Housekeeping

- [ ] Decide package publication (currently `publish_to: none`) and, if
      publishing, split the demo out of the package.
- [x] **Example code for hosts:** `examples/` holds four complete games on
      the public API, linked from the README.
