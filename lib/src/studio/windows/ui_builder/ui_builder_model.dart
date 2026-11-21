/// S7-E: UI Builder (RectTransform anchor math across resolutions),
/// Localization Table Editor (CSV round-trip + missing-key report), and
/// DataAsset Table Editor (`voxui`, `voxloc`, `voxitem`, `voxquest`, `voxstat`).
library;

/// Resolved pixel rectangle from a [RectTransformSpec].
final class ResolvedUiRect {
  final double x;
  final double y;
  final double width;
  final double height;

  const ResolvedUiRect(this.x, this.y, this.width, this.height);
}

/// Unity-style RectTransform anchor/pivot/offset descriptor (`[S7-E]`).
final class RectTransformSpec {
  final double anchorMinX;
  final double anchorMinY;
  final double anchorMaxX;
  final double anchorMaxY;
  final double pivotX;
  final double pivotY;
  final double anchoredPosX;
  final double anchoredPosY;
  final double sizeDeltaX;
  final double sizeDeltaY;

  const RectTransformSpec({
    this.anchorMinX = 0.5,
    this.anchorMinY = 0.5,
    this.anchorMaxX = 0.5,
    this.anchorMaxY = 0.5,
    this.pivotX = 0.5,
    this.pivotY = 0.5,
    this.anchoredPosX = 0.0,
    this.anchoredPosY = 0.0,
    this.sizeDeltaX = 100.0,
    this.sizeDeltaY = 40.0,
  });

  /// Resolves pixel-space rectangle inside a parent viewport of
  /// `[parentWidth x parentHeight]`.
  ResolvedUiRect resolve(double parentWidth, double parentHeight) {
    final minX = anchorMinX * parentWidth;
    final maxX = anchorMaxX * parentWidth;
    final minY = anchorMinY * parentHeight;
    final maxY = anchorMaxY * parentHeight;
    final w = (maxX - minX) + sizeDeltaX;
    final h = (maxY - minY) + sizeDeltaY;
    final pivotWorldX = minX + (maxX - minX) * pivotX + anchoredPosX;
    final pivotWorldY = minY + (maxY - minY) * pivotY + anchoredPosY;
    return ResolvedUiRect(
      pivotWorldX - w * pivotX,
      pivotWorldY - h * pivotY,
      w,
      h,
    );
  }
}

/// Localization table editor with CSV import/export and missing-key reporting
/// (`[S7-E]`).
final class LocalizationTableEditorModel {
  final List<String> locales;
  final Map<String, Map<String, String>> _entries = {};

  LocalizationTableEditorModel(this.locales);

  void setTranslation(String key, String locale, String text) {
    _entries.putIfAbsent(key, () => {})[locale] = text;
  }

  String? getTranslation(String key, String locale) => _entries[key]?[locale];

  /// Returns a map of `locale -> [missingKeys]`.
  Map<String, List<String>> missingKeyReport() {
    final report = <String, List<String>>{for (final l in locales) l: []};
    final keys = _entries.keys.toList()..sort();
    for (final k in keys) {
      for (final l in locales) {
        final v = _entries[k]?[l];
        if (v == null || v.trim().isEmpty) {
          report[l]!.add(k);
        }
      }
    }
    return report;
  }

  String exportCsv() {
    final buf = StringBuffer()..writeln(['key', ...locales].join(','));
    final keys = _entries.keys.toList()..sort();
    for (final k in keys) {
      final row = [k, for (final l in locales) _entries[k]?[l] ?? ''];
      buf.writeln(row.join(','));
    }
    return buf.toString();
  }

  static LocalizationTableEditorModel importCsv(String csv) {
    final lines = csv
        .replaceAll('\r\n', '\n')
        .split('\n')
        .where((l) => l.trim().isNotEmpty)
        .toList();
    if (lines.isEmpty) return LocalizationTableEditorModel(const []);
    final header = lines.first.split(',');
    final locales = header.sublist(1);
    final model = LocalizationTableEditorModel(locales);
    for (var i = 1; i < lines.length; i++) {
      final cols = lines[i].split(',');
      if (cols.isEmpty) continue;
      final key = cols.first;
      for (var c = 1; c < cols.length && c - 1 < locales.length; c++) {
        if (cols[c].isNotEmpty) {
          model.setTranslation(key, locales[c - 1], cols[c]);
        }
      }
    }
    return model;
  }
}
