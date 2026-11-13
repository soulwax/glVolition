/// Smoke index verifying all sharded subsystem domain test suites are present.
library;

import 'dart:io';

import 'package:test/test.dart';

void main() {
  group('Subsystems Domain Shard Index', () {
    const expectedFiles = <String>[
      'test/support/subsystems_test_helpers.dart',
      'test/ai/ai_subsystems_test.dart',
      'test/assets/assets_subsystems_test.dart',
      'test/engine/audio_music_test.dart',
      'test/engine/camera_input_animation_test.dart',
      'test/engine/core_editor_ecs_test.dart',
      'test/engine/gameplay_systems_test.dart',
      'test/engine/procedural_world_test.dart',
      'test/engine/ui_workbench_test.dart',
      'test/native/native_bridge_test.dart',
      'test/network/network_subsystems_test.dart',
      'test/physics/physics_simulation_test.dart',
      'test/physics/physics_world_colliders_test.dart',
      'test/rendering/geometry_culling_splines_test.dart',
      'test/rendering/lighting_shadows_postprocess_test.dart',
      'test/serialization/serialization_subsystems_test.dart',
    ];

    test(
      'all sharded domain test suites and shared helpers exist and define tests',
      () {
        for (final relPath in expectedFiles) {
          final file = File(relPath);
          expect(
            file.existsSync(),
            isTrue,
            reason: 'Missing sharded file: $relPath',
          );
          final content = file.readAsStringSync();
          expect(content, isNotEmpty, reason: 'Empty sharded file: $relPath');
          if (relPath.endsWith('_test.dart')) {
            expect(
              content.contains('void main()'),
              isTrue,
              reason: 'Missing main() in $relPath',
            );
            expect(
              RegExp(r'\btest\(').hasMatch(content),
              isTrue,
              reason: 'Missing test() cases in $relPath',
            );
          }
        }
      },
    );
  });
}
