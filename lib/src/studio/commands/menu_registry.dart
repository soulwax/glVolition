/// Pure-Dart Volition Studio menu & keyboard shortcut registry (S2-0).
///
/// Supports hierarchical menu paths such as `GameObject/Create/Cube`,
/// `Assets/Create/Material`, and `Window/Hierarchy`.
library;

/// Platform-neutral keyboard shortcut chord.
final class StudioShortcut {
  final String key;
  final bool ctrl;
  final bool shift;
  final bool alt;

  const StudioShortcut(
    this.key, {
    this.ctrl = false,
    this.shift = false,
    this.alt = false,
  });

  bool matches({
    required String key,
    bool ctrl = false,
    bool shift = false,
    bool alt = false,
  }) =>
      this.key.toLowerCase() == key.toLowerCase() &&
      this.ctrl == ctrl &&
      this.shift == shift &&
      this.alt == alt;

  String get displayLabel {
    final parts = <String>[
      if (ctrl) 'Ctrl',
      if (shift) 'Shift',
      if (alt) 'Alt',
      key.toUpperCase(),
    ];
    return parts.join('+');
  }
}

/// Single registered menu command item.
final class StudioMenuItem {
  final String id;
  final String menuPath;
  final StudioShortcut? shortcut;
  final int order;
  final bool Function()? isEnabled;
  final void Function()? action;

  const StudioMenuItem({
    required this.id,
    required this.menuPath,
    this.shortcut,
    this.order = 0,
    this.isEnabled,
    this.action,
  });

  List<String> get segments => menuPath
      .split('/')
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();

  String get label => segments.isEmpty ? id : segments.last;
}

/// Tree node returned by [StudioMenuRegistry.buildTree].
final class StudioMenuNode {
  final String label;
  final StudioMenuItem? item;
  final List<StudioMenuNode> children;

  const StudioMenuNode({
    required this.label,
    this.item,
    this.children = const [],
  });

  bool get isLeaf => item != null && children.isEmpty;
}

/// Central registry for Studio top-level menus, context actions, and shortcuts.
final class StudioMenuRegistry {
  final Map<String, StudioMenuItem> _byId = {};

  StudioMenuRegistry({bool registerDefaults = false}) {
    if (registerDefaults) {
      this.registerDefaults();
    }
  }

  void register(StudioMenuItem item) {
    if (item.id.trim().isEmpty || item.menuPath.trim().isEmpty) {
      throw ArgumentError('StudioMenuItem requires non-empty id and menuPath');
    }
    _byId[item.id] = item;
  }

  bool unregister(String id) => _byId.remove(id) != null;

  StudioMenuItem? lookup(String id) => _byId[id];

  List<StudioMenuItem> get all =>
      List<StudioMenuItem>.unmodifiable(_byId.values);

  /// Triggers menu command [id] if registered and enabled.
  bool trigger(String id) {
    final item = _byId[id];
    if (item == null) return false;
    if (item.isEnabled != null && !item.isEnabled!()) return false;
    item.action?.call();
    return true;
  }

  /// Dispatches the first registered enabled item matching the keyboard chord.
  bool handleShortcut({
    required String key,
    bool ctrl = false,
    bool shift = false,
    bool alt = false,
  }) {
    for (final item in _byId.values) {
      final sc = item.shortcut;
      if (sc != null &&
          sc.matches(key: key, ctrl: ctrl, shift: shift, alt: alt)) {
        if (item.isEnabled != null && !item.isEnabled!()) continue;
        item.action?.call();
        return true;
      }
    }
    return false;
  }

  /// Builds a deterministic hierarchical menu tree grouped by `menuPath`.
  List<StudioMenuNode> buildTree() {
    final rootBuilder = _MutableMenuNode('');
    final items = _byId.values.toList()
      ..sort((a, b) {
        final cmp = a.order.compareTo(b.order);
        return cmp != 0 ? cmp : a.menuPath.compareTo(b.menuPath);
      });

    for (final item in items) {
      var cursor = rootBuilder;
      final segs = item.segments;
      for (var i = 0; i < segs.length; i++) {
        final seg = segs[i];
        cursor = cursor.children.putIfAbsent(seg, () => _MutableMenuNode(seg));
        if (i == segs.length - 1) {
          cursor.item = item;
        }
      }
    }

    StudioMenuNode freeze(_MutableMenuNode node) => StudioMenuNode(
      label: node.label,
      item: node.item,
      children: [for (final c in node.children.values) freeze(c)],
    );

    return [for (final c in rootBuilder.children.values) freeze(c)];
  }

  /// Registers baseline Volition Studio menu paths (`File`, `Edit`,
  /// `GameObject/Create/...`, `Assets/Create/...`, `Window/...`).
  void registerDefaults() {
    const defaults = [
      StudioMenuItem(
        id: 'file.save_scene',
        menuPath: 'File/Save Scene',
        shortcut: StudioShortcut('s', ctrl: true),
        order: 10,
      ),
      StudioMenuItem(
        id: 'edit.undo',
        menuPath: 'Edit/Undo',
        shortcut: StudioShortcut('z', ctrl: true),
        order: 20,
      ),
      StudioMenuItem(
        id: 'edit.redo',
        menuPath: 'Edit/Redo',
        shortcut: StudioShortcut('y', ctrl: true),
        order: 21,
      ),
      StudioMenuItem(
        id: 'gameobject.create.empty',
        menuPath: 'GameObject/Create/Empty',
        shortcut: StudioShortcut('n', ctrl: true, shift: true),
        order: 30,
      ),
      StudioMenuItem(
        id: 'gameobject.create.cube',
        menuPath: 'GameObject/Create/3D Object/Cube',
        order: 31,
      ),
      StudioMenuItem(
        id: 'gameobject.create.camera',
        menuPath: 'GameObject/Create/Camera',
        order: 32,
      ),
      StudioMenuItem(
        id: 'gameobject.create.light',
        menuPath: 'GameObject/Create/Light/Directional Light',
        order: 33,
      ),
      StudioMenuItem(
        id: 'assets.create.folder',
        menuPath: 'Assets/Create/Folder',
        order: 40,
      ),
      StudioMenuItem(
        id: 'assets.create.material',
        menuPath: 'Assets/Create/Material',
        order: 41,
      ),
      StudioMenuItem(
        id: 'assets.create.scene',
        menuPath: 'Assets/Create/Scene',
        order: 42,
      ),
      StudioMenuItem(
        id: 'assets.create.prefab',
        menuPath: 'Assets/Create/Prefab',
        order: 43,
      ),
      StudioMenuItem(id: 'window.scene', menuPath: 'Window/Scene', order: 50),
      StudioMenuItem(id: 'window.game', menuPath: 'Window/Game', order: 51),
      StudioMenuItem(
        id: 'window.hierarchy',
        menuPath: 'Window/Hierarchy',
        order: 52,
      ),
      StudioMenuItem(
        id: 'window.inspector',
        menuPath: 'Window/Inspector',
        order: 53,
      ),
      StudioMenuItem(
        id: 'window.project',
        menuPath: 'Window/Project',
        order: 54,
      ),
      StudioMenuItem(
        id: 'window.console',
        menuPath: 'Window/Console',
        order: 55,
      ),
    ];
    for (final item in defaults) {
      register(item);
    }
  }
}

final class _MutableMenuNode {
  final String label;
  StudioMenuItem? item;
  final Map<String, _MutableMenuNode> children = {};
  _MutableMenuNode(this.label);
}
