# Repository Guidelines

## Project Structure & Module Organization

glVolition is a Dart 2D/3D game engine. Public entry points are `lib/gl_volition.dart`, `lib/gl_volition_web.dart`, and `lib/gl_volition_native.dart`. Shared engine logic lives in `lib/src/engine/`; browser and native adapters live in `lib/src/web/` and `lib/src/native/`. Keep the engine core free of platform imports such as `dart:io`, `dart:ffi`, `package:web`, and `dart:js_interop`.

`bin/volition.dart` provides the CLI; `tool/` contains verification, packaging, and development tooling. Tests are grouped by subsystem under `test/`, including `engine/`, `physics/`, `network/`, and `assets/`. Runnable demos live in `example/`; shared assets live in `assets/`. Dependencies in `vendor/`, including `pixeldart` and `voxnet`, are Git submodules.

## Build, Test, and Development Commands

Use Dart SDK compatible with `^3.12.0`. Run commands from the repository root:

- `git submodule update --init --recursive`: initialize vendor dependencies.
- `dart pub get`: resolve root dependencies; also run inside `vendor/pixeldart` and `vendor/voxnet` before full verification.
- `dart run bin/volition.dart doctor`: inspect local toolchain readiness.
- `dart run bin/volition.dart serve example/prism_pulse/main.dart --port 8080`: serve a browser demo.
- `dart compile exe bin/volition.dart -o volition.exe`: build the native CLI.
- `dart analyze`: run static analysis.
- `dart test`: run the root test suite.
- `dart run tool/check_boundaries.dart`: enforce architecture boundaries.
- `dart run tool/verify_all.dart --check-format`: run CI checks, vendor tests, shader checks, and compilation smoke checks.

## Coding Style & Naming Conventions

Use two-space indentation and standard Dart naming: `snake_case.dart` filenames, `UpperCamelCase` types, and `lowerCamelCase` members. Follow `package:lints/recommended.yaml`. Format changes with `dart format bin lib test tool example`. Root analysis excludes `vendor/`; validate changed submodules separately and avoid unrelated vendor formatting.

## Testing Guidelines

Use `package:test`, descriptive `group`/`test` names, and `*_test.dart` filenames. Add regression coverage in the relevant subsystem, using headless hosts where practical. Run focused tests with, for example, `dart test test/engine/editor_undo_delta_test.dart`, then broader checks appropriate to the change. No numeric coverage threshold is configured; preserve determinism and boundary checks.

## Commit & Pull Request Guidelines

History mixes imperative summaries with `feat:`, `refactor:`, and `chore:` prefixes. Use a concise, action-oriented subject and keep commits focused. PRs should explain behavior changes, link relevant issues, and report validation commands and results. Include screenshots for visible editor or rendering changes. Explicitly identify submodule pointer updates; keep generated build output out of commits.
