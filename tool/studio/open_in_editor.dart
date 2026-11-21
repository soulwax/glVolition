/// Daemon helper to open a source `file:line` in the configured external
/// editor (defaults to VS Code `code -g`, `[S2-D]`).
library;

import 'dart:io';

/// Builds the executable and argument vector for opening [filePath] at [line].
({String executable, List<String> arguments}) buildOpenInEditorCommand(
  String filePath,
  int line, {
  int? column,
  String editor = 'code',
}) {
  final target = column != null ? '$filePath:$line:$column' : '$filePath:$line';
  final lower = editor.trim().toLowerCase();
  if (lower == 'code' ||
      lower.endsWith('code.exe') ||
      lower.endsWith('code.cmd')) {
    return (executable: editor, arguments: ['-g', target]);
  }
  return (executable: editor, arguments: [target]);
}

/// Spawns the configured editor detached without blocking the Studio daemon.
Future<bool> openFileInEditor(
  String filePath,
  int line, {
  int? column,
  String editor = 'code',
}) async {
  final cmd = buildOpenInEditorCommand(
    filePath,
    line,
    column: column,
    editor: editor,
  );
  try {
    await Process.start(
      cmd.executable,
      cmd.arguments,
      mode: ProcessStartMode.detached,
      runInShell: Platform.isWindows,
    );
    return true;
  } catch (_) {
    return false;
  }
}
