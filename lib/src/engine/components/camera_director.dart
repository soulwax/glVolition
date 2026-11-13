part of '../../engine.dart';

/// Cinemachine-style virtual camera component synchronized with [vcam.VirtualCameraRig] (E50-2).
final class VirtualCameraComponent extends Behaviour {
  String cameraId;
  int priority;
  double fovYDegrees;
  double near;
  double far;
  double dutchRollRadians;

  GameObject? followTarget;
  GameObject? lookAtTarget;

  vcam.CameraFramingComposer? framingComposer;
  vcam.CameraOrbitRig? orbitRig;
  vcam.CameraTransitionSpec? transitionIn;

  /// When `true` and [orbitRig] is active, probes scene physics colliders to pull
  /// the camera inward around walls and terrain obstacles.
  bool obstacleAvoidance;
  int obstacleLayerMask;
  bool includeTriggerObstacles;

  /// When `true`, writes evaluated composer/orbit pose back onto this GameObject's transform.
  bool applyRigPoseToTransform;

  vcam.VirtualCameraRig? _rig;
  Vec3? _prevFollowPos;

  VirtualCameraComponent({
    this.cameraId = '',
    this.priority = 10,
    this.fovYDegrees = 60.0,
    this.near = 0.1,
    this.far = 200.0,
    this.dutchRollRadians = 0.0,
    this.followTarget,
    this.lookAtTarget,
    this.framingComposer,
    this.orbitRig,
    this.transitionIn,
    this.obstacleAvoidance = true,
    this.obstacleLayerMask = -1,
    this.includeTriggerObstacles = false,
    this.applyRigPoseToTransform = true,
  });

  static final spec = ComponentSpec<VirtualCameraComponent>(
    'VirtualCameraComponent',
    VirtualCameraComponent.new,
    [
      Field.text('cameraId', (c) => c.cameraId, (c, v) => c.cameraId = v),
      Field.integer('priority', (c) => c.priority, (c, v) => c.priority = v),
      Field.number(
        'fovYDegrees',
        (c) => c.fovYDegrees,
        (c, v) => c.fovYDegrees = v,
      ),
      Field.number('near', (c) => c.near, (c, v) => c.near = v),
      Field.number('far', (c) => c.far, (c, v) => c.far = v),
      Field.number(
        'dutchRollRadians',
        (c) => c.dutchRollRadians,
        (c, v) => c.dutchRollRadians = v,
      ),
      Field.boolean(
        'obstacleAvoidance',
        (c) => c.obstacleAvoidance,
        (c, v) => c.obstacleAvoidance = v,
      ),
      Field.boolean(
        'applyRigPoseToTransform',
        (c) => c.applyRigPoseToTransform,
        (c, v) => c.applyRigPoseToTransform = v,
      ),
    ],
  );

  vcam.VirtualCameraRig get rig {
    final existing = _rig;
    if (existing != null) return existing;
    final resolvedId = cameraId.isNotEmpty
        ? cameraId
        : (isAttached ? gameObject.name : 'vcam_${identityHashCode(this)}');
    final created = vcam.VirtualCameraRig(
      id: resolvedId,
      priority: priority,
      enabled: isAttached ? isActiveAndEnabled : enabled,
      framingComposer: framingComposer,
      orbitRig: orbitRig,
      transitionIn: transitionIn,
      pose: vcam.CamPose(
        fovYDegrees: fovYDegrees,
        near: near,
        far: far,
        dutchRollRadians: dutchRollRadians,
      ),
    );
    _rig = created;
    return created;
  }

  static vcam.CamVec3 _toCamVec3(Vec3 v) => vcam.CamVec3(v.x, v.y, v.z);
  static vcam.CamQuat _toCamQuat(Quat q) => vcam.CamQuat(q.x, q.y, q.z, q.w);

  void _syncToRig(double dt) {
    final r = rig;
    r.priority = priority;
    r.enabled = isAttached ? isActiveAndEnabled : enabled;
    r.framingComposer = framingComposer;
    r.orbitRig = orbitRig;
    r.transitionIn = transitionIn;

    final follow = followTarget;
    if (follow != null && !follow.isDestroyed) {
      final fPos = follow.transform.position;
      r.targetPosition = _toCamVec3(fPos);
      final rb = follow.getComponent<RigidBody>();
      if (rb != null) {
        r.targetVelocity = _toCamVec3(rb.velocity);
      } else if (_prevFollowPos != null && dt > 1e-5) {
        r.targetVelocity = _toCamVec3((fPos - _prevFollowPos!) * (1.0 / dt));
      } else {
        r.targetVelocity = vcam.CamVec3.zero;
      }
      _prevFollowPos = fPos;
    } else {
      r.targetPosition = null;
      r.targetVelocity = null;
      _prevFollowPos = null;
    }

    final look = lookAtTarget;
    r.lookAtTarget = (look != null && !look.isDestroyed)
        ? _toCamVec3(look.transform.position)
        : null;

    final drivenByProceduralRig =
        followTarget != null && (framingComposer != null || orbitRig != null);
    if (!drivenByProceduralRig && isAttached) {
      r.pose = vcam.CamPose(
        position: _toCamVec3(transform.position),
        rotation: lookAtTarget == null
            ? _toCamQuat(transform.rotation)
            : r.pose.rotation,
        fovYDegrees: fovYDegrees,
        near: near,
        far: far,
        dutchRollRadians: dutchRollRadians,
      );
    } else {
      r.pose = r.pose.copyWith(
        fovYDegrees: fovYDegrees,
        near: near,
        far: far,
        dutchRollRadians: dutchRollRadians,
      );
    }
  }

  void _syncFromRig() {
    if (!applyRigPoseToTransform || !isAttached) return;
    if (framingComposer == null && orbitRig == null && lookAtTarget == null) {
      return;
    }
    final p = rig.pose;
    transform.position = Vec3(p.position.x, p.position.y, p.position.z);
    final rot = p.composedRotation;
    transform.rotation = Quat(rot.x, rot.y, rot.z, rot.w).normalized;
  }

  @override
  void awake() {
    rig; // Ensures gameObject.name is captured when cameraId is omitted.
    _syncToRig(0.0);
  }

  @override
  void onEnable() {
    rig.enabled = true;
  }

  @override
  void onDisable() {
    rig.enabled = false;
  }
}

/// Drives a sibling [Camera] (and [TransformComponent]) from the highest-priority
/// [VirtualCameraRig]s managed by [vcam.CameraDirectorBrain] (E50-2).
final class CameraBrainComponent extends Behaviour {
  final vcam.CameraDirectorBrain brain;

  /// When `true`, automatically discovers all [VirtualCameraComponent] instances
  /// in the owning [Scene] during [lateUpdate].
  bool autoDiscoverSceneCameras;

  final Map<VirtualCameraComponent, vcam.VirtualCameraRig> _trackedComponents =
      {};

  CameraBrainComponent({
    vcam.CameraDirectorBrain? brain,
    vcam.CameraTransitionSpec defaultTransition =
        const vcam.CameraTransitionSpec(),
    this.autoDiscoverSceneCameras = true,
  }) : brain =
           brain ??
           vcam.CameraDirectorBrain(defaultTransition: defaultTransition);

  static final spec = ComponentSpec<CameraBrainComponent>(
    'CameraBrainComponent',
    CameraBrainComponent.new,
    [
      Field.boolean(
        'autoDiscoverSceneCameras',
        (c) => c.autoDiscoverSceneCameras,
        (c, v) => c.autoDiscoverSceneCameras = v,
      ),
    ],
  );

  vcam.VirtualCameraRig? get activeCamera => brain.activeCamera;
  bool get isBlending => brain.isBlending;
  double get blendProgress => brain.blendProgress;
  vcam.CamPose get currentPose => brain.currentPose;

  void addVirtualCamera(VirtualCameraComponent component) {
    final rig = component.rig;
    _trackedComponents[component] = rig;
    brain.addRig(rig);
  }

  void removeVirtualCamera(VirtualCameraComponent component) {
    final rig = _trackedComponents.remove(component);
    if (rig != null) {
      brain.removeRig(rig);
    }
  }

  void setTransition(
    String fromId,
    String toId,
    vcam.CameraTransitionSpec spec,
  ) => brain.setTransition(fromId, toId, spec);

  void triggerImpulse({double trauma = 0.6, Vec3 kick = Vec3.zero}) =>
      brain.triggerImpulse(
        traumaAmount: trauma,
        kick: vcam.CamVec3(kick.x, kick.y, kick.z),
      );

  void snapToActive() {
    _syncSceneCameras(0.0);
    brain.snapToActive(obstacleProbe: _probeObstacle);
    _applyPoseToCamera(brain.currentPose);
  }

  void _syncSceneCameras(double dt) {
    if (!isAttached) return;
    if (autoDiscoverSceneCameras) {
      final live = scene
          .findObjectsOfType<VirtualCameraComponent>(includeInactive: true)
          .toSet();
      for (final comp in live) {
        if (!_trackedComponents.containsKey(comp)) {
          _trackedComponents[comp] = comp.rig;
          brain.addRig(comp.rig);
        }
      }
      final stale = _trackedComponents.keys
          .where((c) => !live.contains(c) || c.isDestroyed)
          .toList();
      for (final comp in stale) {
        removeVirtualCamera(comp);
      }
    }

    for (final comp in List.of(_trackedComponents.keys)) {
      if (!comp.isDestroyed) {
        comp._syncToRig(dt);
      }
    }
  }

  double? _probeObstacle(
    vcam.CamVec3 origin,
    vcam.CamVec3 dir,
    double maxDistance,
  ) {
    if (!isAttached) return null;
    final activeRig = brain.activeCamera;
    VirtualCameraComponent? activeComp;
    for (final entry in _trackedComponents.entries) {
      if (identical(entry.value, activeRig)) {
        activeComp = entry.key;
        break;
      }
    }
    if (activeComp != null && !activeComp.obstacleAvoidance) {
      return null;
    }

    final hits = scene.physics.raycastAll(
      Ray(
        origin: Vec3(origin.x, origin.y, origin.z),
        direction: Vec3(dir.x, dir.y, dir.z).normalized,
      ),
      maxDistance: maxDistance,
      layerMask: activeComp?.obstacleLayerMask ?? -1,
      includeTriggers: activeComp?.includeTriggerObstacles ?? false,
    );
    final ignoredTarget = activeComp?.followTarget;
    for (final hit in hits) {
      if (ignoredTarget != null && identical(hit.gameObject, ignoredTarget)) {
        continue;
      }
      if (identical(hit.gameObject, gameObject)) continue;
      return hit.distance;
    }
    return null;
  }

  void _applyPoseToCamera(vcam.CamPose pose) {
    if (!isAttached) return;
    transform.position = Vec3(
      pose.position.x,
      pose.position.y,
      pose.position.z,
    );
    final rot = pose.composedRotation;
    transform.rotation = Quat(rot.x, rot.y, rot.z, rot.w).normalized;

    final cam = getComponent<Camera>();
    if (cam != null) {
      cam.fovYRadians = pose.fovYRadians;
      cam.near = pose.near;
      cam.far = pose.far;
    }
  }

  @override
  void start() {
    snapToActive();
  }

  @override
  void lateUpdate() {
    final dt = time.deltaTime;
    _syncSceneCameras(dt);
    final pose = brain.evaluate(dt, obstacleProbe: _probeObstacle);
    for (final comp in _trackedComponents.keys) {
      if (!comp.isDestroyed) {
        comp._syncFromRig();
      }
    }
    _applyPoseToCamera(pose);
  }
}

/// Persistent UI interaction state for [CameraDirectorUI.render].
final class CameraDirectorUiState {
  String? activeButtonId;
}

/// Immediate-mode `voxui` virtual camera director monitor & impulse trigger (E50-2).
final class CameraDirectorUI {
  static bool _drawButton(
    VoxUiContext ui,
    CameraDirectorUiState state,
    String id,
    String label,
    VoxRect rect,
  ) {
    final inp = ui.input;
    final dl = ui.drawList;
    final hovered = rect.contains(inp.mouseX, inp.mouseY);
    if (hovered && inp.wasMouseClicked) {
      state.activeButtonId = id;
    }
    final pressed = hovered && state.activeButtonId == id && inp.isMouseDown;
    final clicked =
        hovered && state.activeButtonId == id && inp.wasMouseReleased;
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
    vcam.CameraDirectorBrain brain, {
    CameraDirectorUiState? state,
    String title = 'Camera Director',
    double x = 20.0,
    double y = 20.0,
    double width = 360.0,
    double height = 300.0,
  }) {
    final uiState = state ?? CameraDirectorUiState();
    if (!ui.beginWindow(title, x: x, y: y, width: width, height: height)) {
      ui.endWindow();
      return;
    }

    final pad = ui.style.windowPadding;
    final dl = ui.drawList;
    final activeId = brain.activeCamera?.id ?? '<none>';
    final pose = brain.currentPose;

    ui.labelValue('Active Rig', activeId, valueColor: VoxColor.cyan);
    ui.labelValue(
      'FOV Y',
      '${pose.fovYDegrees.toStringAsFixed(1)} deg',
      valueColor: VoxColor.lightGray,
    );
    ui.labelValue(
      'Blend State',
      brain.isBlending
          ? '${(brain.blendProgress * 100.0).toStringAsFixed(0)}%'
          : 'Locked',
      valueColor: brain.isBlending ? VoxColor.yellow : VoxColor.green,
    );

    // Horizontal toolbar: Snap & Impulse!
    final barY = y + ui.style.titleBarHeight + pad + 68.0;
    final snapRect = VoxRect(x + pad, barY, 90.0, 22.0);
    if (_drawButton(ui, uiState, 'cam_snap', 'Snap Cut', snapRect)) {
      brain.snapToActive();
    }

    final shakeRect = VoxRect(snapRect.right + 8.0, barY, 96.0, 22.0);
    if (_drawButton(ui, uiState, 'cam_impulse', 'Impulse!', shakeRect)) {
      brain.triggerImpulse(traumaAmount: 0.65);
    }

    // Blend progress bar
    final progX = shakeRect.right + 10.0;
    final progW = math.max(40.0, x + width - pad - progX);
    dl.addRectFilled(
      progX,
      barY + 5.0,
      progW,
      12.0,
      const VoxColor(30, 34, 44, 255),
      cornerRadius: 3.0,
    );
    dl.addRectFilled(
      progX,
      barY + 5.0,
      progW * brain.blendProgress.clamp(0.0, 1.0),
      12.0,
      brain.isBlending ? VoxColor.yellow : VoxColor.cyan,
      cornerRadius: 3.0,
    );

    // Priority stack rows
    final rigs = List<vcam.VirtualCameraRig>.of(brain.rigs)
      ..sort((a, b) => b.priority.compareTo(a.priority));
    var rowY = barY + 34.0;
    dl.addText(
      'Virtual Rigs (${rigs.length}):',
      x + pad,
      rowY,
      color: VoxColor.yellow,
      size: ui.style.fontSize,
    );
    rowY += 18.0;

    for (final rig in rigs) {
      if (rowY + 22.0 > y + height - pad) break;
      final isLive = identical(rig, brain.activeCamera);
      final tag = !rig.enabled ? '[OFF]' : (isLive ? '[LIVE]' : '[IDLE]');
      final tagColor = !rig.enabled
          ? VoxColor.gray
          : (isLive ? VoxColor.green : VoxColor.lightGray);

      dl.addText(
        '$tag ${rig.id} (P${rig.priority})',
        x + pad,
        rowY + 3.0,
        color: tagColor,
        size: ui.style.fontSize - 1.0,
      );

      final boostRect = VoxRect(x + width - pad - 54.0, rowY, 54.0, 18.0);
      if (_drawButton(ui, uiState, 'boost_${rig.id}', 'Solo', boostRect)) {
        var maxPrio = rig.priority;
        for (final other in rigs) {
          if (other.priority > maxPrio) maxPrio = other.priority;
        }
        rig.priority = maxPrio + 5;
        rig.enabled = true;
      }

      rowY += 22.0;
    }

    ui.endWindow();
  }
}
