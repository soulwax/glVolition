/// Pure-Dart `ComponentSpec`-driven Inspector panel model (S2-C):
/// supports single & multi-object editing with mixed-value detection,
/// undoable field/component mutations, add/remove/reset component, and
/// prefab override inspection/apply/revert.
library;

import 'dart:convert';

import '../../../gl_volition.dart';
import '../bridge/editor_host_bridge.dart';
import '../shell/dock_layout.dart';

/// Undoable command setting a [Field] JSON value across one or more target
/// [GameObject]s that share a component of type [componentTypeName].
final class SetComponentFieldCommand implements EditorCommand {
  @override
  final String name;
  final List<String> targetNames;
  final String componentTypeName;
  final String fieldName;
  final Object? newJsonValue;
  final Map<String, Object?> _previousByTarget = {};

  SetComponentFieldCommand({
    required this.targetNames,
    required this.componentTypeName,
    required this.fieldName,
    required this.newJsonValue,
  }) : name = 'Set $componentTypeName.$fieldName';

  @override
  void execute(EditorSession session) {
    final spec = session.engine.registry.specByName(componentTypeName);
    if (spec == null) return;
    final field = spec.fields.where((f) => f.name == fieldName).firstOrNull;
    if (field == null) return;

    for (final targetName in targetNames) {
      final go = session.engine.scene.find(targetName);
      if (go == null) continue;
      final comp = go.components
          .where((c) => c.runtimeType == spec.componentType)
          .firstOrNull;
      if (comp == null) continue;
      _previousByTarget.putIfAbsent(targetName, () => field.readJson(comp));
      field.writeJson(comp, newJsonValue);
    }
  }

  @override
  void undo(EditorSession session) {
    final spec = session.engine.registry.specByName(componentTypeName);
    if (spec == null) return;
    final field = spec.fields.where((f) => f.name == fieldName).firstOrNull;
    if (field == null) return;

    for (final entry in _previousByTarget.entries) {
      final go = session.engine.scene.find(entry.key);
      if (go == null) continue;
      final comp = go.components
          .where((c) => c.runtimeType == spec.componentType)
          .firstOrNull;
      if (comp == null) continue;
      field.writeJson(comp, entry.value);
    }
  }
}

/// Undoable command adding a registered component by [componentTypeName].
final class AddRegisteredComponentCommand implements EditorCommand {
  @override
  final String name;
  final String targetName;
  final String componentTypeName;

  AddRegisteredComponentCommand({
    required this.targetName,
    required this.componentTypeName,
  }) : name = 'Add $componentTypeName';

  @override
  void execute(EditorSession session) {
    final go = session.engine.scene.find(targetName);
    final spec = session.engine.registry.specByName(componentTypeName);
    if (go == null || spec == null) return;
    go.addComponent(spec.create());
  }

  @override
  void undo(EditorSession session) {
    final go = session.engine.scene.find(targetName);
    final spec = session.engine.registry.specByName(componentTypeName);
    if (go == null || spec == null) return;
    final comp = go.components
        .where((c) => c.runtimeType == spec.componentType && !c.isDestroyed)
        .lastOrNull;
    if (comp != null) {
      comp.destroy();
      session.engine.step(0.0);
    }
  }
}

/// Undoable command removing a registered component by [componentTypeName].
final class RemoveRegisteredComponentCommand implements EditorCommand {
  @override
  final String name;
  final String targetName;
  final String componentTypeName;
  Map<String, Object?>? _savedJson;

  RemoveRegisteredComponentCommand({
    required this.targetName,
    required this.componentTypeName,
  }) : name = 'Remove $componentTypeName';

  @override
  void execute(EditorSession session) {
    final go = session.engine.scene.find(targetName);
    final spec = session.engine.registry.specByName(componentTypeName);
    if (go == null || spec == null) return;
    final comp = go.components
        .where((c) => c.runtimeType == spec.componentType && !c.isDestroyed)
        .firstOrNull;
    if (comp == null) return;
    _savedJson = spec.toJson(comp);
    comp.destroy();
    session.engine.step(0.0);
  }

  @override
  void undo(EditorSession session) {
    final go = session.engine.scene.find(targetName);
    final spec = session.engine.registry.specByName(componentTypeName);
    if (go == null || spec == null) return;
    final restored = spec.create();
    if (_savedJson != null) {
      spec.applyJson(restored, _savedJson!);
    }
    go.addComponent(restored);
  }
}

/// Single field view inside an [InspectorComponentSection].
final class InspectorFieldView {
  final String componentTypeName;
  final Field<dynamic, dynamic> field;
  final Object? jsonValue;
  final bool isMixed;
  final bool isPrefabOverride;

  const InspectorFieldView({
    required this.componentTypeName,
    required this.field,
    required this.jsonValue,
    required this.isMixed,
    this.isPrefabOverride = false,
  });

  FieldKind get kind => field.kind;
  FieldMetadata get metadata => field.metadata;
}

/// Component section shown in the Inspector for 1..N selected objects.
final class InspectorComponentSection {
  final String typeName;
  final ComponentSpec<dynamic> spec;
  final List<InspectorFieldView> fields;
  final bool enabled;
  final bool isMixedEnabled;

  const InspectorComponentSection({
    required this.typeName,
    required this.spec,
    required this.fields,
    required this.enabled,
    required this.isMixedEnabled,
  });
}

/// Pure-Dart `ComponentSpec`-driven Inspector panel controller.
final class InspectorPanelModel implements StudioPanel {
  final EditorHostBridge bridge;
  final PrefabRegistry? prefabRegistry;
  bool showHiddenFields = false;

  InspectorPanelModel(this.bridge, {this.prefabRegistry});

  @override
  String get id => 'inspector';

  @override
  String get title => 'Inspector';

  /// Builds the common inspected component sections for the active selection.
  List<InspectorComponentSection> buildSections() {
    final selected = bridge.session.selectedObjects;
    if (selected.isEmpty) return const [];

    final reg = bridge.session.engine.registry;
    final first = selected.first;

    // Collect prefab override map for single-object prefab instances
    final overrideFields = <String, Set<String>>{};
    if (selected.length == 1 && prefabRegistry != null) {
      final overrides = prefabRegistry!.computeInstanceOverrides(
        first,
        registry: reg,
      );
      for (final nodeOv in overrides) {
        if (nodeOv.nodePath.isEmpty || nodeOv.nodePath == '.') {
          for (final entry in nodeOv.componentFieldOverrides.entries) {
            overrideFields
                .putIfAbsent(entry.key, () => <String>{})
                .addAll(entry.value.keys);
          }
        }
      }
    }

    final sections = <InspectorComponentSection>[];
    final seenTypes = <Type>{};

    for (final comp in first.components) {
      if (!seenTypes.add(comp.runtimeType)) continue;
      final spec = reg.specFor(comp);
      if (spec == null) continue;

      // Only include components present on ALL selected objects for multi-edit
      final matched = <Component>[];
      for (final go in selected) {
        final found = go.components
            .where((c) => c.runtimeType == spec.componentType)
            .firstOrNull;
        if (found != null) matched.add(found);
      }
      if (matched.length != selected.length) continue;

      final firstEnabled = matched.first.isActiveAndEnabled;
      final mixedEnabled = matched.any(
        (c) => c.isActiveAndEnabled != firstEnabled,
      );

      final fieldViews = <InspectorFieldView>[];
      for (final field in spec.fields) {
        if (field.metadata.hidden && !showHiddenFields) continue;
        final firstVal = field.readJson(matched.first);
        final firstEncoded = jsonEncode(firstVal);
        var mixed = false;
        for (var i = 1; i < matched.length; i++) {
          if (jsonEncode(field.readJson(matched[i])) != firstEncoded) {
            mixed = true;
            break;
          }
        }
        fieldViews.add(
          InspectorFieldView(
            componentTypeName: spec.typeName,
            field: field,
            jsonValue: mixed ? null : firstVal,
            isMixed: mixed,
            isPrefabOverride:
                overrideFields[spec.typeName]?.contains(field.name) ?? false,
          ),
        );
      }

      sections.add(
        InspectorComponentSection(
          typeName: spec.typeName,
          spec: spec,
          fields: fieldViews,
          enabled: firstEnabled,
          isMixedEnabled: mixedEnabled,
        ),
      );
    }

    return sections;
  }

  /// Applies [newJsonValue] to [fieldName] on [componentTypeName] across all
  /// currently selected objects via an undoable [SetComponentFieldCommand].
  void setFieldValue(
    String componentTypeName,
    String fieldName,
    Object? newJsonValue,
  ) {
    final selected = bridge.session.selectedObjects;
    if (selected.isEmpty) return;
    bridge.dispatchCommand(
      SetComponentFieldCommand(
        targetNames: [for (final g in selected) g.name],
        componentTypeName: componentTypeName,
        fieldName: fieldName,
        newJsonValue: newJsonValue,
      ),
    );
  }

  /// Adds a registered component by [typeName] to all selected objects.
  void addComponent(String typeName) {
    final selected = bridge.session.selectedObjects;
    if (selected.isEmpty) return;
    if (selected.length == 1) {
      bridge.dispatchCommand(
        AddRegisteredComponentCommand(
          targetName: selected.first.name,
          componentTypeName: typeName,
        ),
      );
    } else {
      bridge.dispatchCommand(
        CompoundCommand(
          name: 'Add $typeName (${selected.length})',
          commands: [
            for (final g in selected)
              AddRegisteredComponentCommand(
                targetName: g.name,
                componentTypeName: typeName,
              ),
          ],
        ),
      );
    }
  }

  /// Removes a registered component by [typeName] from all selected objects.
  void removeComponent(String typeName) {
    final selected = bridge.session.selectedObjects;
    if (selected.isEmpty) return;
    if (selected.length == 1) {
      bridge.dispatchCommand(
        RemoveRegisteredComponentCommand(
          targetName: selected.first.name,
          componentTypeName: typeName,
        ),
      );
    } else {
      bridge.dispatchCommand(
        CompoundCommand(
          name: 'Remove $typeName (${selected.length})',
          commands: [
            for (final g in selected)
              RemoveRegisteredComponentCommand(
                targetName: g.name,
                componentTypeName: typeName,
              ),
          ],
        ),
      );
    }
  }

  /// Resets all serialized fields of [typeName] on the selection to default
  /// component values (undoable).
  void resetComponent(String typeName) {
    final spec = bridge.session.engine.registry.specByName(typeName);
    final selected = bridge.session.selectedObjects;
    if (spec == null || selected.isEmpty) return;
    final defaults = spec.toJson(spec.create());
    final cmds = <EditorCommand>[
      for (final f in spec.fields)
        SetComponentFieldCommand(
          targetNames: [for (final g in selected) g.name],
          componentTypeName: typeName,
          fieldName: f.name,
          newJsonValue: defaults[f.name],
        ),
    ];
    if (cmds.isNotEmpty) {
      bridge.dispatchCommand(
        CompoundCommand(name: 'Reset $typeName', commands: cmds),
      );
    }
  }

  /// Filters all registered `ComponentSpec` names for the Add Component menu.
  List<String> searchAvailableComponents(String query) {
    final needle = query.trim().toLowerCase();
    final names =
        bridge.session.engine.registry.registeredSpecs
            .map((s) => s.typeName)
            .where((n) => needle.isEmpty || n.toLowerCase().contains(needle))
            .toList()
          ..sort();
    return names;
  }

  /// Reverts a single prefab-overridden field on [instance] back to the base
  /// prefab value (undoable).
  bool revertPrefabFieldOverride(
    GameObject instance,
    String componentTypeName,
    String fieldName,
  ) {
    final reg = prefabRegistry;
    if (reg == null) return false;
    final comp = instance.getComponent<PrefabInstanceComponent>();
    if (comp == null) return false;
    final basePrefab = reg.findPrefab(comp.prefabName);
    if (basePrefab == null) return false;
    final spec = bridge.session.engine.registry.specByName(componentTypeName);
    if (spec == null) return false;

    final scratchEngine = Engine(HeadlessHost());
    final baseline = basePrefab.instantiate(scratchEngine.scene);
    final baseComp = baseline.components
        .where((c) => c.runtimeType == spec.componentType)
        .firstOrNull;
    if (baseComp == null) return false;
    final baseJson = spec.toJson(baseComp);
    if (!baseJson.containsKey(fieldName)) return false;

    bridge.dispatchCommand(
      SetComponentFieldCommand(
        targetNames: [instance.name],
        componentTypeName: componentTypeName,
        fieldName: fieldName,
        newJsonValue: baseJson[fieldName],
      ),
    );
    return true;
  }

  /// Applies [instance]'s overrides to a new or updated [PrefabVariant] in
  /// [prefabRegistry].
  PrefabVariant? applyOverridesAsVariant(
    GameObject instance,
    String variantName,
  ) {
    final reg = prefabRegistry;
    if (reg == null) return null;
    final variant = reg.extractVariantFromInstance(
      variantName,
      instance,
      registry: bridge.session.engine.registry,
    );
    reg.registerVariant(variantName, variant);
    return variant;
  }

  @override
  Map<String, Object?> saveState() => {'showHiddenFields': showHiddenFields};

  @override
  void restoreState(Map<String, Object?> state) {
    showHiddenFields = state['showHiddenFields'] == true;
  }
}
