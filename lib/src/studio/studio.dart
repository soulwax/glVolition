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
export 'build/build_profiles.dart';
export 'commands/menu_registry.dart';
export 'console/console_model.dart';
export 'extension_host/extension_host.dart';
export 'extensions/editor_extension.dart';
export 'gizmos/light_gizmos.dart';
export 'gizmos/probe_gizmos.dart';
export 'graph/graph_model.dart';
export 'hierarchy/hierarchy_model.dart';
export 'inspector/inspector_model.dart';
export 'inspector/material_inspector.dart';
export 'modules/families/animation_family.dart';
export 'modules/families/gameplay_family.dart';
export 'modules/families/infra_family.dart';
export 'modules/families/physics_family.dart';
export 'modules/families/rendering_family.dart';
export 'modules/families/world_family.dart';
export 'modules/module_descriptor.dart';
export 'modules/module_inventory.g.dart';
export 'modules/module_registry.dart';
export 'prefab_mode/prefab_mode_stage.dart';
export 'project/project_config.dart';
export 'project/project_fs.dart';
export 'project/project_templates.dart';
export 'project_window/project_window_model.dart';
export 'protocol/player_link.dart';
export 'protocol/studio_protocol.dart';
export 'reload/reload_state_snapshot.dart';
export 'shell/app_launcher_model.dart';
export 'shell/dock_layout.dart';
export 'shell/dock_layout_solver.dart';
export 'shell/studio_shortcuts.dart';
export 'shell/studio_workspace_ui.dart';
export 'timeline/timeline_model.dart';
export 'viewport/scene_gizmo_interactor.dart';
export 'viewport/scene_viewport_model.dart';
export 'windows/animation/animator_controller_model.dart';
export 'windows/graphs/graph_schemas.dart';
export 'windows/lighting_window.dart';
export 'windows/modules_window.dart';
export 'windows/profiler/profiler_window_model.dart';
export 'windows/quality_window.dart';
export 'windows/tools_2d/tools_2d_model.dart';
export 'windows/ui_builder/ui_builder_model.dart';
export 'windows/world_tools/world_tools_model.dart';
