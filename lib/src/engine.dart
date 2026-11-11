/// The engine core is one library split into parts so that the lifecycle
/// plumbing (awake/enable/start/destroy bookkeeping) can stay private while
/// living next to the component types that need it.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:pixeldart/pixeldart.dart';
import 'package:voxlog/voxlog.dart';
import 'package:voxui/voxui.dart';
import 'package:voxai/voxai.dart';
import 'package:voxsynth/voxsynth.dart';

part 'engine/host.dart';
part 'engine/headless.dart';
part 'engine/math_ext.dart';
part 'engine/mathfx.dart';
part 'engine/color_ext.dart';
part 'engine/time.dart';
part 'engine/input_actions.dart';
part 'engine/component.dart';
part 'engine/game_object.dart';
part 'engine/transform.dart';
part 'engine/scene.dart';
part 'engine/engine.dart';
part 'engine/debug_controller.dart';
part 'engine/editor_session.dart';
part 'engine/gizmos.dart';
part 'engine/events_coroutines.dart';
part 'engine/tween.dart';
part 'engine/state_machine.dart';
part 'engine/navigation.dart';
part 'engine/spatial_grid_2d.dart';
part 'engine/scene_manager.dart';
part 'engine/save_system.dart';
part 'engine/prefab.dart';
part 'engine/serialization/component_spec.dart';
part 'engine/serialization/scene_serializer.dart';
part 'engine/assets/asset_catalog.dart';
part 'engine/components/camera.dart';
part 'engine/components/cinematic_camera.dart';
part 'engine/components/light.dart';
part 'engine/components/renderers.dart';
part 'engine/components/lod_billboard.dart';
part 'engine/components/particle_system.dart';
part 'engine/components/audio_source.dart';
part 'engine/components/physics.dart';
part 'engine/components/physics_raycaster.dart';
part 'engine/components/character_controller.dart';
part 'engine/components/trail_renderer.dart';
part 'engine/components/sprites_2d.dart';
part 'engine/components/parallax_2d.dart';
part 'engine/components/tilemap.dart';
part 'engine/components/animator.dart';
part 'engine/components/spline.dart';
part 'engine/components/terrain_water.dart';
part 'engine/components/atmosphere_volume.dart';
part 'engine/components/post_process_volume.dart';
part 'engine/components/constraints.dart';
part 'engine/components/ai.dart';
part 'engine/ui/canvas_ui.dart';
