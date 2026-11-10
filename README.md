# glVolition (`package:gl_volition`)

A Unity-style game engine (`GameObject`, `Component`, `Behaviour`, fixed-step simulation, scenes, prefabs, object pools, 2D sprites/tilemaps/UI, 3D terrain/water/atmosphere, CLI, and live inspector) built around the [`pixeldart`](https://github.com/soulwax/pixeldart) WebGL2 renderer submodule.

## Quick Start

```bash
# Clone with submodule
git clone --recurse-submodules https://github.com/soulwax/glVolition.git
cd glVolition

# Run headless VM unit & gameplay tests (<1s)
dart test

# Serve an example with live reload & SSE error overlay
dart run gl_volition:volition serve example/pixel_rocket/main.dart --port 8080

# Production build (js | wasm | windows)
dart run gl_volition:volition build example/pixel_rocket/main.dart --target js
```

## Architecture

- **`package:gl_volition/gl_volition.dart`** (`lib/gl_volition.dart`): Platform-neutral core (`Engine`, `Scene`, `GameObject`, `Component`, `Behaviour`, `TransformComponent`, `Time`, `InputActions`, `PhysicsWorld`, `Prefab`, `ObjectPool`, `ComponentSpec`, `SceneSerializer`, `AssetCatalog`, 2D/3D components, `UICanvas`, `HeadlessHost`). Zero `package:web` or `dart:io` dependencies so full gameplay suites run headlessly on the Dart VM in milliseconds.
- **`package:gl_volition/gl_volition_web.dart`** (`lib/gl_volition_web.dart`): Browser host (`WebEngineHost`, `WebEngineRunner`, `WebAudioDevice`, `InspectorOverlay`) backed by `pixeldart`.
- **`vendor/pixeldart/`**: Git submodule providing the underlying WebGL2 rendering pipeline.
