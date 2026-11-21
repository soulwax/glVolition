part of '../../engine.dart';

/// Marks a field on a [Component] or [DataAsset] for automatic spec generation
/// by `volition codegen` (`[S5-0]`).
final class Serialized {
  final String? name;
  const Serialized([this.name]);
}

/// Marks a field as serialized but hidden from the Studio Inspector (`[S5-0]`).
final class HideInInspector {
  const HideInInspector();
}

/// Constrains a numeric field to `[min, max]` and renders a slider in the
/// Studio Inspector (`[S5-0]`).
final class Range {
  final num min;
  final num max;
  const Range(this.min, this.max);
}

/// Constrains a numeric field to `>= min` (`[S5-0]`).
final class Min {
  final num min;
  const Min(this.min);
}

/// Inspector hover tooltip text (`[S5-0]`).
final class Tooltip {
  final String message;
  const Tooltip(this.message);
}

/// Inspector section header displayed above a field (`[S5-0]`).
final class Header {
  final String title;
  const Header(this.title);
}

/// Adds vertical spacing (in logical pixels) above a field in the Inspector
/// (`[S5-0]`).
final class InspectorSpace {
  final double height;
  const InspectorSpace([this.height = 8.0]);
}

/// Renders a string field as a multi-line text area in the Inspector (`[S5-0]`).
final class Multiline {
  final int lines;
  const Multiline([this.lines = 3]);
}

/// Declares that attaching this component automatically requires [componentType]
/// on the same [GameObject] (`[S5-0]`).
final class RequireComponent {
  final Type componentType;
  const RequireComponent(this.componentType);
}

/// Prevents attaching more than one instance of this component to the same
/// [GameObject] (`[S5-0]`).
final class DisallowMultipleComponent {
  const DisallowMultipleComponent();
}

/// Allows a [Behaviour] to tick in Edit Mode inside Volition Studio (`[S5-0]`).
final class ExecuteInEditMode {
  const ExecuteInEditMode();
}

/// Registers a component under `Component > <menuPath>` in Studio (`[S5-0]`).
final class AddComponentMenu {
  final String menuPath;
  const AddComponentMenu(this.menuPath);
}

/// Registers a [DataAsset] subclass under `Assets > Create > <menuName>`
/// (`[S5-0]`).
final class CreateAssetMenu {
  final String menuName;
  final String fileName;
  const CreateAssetMenu({required this.menuName, this.fileName = 'NewAsset'});
}

/// Shorthand annotation instances for ergonomic Dart metadata usage.
const serialized = Serialized();
const hideInInspector = HideInInspector();
const disallowMultipleComponent = DisallowMultipleComponent();
const executeInEditMode = ExecuteInEditMode();
