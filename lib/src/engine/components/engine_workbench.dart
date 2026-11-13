part of '../../engine.dart';

/// Active panel tab inside [EngineWorkbenchComponent].
enum WorkbenchTab { hierarchy, inspector, profiler }

/// Persistent immediate-mode UI interaction state for [EngineWorkbenchComponent].
final class EngineWorkbenchUiState {
  String? activeButtonId;
  int scrollIndex = 0;
}

/// Dockable in-canvas runtime workbench providing scene hierarchy browsing,
/// live [ComponentSpec] property editing, and frame telemetry via `voxui` (E96-2).
final class EngineWorkbenchComponent extends Behaviour {
  static const double _defaultWindowX = 16.0;
  static const double _defaultWindowY = 16.0;
  static const double _defaultWindowWidth = 380.0;
  static const double _defaultWindowHeight = 420.0;

  bool visible;
  String toggleKeyCode;
  double designWidth;
  double designHeight;
  WorkbenchTab activeTab;
  bool clampWindowsToViewport;

  GameObject? selectedObject;
  ComponentRegistry? registry;
  BitmapFont? font;

  final VoxUiContext uiContext = VoxUiContext();
  final VoxUiInputBridge inputBridge = VoxUiInputBridge();
  late final VoxUiRenderer uiRenderer = VoxUiRenderer(
    designWidth: designWidth,
    designHeight: designHeight,
    font: font,
  );
  final EngineWorkbenchUiState uiState = EngineWorkbenchUiState();

  int lastRenderedCommands = 0;
  DrawList? lastDrawList;

  late final ComponentRegistry _fallbackRegistry = ComponentRegistry.defaults();

  EngineWorkbenchComponent({
    this.visible = true,
    this.toggleKeyCode = 'F11',
    this.designWidth = 1280.0,
    this.designHeight = 720.0,
    this.activeTab = WorkbenchTab.hierarchy,
    this.clampWindowsToViewport = true,
    this.selectedObject,
    this.registry,
    this.font,
  });

  static final spec = ComponentSpec<EngineWorkbenchComponent>(
    'EngineWorkbenchComponent',
    EngineWorkbenchComponent.new,
    [
      Field.boolean('visible', (c) => c.visible, (c, v) => c.visible = v),
      Field.text(
        'toggleKeyCode',
        (c) => c.toggleKeyCode,
        (c, v) => c.toggleKeyCode = v,
      ),
      Field.number(
        'designWidth',
        (c) => c.designWidth,
        (c, v) => c.designWidth = v,
      ),
      Field.number(
        'designHeight',
        (c) => c.designHeight,
        (c, v) => c.designHeight = v,
      ),
      Field.enumValue<EngineWorkbenchComponent, WorkbenchTab>(
        'activeTab',
        WorkbenchTab.values,
        (c) => c.activeTab,
        (c, v) => c.activeTab = v,
      ),
      Field.boolean(
        'clampWindowsToViewport',
        (c) => c.clampWindowsToViewport,
        (c, v) => c.clampWindowsToViewport = v,
      ),
    ],
  );

  @override
  void _onEnableInternal() {
    if (!scene._workbenches.contains(this)) {
      scene._workbenches.add(this);
    }
  }

  @override
  void _onDisableInternal() {
    scene._workbenches.remove(this);
  }

  @override
  void update() {
    final rawInput = engine.host.input;
    if (toggleKeyCode.isNotEmpty && rawInput.wasPressed(toggleKeyCode)) {
      visible = !visible;
    }
    if (!visible) {
      lastDrawList = null;
      return;
    }

    final frameInput = inputBridge.sample(
      rawInput,
      viewportWidth: engine.graphics.viewportWidth,
      viewportHeight: engine.graphics.viewportHeight,
      designWidth: designWidth,
      designHeight: designHeight,
    );
    renderFrame(frameInput);
  }

  /// Builds one immediate-mode `voxui` workbench frame for [frameInput] and
  /// stores the resulting [DrawList] in [lastDrawList].
  DrawList renderFrame(VoxInput frameInput) {
    if (selectedObject != null && selectedObject!.isDestroyed) {
      selectedObject = null;
    }

    var winX = _defaultWindowX;
    var winY = _defaultWindowY;
    var winW = _defaultWindowWidth;
    var winH = _defaultWindowHeight;

    if (clampWindowsToViewport) {
      final maxW = math.max(1.0, designWidth);
      final maxH = math.max(1.0, designHeight);
      winW = math.min(_defaultWindowWidth, maxW);
      winH = math.min(_defaultWindowHeight, maxH);
      winX = _defaultWindowX.clamp(0.0, math.max(0.0, maxW - winW));
      winY = _defaultWindowY.clamp(0.0, math.max(0.0, maxH - winH));
    }

    uiContext.beginFrame(frameInput);
    if (uiContext.beginWindow(
      'Engine Workbench',
      x: winX,
      y: winY,
      width: winW,
      height: winH,
    )) {
      final pad = uiContext.style.windowPadding;
      final innerX = winX + pad;
      final innerW = math.max(0.0, winW - pad * 2.0);
      final innerRight = innerX + innerW;
      final contentBottom = winY + winH - pad;

      // Top tab selector row
      final tabY = winY + uiContext.style.titleBarHeight + pad;
      const tabH = 24.0;
      const tabGap = 6.0;
      final tabW = math.max(24.0, (innerW - tabGap * 2.0) / 3.0);

      final hierarchyTabRect = VoxRect(innerX, tabY, tabW, tabH);
      if (_drawButton(
        uiContext,
        uiState,
        'wb_tab_hierarchy',
        'Hierarchy',
        hierarchyTabRect,
        active: activeTab == WorkbenchTab.hierarchy,
      )) {
        if (activeTab != WorkbenchTab.hierarchy) {
          activeTab = WorkbenchTab.hierarchy;
          uiState.scrollIndex = 0;
        }
      }

      final inspectorTabRect = VoxRect(
        hierarchyTabRect.right + tabGap,
        tabY,
        tabW,
        tabH,
      );
      if (_drawButton(
        uiContext,
        uiState,
        'wb_tab_inspector',
        'Inspector',
        inspectorTabRect,
        active: activeTab == WorkbenchTab.inspector,
      )) {
        if (activeTab != WorkbenchTab.inspector) {
          activeTab = WorkbenchTab.inspector;
          uiState.scrollIndex = 0;
        }
      }

      final profilerTabRect = VoxRect(
        inspectorTabRect.right + tabGap,
        tabY,
        tabW,
        tabH,
      );
      if (_drawButton(
        uiContext,
        uiState,
        'wb_tab_profiler',
        'Profiler',
        profilerTabRect,
        active: activeTab == WorkbenchTab.profiler,
      )) {
        if (activeTab != WorkbenchTab.profiler) {
          activeTab = WorkbenchTab.profiler;
          uiState.scrollIndex = 0;
        }
      }

      final sepY = tabY + tabH + 4.0;
      uiContext.drawList.addLine(
        innerX,
        sepY,
        innerRight,
        sepY,
        uiContext.style.separator,
      );

      final contentTop = sepY + 6.0;
      switch (activeTab) {
        case WorkbenchTab.hierarchy:
          _renderHierarchyTab(
            innerX: innerX,
            innerW: innerW,
            innerRight: innerRight,
            contentTop: contentTop,
            contentBottom: contentBottom,
          );
        case WorkbenchTab.inspector:
          _renderInspectorTab(
            innerX: innerX,
            innerW: innerW,
            innerRight: innerRight,
            contentTop: contentTop,
            contentBottom: contentBottom,
          );
        case WorkbenchTab.profiler:
          _renderProfilerTab(
            innerX: innerX,
            innerW: innerW,
            innerRight: innerRight,
            contentTop: contentTop,
            contentBottom: contentBottom,
          );
      }
    }
    uiContext.endWindow();

    final drawList = uiContext.endFrame();
    lastDrawList = drawList;
    return drawList;
  }

  /// Renders the current workbench [DrawList] to [encoder] via [uiRenderer].
  void encodeOverlay(
    RenderEncoder encoder,
    int viewportWidth,
    int viewportHeight,
  ) {
    if (!visible || lastDrawList == null) return;
    uiRenderer
      ..designWidth = designWidth
      ..designHeight = designHeight
      ..font = font;
    lastRenderedCommands = uiRenderer.renderDrawList(
      lastDrawList!,
      encoder,
      viewportWidth: viewportWidth,
      viewportHeight: viewportHeight,
    );
  }

  void _renderHierarchyTab({
    required double innerX,
    required double innerW,
    required double innerRight,
    required double contentTop,
    required double contentBottom,
  }) {
    final dl = uiContext.drawList;
    final entries = <({GameObject object, int depth})>[];
    if (isAttached) {
      void visit(GameObject go, int depth) {
        if (go.isDestroyed || go._destroyRequested) return;
        entries.add((object: go, depth: depth));
        for (final child in go.children) {
          visit(child, depth + 1);
        }
      }

      for (final root in scene.rootGameObjects) {
        visit(root, 0);
      }
    }

    dl.addText(
      'Objects: ${entries.length} | Sel: ${selectedObject?.name ?? 'None'}',
      innerX,
      contentTop + 2.0,
      color: VoxColor.cyan,
      size: uiContext.style.fontSize,
    );

    const listOffsetY = 24.0;
    const rowH = 22.0;
    const rowStride = 24.0;
    final listTop = contentTop + listOffsetY;
    final maxVisible = math.max(
      1,
      ((contentBottom - listTop) / rowStride).floor(),
    );
    final maxScroll = math.max(0, entries.length - maxVisible);
    uiState.scrollIndex = uiState.scrollIndex.clamp(0, maxScroll);

    if (innerW >= 180.0) {
      final upRect = VoxRect(innerRight - 52.0, contentTop, 24.0, 18.0);
      if (_drawButton(uiContext, uiState, 'wb_hier_up', '^', upRect)) {
        uiState.scrollIndex = math.max(0, uiState.scrollIndex - 1);
      }
      final dnRect = VoxRect(innerRight - 24.0, contentTop, 24.0, 18.0);
      if (_drawButton(uiContext, uiState, 'wb_hier_dn', 'v', dnRect)) {
        uiState.scrollIndex = math.min(maxScroll, uiState.scrollIndex + 1);
      }
    }

    if (entries.isEmpty) {
      dl.addText(
        'Scene has no GameObjects.',
        innerX,
        listTop + 4.0,
        color: uiContext.style.textDisabled,
        size: uiContext.style.fontSize,
      );
      return;
    }

    final visibleCount = math.min(
      maxVisible,
      entries.length - uiState.scrollIndex,
    );
    for (var i = 0; i < visibleCount; i++) {
      final idx = uiState.scrollIndex + i;
      final entry = entries[idx];
      final go = entry.object;
      final rowY = listTop + i * rowStride;
      if (rowY + rowH > contentBottom) break;

      final indent = math.min(entry.depth, 5) * 12.0;
      const toggleW = 44.0;
      const gap = 4.0;
      final selectW = math.max(40.0, innerW - indent - toggleW - gap);
      final selectRect = VoxRect(innerX + indent, rowY, selectW, rowH);
      final prefix = entry.depth > 0
          ? '${' ' * math.min(entry.depth, 4)}- '
          : '';
      final isSelected = identical(selectedObject, go);

      if (_drawButton(
        uiContext,
        uiState,
        'wb_hier_sel_$idx',
        '$prefix${go.name}',
        selectRect,
        active: isSelected,
        alignLeft: true,
      )) {
        selectedObject = go;
      }

      final toggleRect = VoxRect(innerRight - toggleW, rowY, toggleW, rowH);
      if (_drawButton(
        uiContext,
        uiState,
        'wb_hier_act_$idx',
        go.activeSelf ? '[on]' : '[off]',
        toggleRect,
        active: go.activeSelf,
      )) {
        go.setActive(!go.activeSelf);
      }
    }
  }

  void _renderInspectorTab({
    required double innerX,
    required double innerW,
    required double innerRight,
    required double contentTop,
    required double contentBottom,
  }) {
    final dl = uiContext.drawList;
    final target = selectedObject;
    if (target == null || target.isDestroyed) {
      dl.addText(
        'No GameObject selected.',
        innerX,
        contentTop + 4.0,
        color: uiContext.style.textDisabled,
        size: uiContext.style.fontSize,
      );
      return;
    }

    dl.addText(
      '${target.name} (${target.activeSelf ? 'Active' : 'Inactive'})',
      innerX,
      contentTop + 2.0,
      color: VoxColor.cyan,
      size: uiContext.style.fontSize,
    );

    final reg =
        registry ??
        (isAttached && scene.isLoaded ? engine.registry : _fallbackRegistry);

    final rows = <_InspectorRow>[
      _InspectorRow.header('Transform'),
      _InspectorRow.number(
        id: 'tx_pos_x',
        label: 'Position X',
        read: () => target.transform.position.x,
        write: (v) {
          final p = target.transform.position;
          target.transform.position = Vec3(v, p.y, p.z);
        },
        step: 0.5,
      ),
      _InspectorRow.number(
        id: 'tx_pos_y',
        label: 'Position Y',
        read: () => target.transform.position.y,
        write: (v) {
          final p = target.transform.position;
          target.transform.position = Vec3(p.x, v, p.z);
        },
        step: 0.5,
      ),
      _InspectorRow.number(
        id: 'tx_pos_z',
        label: 'Position Z',
        read: () => target.transform.position.z,
        write: (v) {
          final p = target.transform.position;
          target.transform.position = Vec3(p.x, p.y, v);
        },
        step: 0.5,
      ),
    ];

    var compIndex = 0;
    for (final c in target.components) {
      if (c is TransformComponent || c.isDestroyed) continue;
      final spec = reg.specFor(c);
      if (spec == null) {
        rows.add(_InspectorRow.header('${c.runtimeType} (unregistered)'));
        compIndex++;
        continue;
      }

      rows.add(_InspectorRow.header(spec.typeName));
      for (final field in spec.fields) {
        final fieldId = 'c${compIndex}_${spec.typeName}_${field.name}';
        switch (field.kind) {
          case FieldKind.boolean:
            rows.add(
              _InspectorRow.boolean(
                id: fieldId,
                label: field.name,
                read: () => field.getter(c) as bool,
                write: (v) => field.setter(c, v),
              ),
            );
          case FieldKind.number:
            rows.add(
              _InspectorRow.number(
                id: fieldId,
                label: field.name,
                read: () => (field.getter(c) as num).toDouble(),
                write: (v) => field.setter(c, v),
                step: 0.1,
              ),
            );
          case FieldKind.integer:
            rows.add(
              _InspectorRow.integer(
                id: fieldId,
                label: field.name,
                read: () => (field.getter(c) as num).toInt(),
                write: (v) => field.setter(c, v),
              ),
            );
          case FieldKind.text:
            rows.add(
              _InspectorRow.text(
                label: field.name,
                read: () => field.getter(c).toString(),
              ),
            );
          case FieldKind.vec3:
            rows.add(
              _InspectorRow.text(
                label: field.name,
                read: () {
                  final v = field.getter(c) as Vec3;
                  return '(${v.x.toStringAsFixed(1)}, ${v.y.toStringAsFixed(1)}, ${v.z.toStringAsFixed(1)})';
                },
              ),
            );
          case FieldKind.quat:
            rows.add(
              _InspectorRow.text(
                label: field.name,
                read: () {
                  final q = field.getter(c) as Quat;
                  return '(${q.x.toStringAsFixed(2)}, ${q.y.toStringAsFixed(2)}, ${q.z.toStringAsFixed(2)}, ${q.w.toStringAsFixed(2)})';
                },
              ),
            );
          case FieldKind.color:
            rows.add(
              _InspectorRow.color(
                label: field.name,
                read: () => field.getter(c) as LinearColor,
              ),
            );
          case FieldKind.enumeration:
            rows.add(
              _InspectorRow.text(
                label: field.name,
                read: () => (field.getter(c) as Enum).name,
              ),
            );
        }
      }
      compIndex++;
    }

    const listOffsetY = 24.0;
    const rowH = 22.0;
    const rowStride = 24.0;
    final listTop = contentTop + listOffsetY;
    final maxVisible = math.max(
      1,
      ((contentBottom - listTop) / rowStride).floor(),
    );
    final maxScroll = math.max(0, rows.length - maxVisible);
    uiState.scrollIndex = uiState.scrollIndex.clamp(0, maxScroll);

    if (innerW >= 180.0) {
      final upRect = VoxRect(innerRight - 52.0, contentTop, 24.0, 18.0);
      if (_drawButton(uiContext, uiState, 'wb_insp_up', '^', upRect)) {
        uiState.scrollIndex = math.max(0, uiState.scrollIndex - 1);
      }
      final dnRect = VoxRect(innerRight - 24.0, contentTop, 24.0, 18.0);
      if (_drawButton(uiContext, uiState, 'wb_insp_dn', 'v', dnRect)) {
        uiState.scrollIndex = math.min(maxScroll, uiState.scrollIndex + 1);
      }
    }

    final visibleCount = math.min(
      maxVisible,
      rows.length - uiState.scrollIndex,
    );
    for (var i = 0; i < visibleCount; i++) {
      final row = rows[uiState.scrollIndex + i];
      final rowY = listTop + i * rowStride;
      if (rowY + rowH > contentBottom) break;

      switch (row.kind) {
        case _InspectorRowKind.header:
          dl.addRectFilled(
            innerX,
            rowY,
            innerW,
            rowH,
            uiContext.style.headerBg,
            cornerRadius: uiContext.style.frameRounding,
          );
          dl.addText(
            row.label,
            innerX + 6.0,
            rowY + (rowH - uiContext.style.fontSize) * 0.5,
            color: VoxColor.yellow,
            size: uiContext.style.fontSize,
          );
        case _InspectorRowKind.boolean:
          final val = row.readBool!();
          dl.addText(
            row.label,
            innerX + 4.0,
            rowY + (rowH - uiContext.style.fontSize) * 0.5,
            color: uiContext.style.text,
            size: uiContext.style.fontSize,
          );
          final toggleRect = VoxRect(innerRight - 56.0, rowY, 56.0, rowH);
          if (_drawButton(
            uiContext,
            uiState,
            'wb_bool_${row.id}',
            val ? 'true' : 'false',
            toggleRect,
            active: val,
          )) {
            row.writeBool!(!val);
          }
        case _InspectorRowKind.number:
          final val = row.readDouble!();
          dl.addText(
            '${row.label}: ${val.toStringAsFixed(2)}',
            innerX + 4.0,
            rowY + (rowH - uiContext.style.fontSize) * 0.5,
            color: uiContext.style.text,
            size: uiContext.style.fontSize,
          );
          final minusRect = VoxRect(innerRight - 56.0, rowY, 26.0, rowH);
          if (_drawButton(
            uiContext,
            uiState,
            'wb_num_sub_${row.id}',
            '-',
            minusRect,
          )) {
            final next = ((val - row.step) * 10000.0).roundToDouble() / 10000.0;
            row.writeDouble!(next);
          }
          final plusRect = VoxRect(innerRight - 26.0, rowY, 26.0, rowH);
          if (_drawButton(
            uiContext,
            uiState,
            'wb_num_add_${row.id}',
            '+',
            plusRect,
          )) {
            final next = ((val + row.step) * 10000.0).roundToDouble() / 10000.0;
            row.writeDouble!(next);
          }
        case _InspectorRowKind.integer:
          final val = row.readInt!();
          dl.addText(
            '${row.label}: $val',
            innerX + 4.0,
            rowY + (rowH - uiContext.style.fontSize) * 0.5,
            color: uiContext.style.text,
            size: uiContext.style.fontSize,
          );
          final minusRect = VoxRect(innerRight - 56.0, rowY, 26.0, rowH);
          if (_drawButton(
            uiContext,
            uiState,
            'wb_int_sub_${row.id}',
            '-',
            minusRect,
          )) {
            row.writeInt!(val - 1);
          }
          final plusRect = VoxRect(innerRight - 26.0, rowY, 26.0, rowH);
          if (_drawButton(
            uiContext,
            uiState,
            'wb_int_add_${row.id}',
            '+',
            plusRect,
          )) {
            row.writeInt!(val + 1);
          }
        case _InspectorRowKind.text:
          dl.addText(
            '${row.label}: ${row.readText!()}',
            innerX + 4.0,
            rowY + (rowH - uiContext.style.fontSize) * 0.5,
            color: VoxColor.lightGray,
            size: uiContext.style.fontSize,
          );
        case _InspectorRowKind.color:
          final c = row.readColor!();
          dl.addText(
            '${row.label}: (${c.r.toStringAsFixed(2)}, ${c.g.toStringAsFixed(2)}, ${c.b.toStringAsFixed(2)})',
            innerX + 4.0,
            rowY + (rowH - uiContext.style.fontSize) * 0.5,
            color: VoxColor.lightGray,
            size: uiContext.style.fontSize,
          );
          final swatchColor = VoxColor(
            (c.r.clamp(0.0, 1.0) * 255.0).round(),
            (c.g.clamp(0.0, 1.0) * 255.0).round(),
            (c.b.clamp(0.0, 1.0) * 255.0).round(),
          );
          dl.addRectFilled(
            innerRight - 26.0,
            rowY + 2.0,
            24.0,
            rowH - 4.0,
            swatchColor,
            cornerRadius: 2.0,
          );
          dl.addRectOutline(
            innerRight - 26.0,
            rowY + 2.0,
            24.0,
            rowH - 4.0,
            uiContext.style.windowBorder,
            cornerRadius: 2.0,
          );
      }
    }
  }

  void _renderProfilerTab({
    required double innerX,
    required double innerW,
    required double innerRight,
    required double contentTop,
    required double contentBottom,
  }) {
    final dl = uiContext.drawList;
    final hasScene = isAttached && scene.isLoaded;
    final unscaledDt = hasScene ? time.unscaledDeltaTime : 0.0;
    final instantFps = unscaledDt > 1e-6 ? 1.0 / unscaledDt : 0.0;
    final frameCount = hasScene ? time.frameCount : 0;
    final timeScale = hasScene ? time.timeScale : 1.0;

    final activeObjects = isAttached
        ? scene._allObjects(includeInactive: false).length
        : 0;
    final cameraCount = isAttached
        ? scene.findObjectsOfType<Camera>().length
        : 0;
    final meshRendererCount = isAttached
        ? scene.findObjectsOfType<MeshRenderer>().length
        : 0;
    final lightCount = isAttached ? scene.findObjectsOfType<Light>().length : 0;
    final debugCtrl = isAttached
        ? scene.findObjectOfType<DebugController>()
        : null;

    var y = contentTop;
    const lineStep = 20.0;

    void drawLineRow(String label, String value, VoxColor valueColor) {
      if (y + 18.0 > contentBottom) return;
      dl.addText(
        '$label: ',
        innerX,
        y,
        color: uiContext.style.text,
        size: uiContext.style.fontSize,
      );
      final labelW = (label.length + 2) * (uiContext.style.fontSize * 0.6);
      dl.addText(
        value,
        innerX + labelW,
        y,
        color: valueColor,
        size: uiContext.style.fontSize,
      );
      y += lineStep;
    }

    drawLineRow(
      'FPS / dt',
      '${instantFps.toStringAsFixed(1)} fps | ${(unscaledDt * 1000.0).toStringAsFixed(2)} ms',
      VoxColor.cyan,
    );
    drawLineRow(
      'Frame / Scale',
      '#$frameCount | ${timeScale.toStringAsFixed(2)}x',
      VoxColor.lightGray,
    );
    drawLineRow('Active Objects', '$activeObjects', VoxColor.green);
    drawLineRow('Cameras', '$cameraCount', VoxColor.lightGray);
    drawLineRow('MeshRenderers', '$meshRendererCount', VoxColor.lightGray);
    drawLineRow('Lights', '$lightCount', VoxColor.yellow);

    if (y + 6.0 <= contentBottom) {
      dl.addLine(
        innerX,
        y + 2.0,
        innerRight,
        y + 2.0,
        uiContext.style.separator,
      );
      y += 10.0;
    }

    if (debugCtrl != null) {
      final m = debugCtrl.metrics();
      drawLineRow(
        'DebugController',
        'FPS ${m.fps.toStringAsFixed(1)} | p50 ${m.p50FrameMs.toStringAsFixed(1)}ms | p95 ${m.p95FrameMs.toStringAsFixed(1)}ms',
        VoxColor.cyan,
      );
      drawLineRow(
        'Populations',
        'Beh ${m.activeBehaviourCount} | Col ${m.colliderCount} | Pfx ${m.particleSystemCount}',
        VoxColor.green,
      );
      drawLineRow(
        'Fixed / State',
        '${m.fixedStepsLastFrame} steps | ${m.paused ? 'PAUSED' : 'RUNNING'}',
        m.paused ? VoxColor.yellow : VoxColor.lightGray,
      );

      if (y + 24.0 <= contentBottom && innerW >= 180.0) {
        final pauseRect = VoxRect(innerX, y + 2.0, 96.0, 22.0);
        if (_drawButton(
          uiContext,
          uiState,
          'wb_prof_pause',
          debugCtrl.isPaused ? 'Resume' : 'Pause',
          pauseRect,
          active: debugCtrl.isPaused,
        )) {
          debugCtrl.togglePause();
        }
        final stepRect = VoxRect(pauseRect.right + 8.0, y + 2.0, 96.0, 22.0);
        if (_drawButton(
          uiContext,
          uiState,
          'wb_prof_step',
          'Step Fixed',
          stepRect,
        )) {
          debugCtrl.stepSingleFrame();
        }
      }
    } else {
      drawLineRow(
        'DebugController',
        'Not attached',
        uiContext.style.textDisabled,
      );
    }
  }

  static bool _drawButton(
    VoxUiContext ui,
    EngineWorkbenchUiState state,
    String id,
    String label,
    VoxRect rect, {
    bool active = false,
    bool alignLeft = false,
  }) {
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
    final textX = alignLeft
        ? rect.x + 6.0
        : rect.x + math.max(4.0, (rect.width - textW) * 0.5);
    dl.addText(
      label,
      textX,
      rect.y + (rect.height - ui.style.fontSize) * 0.5,
      color: ui.style.text,
      size: ui.style.fontSize,
    );
    return clicked;
  }
}

enum _InspectorRowKind { header, boolean, number, integer, text, color }

final class _InspectorRow {
  final _InspectorRowKind kind;
  final String id;
  final String label;
  final double step;
  final bool Function()? readBool;
  final void Function(bool)? writeBool;
  final double Function()? readDouble;
  final void Function(double)? writeDouble;
  final int Function()? readInt;
  final void Function(int)? writeInt;
  final String Function()? readText;
  final LinearColor Function()? readColor;

  const _InspectorRow._({
    required this.kind,
    this.id = '',
    required this.label,
    this.step = 0.1,
    this.readBool,
    this.writeBool,
    this.readDouble,
    this.writeDouble,
    this.readInt,
    this.writeInt,
    this.readText,
    this.readColor,
  });

  factory _InspectorRow.header(String title) =>
      _InspectorRow._(kind: _InspectorRowKind.header, label: title);

  factory _InspectorRow.boolean({
    required String id,
    required String label,
    required bool Function() read,
    required void Function(bool) write,
  }) => _InspectorRow._(
    kind: _InspectorRowKind.boolean,
    id: id,
    label: label,
    readBool: read,
    writeBool: write,
  );

  factory _InspectorRow.number({
    required String id,
    required String label,
    required double Function() read,
    required void Function(double) write,
    double step = 0.1,
  }) => _InspectorRow._(
    kind: _InspectorRowKind.number,
    id: id,
    label: label,
    step: step,
    readDouble: read,
    writeDouble: write,
  );

  factory _InspectorRow.integer({
    required String id,
    required String label,
    required int Function() read,
    required void Function(int) write,
  }) => _InspectorRow._(
    kind: _InspectorRowKind.integer,
    id: id,
    label: label,
    readInt: read,
    writeInt: write,
  );

  factory _InspectorRow.text({
    required String label,
    required String Function() read,
  }) => _InspectorRow._(
    kind: _InspectorRowKind.text,
    label: label,
    readText: read,
  );

  factory _InspectorRow.color({
    required String label,
    required LinearColor Function() read,
  }) => _InspectorRow._(
    kind: _InspectorRowKind.color,
    label: label,
    readColor: read,
  );
}
