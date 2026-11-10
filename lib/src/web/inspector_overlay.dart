import 'dart:convert';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import '../../gl_volition.dart';

/// Browser-side live Hierarchy & Component Inspector overlay (E6-1..E6-4).
///
/// Toggle visibility with `F12` or `Alt+I`, or pick a 3D [GameObject] in the
/// viewport with `Alt + LeftClick`.
final class InspectorOverlay {
  final Engine engine;
  final web.HTMLCanvasElement canvas;

  web.HTMLDivElement? _root;
  web.HTMLDivElement? _treeContainer;
  web.HTMLDivElement? _inspectorContainer;

  GameObject? _selected;
  String _filter = '';
  bool _visible = false;

  late final JSFunction _onKeyDown = ((web.KeyboardEvent e) {
    if (e.code == 'F12' || (e.altKey && e.code == 'KeyI')) {
      e.preventDefault();
      toggle();
    }
  }).toJS;

  late final JSFunction _onCanvasClick = ((web.MouseEvent e) {
    if (!e.altKey || e.button != 0) return;
    final rect = canvas.getBoundingClientRect();
    if (rect.width <= 0 || rect.height <= 0) return;
    final x = (e.clientX - rect.left) * (canvas.width / rect.width);
    final y = (e.clientY - rect.top) * (canvas.height / rect.height);
    final cam = Camera.of(engine.scene);
    final ray = cam?.screenPointToRay(x, y);
    if (ray == null) return;

    final physHit = engine.scene.physics.raycast(ray);
    if (physHit != null) {
      select(physHit.gameObject);
      if (!_visible) show();
      return;
    }
    final visHit = engine.scene.raycastVisuals(ray);
    if (visHit != null) {
      select(visHit.$1);
      if (!_visible) show();
    }
  }).toJS;

  InspectorOverlay(this.engine, this.canvas) {
    web.window.addEventListener('keydown', _onKeyDown);
    canvas.addEventListener('mousedown', _onCanvasClick);
  }

  bool get isVisible => _visible;
  GameObject? get selected => _selected;

  void toggle() => _visible ? hide() : show();

  void show() {
    _visible = true;
    _ensureDom();
    _root!.style.display = 'flex';
    refresh();
  }

  void hide() {
    _visible = false;
    _root?.style.display = 'none';
  }

  void select(GameObject? object) {
    _selected = object;
    if (_visible) refresh();
  }

  void refresh() {
    if (!_visible) return;
    _ensureDom();
    _renderTree();
    _renderInspector();
  }

  void dispose() {
    web.window.removeEventListener('keydown', _onKeyDown);
    canvas.removeEventListener('mousedown', _onCanvasClick);
    _root?.remove();
    _root = null;
  }

  void _ensureDom() {
    if (_root != null) return;
    final doc = web.document;
    final panel = doc.createElement('div') as web.HTMLDivElement;
    panel.style.cssText =
        'position:fixed;top:8px;right:8px;bottom:8px;width:340px;'
        'background:rgba(14,13,24,0.93);color:#ece9f8;'
        'font:12px/1.4 ui-monospace,Consolas,monospace;'
        'border:1px solid #3c365c;border-radius:6px;z-index:99999;'
        'display:none;flex-direction:column;overflow:hidden;'
        'box-shadow:0 8px 28px rgba(0,0,0,0.55);';

    // Header bar
    final header = doc.createElement('div') as web.HTMLDivElement;
    header.style.cssText =
        'display:flex;align-items:center;justify-content:space-between;'
        'padding:6px 10px;background:#1c1930;border-bottom:1px solid #3c365c;'
        'font-weight:bold;gap:6px;';
    final title = doc.createElement('span') as web.HTMLSpanElement
      ..textContent = 'glVolition';

    final controls = doc.createElement('div') as web.HTMLDivElement;
    controls.style.cssText = 'display:flex;gap:4px;';

    const btnCss =
        'background:#322c56;color:#fff;border:1px solid #59508a;'
        'border-radius:4px;padding:2px 6px;cursor:pointer;font:inherit;';

    final playStopBtn = doc.createElement('button') as web.HTMLButtonElement
      ..textContent = engine.editor.isPlaying ? 'Stop' : 'Play'
      ..style.cssText = btnCss;
    playStopBtn.addEventListener(
      'click',
      ((web.Event _) {
        if (engine.editor.isPlaying) {
          if (!engine.editor.hasSnapshot) {
            engine.editor.captureBaselineSnapshot();
          }
          engine.editor.stopPlayMode();
          playStopBtn.textContent = 'Play';
        } else {
          engine.editor.enterPlayMode();
          playStopBtn.textContent = 'Stop';
        }
        refresh();
      }).toJS,
    );

    final freeCamBtn = doc.createElement('button') as web.HTMLButtonElement
      ..textContent = 'FreeCam'
      ..style.cssText = btnCss;
    freeCamBtn.addEventListener(
      'click',
      ((web.Event _) {
        engine.editor.selected = _selected;
        final next = !engine.editor.isFreeLookEnabled;
        engine.editor.setFreeLook(next);
        freeCamBtn.style.background = next ? '#5e4b9e' : '#322c56';
      }).toJS,
    );

    final exportBtn = doc.createElement('button') as web.HTMLButtonElement
      ..textContent = 'Save JSON'
      ..style.cssText = btnCss;
    exportBtn.addEventListener(
      'click',
      ((web.Event _) {
        final json = const JsonEncoder.withIndent('  ').convert(
          engine.scene.toJson(registry: engine.registry),
        );
        web.console.log(json.toJS);
        web.window
            .fetch(
              '/__rocket_save_scene'.toJS,
              web.RequestInit(method: 'POST', body: json.toJS),
            )
            .toDart
            .then(
              (_) => exportBtn.textContent = 'Saved!',
              onError: (Object _) => exportBtn.textContent = 'Logged!',
            );
      }).toJS,
    );

    final newObjBtn = doc.createElement('button') as web.HTMLButtonElement
      ..textContent = '+ Object'
      ..style.cssText = btnCss;
    newObjBtn.addEventListener(
      'click',
      ((web.Event _) {
        engine.editor.recordUndoState('create object');
        final count = engine.scene.rootGameObjects.length + 1;
        final created = engine.scene.createGameObject('GameObject_$count');
        _selected = created;
        refresh();
      }).toJS,
    );

    final undoBtn = doc.createElement('button') as web.HTMLButtonElement
      ..textContent = 'Undo'
      ..style.cssText = btnCss;
    undoBtn.addEventListener(
      'click',
      ((web.Event _) {
        if (engine.editor.undo()) {
          _selected = engine.editor.selected;
          refresh();
        }
      }).toJS,
    );

    final redoBtn = doc.createElement('button') as web.HTMLButtonElement
      ..textContent = 'Redo'
      ..style.cssText = btnCss;
    redoBtn.addEventListener(
      'click',
      ((web.Event _) {
        if (engine.editor.redo()) {
          _selected = engine.editor.selected;
          refresh();
        }
      }).toJS,
    );

    controls.append(newObjBtn);
    controls.append(undoBtn);
    controls.append(redoBtn);
    controls.append(playStopBtn);
    controls.append(freeCamBtn);
    controls.append(exportBtn);
    header.append(title);
    header.append(controls);

    // Search input
    final search = doc.createElement('input') as web.HTMLInputElement
      ..type = 'text'
      ..placeholder = 'Filter GameObjects...';
    search.style.cssText =
        'margin:6px 8px;padding:4px 6px;background:#121020;color:#fff;'
        'border:1px solid #3c365c;border-radius:4px;font:inherit;';
    search.addEventListener(
      'input',
      ((web.Event _) {
        _filter = search.value.trim().toLowerCase();
        _renderTree();
      }).toJS,
    );

    // Tree view
    final tree = doc.createElement('div') as web.HTMLDivElement;
    tree.style.cssText =
        'flex:0 0 42%;overflow-y:auto;padding:4px 8px;'
        'border-bottom:1px solid #3c365c;';
    _treeContainer = tree;

    // Inspector pane
    final inspector = doc.createElement('div') as web.HTMLDivElement;
    inspector.style.cssText = 'flex:1;overflow-y:auto;padding:8px 10px;';
    _inspectorContainer = inspector;

    panel.append(header);
    panel.append(search);
    panel.append(tree);
    panel.append(inspector);
    doc.body?.append(panel);
    _root = panel;
  }

  void _renderTree() {
    final container = _treeContainer;
    if (container == null) return;
    container.textContent = '';

    void addNode(GameObject go, int depth) {
      final matches = _filter.isEmpty ||
          go.name.toLowerCase().contains(_filter) ||
          go.tag.toLowerCase().contains(_filter);
      if (matches) {
        final row = web.document.createElement('div') as web.HTMLDivElement;
        final isSel = identical(go, _selected);
        row.style.cssText =
            'display:flex;align-items:center;gap:6px;'
            'padding:2px 4px;padding-left:${4 + depth * 12}px;'
            'cursor:pointer;border-radius:3px;'
            'background:${isSel ? "#3b3266" : "transparent"};';

        final cb = web.document.createElement('input') as web.HTMLInputElement
          ..type = 'checkbox'
          ..checked = go.activeSelf;
        cb.addEventListener(
          'change',
          ((web.Event e) {
            e.stopPropagation();
            go.setActive(cb.checked);
            refresh();
          }).toJS,
        );

        final label = web.document.createElement('span') as web.HTMLSpanElement
          ..textContent = '${go.name} ${go.tag != "Untagged" ? "[${go.tag}]" : ""}';
        if (!go.activeInHierarchy) {
          label.style.opacity = '0.45';
        }

        row.addEventListener(
          'click',
          ((web.Event _) {
            _selected = go;
            refresh();
          }).toJS,
        );

        row.append(cb);
        row.append(label);
        container.append(row);
      }
      for (final child in go.children) {
        addNode(child, depth + 1);
      }
    }

    for (final root in engine.scene.rootGameObjects) {
      addNode(root, 0);
    }
  }

  void _renderInspector() {
    final container = _inspectorContainer;
    if (container == null) return;
    container.textContent = '';

    final go = _selected;
    if (go == null || go.isDestroyed) {
      final empty = web.document.createElement('div') as web.HTMLDivElement
        ..textContent = 'Select a GameObject (or Alt+Click in viewport).';
      empty.style.opacity = '0.6';
      container.append(empty);
      return;
    }

    // Transform section
    final tTitle = web.document.createElement('div') as web.HTMLDivElement
      ..textContent = 'Transform (${go.name})';
    tTitle.style.cssText = 'font-weight:bold;margin-bottom:4px;color:#b8afff;';
    container.append(tTitle);

    _appendVec3Editor(
      container,
      'Position',
      () => go.transform.localPosition,
      (v) => go.transform.localPosition = v,
    );
    _appendNumberEditor(
      container,
      'Scale',
      () => go.transform.localScale,
      (v) => go.transform.localScale = v,
    );

    // Registered ComponentSpec sections
    for (final comp in go.components) {
      if (comp is TransformComponent) continue;
      final spec = engine.registry.specFor(comp);
      final header = web.document.createElement('div') as web.HTMLDivElement
        ..textContent = spec?.typeName ?? comp.runtimeType.toString();
      header.style.cssText =
          'font-weight:bold;margin-top:8px;margin-bottom:4px;color:#b8afff;'
          'border-top:1px solid #2b2742;padding-top:6px;';
      container.append(header);

      if (spec != null) {
        for (final field in spec.fields) {
          _appendSpecFieldEditor(container, comp, field);
        }
      }
    }

    // Action row: + Add Component dropdown and Delete Object button
    final actionRow = web.document.createElement('div') as web.HTMLDivElement;
    actionRow.style.cssText =
        'display:flex;gap:6px;margin-top:12px;padding-top:8px;'
        'border-top:1px solid #2b2742;align-items:center;';

    final addSelect = web.document.createElement('select') as web.HTMLSelectElement;
    addSelect.style.cssText =
        'flex:1;background:#18152b;color:#ece9f8;border:1px solid #3c365c;'
        'border-radius:4px;padding:3px 6px;font:inherit;';
    final placeholder = web.document.createElement('option') as web.HTMLOptionElement
      ..value = ''
      ..textContent = '+ Add Component...';
    addSelect.append(placeholder);
    for (final spec in engine.registry.registeredSpecs) {
      final opt = web.document.createElement('option') as web.HTMLOptionElement
        ..value = spec.typeName
        ..textContent = spec.typeName;
      addSelect.append(opt);
    }
    addSelect.addEventListener(
      'change',
      ((web.Event _) {
        final chosen = addSelect.value;
        if (chosen.isEmpty) return;
        final spec = engine.registry.specByName(chosen);
        if (spec != null) {
          go.addComponent(spec.create());
          refresh();
        }
      }).toJS,
    );

    final copyBtn = web.document.createElement('button') as web.HTMLButtonElement
      ..textContent = 'Copy'
      ..style.cssText =
          'background:#242038;color:#ece9f8;border:1px solid #4e4675;'
          'border-radius:4px;padding:3px 8px;cursor:pointer;font:inherit;';
    copyBtn.addEventListener(
      'click',
      ((web.Event _) {
        final clone = engine.editor.duplicate(go);
        if (clone != null) {
          _selected = clone;
          refresh();
        }
      }).toJS,
    );

    final deleteBtn = web.document.createElement('button') as web.HTMLButtonElement
      ..textContent = 'Delete'
      ..style.cssText =
          'background:#541f2d;color:#ffd2d8;border:1px solid #8a344c;'
          'border-radius:4px;padding:3px 8px;cursor:pointer;font:inherit;';
    deleteBtn.addEventListener(
      'click',
      ((web.Event _) {
        go.destroy();
        _selected = null;
        refresh();
      }).toJS,
    );

    actionRow.append(addSelect);
    actionRow.append(copyBtn);
    actionRow.append(deleteBtn);
    container.append(actionRow);
  }

  void _appendNumberEditor(
    web.HTMLElement parent,
    String label,
    double Function() get,
    void Function(double) set,
  ) {
    final row = web.document.createElement('div') as web.HTMLDivElement;
    row.style.cssText = 'display:flex;justify-content:space-between;align-items:center;margin:2px 0;';
    final span = web.document.createElement('span') as web.HTMLSpanElement..textContent = label;
    final input = web.document.createElement('input') as web.HTMLInputElement
      ..type = 'number'
      ..step = '0.1'
      ..value = get().toStringAsFixed(2);
    input.style.cssText =
        'width:90px;background:#121020;color:#fff;border:1px solid #3c365c;'
        'border-radius:3px;padding:1px 4px;font:inherit;';
    input.addEventListener(
      'change',
      ((web.Event _) {
        final v = double.tryParse(input.value);
        if (v != null && v.isFinite) set(v);
      }).toJS,
    );
    row.append(span);
    row.append(input);
    parent.append(row);
  }

  void _appendVec3Editor(
    web.HTMLElement parent,
    String label,
    Vec3 Function() get,
    void Function(Vec3) set,
  ) {
    final row = web.document.createElement('div') as web.HTMLDivElement;
    row.style.cssText = 'display:flex;justify-content:space-between;align-items:center;margin:2px 0;gap:4px;';
    final span = web.document.createElement('span') as web.HTMLSpanElement..textContent = label;
    final inputs = web.document.createElement('div') as web.HTMLDivElement;
    inputs.style.cssText = 'display:flex;gap:3px;';

    final cur = get();
    final ix = _smallNumberInput(cur.x);
    final iy = _smallNumberInput(cur.y);
    final iz = _smallNumberInput(cur.z);

    void apply() {
      final x = double.tryParse(ix.value) ?? get().x;
      final y = double.tryParse(iy.value) ?? get().y;
      final z = double.tryParse(iz.value) ?? get().z;
      set(Vec3(x, y, z));
    }

    ix.addEventListener('change', ((web.Event _) => apply()).toJS);
    iy.addEventListener('change', ((web.Event _) => apply()).toJS);
    iz.addEventListener('change', ((web.Event _) => apply()).toJS);

    inputs.append(ix);
    inputs.append(iy);
    inputs.append(iz);
    row.append(span);
    row.append(inputs);
    parent.append(row);
  }

  web.HTMLInputElement _smallNumberInput(double initial) {
    final input = web.document.createElement('input') as web.HTMLInputElement
      ..type = 'number'
      ..step = '0.1'
      ..value = initial.toStringAsFixed(2);
    input.style.cssText =
        'width:56px;background:#121020;color:#fff;border:1px solid #3c365c;'
        'border-radius:3px;padding:1px 3px;font:inherit;';
    return input;
  }

  void _appendSpecFieldEditor(
    web.HTMLElement parent,
    Component comp,
    Field<dynamic, dynamic> field,
  ) {
    final raw = field.readJson(comp);
    switch (field.kind) {
      case FieldKind.number:
        _appendNumberEditor(
          parent,
          field.name,
          () => (field.readJson(comp) as num).toDouble(),
          (v) => field.writeJson(comp, v),
        );
      case FieldKind.integer:
        _appendNumberEditor(
          parent,
          field.name,
          () => (field.readJson(comp) as num).toDouble(),
          (v) => field.writeJson(comp, v.round()),
        );
      case FieldKind.boolean:
        final row = web.document.createElement('div') as web.HTMLDivElement;
        row.style.cssText = 'display:flex;justify-content:space-between;align-items:center;margin:2px 0;';
        final span = web.document.createElement('span') as web.HTMLSpanElement..textContent = field.name;
        final cb = web.document.createElement('input') as web.HTMLInputElement
          ..type = 'checkbox'
          ..checked = raw == true;
        cb.addEventListener(
          'change',
          ((web.Event _) => field.writeJson(comp, cb.checked)).toJS,
        );
        row.append(span);
        row.append(cb);
        parent.append(row);
      case FieldKind.text:
      case FieldKind.enumeration:
        final row = web.document.createElement('div') as web.HTMLDivElement;
        row.style.cssText = 'display:flex;justify-content:space-between;align-items:center;margin:2px 0;';
        final span = web.document.createElement('span') as web.HTMLSpanElement..textContent = field.name;
        final input = web.document.createElement('input') as web.HTMLInputElement
          ..type = 'text'
          ..value = raw?.toString() ?? '';
        input.style.cssText =
            'width:110px;background:#121020;color:#fff;border:1px solid #3c365c;'
            'border-radius:3px;padding:1px 4px;font:inherit;';
        input.addEventListener(
          'change',
          ((web.Event _) => field.writeJson(comp, input.value)).toJS,
        );
        row.append(span);
        row.append(input);
        parent.append(row);
      case FieldKind.vec3:
      case FieldKind.color:
        _appendVec3Editor(
          parent,
          field.name,
          () {
            final list = field.readJson(comp) as List<Object?>;
            return Vec3(
              (list[0] as num).toDouble(),
              (list[1] as num).toDouble(),
              (list[2] as num).toDouble(),
            );
          },
          (v) => field.writeJson(comp, [v.x, v.y, v.z]),
        );
      case FieldKind.quat:
        break;
    }
  }
}
