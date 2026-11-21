/// Pure-Dart Volition Studio core library (S1-0).
///
/// Must stay free of platform imports (`dart:io`, `dart:ffi`, `dart:isolate`,
/// `package:web`, `dart:js_interop`, `dart:html`).
library;

export 'assets/asset_database.dart';
export 'assets/asset_meta.dart';
export 'assets/importers/material_importer.dart';
export 'baking/lightmapper.dart';
export 'bridge/editor_host_bridge.dart';
export 'commands/menu_registry.dart';
export 'console/console_model.dart';
export 'extension_host/extension_host.dart';
export 'extensions/editor_extension.dart';
export 'gizmos/light_gizmos.dart';
export 'gizmos/probe_gizmos.dart';
export 'hierarchy/hierarchy_model.dart';
export 'inspector/inspector_model.dart';
export 'inspector/material_inspector.dart';
export 'modules/module_descriptor.dart';
export 'modules/module_inventory.g.dart';
export 'modules/module_registry.dart';
export 'prefab_mode/prefab_mode_stage.dart';
export 'project/project_config.dart';
export 'project/project_fs.dart';
export 'project_window/project_window_model.dart';
export 'protocol/studio_protocol.dart';
export 'reload/reload_state_snapshot.dart';
export 'shell/dock_layout.dart';
export 'viewport/scene_viewport_model.dart';
export 'windows/lighting_window.dart';
export 'windows/quality_window.dart';
