part of '../../engine.dart';

/// Cascaded shadow map split, texel-snapped ortho bounds & PCSS rig (`voxshadow`) (E85-2).
final class CascadedShadowRigComponent extends Behaviour {
  int cascadeCount;
  int shadowMapResolution;
  double splitLambda;
  double maxShadowDistance;
  bool snapToTexels;
  double lightWorldRadius;
  int pcfSampleCount;
  bool autoRebuildOnUpdate;
  bool syncEnvironmentSettings;

  Camera? targetCamera;
  Light? targetLight;

  List<shadow.ShadowCascadeSplit> splits = const [];
  List<shadow.FittedCascadeOrtho> cascades = const [];
  late shadow.PcssKernelTable pcssKernel;

  CascadedShadowRigComponent({
    this.cascadeCount = 4,
    this.shadowMapResolution = 1024,
    this.splitLambda = 0.65,
    this.maxShadowDistance = 120.0,
    this.snapToTexels = true,
    this.lightWorldRadius = 0.5,
    this.pcfSampleCount = 16,
    this.autoRebuildOnUpdate = true,
    this.syncEnvironmentSettings = true,
    this.targetCamera,
    this.targetLight,
  }) {
    pcssKernel = shadow.PcssKernelTable.vogelDisk(sampleCount: pcfSampleCount);
  }

  static final spec = ComponentSpec<CascadedShadowRigComponent>(
    'CascadedShadowRigComponent',
    CascadedShadowRigComponent.new,
    [
      Field.integer('cascadeCount', (c) => c.cascadeCount, (c, v) => c.cascadeCount = v),
      Field.integer(
        'shadowMapResolution',
        (c) => c.shadowMapResolution,
        (c, v) => c.shadowMapResolution = v,
      ),
      Field.number('splitLambda', (c) => c.splitLambda, (c, v) => c.splitLambda = v),
      Field.number(
        'maxShadowDistance',
        (c) => c.maxShadowDistance,
        (c, v) => c.maxShadowDistance = v,
      ),
      Field.boolean('snapToTexels', (c) => c.snapToTexels, (c, v) => c.snapToTexels = v),
      Field.number(
        'lightWorldRadius',
        (c) => c.lightWorldRadius,
        (c, v) => c.lightWorldRadius = v,
      ),
      Field.integer('pcfSampleCount', (c) => c.pcfSampleCount, (c, v) => c.pcfSampleCount = v),
      Field.boolean(
        'autoRebuildOnUpdate',
        (c) => c.autoRebuildOnUpdate,
        (c, v) => c.autoRebuildOnUpdate = v,
      ),
      Field.boolean(
        'syncEnvironmentSettings',
        (c) => c.syncEnvironmentSettings,
        (c, v) => c.syncEnvironmentSettings = v,
      ),
    ],
  );

  Camera? _resolveCamera() {
    if (targetCamera != null) return targetCamera;
    if (!isAttached || !scene.isLoaded) return null;
    return Camera.of(scene);
  }

  Light? _resolveDirectionalLight() {
    if (targetLight != null) return targetLight;
    if (!isAttached || !scene.isLoaded) return null;
    for (final l in scene.findObjectsOfType<Light>()) {
      if (l.isActiveAndEnabled && l.type == LightType.directional) {
        return l;
      }
    }
    return null;
  }

  /// Computes practical splits and texel-snapped light ortho matrices for all cascades.
  List<shadow.FittedCascadeOrtho> rebuildCascades({double? aspectRatioOverride}) {
    final cam = _resolveCamera();
    final light = _resolveDirectionalLight();

    final camNear = math.max(0.05, cam?.near ?? 0.1);
    final camFar = math.max(camNear + 1.0, math.min(cam?.far ?? maxShadowDistance, maxShadowDistance));
    final fovY = cam?.fovYRadians ?? 1.0;

    var aspect = aspectRatioOverride ?? (16.0 / 9.0);
    if (aspectRatioOverride == null && isAttached && scene.isLoaded) {
      final vw = engine.graphics.viewportWidth;
      final vh = engine.graphics.viewportHeight;
      if (vw > 0 && vh > 0) aspect = vw / vh;
    }

    final camPos = cam != null && cam.isAttached ? cam.transform.position : Vec3.zero;
    final camFwd = cam != null && cam.isAttached ? cam.transform.forward : kForward;
    final camUp = cam != null && cam.isAttached ? cam.transform.up : kUp;

    final lFwdVec = light != null && light.isAttached
        ? light.transform.forward
        : (isAttached ? transform.forward : const Vec3(0.4, -0.85, -0.34).normalized);

    splits = shadow.ShadowCascadeSplitter.computeSplits(
      nearPlane: camNear,
      farPlane: camFar,
      cascadeCount: cascadeCount,
      lambda: splitLambda,
    );

    final sCamPos = shadow.ShadowVec3(camPos.x, camPos.y, camPos.z);
    final sCamFwd = shadow.ShadowVec3(camFwd.x, camFwd.y, camFwd.z);
    final sCamUp = shadow.ShadowVec3(camUp.x, camUp.y, camUp.z);
    final sLightFwd = shadow.ShadowVec3(lFwdVec.x, lFwdVec.y, lFwdVec.z);

    cascades = [
      for (final split in splits)
        shadow.LightOrthoFitter.fitCascade(
          cameraPosition: sCamPos,
          cameraForward: sCamFwd,
          cameraUp: sCamUp,
          fovYRadians: fovY,
          aspectRatio: aspect,
          splitNear: split.nearPlane,
          splitFar: split.farPlane,
          lightForward: sLightFwd,
          shadowMapResolution: shadowMapResolution,
          snapToTexels: snapToTexels,
        ),
    ];

    if (pcssKernel.taps.length != pcfSampleCount.clamp(1, 128)) {
      pcssKernel = shadow.PcssKernelTable.vogelDisk(sampleCount: pcfSampleCount);
    }
    if (syncEnvironmentSettings && isAttached && scene.isLoaded) {
      final baseTexel = cascades.isNotEmpty ? cascades.first.texelWorldSize : 0.05;
      scene.renderSettings
        ..shadowFilterRadius = lightWorldRadius.clamp(0.0, 3.0)
        ..shadowBias = (baseTexel * 0.008).clamp(0.0005, 0.01);
    }
    return cascades;
  }

  double estimatePenumbra({
    required double receiverDepth,
    required double averageBlockerDepth,
  }) =>
      shadow.PcssKernelTable.estimatePenumbraWidth(
        receiverDepth: receiverDepth,
        averageBlockerDepth: averageBlockerDepth,
        lightWorldRadius: lightWorldRadius,
      );

  @override
  void update() {
    if (!autoRebuildOnUpdate) return;
    rebuildCascades();
  }
}

/// Persistent UI state for [ShadowCascadeInspectorUI.render].
final class ShadowCascadeInspectorUiState {
  String? activeButtonId;
}

/// Immediate-mode `voxui` cascaded shadow split & texel-snap inspector (E85-2).
final class ShadowCascadeInspectorUI {
  static bool _drawButton(
    VoxUiContext ui,
    ShadowCascadeInspectorUiState state,
    String id,
    String label,
    VoxRect rect,
  ) {
    final inp = ui.input;
    final dl = ui.drawList;
    final hovered = rect.contains(inp.mouseX, inp.mouseY);
    if (hovered && inp.wasMouseClicked) state.activeButtonId = id;
    final pressed = hovered && state.activeButtonId == id && inp.isMouseDown;
    final clicked = hovered && state.activeButtonId == id && inp.wasMouseReleased;
    if (inp.wasMouseReleased && state.activeButtonId == id) {
      state.activeButtonId = null;
    }

    final bg = pressed
        ? ui.style.buttonActive
        : (hovered ? ui.style.buttonHover : ui.style.buttonBg);
    dl.addRectFilled(
      rect.x,
      rect.y,
      rect.width,
      rect.height,
      bg,
      cornerRadius: ui.style.frameRounding,
    );
    dl.addRectOutline(
      rect.x,
      rect.y,
      rect.width,
      rect.height,
      ui.style.windowBorder,
      cornerRadius: ui.style.frameRounding,
    );
    final textW = label.length * (ui.style.fontSize * 0.6);
    dl.addText(
      label,
      rect.x + math.max(4.0, (rect.width - textW) * 0.5),
      rect.y + (rect.height - ui.style.fontSize) * 0.5,
      color: ui.style.text,
      size: ui.style.fontSize,
    );
    return clicked;
  }

  static void render(
    VoxUiContext ui,
    CascadedShadowRigComponent rig, {
    ShadowCascadeInspectorUiState? state,
    String title = 'Shadow Cascades',
    double x = 20.0,
    double y = 20.0,
    double width = 415.0,
    double height = 245.0,
  }) {
    final uiState = state ?? ShadowCascadeInspectorUiState();
    if (!ui.beginWindow(title, x: x, y: y, width: width, height: height)) {
      ui.endWindow();
      return;
    }

    final pad = ui.style.windowPadding;
    ui.labelValue(
      'Cascades / Res',
      '${rig.cascadeCount}x @ ${rig.shadowMapResolution}px | lambda ${rig.splitLambda.toStringAsFixed(2)}',
      valueColor: VoxColor.cyan,
    );
    final c0Texel = rig.cascades.isNotEmpty
        ? '${rig.cascades.first.texelWorldSize.toStringAsFixed(3)}m'
        : 'unbuilt';
    ui.labelValue(
      'Texel Snap / C0',
      '${rig.snapToTexels ? 'On' : 'Off'} | texel $c0Texel',
      valueColor: rig.snapToTexels ? VoxColor.green : VoxColor.yellow,
    );
    final maxFar = rig.splits.isNotEmpty ? rig.splits.last.farPlane.toStringAsFixed(1) : '-';
    ui.labelValue(
      'Max Dist / PCSS',
      '${maxFar}m | ${rig.pcssKernel.taps.length} Vogel taps',
      valueColor: VoxColor.lightGray,
    );
    ui.labelValue(
      'Light Radius',
      '${rig.lightWorldRadius.toStringAsFixed(2)}m | Auto ${rig.autoRebuildOnUpdate ? 'On' : 'Off'}',
      valueColor: VoxColor.yellow,
    );

    final barY = y + ui.style.titleBarHeight + pad + 92.0;
    final snapRect = VoxRect(x + pad, barY, 78.0, 22.0);
    if (_drawButton(ui, uiState, 'csm_snap', rig.snapToTexels ? 'Snap: On' : 'Snap: Off', snapRect)) {
      rig.snapToTexels = !rig.snapToTexels;
      rig.rebuildCascades();
    }

    final incRect = VoxRect(snapRect.right + 8.0, barY, 92.0, 22.0);
    if (_drawButton(ui, uiState, 'csm_inc', 'Cascades +1', incRect)) {
      rig.cascadeCount = rig.cascadeCount >= 6 ? 1 : rig.cascadeCount + 1;
      rig.rebuildCascades();
    }

    final lamRect = VoxRect(incRect.right + 8.0, barY, 92.0, 22.0);
    if (_drawButton(ui, uiState, 'csm_lam', 'Lambda +0.1', lamRect)) {
      rig.splitLambda = ((rig.splitLambda + 0.1) > 1.0 ? 0.1 : rig.splitLambda + 0.1);
      rig.rebuildCascades();
    }

    final rebRect = VoxRect(lamRect.right + 8.0, barY, 78.0, 22.0);
    if (_drawButton(ui, uiState, 'csm_reb', 'Rebuild', rebRect)) {
      rig.rebuildCascades();
    }

    ui.endWindow();
  }
}
