/// Deterministic `volition codegen` `ComponentSpec` & `DataAsset` generator
/// (`[S5-A]`):
/// Scans Dart source files for `@Serialized` / `@Range` / `@Min` / `@Tooltip` /
/// `@Header` / `@Space` / `@Multiline` / `@HideInInspector` / `@RequireComponent`
/// / `@AddComponentMenu` annotations and emits deterministic `*.spec.g.dart`.
library;

/// Diagnostic emitted by [SpecCodeGenerator] with exact `file:line` location.
final class CodegenDiagnostic {
  final String filePath;
  final int line;
  final String message;

  const CodegenDiagnostic({
    required this.filePath,
    required this.line,
    required this.message,
  });

  @override
  String toString() => '$filePath:$line: $message';
}

/// Output of running [SpecCodeGenerator.generateForSource].
final class CodegenResult {
  final String generatedCode;
  final List<CodegenDiagnostic> diagnostics;
  final int classCount;
  final int fieldCount;

  const CodegenResult({
    required this.generatedCode,
    required this.diagnostics,
    required this.classCount,
    required this.fieldCount,
  });

  bool get hasErrors => diagnostics.isNotEmpty;
}

final class _ParsedField {
  final String dartType;
  final String name;
  final String serializedName;
  final num? rangeMin;
  final num? rangeMax;
  final num? minVal;
  final String? tooltip;
  final String? header;
  final double? space;
  final int? multiline;
  final bool hidden;

  const _ParsedField({
    required this.dartType,
    required this.name,
    required this.serializedName,
    this.rangeMin,
    this.rangeMax,
    this.minVal,
    this.tooltip,
    this.header,
    this.space,
    this.multiline,
    this.hidden = false,
  });
}

final class _ParsedClass {
  final String name;
  final String superClass;
  final List<String> requiredComponents;
  final String? menuPath;
  final bool disallowMultiple;
  final bool executeInEditMode;
  final List<_ParsedField> fields;

  const _ParsedClass({
    required this.name,
    required this.superClass,
    required this.requiredComponents,
    this.menuPath,
    this.disallowMultiple = false,
    this.executeInEditMode = false,
    required this.fields,
  });
}

/// Deterministic Dart source scanner & `*.spec.g.dart` emitter (`[S5-A]`).
abstract final class SpecCodeGenerator {
  static final _classHeaderRe = RegExp(
    r'^(?:final\s+|base\s+|sealed\s+)?class\s+(\w+)\s+extends\s+(Component|Behaviour|DataAsset)\b',
  );
  static final _fieldDeclRe = RegExp(
    r'^\s*([A-Za-z_][A-Za-z0-9_<>?,\s]*?)\s+([a-zA-Z_]\w*)\s*(?:=[^;]+)?;\s*$',
  );
  static final _rangeRe = RegExp(
    r'@Range\(\s*(-?\d+(?:\.\d+)?)\s*,\s*(-?\d+(?:\.\d+)?)\s*\)',
  );
  static final _minRe = RegExp(r'@Min\(\s*(-?\d+(?:\.\d+)?)\s*\)');
  static final _tooltipRe = RegExp(r'''@Tooltip\(\s*['"]([^'"]*)['"]\s*\)''');
  static final _headerRe = RegExp(r'''@Header\(\s*['"]([^'"]*)['"]\s*\)''');
  static final _spaceRe = RegExp(r'@Space\(\s*(-?\d+(?:\.\d+)?)?\s*\)');
  static final _multilineRe = RegExp(r'@Multiline\(\s*(\d+)?\s*\)');
  static final _requireRe = RegExp(r'@RequireComponent\(\s*(\w+)\s*\)');
  static final _menuRe = RegExp(
    r'''@AddComponentMenu\(\s*['"]([^'"]*)['"]\s*\)''',
  );
  static final _serializedNameRe = RegExp(
    r'''@Serialized\(\s*['"]([^'"]*)['"]\s*\)''',
  );

  static const Set<String> _supportedTypes = {
    'double',
    'int',
    'bool',
    'String',
    'Vec2',
    'Vec3',
    'AssetRef?',
  };

  /// Parses [source] and emits deterministic `ComponentSpec` / `DataAsset`
  /// registration code along with any `file:line` diagnostics.
  static CodegenResult generateForSource(
    String source, {
    required String filePath,
  }) {
    final lines = source.replaceAll('\r\n', '\n').split('\n');
    final diagnostics = <CodegenDiagnostic>[];
    final classes = <_ParsedClass>[];

    final pendingAnnotations = <String>[];
    var i = 0;
    while (i < lines.length) {
      final trimmed = lines[i].trim();
      if (trimmed.startsWith('@')) {
        pendingAnnotations.add(trimmed);
        i++;
        continue;
      }

      final classMatch = _classHeaderRe.firstMatch(trimmed);
      if (classMatch != null) {
        final className = classMatch.group(1)!;
        final superClass = classMatch.group(2)!;
        final classAnns = pendingAnnotations.join(' ');
        pendingAnnotations.clear();

        final reqs = [
          for (final m in _requireRe.allMatches(classAnns)) m.group(1)!,
        ]..sort();
        final menu = _menuRe.firstMatch(classAnns)?.group(1);
        final disallowMultiple =
            classAnns.contains('@DisallowMultipleComponent') ||
            classAnns.contains('@disallowMultipleComponent');
        final editMode =
            classAnns.contains('@ExecuteInEditMode') ||
            classAnns.contains('@executeInEditMode');

        // Scan class body until matching closing brace
        var braceDepth = _braceDelta(lines[i]);
        i++;
        final fieldAnns = <String>[];
        final fields = <_ParsedField>[];

        while (i < lines.length && braceDepth > 0) {
          final rawLine = lines[i];
          final t = rawLine.trim();
          if (braceDepth == 1) {
            if (t.startsWith('@') &&
                t.endsWith(';') &&
                (t.contains('@Serialized') || t.contains('@serialized'))) {
              // Single-line `@Serialized @Range(0, 10) double speed = 1.0;`
              final splitIdx = _findDeclarationStart(t);
              if (splitIdx > 0) {
                final anns = [
                  ...fieldAnns,
                  t.substring(0, splitIdx).trim(),
                ].join(' ');
                fieldAnns.clear();
                final decl = t.substring(splitIdx).trim();
                _parseFieldIfAnnotated(
                  anns,
                  decl,
                  i + 1,
                  filePath,
                  fields,
                  diagnostics,
                );
              }
            } else if (t.startsWith('@')) {
              fieldAnns.add(t);
            } else if (fieldAnns.isNotEmpty && t.isNotEmpty) {
              final combined = fieldAnns.join(' ');
              fieldAnns.clear();
              _parseFieldIfAnnotated(
                combined,
                t,
                i + 1,
                filePath,
                fields,
                diagnostics,
              );
            }
          }
          braceDepth += _braceDelta(rawLine);
          i++;
        }

        if (fields.isNotEmpty || reqs.isNotEmpty || menu != null) {
          classes.add(
            _ParsedClass(
              name: className,
              superClass: superClass,
              requiredComponents: reqs,
              menuPath: menu,
              disallowMultiple: disallowMultiple,
              executeInEditMode: editMode,
              fields: fields,
            ),
          );
        }
        continue;
      }

      if (trimmed.isNotEmpty && !trimmed.startsWith('//')) {
        pendingAnnotations.clear();
      }
      i++;
    }

    classes.sort((a, b) => a.name.compareTo(b.name));

    final buf = StringBuffer()
      ..writeln('// GENERATED BY volition codegen — DO NOT EDIT.')
      ..writeln('// Source: $filePath')
      ..writeln('');

    var totalFields = 0;
    for (final c in classes) {
      totalFields += c.fields.length;
      if (c.superClass == 'DataAsset') {
        buf.writeln(
          'void register${c.name}DataAsset(DataAssetRegistry registry) {',
        );
        buf.writeln("  registry.register('${c.name}', ${c.name}.new);");
        buf.writeln('}');
        buf.writeln('');
        continue;
      }

      buf.writeln('final ComponentSpec<${c.name}> ${c.name}GeneratedSpec =');
      buf.writeln("    ComponentSpec<${c.name}>('${c.name}', ${c.name}.new, [");
      for (final f in c.fields) {
        buf.writeln('      ${_emitField(f)},');
      }
      buf.writeln('    ]);');
      if (c.requiredComponents.isNotEmpty) {
        buf.writeln(
          'const List<Type> ${c.name}RequiredComponents = '
          '[${c.requiredComponents.join(', ')}];',
        );
      }
      if (c.menuPath != null) {
        buf.writeln(
          "const String ${c.name}ComponentMenuPath = '${c.menuPath}';",
        );
      }
      buf.writeln('');
    }

    return CodegenResult(
      generatedCode: buf.toString(),
      diagnostics: List.unmodifiable(diagnostics),
      classCount: classes.length,
      fieldCount: totalFields,
    );
  }

  static void _parseFieldIfAnnotated(
    String anns,
    String decl,
    int lineNumber,
    String filePath,
    List<_ParsedField> fields,
    List<CodegenDiagnostic> diagnostics,
  ) {
    if (!anns.contains('@Serialized') && !anns.contains('@serialized')) {
      return;
    }
    final m = _fieldDeclRe.firstMatch(decl);
    if (m == null) {
      diagnostics.add(
        CodegenDiagnostic(
          filePath: filePath,
          line: lineNumber,
          message: 'Could not parse @Serialized field declaration: "$decl"',
        ),
      );
      return;
    }
    final dartType = m.group(1)!.trim();
    final fieldName = m.group(2)!.trim();
    if (dartType.contains('<') || dartType.contains('>')) {
      diagnostics.add(
        CodegenDiagnostic(
          filePath: filePath,
          line: lineNumber,
          message:
              'Generic field type "$dartType" on "$fieldName" is not supported by volition codegen.',
        ),
      );
      return;
    }
    if (!_supportedTypes.contains(dartType)) {
      diagnostics.add(
        CodegenDiagnostic(
          filePath: filePath,
          line: lineNumber,
          message:
              'Unsupported @Serialized field type "$dartType" on "$fieldName".',
        ),
      );
      return;
    }

    final rangeMatch = _rangeRe.firstMatch(anns);
    final minMatch = _minRe.firstMatch(anns);
    final tooltipMatch = _tooltipRe.firstMatch(anns);
    final headerMatch = _headerRe.firstMatch(anns);
    final spaceMatch = _spaceRe.firstMatch(anns);
    final multiMatch = _multilineRe.firstMatch(anns);
    final customName = _serializedNameRe.firstMatch(anns)?.group(1);

    fields.add(
      _ParsedField(
        dartType: dartType,
        name: fieldName,
        serializedName: customName ?? fieldName,
        rangeMin: rangeMatch != null ? num.parse(rangeMatch.group(1)!) : null,
        rangeMax: rangeMatch != null ? num.parse(rangeMatch.group(2)!) : null,
        minVal: minMatch != null ? num.parse(minMatch.group(1)!) : null,
        tooltip: tooltipMatch?.group(1),
        header: headerMatch?.group(1),
        space: spaceMatch != null
            ? (spaceMatch.group(1) != null
                  ? double.parse(spaceMatch.group(1)!)
                  : 8.0)
            : null,
        multiline: multiMatch != null
            ? (multiMatch.group(1) != null
                  ? int.parse(multiMatch.group(1)!)
                  : 3)
            : null,
        hidden:
            anns.contains('@HideInInspector') ||
            anns.contains('@hideInInspector'),
      ),
    );
  }

  static String _emitField(_ParsedField f) {
    final fn = switch (f.dartType) {
      'double' => 'Field.number',
      'int' => 'Field.integer',
      'bool' => 'Field.boolean',
      'String' => 'Field.text',
      'Vec2' => 'Field.vec2',
      'Vec3' => 'Field.vec3',
      'AssetRef?' => 'Field.assetRef',
      _ => 'Field.text',
    };
    final metaParts = <String>[];
    if (f.rangeMin != null) metaParts.add('min: ${f.rangeMin}');
    if (f.rangeMax != null) metaParts.add('max: ${f.rangeMax}');
    if (f.minVal != null && f.rangeMin == null) {
      metaParts.add('min: ${f.minVal}');
    }
    if (f.tooltip != null) metaParts.add("tooltip: '${f.tooltip}'");
    if (f.header != null) metaParts.add("header: '${f.header}'");
    if (f.hidden) metaParts.add('hidden: true');
    if (f.multiline != null) metaParts.add('multiline: true');

    final metaArg = metaParts.isEmpty
        ? ''
        : ', metadata: const FieldMetadata(${metaParts.join(', ')})';
    return "$fn('${f.serializedName}', (c) => c.${f.name}, (c, v) => c.${f.name} = v$metaArg)";
  }

  static int _braceDelta(String line) {
    var d = 0;
    for (var i = 0; i < line.length; i++) {
      final ch = line.codeUnitAt(i);
      if (ch == 0x7B) d++; // {
      if (ch == 0x7D) d--; // }
    }
    return d;
  }

  static int _findDeclarationStart(String line) {
    var i = 0;
    while (i < line.length) {
      while (i < line.length && line[i] == ' ') {
        i++;
      }
      if (i >= line.length || line[i] != '@') return i;
      i++;
      while (i < line.length && RegExp(r'[A-Za-z0-9_]').hasMatch(line[i])) {
        i++;
      }
      if (i < line.length && line[i] == '(') {
        var depth = 1;
        i++;
        while (i < line.length && depth > 0) {
          if (line[i] == '(') depth++;
          if (line[i] == ')') depth--;
          i++;
        }
      }
    }
    return -1;
  }
}
