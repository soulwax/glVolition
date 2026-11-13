part of '../../engine.dart';

/// Material presets for [AcousticRoomComponent] mapped to `voxreverb` absorption profiles (E70-2).
enum AcousticMaterialPreset {
  concrete,
  stoneCavern,
  woodPanel,
  heavyCarpet,
  glass,
  metal,
  acousticFoam,
}

reverb.AcousticSurfaceMaterial _materialFromPreset(
  AcousticMaterialPreset preset,
) {
  switch (preset) {
    case AcousticMaterialPreset.concrete:
      return reverb.AcousticSurfaceMaterial.concrete;
    case AcousticMaterialPreset.stoneCavern:
      return reverb.AcousticSurfaceMaterial.stoneCavern;
    case AcousticMaterialPreset.woodPanel:
      return reverb.AcousticSurfaceMaterial.woodPanel;
    case AcousticMaterialPreset.heavyCarpet:
      return reverb.AcousticSurfaceMaterial.heavyCarpet;
    case AcousticMaterialPreset.glass:
      return reverb.AcousticSurfaceMaterial.glass;
    case AcousticMaterialPreset.metal:
      return reverb.AcousticSurfaceMaterial.metal;
    case AcousticMaterialPreset.acousticFoam:
      return reverb.AcousticSurfaceMaterial.acousticFoam;
  }
}

/// Enclosed acoustic room volume computing Eyring RT60 decay and driving sibling
/// [AudioReverbZone]s & cross-room portal diffraction (E70-2).
final class AcousticRoomComponent extends Behaviour {
  String roomId;
  Vec3 size;
  AcousticMaterialPreset materialPreset;
  double airAbsorptionPerMeter;
  bool autoSyncReverbZone;

  AudioReverbZone? boundReverbZone;
  reverb.AcousticPathResult? _lastSolvedPath;

  AcousticRoomComponent({
    this.roomId = '',
    this.size = const Vec3(12.0, 5.0, 12.0),
    this.materialPreset = AcousticMaterialPreset.concrete,
    this.airAbsorptionPerMeter = 0.002,
    this.autoSyncReverbZone = true,
    this.boundReverbZone,
  });

  static final spec = ComponentSpec<AcousticRoomComponent>(
    'AcousticRoomComponent',
    AcousticRoomComponent.new,
    [
      Field.text('roomId', (r) => r.roomId, (r, v) => r.roomId = v),
      Field.vec3('size', (r) => r.size, (r, v) => r.size = v),
      Field.enumValue<AcousticRoomComponent, AcousticMaterialPreset>(
        'materialPreset',
        AcousticMaterialPreset.values,
        (r) => r.materialPreset,
        (r, v) => r.materialPreset = v,
      ),
      Field.number(
        'airAbsorptionPerMeter',
        (r) => r.airAbsorptionPerMeter,
        (r, v) => r.airAbsorptionPerMeter = v,
      ),
      Field.boolean(
        'autoSyncReverbZone',
        (r) => r.autoSyncReverbZone,
        (r, v) => r.autoSyncReverbZone = v,
      ),
    ],
  );

  String get effectiveRoomId => roomId.isNotEmpty
      ? roomId
      : (isAttached ? gameObject.name : 'room_$instanceId');

  reverb.AcousticPathResult? get lastSolvedPath => _lastSolvedPath;

  reverb.AcousticRoomVolume toRoomVolume() {
    final center = isAttached ? transform.position : Vec3.zero;
    final half = size * 0.5;
    final bounds = reverb.ReverbAabb(
      reverb.ReverbVec3(
        center.x - half.x,
        center.y - half.y,
        center.z - half.z,
      ),
      reverb.ReverbVec3(
        center.x + half.x,
        center.y + half.y,
        center.z + half.z,
      ),
    );
    return reverb.AcousticRoomVolume(
      id: effectiveRoomId,
      bounds: bounds,
      defaultMaterial: _materialFromPreset(materialPreset),
      airAbsorptionPerMeter: airAbsorptionPerMeter,
      enabled: isAttached ? _active : true,
    );
  }

  double get eyringRt60 => toRoomVolume().computeEyringRt60();
  double get sabineRt60 => toRoomVolume().computeSabineRt60();
  double get wetSendSuggestion => toRoomVolume().wetSendSuggestion;

  /// Collects all active [AcousticRoomComponent]s & [AcousticPortalComponent]s in [scene].
  static reverb.AcousticPropagationSolver buildSolver(Scene scene) {
    final solver = reverb.AcousticPropagationSolver();
    for (final room in scene.findObjectsOfType<AcousticRoomComponent>()) {
      if (room._active) {
        solver.addRoom(room.toRoomVolume());
      }
    }
    for (final portal in scene.findObjectsOfType<AcousticPortalComponent>()) {
      if (portal._active) {
        solver.addAperture(portal.toAperture());
      }
    }
    return solver;
  }

  /// Evaluates acoustic transmission path from [emitterPosition] to [listenerPosition].
  reverb.AcousticPathResult solveToListener({
    Vec3? emitterPosition,
    Vec3? listenerPosition,
  }) {
    final solver = isAttached
        ? buildSolver(scene)
        : (reverb.AcousticPropagationSolver()..addRoom(toRoomVolume()));

    final emit =
        emitterPosition ?? (isAttached ? transform.position : Vec3.zero);
    final listener =
        listenerPosition ??
        (isAttached
            ? (AudioListener.of(scene)?.transform.position ??
                  Camera.of(scene)?.transform.position ??
                  Vec3.zero)
            : Vec3.zero);

    final res = solver.solve(
      emitterPos: reverb.ReverbVec3(emit.x, emit.y, emit.z),
      listenerPos: reverb.ReverbVec3(listener.x, listener.y, listener.z),
    );
    _lastSolvedPath = res;
    return res;
  }

  void syncReverbZone() {
    final zone =
        boundReverbZone ??
        (isAttached ? getComponent<AudioReverbZone>() : null);
    if (zone == null) return;
    final vol = toRoomVolume();
    final rt = vol.computeEyringRt60();
    zone
      ..roomSize = (rt / 3.5).clamp(0.15, 0.98).toDouble()
      ..damp = vol.hfDampRatio
      ..wet = vol.wetSendSuggestion;
  }

  @override
  void update() {
    if (autoSyncReverbZone) {
      syncReverbZone();
    }
  }
}

/// Acoustic portal (doorway/window/corridor link) connecting two [AcousticRoomComponent]s (E70-2).
final class AcousticPortalComponent extends Behaviour {
  String portalId;
  String roomAId;
  String roomBId;
  double areaSqMeters;
  double openFactor;
  double closedTransmissionGain;

  AudioLowPassFilterComponent? boundLowPassFilter;

  AcousticPortalComponent({
    this.portalId = '',
    this.roomAId = '',
    this.roomBId = '',
    this.areaSqMeters = 2.2,
    this.openFactor = 1.0,
    this.closedTransmissionGain = 0.08,
    this.boundLowPassFilter,
  });

  static final spec = ComponentSpec<AcousticPortalComponent>(
    'AcousticPortalComponent',
    AcousticPortalComponent.new,
    [
      Field.text('portalId', (p) => p.portalId, (p, v) => p.portalId = v),
      Field.text('roomAId', (p) => p.roomAId, (p, v) => p.roomAId = v),
      Field.text('roomBId', (p) => p.roomBId, (p, v) => p.roomBId = v),
      Field.number(
        'areaSqMeters',
        (p) => p.areaSqMeters,
        (p, v) => p.areaSqMeters = v,
      ),
      Field.number(
        'openFactor',
        (p) => p.openFactor,
        (p, v) => p.openFactor = v,
      ),
      Field.number(
        'closedTransmissionGain',
        (p) => p.closedTransmissionGain,
        (p, v) => p.closedTransmissionGain = v,
      ),
    ],
  );

  String get effectivePortalId => portalId.isNotEmpty
      ? portalId
      : (isAttached ? gameObject.name : 'portal_$instanceId');

  reverb.AcousticAperture toAperture() {
    final pos = isAttached ? transform.position : Vec3.zero;
    return reverb.AcousticAperture(
      id: effectivePortalId,
      roomAId: roomAId,
      roomBId: roomBId,
      center: reverb.ReverbVec3(pos.x, pos.y, pos.z),
      areaSqMeters: areaSqMeters,
      openFactor: openFactor,
      closedTransmissionGain: closedTransmissionGain,
      enabled: isAttached ? _active : true,
    );
  }

  void setOpen(double factor) {
    openFactor = factor.clamp(0.0, 1.0).toDouble();
    final lpf =
        boundLowPassFilter ??
        (isAttached ? getComponent<AudioLowPassFilterComponent>() : null);
    if (lpf != null) {
      lpf.cutoffFrequency = toAperture().lowPassCutoffHz;
    }
  }
}

/// Persistent UI interaction state for [AcousticsInspectorUI.render].
final class AcousticsInspectorUiState {
  String? activeButtonId;
}

/// Immediate-mode `voxui` room acoustics, Eyring RT60 & portal diffraction inspector (E70-2).
final class AcousticsInspectorUI {
  static bool _drawButton(
    VoxUiContext ui,
    AcousticsInspectorUiState state,
    String id,
    String label,
    VoxRect rect,
  ) {
    final inp = ui.input;
    final dl = ui.drawList;
    final hovered = rect.contains(inp.mouseX, inp.mouseY);
    if (hovered && inp.wasMouseClicked) state.activeButtonId = id;
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
    AcousticRoomComponent room, {
    AcousticPortalComponent? portal,
    Vec3? emitterPosition,
    Vec3? listenerPosition,
    AcousticsInspectorUiState? state,
    String title = 'Room Acoustics',
    double x = 20.0,
    double y = 20.0,
    double width = 360.0,
    double height = 240.0,
  }) {
    final uiState = state ?? AcousticsInspectorUiState();
    if (!ui.beginWindow(title, x: x, y: y, width: width, height: height)) {
      ui.endWindow();
      return;
    }

    final pad = ui.style.windowPadding;
    final vol = room.toRoomVolume();
    final solved = room.lastSolvedPath;

    ui.labelValue(
      'Room / Mat',
      '${vol.volumeM3.toStringAsFixed(0)}m3 (${room.materialPreset.name})',
      valueColor: VoxColor.cyan,
    );
    ui.labelValue(
      'Eyring RT60',
      '${vol.computeEyringRt60().toStringAsFixed(2)}s / Wet ${(vol.wetSendSuggestion * 100).round()}%',
      valueColor: VoxColor.green,
    );
    ui.labelValue(
      'Diffraction / LPF',
      solved == null
          ? 'Not solved'
          : '${(solved.diffractionGain * 100).round()}% / ${solved.lowPassCutoffHz.round()}Hz',
      valueColor: VoxColor.yellow,
    );
    ui.labelValue(
      'Portal Door',
      portal == null
          ? 'None'
          : '${portal.effectivePortalId} (${(portal.openFactor * 100).round()}%)',
      valueColor: VoxColor.lightGray,
    );

    final barY = y + ui.style.titleBarHeight + pad + 90.0;
    final solveRect = VoxRect(x + pad, barY, 88.0, 22.0);
    if (_drawButton(ui, uiState, 'ac_solve', 'Solve Path', solveRect)) {
      room.solveToListener(
        emitterPosition: emitterPosition,
        listenerPosition: listenerPosition,
      );
    }

    final doorRect = VoxRect(solveRect.right + 8.0, barY, 96.0, 22.0);
    if (_drawButton(ui, uiState, 'ac_door', 'Toggle Door', doorRect)) {
      if (portal != null) {
        portal.setOpen(portal.openFactor > 0.5 ? 0.0 : 1.0);
      }
    }

    final matRect = VoxRect(doorRect.right + 8.0, barY, 82.0, 22.0);
    if (_drawButton(ui, uiState, 'ac_mat', 'Cycle Mat', matRect)) {
      const presets = AcousticMaterialPreset.values;
      final nextIdx = (room.materialPreset.index + 1) % presets.length;
      room.materialPreset = presets[nextIdx];
      room.syncReverbZone();
    }

    ui.endWindow();
  }
}
