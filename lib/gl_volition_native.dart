/// Native / AOT host for `package:gl_volition`: drives `pixeldart`'s
/// [SceneRenderer] over [GlesDevice] or any custom [GpuDevice] via
/// [DefaultSceneRendererFactory] without `package:web`.
library;

export 'gl_volition.dart';
export 'package:pixeldart/pixeldart.dart';
export 'package:pixeldart/pixeldart_advanced.dart';
export 'package:pixeldart/rendering/webgl/device_api.dart';

export 'src/native/native_bindings.dart';
export 'src/native/native_host.dart';
export 'src/native/native_input.dart';
export 'src/native/native_async_decode.dart';
export 'src/native/native_ffi_transport.dart';
export 'src/native/sdl3_bindings.dart';
export 'src/native/gles3_bindings.dart';
export 'src/native/gles3_ffi_device.dart';
export 'src/native/native_audio_device.dart';
