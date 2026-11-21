/// Volition Studio Standalone App Mode & First-Run Project Picker (`[S8-C]`):
library;

enum StudioWindowLaunchMode { nativeWebView, browserAppMode, browserTab }

/// Recent project entry shown in the first-run Project Picker (`[S8-C]`).
final class RecentProjectEntry {
  final String name;
  final String path;
  final int lastOpenedEpochMs;

  const RecentProjectEntry({
    required this.name,
    required this.path,
    required this.lastOpenedEpochMs,
  });

  Map<String, Object?> toJson() => {
    'name': name,
    'path': path,
    'lastOpenedEpochMs': lastOpenedEpochMs,
  };

  factory RecentProjectEntry.fromJson(Map<String, Object?> json) =>
      RecentProjectEntry(
        name: json['name'] as String,
        path: json['path'] as String,
        lastOpenedEpochMs: (json['lastOpenedEpochMs'] as num).toInt(),
      );
}

/// Pure-Dart model for `volition gui --app` launch selection and first-run
/// project picker (`[S8-C]`).
final class StudioAppLauncherModel {
  final List<RecentProjectEntry> _recent = [];
  final int maxRecent;

  StudioAppLauncherModel({this.maxRecent = 10});

  List<RecentProjectEntry> get recentProjects => List.unmodifiable(_recent);

  /// Chooses the best app-window strategy from `volition doctor` capabilities.
  static StudioWindowLaunchMode selectLaunchMode({
    required bool hasWebView2OrNativeWrapper,
    required bool hasChromiumBrowser,
    required bool appModeRequested,
  }) {
    if (!appModeRequested) return StudioWindowLaunchMode.browserTab;
    if (hasWebView2OrNativeWrapper) return StudioWindowLaunchMode.nativeWebView;
    if (hasChromiumBrowser) return StudioWindowLaunchMode.browserAppMode;
    return StudioWindowLaunchMode.browserTab;
  }

  /// Records a project as most-recently-opened (MRU ordering, deduplicated).
  void recordOpened(String name, String path, int epochMs) {
    _recent.removeWhere((e) => e.path == path);
    _recent.insert(
      0,
      RecentProjectEntry(name: name, path: path, lastOpenedEpochMs: epochMs),
    );
    if (_recent.length > maxRecent) {
      _recent.removeRange(maxRecent, _recent.length);
    }
  }
}
