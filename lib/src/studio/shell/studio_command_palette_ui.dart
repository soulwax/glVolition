/// Pure-Dart Unity Quick Search / Command Palette (`Ctrl+K`) (`[Wave G16]`):
/// Floating fuzzy-search modal over all registered Studio menu commands,
/// active Scene `GameObject`s (select & frame), CLI actions, and workspace
/// layout presets.
library;

import '../../../gl_volition.dart';
import 'studio_shortcuts.dart';
import 'studio_workspace_ui.dart';

/// Category tag shown beside each Command Palette search result.
enum PaletteItemKind { command, gameObject, cli, layout }

/// Single executable entry in the Quick Search / Command Palette.
final class PaletteEntry {
  final String title;
  final String subtitle;
  final PaletteItemKind kind;
  final void Function() onExecute;

  const PaletteEntry({
    required this.title,
    required this.subtitle,
    required this.kind,
    required this.onExecute,
  });
}

/// Interactive Quick Search / Command Palette controller (`[Wave G16]`).
final class StudioCommandPaletteController {
  bool isOpen = false;
  String query = '';
  int selectedIndex = 0;

  void open() {
    isOpen = true;
    query = '';
    selectedIndex = 0;
  }

  void close() {
    isOpen = false;
    query = '';
    selectedIndex = 0;
  }

  /// Collects and fuzzy-filters matching [PaletteEntry] items for [shell].
  List<PaletteEntry> queryEntries(StudioWorkspaceShell shell) {
    final all = <PaletteEntry>[];

    // 1. Registered Studio menu items
    for (final item in shell.menus.all) {
      all.add(
        PaletteEntry(
          title: item.menuPath,
          subtitle: 'Menu',
          kind: PaletteItemKind.command,
          onExecute: () => shell.menus.trigger(item.id),
        ),
      );
    }

    // 2. Active Scene GameObjects (select & frame in Scene View)
    void collectObjects(List<GameObject> nodes) {
      for (final go in nodes) {
        if (go.isDestroyed) continue;
        all.add(
          PaletteEntry(
            title: go.name,
            subtitle: 'Select & Frame GameObject',
            kind: PaletteItemKind.gameObject,
            onExecute: () {
              shell.bridge.selectObjects([go]);
              shell.sceneViewport.editorCamera.target = go.transform.position;
              shell.sceneViewport.editorCamera.distance = 6.0;
            },
          ),
        );
        if (go.children.isNotEmpty) collectObjects(go.children);
      }
    }

    collectObjects(shell.bridge.session.engine.scene.rootGameObjects);

    // 3. Built-in CLI actions
    all.addAll([
      PaletteEntry(
        title: 'CLI: volition doctor',
        subtitle: 'Inspect toolchain readiness',
        kind: PaletteItemKind.cli,
        onExecute: () => shell.cli.execute(const ['doctor']),
      ),
      PaletteEntry(
        title: 'CLI: volition codegen --check',
        subtitle: 'Verify generated @Serialized specs',
        kind: PaletteItemKind.cli,
        onExecute: () => shell.cli.execute(const ['codegen', '--check']),
      ),
      PaletteEntry(
        title: 'CLI: volition dist --studio --dry-run',
        subtitle: 'Preview portable AOT Studio bundle',
        kind: PaletteItemKind.cli,
        onExecute: () =>
            shell.cli.execute(const ['dist', '--studio', '--dry-run']),
      ),
    ]);

    // 4. Layout presets
    for (final preset in const ['Default', 'Wide', '2 by 3']) {
      all.add(
        PaletteEntry(
          title: 'Layout: $preset',
          subtitle: 'Switch Unity docking preset',
          kind: PaletteItemKind.layout,
          onExecute: () => shell.applyLayoutPreset(preset),
        ),
      );
    }

    final q = query.trim().toLowerCase();
    if (q.isEmpty) return all.take(12).toList();

    final matches = all.where((e) {
      final hay = '${e.title} ${e.subtitle}'.toLowerCase();
      return hay.contains(q);
    }).toList();
    return matches.take(12).toList();
  }

  /// Renders the floating Command Palette modal into [dl] (overlay layer) and
  /// handles keyboard typing, navigation, Enter execution, and mouse clicks.
  void render({
    required StudioWorkspaceShell shell,
    required DrawList dl,
    required VoxInput input,
    StudioKeyboardState? keyboard,
    required double width,
    required double height,
  }) {
    if (!isOpen) return;

    if (keyboard != null) {
      if (keyboard.wasPressed('escape')) {
        close();
        return;
      }
      if (keyboard.backspace && query.isNotEmpty) {
        query = query.substring(0, query.length - 1);
        selectedIndex = 0;
      }
      if (keyboard.typedText.isNotEmpty) {
        query += keyboard.typedText;
        selectedIndex = 0;
      }
    }

    final entries = queryEntries(shell);
    if (entries.isEmpty) {
      selectedIndex = 0;
    } else {
      if (keyboard != null && keyboard.wasPressed('arrowdown')) {
        selectedIndex = (selectedIndex + 1) % entries.length;
      }
      if (keyboard != null && keyboard.wasPressed('arrowup')) {
        selectedIndex = (selectedIndex - 1 + entries.length) % entries.length;
      }
      if (keyboard != null && keyboard.wasPressed('enter')) {
        final chosen = entries[selectedIndex.clamp(0, entries.length - 1)];
        close();
        chosen.onExecute();
        return;
      }
    }

    // Floating centered modal near top of window (VS Code / Unity Quick Search style)
    final mw = (width * 0.48).clamp(380.0, 560.0);
    const rowH = 26.0;
    final mh = 44.0 + (entries.isEmpty ? 32.0 : entries.length * rowH + 8.0);
    final mx = (width - mw) * 0.5;
    final my = 68.0;
    final modalRect = VoxRect(mx, my, mw, mh);

    dl.addRectFilled(
      mx,
      my,
      mw,
      mh,
      const VoxColor(38, 40, 46, 248),
      cornerRadius: 6,
    );
    dl.addRectOutline(
      mx,
      my,
      mw,
      mh,
      const VoxColor(58, 121, 187, 255),
      thickness: 2,
    );

    // Search input box
    dl.addRectFilled(
      mx + 10,
      my + 10,
      mw - 20,
      26,
      const VoxColor(26, 28, 32, 255),
      cornerRadius: 3,
    );
    dl.addText(
      query.isEmpty
          ? 'Quick Search (Ctrl+K): commands, objects, CLI...'
          : query,
      mx + 18,
      my + 17,
      color: query.isEmpty
          ? const VoxColor(140, 146, 156, 255)
          : const VoxColor(240, 242, 246, 255),
      size: 11,
    );

    if (entries.isEmpty) {
      dl.addText(
        'No matching commands or objects.',
        mx + 16,
        my + 48,
        color: const VoxColor(150, 155, 165, 255),
        size: 11,
      );
    } else {
      for (var i = 0; i < entries.length; i++) {
        final entry = entries[i];
        final rr = VoxRect(mx + 8, my + 42 + i * rowH, mw - 16, rowH - 2);
        final hov = rr.contains(input.mouseX, input.mouseY);
        final isSel = i == selectedIndex || hov;
        if (isSel) {
          dl.addRectFilled(
            rr.x,
            rr.y,
            rr.width,
            rr.height,
            const VoxColor(58, 121, 187, 255),
            cornerRadius: 3,
          );
        }
        final badge = switch (entry.kind) {
          PaletteItemKind.command => '[CMD]',
          PaletteItemKind.gameObject => '[OBJ]',
          PaletteItemKind.cli => '[CLI]',
          PaletteItemKind.layout => '[LAY]',
        };
        dl.addText(
          '$badge ${entry.title}',
          rr.x + 8,
          rr.y + 5,
          color: const VoxColor(238, 240, 245, 255),
          size: 11,
        );
        if (hov && input.wasMouseClicked) {
          close();
          entry.onExecute();
          return;
        }
      }
    }

    if (input.wasMouseClicked &&
        !modalRect.contains(input.mouseX, input.mouseY)) {
      close();
    }
  }
}
