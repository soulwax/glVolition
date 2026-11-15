part of '../../engine.dart';

/// Invoked when a cached asset is evicted or unloaded from [AssetCatalog].
typedef AssetEvictionCallback<T> = void Function(String key, T asset);

/// Residency status for ref-counted entries inside [AssetCatalog].
enum AssetResidencyState { unreferenced, resident, evicted }

/// Ref-counted handle to an engine-managed asset in [AssetCatalog].
final class AssetHandle<T> {
  final String key;
  final T value;
  final ({
    void Function(String key)? onAcquire,
    void Function(String key)? onRelease,
    int Function(String key)? refCountLookup,
  })
  _hooks;
  bool _released = false;

  AssetHandle({
    required this.key,
    required this.value,
    void Function(String key)? onAcquire,
    void Function(String key)? onRelease,
    int Function(String key)? refCountLookup,
  }) : _hooks = (
         onAcquire: onAcquire,
         onRelease: onRelease,
         refCountLookup: refCountLookup,
       );

  /// Current global reference count tracked for [key].
  int get refCount => _hooks.refCountLookup?.call(key) ?? (_released ? 0 : 1);

  /// Whether this handle instance has already been released.
  bool get isReleased => _released;

  /// Creates an additional retained [AssetHandle] referencing the same asset.
  AssetHandle<T> acquire() {
    _hooks.onAcquire?.call(key);
    return AssetHandle<T>(
      key: key,
      value: value,
      onAcquire: _hooks.onAcquire,
      onRelease: _hooks.onRelease,
      refCountLookup: _hooks.refCountLookup,
    );
  }

  /// Releases this handle's reference once. Safe to call multiple times.
  void release() {
    if (_released) return;
    _released = true;
    _hooks.onRelease?.call(key);
  }
}

/// 3D color-grading lookup table (LUT) parsed from `.cube` text or packed binary.
final class LutAsset {
  final String key;
  final int size;
  final Float32List rgbData;
  final String title;

  LutAsset({
    required this.key,
    required this.size,
    required this.rgbData,
    this.title = '',
  });

  int get texelCount => size * size * size;
}
