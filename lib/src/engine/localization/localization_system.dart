part of '../../engine.dart';

/// Manages runtime game localization via [loc.LocalizationManager] on a [GameObject],
/// integrating asset loading and persistent language preferences via [EngineHost] (E49-2).
final class LocalizationComponent extends Behaviour {
  final loc.LocalizationManager manager;

  void Function(String newLocale)? onLocaleChanged;

  LocalizationComponent({
    loc.LocalizationManager? manager,
    String activeLocale = 'en',
    String fallbackLocale = 'en',
    this.onLocaleChanged,
  }) : manager =
           manager ??
           loc.LocalizationManager(
             activeLocale: activeLocale,
             fallbackLocale: fallbackLocale,
           ) {
    this.manager.addLocaleListener((locale) => onLocaleChanged?.call(locale));
  }

  String get activeLocale => manager.activeLocale;
  loc.LocalizationTable get table => manager.table;

  bool setLocale(String localeTag) => manager.setLocale(localeTag);

  void loadCsv(String csvContent) => manager.table.loadCsv(csvContent);
  void loadJsonString(String localeTag, String jsonText) =>
      manager.table.loadJsonString(localeTag, jsonText);

  Future<void> loadCsvAsset(String path, {AssetLoader? loader}) async {
    final targetLoader = loader ?? engine.host.assets;
    final csv = await targetLoader.loadText(path);
    manager.table.loadCsv(csv);
  }

  Future<void> loadJsonAsset(
    String localeTag,
    String path, {
    AssetLoader? loader,
  }) async {
    final targetLoader = loader ?? engine.host.assets;
    final json = await targetLoader.loadText(path);
    manager.table.loadJsonString(localeTag, json);
  }

  String tr(
    String key, {
    Map<String, Object?> params = const {},
    String? defaultValue,
  }) => manager.tr(key, params: params, defaultValue: defaultValue);

  String trPlural(
    String key,
    num count, {
    Map<String, Object?> params = const {},
    String? defaultValue,
  }) =>
      manager.trPlural(key, count, params: params, defaultValue: defaultValue);

  void saveLocalePreference([String storageKey = 'voxloc.locale']) {
    if (!isAttached) return;
    engine.host.storage.write(storageKey, manager.activeLocale);
  }

  bool loadLocalePreference([String storageKey = 'voxloc.locale']) {
    if (!isAttached) return false;
    final saved = engine.host.storage.read(storageKey);
    if (saved == null || saved.trim().isEmpty) return false;
    manager.setLocale(saved);
    return true;
  }
}

/// Immediate-mode `voxui` localization inspector & live locale switcher (E49-2).
final class LocalizationDebuggerUI {
  static void render(
    VoxUiContext ui,
    loc.LocalizationManager manager, {
    List<String> previewKeys = const [],
    String title = 'Localization Inspector',
    double x = 20.0,
    double y = 20.0,
    double width = 360.0,
    double height = 280.0,
  }) {
    if (!ui.beginWindow(title, x: x, y: y, width: width, height: height)) {
      ui.endWindow();
      return;
    }

    ui.labelValue(
      'Active Locale',
      manager.activeLocale,
      valueColor: VoxColor.cyan,
    );
    ui.labelValue(
      'Fallback Chain',
      manager.fallbackChain.join(' -> '),
      valueColor: VoxColor.lightGray,
    );

    final glyphs = manager.table
        .collectGlyphCodePoints(localeTag: manager.activeLocale)
        .length;
    ui.labelValue('Unique Glyphs', '$glyphs', valueColor: VoxColor.green);
    ui.labelValue(
      'Missing Keys',
      '${manager.missingKeys.length}',
      valueColor: manager.missingKeys.isEmpty ? VoxColor.green : VoxColor.red,
    );

    final locales = manager.table.availableLocales.toList()..sort();
    if (locales.isNotEmpty) {
      ui.separator();
      ui.text('Switch Locale:', color: VoxColor.yellow);
      for (final locTag in locales) {
        final label = locTag == manager.activeLocale ? '[*] $locTag' : locTag;
        if (ui.button(label, height: 20.0)) {
          manager.setLocale(locTag);
        }
      }
    }

    if (previewKeys.isNotEmpty) {
      ui.separator();
      ui.text('Previews:', color: VoxColor.cyan);
      for (final key in previewKeys) {
        ui.labelValue(key, manager.tr(key), valueColor: ui.style.text);
      }
    }

    ui.endWindow();
  }
}
