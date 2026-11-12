part of '../../engine.dart';

/// Distance-based shadow caster LOD & hysteresis controller backed by
/// `pixeldart`'s [ShadowCasterLodPolicy] (E102).
final class ShadowCasterLodComponent extends Behaviour {
  double fullToReduced;
  double reducedToCulled;
  double hysteresisDistance;
  bool applyToTarget;

  MeshHandle? fullMesh;
  MeshHandle? reducedMesh;
  MeshRenderer? targetRenderer;

  ShadowCasterLod currentLod = ShadowCasterLod.full;
  ShadowCasterLod? forcedLod;
  double lastDistance = 0.0;

  ShadowCasterLod? _previousLod;
  bool? _originalCastsShadow;
  MeshHandle? _originalMesh;

  ShadowCasterLodComponent({
    this.fullToReduced = 8.0,
    this.reducedToCulled = 20.0,
    this.hysteresisDistance = 1.0,
    this.applyToTarget = true,
    this.fullMesh,
    this.reducedMesh,
    this.targetRenderer,
    this.forcedLod,
  });

  static final spec = ComponentSpec<ShadowCasterLodComponent>(
    'ShadowCasterLodComponent',
    ShadowCasterLodComponent.new,
    [
      Field.number(
        'fullToReduced',
        (c) => c.fullToReduced,
        (c, v) => c.fullToReduced = v,
      ),
      Field.number(
        'reducedToCulled',
        (c) => c.reducedToCulled,
        (c, v) => c.reducedToCulled = v,
      ),
      Field.number(
        'hysteresisDistance',
        (c) => c.hysteresisDistance,
        (c, v) => c.hysteresisDistance = v,
      ),
      Field.boolean(
        'applyToTarget',
        (c) => c.applyToTarget,
        (c, v) => c.applyToTarget = v,
      ),
      Field.boolean('enabled', (c) => c.enabled, (c, v) => c.enabled = v),
    ],
  );

  /// Validated [ShadowCasterLodPolicy] built from the current thresholds.
  ShadowCasterLodPolicy get policy {
    final safeFull =
        fullToReduced.isFinite && fullToReduced > 0.0 ? fullToReduced : 0.01;
    final safeReduced =
        reducedToCulled.isFinite && reducedToCulled > safeFull
            ? reducedToCulled
            : safeFull + 0.01;
    final safeHyst =
        hysteresisDistance.isFinite && hysteresisDistance >= 0.0
            ? hysteresisDistance
            : 0.0;
    return ShadowCasterLodPolicy(
      fullToReduced: safeFull,
      reducedToCulled: safeReduced,
      hysteresisDistance: safeHyst,
    );
  }

  MeshRenderer? _resolveTargetRenderer() {
    if (targetRenderer != null) return targetRenderer;
    if (!isAttached || isDestroyed) return null;
    return getComponent<MeshRenderer>();
  }

  Vec3 _resolveReferencePoint() {
    if (!isAttached) return Vec3.zero;
    final pos = transform.position;

    Light? nearestSpot;
    var bestSpotDistSq = double.infinity;
    Light? nearestOther;
    var bestOtherDistSq = double.infinity;

    for (final light in scene._lights) {
      if (!light.isActiveAndEnabled || light.isDestroyed) continue;
      if (light.type == LightType.directional) continue;
      final dSq = (light.transform.position - pos).lengthSquared;
      if (light.type == LightType.spot) {
        if (dSq < bestSpotDistSq) {
          bestSpotDistSq = dSq;
          nearestSpot = light;
        }
      } else {
        if (dSq < bestOtherDistSq) {
          bestOtherDistSq = dSq;
          nearestOther = light;
        }
      }
    }

    if (nearestSpot != null) return nearestSpot.transform.position;
    if (nearestOther != null) return nearestOther.transform.position;

    final cam = Camera.of(scene);
    if (cam != null && cam.isAttached && !cam.isDestroyed) {
      cam._sync();
      return cam.controller.eye;
    }
    return Vec3.zero;
  }

  /// Evaluates distance to the reference light/camera, selects the next
  /// [ShadowCasterLod] with hysteresis, and optionally applies it to the
  /// target [MeshRenderer].
  void evaluateNow() {
    if (isDestroyed) return;
    if (!isAttached) {
      if (forcedLod != null) {
        _previousLod = forcedLod;
        currentLod = forcedLod!;
      }
      return;
    }
    final refPoint = _resolveReferencePoint();
    final distance = (transform.position - refPoint).length;
    lastDistance = distance;

    final selected =
        forcedLod ?? policy.select(distance, previous: _previousLod);
    _previousLod = selected;
    currentLod = selected;

    if (!applyToTarget) return;
    final renderer = _resolveTargetRenderer();
    if (renderer == null || renderer.isDestroyed) return;

    _originalCastsShadow ??= renderer.castsShadow;
    _originalMesh ??= renderer.mesh;

    switch (selected) {
      case ShadowCasterLod.full:
        renderer.castsShadow = _originalCastsShadow ?? true;
        if (fullMesh != null) {
          renderer.mesh = fullMesh;
        } else if (_originalMesh != null) {
          renderer.mesh = _originalMesh;
        }
      case ShadowCasterLod.reduced:
        renderer.castsShadow = _originalCastsShadow ?? true;
        if (reducedMesh != null) {
          renderer.mesh = reducedMesh;
        }
      case ShadowCasterLod.culled:
        renderer.castsShadow = false;
    }
  }

  @override
  void lateUpdate() {
    evaluateNow();
  }

  @override
  void onDisable() {
    final renderer = _resolveTargetRenderer();
    if (renderer != null && !renderer.isDestroyed) {
      if (_originalCastsShadow != null) {
        renderer.castsShadow = _originalCastsShadow!;
      }
      final restoreMesh = fullMesh ?? _originalMesh;
      if (restoreMesh != null) {
        renderer.mesh = restoreMesh;
      }
    }
    _originalCastsShadow = null;
    _originalMesh = null;
    _previousLod = null;
  }
}

/// Persistent UI state for [ShadowCasterLodInspectorUI.render].
final class ShadowCasterLodUiState {
  bool expanded = true;
  String? activeButtonId;
}

/// Immediate-mode `voxui` shadow caster LOD & hysteresis inspector (E102).
final class ShadowCasterLodInspectorUI {
  static bool _drawButton(
    VoxUiContext ui,
    ShadowCasterLodUiState state,
    String id,
    String label,
    VoxRect rect, {
    bool active = false,
  }) {
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
        : (active
              ? ui.style.tabActive
              : (hovered ? ui.style.buttonHover : ui.style.buttonBg));
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
    ShadowCasterLodComponent comp, {
    ShadowCasterLodUiState? state,
    String title = 'Shadow Caster LOD',
    double x = 20.0,
    double y = 20.0,
    double width = 415.0,
    double height = 245.0,
  }) {
    final uiState = state ?? ShadowCasterLodUiState();
    if (!ui.beginWindow(title, x: x, y: y, width: width, height: height)) {
      ui.endWindow();
      return;
    }
    if (!uiState.expanded) {
      ui.endWindow();
      return;
    }

    final pad = ui.style.windowPadding;
    final lodColor = switch (comp.currentLod) {
      ShadowCasterLod.full => VoxColor.green,
      ShadowCasterLod.reduced => VoxColor.yellow,
      ShadowCasterLod.culled => VoxColor.red,
    };

    ui.labelValue(
      'Shadow LOD',
      '${comp.currentLod.name} | ${comp.forcedLod == null ? 'Auto' : 'Forced'}',
      valueColor: lodColor,
    );
    ui.labelValue(
      'Distance',
      '${comp.lastDistance.toStringAsFixed(2)}m | apply ${comp.applyToTarget ? 'On' : 'Off'}',
      valueColor: VoxColor.cyan,
    );
    ui.labelValue(
      'Thresholds',
      'full<${comp.fullToReduced.toStringAsFixed(1)}m | red<${comp.reducedToCulled.toStringAsFixed(1)}m',
      valueColor: VoxColor.lightGray,
    );
    ui.labelValue(
      'Hysteresis / Mode',
      '+/-${comp.hysteresisDistance.toStringAsFixed(1)}m | ${comp.forcedLod?.name ?? 'auto'}',
      valueColor: comp.forcedLod != null ? VoxColor.yellow : VoxColor.lightGray,
    );

    final barY = y + ui.style.titleBarHeight + pad + 92.0;

    final autoRect = VoxRect(x + pad, barY, 76.0, 22.0);
    if (_drawButton(
      ui,
      uiState,
      'scl_auto',
      'Auto',
      autoRect,
      active: comp.forcedLod == null,
    )) {
      comp.forcedLod = null;
      comp.evaluateNow();
    }

    final fullRect = VoxRect(autoRect.right + 8.0, barY, 76.0, 22.0);
    if (_drawButton(
      ui,
      uiState,
      'scl_full',
      'Full',
      fullRect,
      active: comp.forcedLod == ShadowCasterLod.full,
    )) {
      comp.forcedLod = ShadowCasterLod.full;
      comp.evaluateNow();
    }

    final reducedRect = VoxRect(fullRect.right + 8.0, barY, 92.0, 22.0);
    if (_drawButton(
      ui,
      uiState,
      'scl_reduced',
      'Reduced',
      reducedRect,
      active: comp.forcedLod == ShadowCasterLod.reduced,
    )) {
      comp.forcedLod = ShadowCasterLod.reduced;
      comp.evaluateNow();
    }

    final culledRect = VoxRect(reducedRect.right + 8.0, barY, 88.0, 22.0);
    if (_drawButton(
      ui,
      uiState,
      'scl_culled',
      'Culled',
      culledRect,
      active: comp.forcedLod == ShadowCasterLod.culled,
    )) {
      comp.forcedLod = ShadowCasterLod.culled;
      comp.evaluateNow();
    }

    ui.endWindow();
  }
}
