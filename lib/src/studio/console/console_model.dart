/// Pure-Dart Console panel model (S2-D): captures logs and `reportError`
/// frames with collapse deduplication, level filters, search, and `file:line`
/// stack-frame extraction.
library;

import '../shell/dock_layout.dart';

enum ConsoleLogLevel { info, warning, error }

/// Parsed `file:line` location from a Dart stack frame.
final class ConsoleSourceLocation {
  final String filePath;
  final int line;
  final int? column;

  const ConsoleSourceLocation({
    required this.filePath,
    required this.line,
    this.column,
  });
}

/// Single log or error entry displayed in the Studio Console panel.
final class ConsoleLogEntry {
  final ConsoleLogLevel level;
  final String message;
  final String? stackTrace;
  final ConsoleSourceLocation? sourceLocation;
  final int timestampMs;
  final int count;

  const ConsoleLogEntry({
    required this.level,
    required this.message,
    this.stackTrace,
    this.sourceLocation,
    this.timestampMs = 0,
    this.count = 1,
  });

  ConsoleLogEntry copyWith({int? count, int? timestampMs}) => ConsoleLogEntry(
    level: level,
    message: message,
    stackTrace: stackTrace,
    sourceLocation: sourceLocation,
    timestampMs: timestampMs ?? this.timestampMs,
    count: count ?? this.count,
  );
}

/// Pure-Dart Console panel controller.
final class ConsolePanelModel implements StudioPanel {
  static final RegExp _stackLocPattern = RegExp(
    r'\((?:file:///?)?((?:[A-Za-z]:)?[^():\s]+):(\d+)(?::(\d+))?\)',
  );

  final int maxEntries;
  final List<ConsoleLogEntry> _entries = [];

  bool showInfo = true;
  bool showWarning = true;
  bool showError = true;
  bool collapseDuplicates = false;
  String searchQuery = '';

  ConsolePanelModel({this.maxEntries = 1000});

  @override
  String get id => 'console';

  @override
  String get title => 'Console';

  int get totalCount => _entries.length;
  int get infoCount =>
      _entries.where((e) => e.level == ConsoleLogLevel.info).length;
  int get warningCount =>
      _entries.where((e) => e.level == ConsoleLogLevel.warning).length;
  int get errorCount =>
      _entries.where((e) => e.level == ConsoleLogLevel.error).length;

  /// Extracts the first `(path:line[:col])` location from a Dart stack trace.
  static ConsoleSourceLocation? parseSourceLocation(String? stackTrace) {
    if (stackTrace == null || stackTrace.isEmpty) return null;
    final match = _stackLocPattern.firstMatch(stackTrace);
    if (match == null) return null;
    final filePath = match.group(1)!;
    final line = int.tryParse(match.group(2)!) ?? 1;
    final col = match.group(3) != null ? int.tryParse(match.group(3)!) : null;
    return ConsoleSourceLocation(filePath: filePath, line: line, column: col);
  }

  void log(
    ConsoleLogLevel level,
    String message, {
    String? stackTrace,
    int timestampMs = 0,
  }) {
    _entries.add(
      ConsoleLogEntry(
        level: level,
        message: message,
        stackTrace: stackTrace,
        sourceLocation: parseSourceLocation(stackTrace),
        timestampMs: timestampMs,
      ),
    );
    if (_entries.length > maxEntries) {
      _entries.removeAt(0);
    }
  }

  void recordEngineError(
    Object error,
    StackTrace stack, {
    int timestampMs = 0,
  }) {
    log(
      ConsoleLogLevel.error,
      error.toString(),
      stackTrace: stack.toString(),
      timestampMs: timestampMs,
    );
  }

  void clear() => _entries.clear();

  /// Returns filtered (and optionally collapsed) console entries.
  List<ConsoleLogEntry> visibleEntries() {
    final needle = searchQuery.trim().toLowerCase();
    final filtered = <ConsoleLogEntry>[];

    for (final entry in _entries) {
      final levelOk = switch (entry.level) {
        ConsoleLogLevel.info => showInfo,
        ConsoleLogLevel.warning => showWarning,
        ConsoleLogLevel.error => showError,
      };
      if (!levelOk) continue;
      if (needle.isNotEmpty &&
          !entry.message.toLowerCase().contains(needle) &&
          !(entry.stackTrace?.toLowerCase().contains(needle) ?? false)) {
        continue;
      }
      filtered.add(entry);
    }

    if (!collapseDuplicates) {
      return List<ConsoleLogEntry>.unmodifiable(filtered);
    }

    final collapsed = <String, ConsoleLogEntry>{};
    for (final entry in filtered) {
      final key = '${entry.level.name}|${entry.message}';
      final existing = collapsed[key];
      if (existing == null) {
        collapsed[key] = entry;
      } else {
        collapsed[key] = existing.copyWith(
          count: existing.count + 1,
          timestampMs: entry.timestampMs,
        );
      }
    }
    return List<ConsoleLogEntry>.unmodifiable(collapsed.values);
  }

  @override
  Map<String, Object?> saveState() => {
    'showInfo': showInfo,
    'showWarning': showWarning,
    'showError': showError,
    'collapseDuplicates': collapseDuplicates,
    'searchQuery': searchQuery,
  };

  @override
  void restoreState(Map<String, Object?> state) {
    showInfo = state['showInfo'] as bool? ?? true;
    showWarning = state['showWarning'] as bool? ?? true;
    showError = state['showError'] as bool? ?? true;
    collapseDuplicates = state['collapseDuplicates'] == true;
    searchQuery = state['searchQuery'] as String? ?? '';
  }
}
