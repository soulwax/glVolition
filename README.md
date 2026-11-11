# glVolition (`package:gl_volition`)

A Unity-style game engine (`GameObject`, `Component`, `Behaviour`, fixed-step simulation, scenes, prefabs, object pools, 2D sprites/tilemaps/UI, 3D terrain/water/atmosphere, CLI, and live inspector) built around the [`pixeldart`](https://github.com/soulwax/pixeldart) WebGL2 renderer submodule (`./vendor/pixeldart`).

## Quick Start

```bash
# Clone with submodule
git clone --recurse-submodules https://github.com/soulwax/glVolition.git
cd glVolition

# Run headless VM unit & gameplay tests (<1s)
dart test

# Build the engine
dart run gl_volition:volition build lib/gl_volition.dart --target js

# Build wasm and executable targets
dart run gl_volition:volition build lib/gl_volition.dart --target wasm
dart run gl_volition:volition build lib/gl_volition.dart --target windows

# Build dungeon_2d example (2D dungeon crawler)
dart run gl_volition:volition build example/dungeon_2d/main.dart --target js
dart run gl_volition:volition build example/dungeon_2d/main.dart -- target wasm
dart run gl_volition:volition build example/dungeon_2d/main.dart --target windows

# Build island_3d example (3D harbour simulation)
dart run gl_volition:volition build example/island_3d/main.dart --target js
dart run gl_volition:volition build example/island_3d/main.dart --target wasm
dart run gl_volition:volition build example/island_3d/main.dart --target windows

# Build procession example (2D escort mission)
dart run gl_volition:volition build example/procession/main.dart --target js
dart run gl_volition:volition build example/procession/main.dart --target wasm
dart run gl_volition:volition build example/procession/main.dart --target windows

# Build pixel_rocket example (3D flight game)
dart run gl_volition:volition build example/pixel_rocket/main.dart --target js
dart run gl_volition:volition build example/pixel_rocket/main.dart --target wasm
dart run gl_volition:volition build example/pixel_rocket/main.dart --target windows
# Serve an example with live reload, hot state, & live inspector (F12 / Alt+I)
dart run gl_volition:volition serve example/\<target\>/main.dart --port 8080

# Production builds (js | wasm | windows | exe)
dart run gl_volition:volition build example/pixel_rocket/main.dart --target js
dart run gl_volition:volition build example/pixel_rocket/main.dart --target wasm
dart run gl_volition:volition build example/pixel_rocket/main.dart --target windows
```

## Validation Games & Examples

| Example                      | Path                    | Subsystems Exercised                                                                                                                                     |
| ---------------------------- | ----------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Pixel Rocket** (3D Flight) | `example/pixel_rocket/` | `MeshRenderer`, `FollowCamera`, `SphereCollider`, `Prefab`, `ObjectPool`, `ParticleSystem`, `AudioSource`, `KeyValueStore`                               |
| **Lantern** (2D Dungeon)     | `example/dungeon_2d/`   | `Camera2DComponent`, `TilemapComponent.moveAndSlideCircle`, `SpriteRenderer`, `SpriteAnimator`, `Light.point`, `UICanvas`                                |
| **Procession** (2D Escort)   | `example/procession/`   | `LeaderBehaviour` escort chain, `VillagerBehaviour` recruitment & Sanctuary delivery, `SwarmEnemyBehaviour` torch repulsion                              |
| **Tidewatch** (3D Harbour)   | `example/island_3d/`    | `TerrainComponent`, `WaterSurfaceComponent`, `BuoyantBody`, `SplinePath`, `SplineFollower`, `Animator`, `AtmosphereVolume`, `Camera.screenToGroundPlane` |

## Architecture

- **`package:gl_volition/gl_volition.dart`** (`lib/gl_volition.dart`): Platform-neutral core (`Engine`, `Scene`, `GameObject`, `Component`, `Behaviour`, `TransformComponent`, `Time`, `InputActions`, `PhysicsWorld`, `Prefab`, `ObjectPool`, `ComponentSpec`, `SceneSerializer`, `AssetCatalog`, `EditorSession`, 2D/3D components, `UICanvas`, `HeadlessHost`). Zero `package:web` or `dart:io` dependencies so full gameplay suites run headlessly on the Dart VM in milliseconds.
- **`package:gl_volition/gl_volition_web.dart`** (`lib/gl_volition_web.dart`): Browser host (`WebEngineHost`, `WebEngineRunner`, `WebAudioDevice`, `InspectorOverlay`) backed by `pixeldart`.
- **`package:gl_volition/gl_volition_native.dart`** (`lib/gl_volition_native.dart`): Native / AOT host (`NativeEngineHost`, `GlesDevice`, `FileAssetLoader`, `JsonFileStore`) driving `pixeldart`'s `SceneRenderer` via `DefaultSceneRendererFactory` without `package:web`.
- **`vendor/pixeldart/`**: Git submodule providing the underlying WebGL2 / `GpuDevice` rendering pipeline.
