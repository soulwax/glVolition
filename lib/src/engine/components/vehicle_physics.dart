part of '../../engine.dart';

/// Quick chassis preset for [VehicleChassisComponent] serialization and defaults (E58-2).
enum VehicleChassisPreset {
  sportsCar,
  offroad4x4,
}

/// Marks a child [GameObject] as a wheel visual driven by a parent [VehicleChassisComponent] (E58-2).
final class WheelSuspensionComponent extends Component {
  int wheelIndex;
  Vec3 visualOffset;
  bool syncSpin;
  bool syncSteer;
  bool syncSuspensionTravel;

  WheelSuspensionComponent({
    this.wheelIndex = 0,
    this.visualOffset = Vec3.zero,
    this.syncSpin = true,
    this.syncSteer = true,
    this.syncSuspensionTravel = true,
  });

  static final spec = ComponentSpec<WheelSuspensionComponent>(
    'WheelSuspensionComponent',
    WheelSuspensionComponent.new,
    [
      Field.integer('wheelIndex', (w) => w.wheelIndex, (w, v) => w.wheelIndex = v),
      Field.vec3('visualOffset', (w) => w.visualOffset, (w, v) => w.visualOffset = v),
      Field.boolean('syncSpin', (w) => w.syncSpin, (w, v) => w.syncSpin = v),
      Field.boolean('syncSteer', (w) => w.syncSteer, (w, v) => w.syncSteer = v),
      Field.boolean(
        'syncSuspensionTravel',
        (w) => w.syncSuspensionTravel,
        (w, v) => w.syncSuspensionTravel = v,
      ),
    ],
  );
}

/// Fixed-step 3D raycast vehicle physics controller backed by `voxwheel` (E58-2).
///
/// Raycasts wheel suspension struts against non-trigger scene colliders (with optional
/// flat ground fallback), integrates brush tire friction & multi-gear RPM curves,
/// updates this [GameObject]'s [Transform], and animates child [WheelSuspensionComponent]s.
final class VehicleChassisComponent extends Behaviour {
  VehicleChassisPreset preset;
  wheel.DriveLayout driveLayout;
  double mass;
  double maxSteerAngleDegrees;
  double suspensionStiffness;
  double suspensionRestLength;
  double wheelRadius;
  double peakGripMu;
  double throttleInput;
  double brakeInput;
  double steerInput;
  bool handbrakeInput;
  bool useScenePhysicsRaycasts;
  bool useFlatGroundFallback;
  double groundPlaneY;
  int raycastLayerMask;
  bool includeTriggers;
  bool autoSyncChildWheels;

  wheel.VehicleDynamicsSolver? _solver;
  VehicleChassisPreset? _builtPreset;
  wheel.DriveLayout? _builtLayout;
  double? _builtMass;
  double? _builtStiffness;
  double? _builtRestLen;
  double? _builtRadius;
  double? _builtGrip;
  double? _builtMaxSteerDeg;

  VehicleChassisComponent({
    this.preset = VehicleChassisPreset.sportsCar,
    this.driveLayout = wheel.DriveLayout.rwd,
    this.mass = 1350.0,
    this.maxSteerAngleDegrees = 32.0,
    this.suspensionStiffness = 32000.0,
    this.suspensionRestLength = 0.45,
    this.wheelRadius = 0.34,
    this.peakGripMu = 1.15,
    this.throttleInput = 0.0,
    this.brakeInput = 0.0,
    this.steerInput = 0.0,
    this.handbrakeInput = false,
    this.useScenePhysicsRaycasts = true,
    this.useFlatGroundFallback = true,
    this.groundPlaneY = 0.0,
    this.raycastLayerMask = -1,
    this.includeTriggers = false,
    this.autoSyncChildWheels = true,
  });

  static final spec = ComponentSpec<VehicleChassisComponent>(
    'VehicleChassisComponent',
    VehicleChassisComponent.new,
    [
      Field.enumValue<VehicleChassisComponent, VehicleChassisPreset>(
        'preset',
        VehicleChassisPreset.values,
        (v) => v.preset,
        (v, val) => v.preset = val,
      ),
      Field.enumValue<VehicleChassisComponent, wheel.DriveLayout>(
        'driveLayout',
        wheel.DriveLayout.values,
        (v) => v.driveLayout,
        (v, val) => v.driveLayout = val,
      ),
      Field.number('mass', (v) => v.mass, (v, val) => v.mass = val),
      Field.number(
        'maxSteerAngleDegrees',
        (v) => v.maxSteerAngleDegrees,
        (v, val) => v.maxSteerAngleDegrees = val,
      ),
      Field.number(
        'suspensionStiffness',
        (v) => v.suspensionStiffness,
        (v, val) => v.suspensionStiffness = val,
      ),
      Field.number(
        'suspensionRestLength',
        (v) => v.suspensionRestLength,
        (v, val) => v.suspensionRestLength = val,
      ),
      Field.number('wheelRadius', (v) => v.wheelRadius, (v, val) => v.wheelRadius = val),
      Field.number('peakGripMu', (v) => v.peakGripMu, (v, val) => v.peakGripMu = val),
      Field.number('throttleInput', (v) => v.throttleInput, (v, val) => v.throttleInput = val),
      Field.number('brakeInput', (v) => v.brakeInput, (v, val) => v.brakeInput = val),
      Field.number('steerInput', (v) => v.steerInput, (v, val) => v.steerInput = val),
      Field.boolean('handbrakeInput', (v) => v.handbrakeInput, (v, val) => v.handbrakeInput = val),
      Field.boolean(
        'useScenePhysicsRaycasts',
        (v) => v.useScenePhysicsRaycasts,
        (v, val) => v.useScenePhysicsRaycasts = val,
      ),
      Field.boolean(
        'useFlatGroundFallback',
        (v) => v.useFlatGroundFallback,
        (v, val) => v.useFlatGroundFallback = val,
      ),
      Field.number('groundPlaneY', (v) => v.groundPlaneY, (v, val) => v.groundPlaneY = val),
    ],
  );

  wheel.VehicleDynamicsSolver _ensureSolver() {
    final dirty = _solver == null ||
        _builtPreset != preset ||
        _builtLayout != driveLayout ||
        _builtMass != mass ||
        _builtStiffness != suspensionStiffness ||
        _builtRestLen != suspensionRestLength ||
        _builtRadius != wheelRadius ||
        _builtGrip != peakGripMu ||
        _builtMaxSteerDeg != maxSteerAngleDegrees;

    if (!dirty) return _solver!;

    final baseSpec = preset == VehicleChassisPreset.offroad4x4
        ? wheel.VehicleSpec.offroad4x4()
        : wheel.VehicleSpec.sportsCar();
    final drivetrain = wheel.DrivetrainSpec(
      layout: driveLayout,
      idleRpm: baseSpec.drivetrain.idleRpm,
      redlineRpm: baseSpec.drivetrain.redlineRpm,
      upshiftRpm: baseSpec.drivetrain.upshiftRpm,
      downshiftRpm: baseSpec.drivetrain.downshiftRpm,
      finalDriveRatio: baseSpec.drivetrain.finalDriveRatio,
      reverseRatio: baseSpec.drivetrain.reverseRatio,
      gearRatios: baseSpec.drivetrain.gearRatios,
      transmissionEfficiency: baseSpec.drivetrain.transmissionEfficiency,
      maxBrakeTorqueNm: baseSpec.drivetrain.maxBrakeTorqueNm,
      handbrakeTorqueNm: baseSpec.drivetrain.handbrakeTorqueNm,
      engineBrakingTorqueNm: baseSpec.drivetrain.engineBrakingTorqueNm,
      awdFrontBias: baseSpec.drivetrain.awdFrontBias,
      autoShift: baseSpec.drivetrain.autoShift,
      torqueCurve: baseSpec.drivetrain.torqueCurve,
    );
    final configuredWheels = [
      for (final w in baseSpec.wheels)
        wheel.WheelConfig(
          id: w.id,
          localAnchor: w.localAnchor,
          axle: w.axle,
          sideSign: w.sideSign,
          restLength: suspensionRestLength,
          maxTravel: w.maxTravel,
          wheelRadius: wheelRadius,
          springStiffness: suspensionStiffness,
          damperCompression: w.damperCompression,
          damperRebound: w.damperRebound,
          wheelInertia: w.wheelInertia,
          steerable: w.steerable,
          braked: w.braked,
          handbraked: w.handbraked,
          peakGripMu: peakGripMu,
        ),
    ];

    final pos = isAttached ? transform.position : const Vec3(0.0, 0.7, 0.0);
    final rot = isAttached ? transform.rotation : Quat.identity;
    final prevVel = _solver?.state.linearVelocity ?? wheel.WheelVec3.zero;
    final prevAngVel = _solver?.state.angularVelocity ?? wheel.WheelVec3.zero;
    final prevGear = _solver?.state.currentGear ?? 1;
    final prevRpm = _solver?.state.rpm ?? drivetrain.idleRpm;

    final customSpec = wheel.VehicleSpec(
      mass: math.max(100.0, mass),
      inertiaTensor: baseSpec.inertiaTensor,
      centerOfMassOffset: baseSpec.centerOfMassOffset,
      maxSteerAngleRad: maxSteerAngleDegrees * math.pi / 180.0,
      dragCoefficient: baseSpec.dragCoefficient,
      frontalArea: baseSpec.frontalArea,
      downforceCoefficient: baseSpec.downforceCoefficient,
      gravity: baseSpec.gravity,
      chassisRollTorqueScale: baseSpec.chassisRollTorqueScale,
      tireModel: baseSpec.tireModel,
      drivetrain: drivetrain,
      wheels: configuredWheels,
      antiRollPairs: baseSpec.antiRollPairs,
    );

    final nextSolver = wheel.VehicleDynamicsSolver(
      spec: customSpec,
      initialPosition: wheel.WheelVec3(pos.x, pos.y, pos.z),
      initialRotation: wheel.WheelQuat(rot.x, rot.y, rot.z, rot.w),
    );
    if (_solver != null) {
      nextSolver.state
        ..linearVelocity = prevVel
        ..angularVelocity = prevAngVel
        ..currentGear = prevGear
        ..rpm = prevRpm;
    }

    _solver = nextSolver;
    _builtPreset = preset;
    _builtLayout = driveLayout;
    _builtMass = mass;
    _builtStiffness = suspensionStiffness;
    _builtRestLen = suspensionRestLength;
    _builtRadius = wheelRadius;
    _builtGrip = peakGripMu;
    _builtMaxSteerDeg = maxSteerAngleDegrees;
    return nextSolver;
  }

  wheel.VehicleDynamicsSolver get solver => _ensureSolver();
  wheel.VehicleState get state => _ensureSolver().state;
  double get speedMps => state.speedMps;
  double get speedKmh => state.speedKmh;
  double get forwardSpeedMps => state.forwardSpeedMps;
  double get rpm => state.rpm;
  int get currentGear => state.currentGear;
  int get groundedWheels => state.groundedWheelCount;

  void setInputs({
    double? throttle,
    double? brake,
    double? steer,
    bool? handbrake,
  }) {
    if (throttle != null) throttleInput = throttle;
    if (brake != null) brakeInput = brake;
    if (steer != null) steerInput = steer;
    if (handbrake != null) handbrakeInput = handbrake;
  }

  void shiftUp() => _ensureSolver().shiftUp();
  void shiftDown() => _ensureSolver().shiftDown();

  void resetVehicle({Vec3? position, Quat? rotation}) {
    final targetPos = position ?? (isAttached ? transform.position : const Vec3(0.0, 0.7, 0.0));
    final targetRot = rotation ?? (isAttached ? transform.rotation : Quat.identity);
    _ensureSolver().reset(
      position: wheel.WheelVec3(targetPos.x, targetPos.y, targetPos.z),
      rotation: wheel.WheelQuat(targetRot.x, targetRot.y, targetRot.z, targetRot.w),
    );
    if (isAttached) {
      transform
        ..position = targetPos
        ..rotation = targetRot;
      _syncWheelChildren();
    }
  }

  bool _isSelfOrDescendant(GameObject target) {
    GameObject? cursor = target;
    while (cursor != null) {
      if (identical(cursor, gameObject)) return true;
      cursor = cursor.parent;
    }
    return false;
  }

  wheel.WheelVec3 _estimateColliderNormal(Collider collider, Vec3 hitPoint) {
    if (collider is SphereCollider) {
      final n = (hitPoint - collider.worldCenter).normalized;
      return wheel.WheelVec3(n.x, n.y, n.z);
    }
    if (collider is BoxCollider) {
      final b = collider.worldBounds;
      final c = b.center;
      final half = (b.max - b.min) * 0.5;
      final rel = hitPoint - c;
      final dx = (rel.x.abs() / math.max(1e-5, half.x));
      final dy = (rel.y.abs() / math.max(1e-5, half.y));
      final dz = (rel.z.abs() / math.max(1e-5, half.z));
      if (dx >= dy && dx >= dz) {
        return wheel.WheelVec3(rel.x >= 0 ? 1.0 : -1.0, 0.0, 0.0);
      }
      if (dz >= dy && dz >= dx) {
        return wheel.WheelVec3(0.0, 0.0, rel.z >= 0 ? 1.0 : -1.0);
      }
      return wheel.WheelVec3(0.0, rel.y >= 0 ? 1.0 : -1.0, 0.0);
    }
    return wheel.WheelVec3.unitY;
  }

  wheel.WheelRaycastHit? _queryGround(
    wheel.WheelVec3 origin,
    wheel.WheelVec3 direction,
    double maxDistance,
    int wheelIndex,
  ) {
    if (useScenePhysicsRaycasts && isAttached) {
      final ray = Ray(
        origin: Vec3(origin.x, origin.y, origin.z),
        direction: Vec3(direction.x, direction.y, direction.z),
      );
      final hits = scene.physics.raycastAll(
        ray,
        maxDistance: maxDistance,
        layerMask: raycastLayerMask,
        includeTriggers: includeTriggers,
      );
      for (final hit in hits) {
        if (_isSelfOrDescendant(hit.gameObject)) continue;
        return wheel.WheelRaycastHit(
          distance: hit.distance,
          point: wheel.WheelVec3(hit.point.x, hit.point.y, hit.point.z),
          normal: _estimateColliderNormal(hit.collider, hit.point),
        );
      }
    }
    if (useFlatGroundFallback) {
      return wheel.VehicleDynamicsSolver.flatGroundQuery(groundY: groundPlaneY)(
        origin,
        direction,
        maxDistance,
        wheelIndex,
      );
    }
    return null;
  }

  void _syncWheelChildren() {
    if (!autoSyncChildWheels || !isAttached) return;
    final s = _ensureSolver();
    void visit(GameObject node) {
      final wComp = node.getComponent<WheelSuspensionComponent>();
      if (wComp != null &&
          wComp.wheelIndex >= 0 &&
          wComp.wheelIndex < s.state.wheelStates.length) {
        final cfg = s.spec.wheels[wComp.wheelIndex];
        final ws = s.state.wheelStates[wComp.wheelIndex];
        final travelY = wComp.syncSuspensionTravel ? -ws.suspensionLength : -cfg.restLength;
        node.transform.localPosition = Vec3(
          cfg.localAnchor.x + wComp.visualOffset.x,
          cfg.localAnchor.y + travelY + wComp.visualOffset.y,
          cfg.localAnchor.z + wComp.visualOffset.z,
        );
        var q = Quat.identity;
        if (wComp.syncSteer && ws.steerAngleRad.abs() > 1e-6) {
          q = Quat.axisAngle(Vec3.unitY, -ws.steerAngleRad);
        }
        if (wComp.syncSpin && ws.spinAngleRad.abs() > 1e-6) {
          q = q * Quat.axisAngle(Vec3.unitX, -ws.spinAngleRad);
        }
        node.transform.localRotation = q;
      }
      for (final child in node.children) {
        visit(child);
      }
    }

    for (final child in gameObject.children) {
      visit(child);
    }
  }

  @override
  void onEnable() {
    _ensureSolver();
    _syncWheelChildren();
  }

  @override
  void fixedUpdate() {
    final s = _ensureSolver();
    final dt = time.fixedDeltaTime;
    if (dt <= 0.0) return;

    if (isAttached) {
      final pos = transform.position;
      final rot = transform.rotation;
      s.state
        ..position = wheel.WheelVec3(pos.x, pos.y, pos.z)
        ..rotation = wheel.WheelQuat(rot.x, rot.y, rot.z, rot.w);
    }

    s.step(
      dt,
      wheel.VehicleInput(
        throttle: throttleInput,
        brake: brakeInput,
        steer: steerInput,
        handbrake: handbrakeInput,
      ),
      groundQuery: _queryGround,
    );

    if (isAttached) {
      transform
        ..position = Vec3(s.state.position.x, s.state.position.y, s.state.position.z)
        ..rotation = Quat(
          s.state.rotation.x,
          s.state.rotation.y,
          s.state.rotation.z,
          s.state.rotation.w,
        );
      _syncWheelChildren();
    }
  }
}

/// Persistent UI interaction state for [VehicleTelemetryUI.render].
final class VehicleTelemetryUiState {
  String? activeButtonId;
}

/// Immediate-mode `voxui` telemetry and gearbox inspector panel for [VehicleChassisComponent] (E58-2).
final class VehicleTelemetryUI {
  static bool _drawButton(
    VoxUiContext ui,
    VehicleTelemetryUiState state,
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
    if (inp.wasMouseReleased && state.activeButtonId == id) state.activeButtonId = null;

    final bg = pressed
        ? ui.style.buttonActive
        : (hovered ? ui.style.buttonHover : ui.style.buttonBg);
    dl.addRectFilled(rect.x, rect.y, rect.width, rect.height, bg, cornerRadius: ui.style.frameRounding);
    dl.addRectOutline(rect.x, rect.y, rect.width, rect.height, ui.style.windowBorder, cornerRadius: ui.style.frameRounding);
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
    VehicleChassisComponent vehicle, {
    VehicleTelemetryUiState? state,
    String title = 'Vehicle Telemetry',
    double x = 20.0,
    double y = 20.0,
    double width = 360.0,
    double height = 240.0,
  }) {
    final uiState = state ?? VehicleTelemetryUiState();
    if (!ui.beginWindow(title, x: x, y: y, width: width, height: height)) {
      ui.endWindow();
      return;
    }

    final pad = ui.style.windowPadding;
    final gearLabel = switch (vehicle.currentGear) {
      -1 => 'R',
      0 => 'N',
      int g => 'G$g',
    };
    final ws = vehicle.state.wheelStates;
    var maxSlip = 0.0;
    for (final w in ws) {
      final combined = math.sqrt(w.slipRatio * w.slipRatio + w.slipAngleRad * w.slipAngleRad);
      if (combined > maxSlip) maxSlip = combined;
    }

    ui.labelValue(
      'Speed / Gear',
      '${vehicle.speedKmh.toStringAsFixed(1)} km/h / $gearLabel',
      valueColor: VoxColor.cyan,
    );
    ui.labelValue(
      'RPM / Drive',
      '${vehicle.rpm.round()} RPM / ${vehicle.driveLayout.name.toUpperCase()}',
      valueColor: VoxColor.lightGray,
    );
    ui.labelValue(
      'Grounded / Slip',
      '${vehicle.groundedWheels}/${ws.length} / ${maxSlip.toStringAsFixed(2)}',
      valueColor: VoxColor.green,
    );
    ui.labelValue(
      'Throttle / Brake',
      '${(vehicle.throttleInput * 100).round()}% / ${(vehicle.brakeInput * 100).round()}%',
      valueColor: VoxColor.yellow,
    );

    final barY = y + ui.style.titleBarHeight + pad + 90.0;
    final downRect = VoxRect(x + pad, barY, 80.0, 22.0);
    if (_drawButton(ui, uiState, 'veh_shift_down', 'Shift -', downRect)) {
      vehicle.shiftDown();
    }

    final upRect = VoxRect(downRect.right + 8.0, barY, 80.0, 22.0);
    if (_drawButton(ui, uiState, 'veh_shift_up', 'Shift +', upRect)) {
      vehicle.shiftUp();
    }

    final resetRect = VoxRect(upRect.right + 8.0, barY, 84.0, 22.0);
    if (_drawButton(ui, uiState, 'veh_reset', 'Reset', resetRect)) {
      vehicle.resetVehicle();
    }

    ui.endWindow();
  }
}
