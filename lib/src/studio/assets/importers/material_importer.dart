/// Volition Studio `.vmat` Material Importer & Live Hot-Update Registry (`[S4-E]`):
/// Imports `.vmat` JSON assets into [VmatAsset]/[MaterialDefinition] and fans
/// out live edits to every subscribed renderer/material consumer.
library;

import 'dart:convert';

import 'package:pixeldart/rendering/api/environment.dart';
import 'package:pixeldart/rendering/api/materials.dart';

import '../../project/project_fs.dart';

typedef MaterialHotUpdateListener =
    void Function(VmatAsset asset, MaterialDefinition compiled);

/// Pure-Dart `.vmat` importer with GUID-keyed hot-update fan-out (`[S4-E]`).
final class VmatImporter {
  final ProjectFileSystem fs;
  final Map<String, VmatAsset> _assetsByGuid = <String, VmatAsset>{};
  final Map<String, MaterialDefinition> _compiledByGuid =
      <String, MaterialDefinition>{};
  final Map<String, List<MaterialHotUpdateListener>> _subscribers =
      <String, List<MaterialHotUpdateListener>>{};

  VmatImporter(this.fs);

  VmatAsset? assetByGuid(String guid) => _assetsByGuid[guid];
  MaterialDefinition? compiledByGuid(String guid) => _compiledByGuid[guid];

  /// Imports (or re-imports) a `.vmat` file from [path], compiles its
  /// [MaterialDefinition], and notifies all subscribers bound to its GUID.
  Future<VmatAsset> importFromPath(String path) async {
    final text = await fs.readString(path);
    final decoded = jsonDecode(text) as Map<String, Object?>;
    final asset = VmatAsset.fromJson(decoded);
    return updateAsset(asset);
  }

  /// Writes [asset] to [path] and fans out the hot-update.
  Future<VmatAsset> saveToPath(String path, VmatAsset asset) async {
    await fs.writeString(
      path,
      const JsonEncoder.withIndent('  ').convert(asset.toJson()),
    );
    return updateAsset(asset);
  }

  /// Updates an in-memory [VmatAsset] and immediately notifies every bound
  /// subscriber (SRP-batcher style hot-update).
  VmatAsset updateAsset(VmatAsset asset) {
    final compiled = asset.toMaterialDefinition();
    _assetsByGuid[asset.guid] = asset;
    _compiledByGuid[asset.guid] = compiled;
    final listeners = _subscribers[asset.guid];
    if (listeners != null) {
      for (final l in List<MaterialHotUpdateListener>.of(listeners)) {
        l(asset, compiled);
      }
    }
    return asset;
  }

  /// Subscribes a consumer to live hot-updates for material [guid].
  void Function() subscribe(String guid, MaterialHotUpdateListener listener) {
    final list = _subscribers.putIfAbsent(guid, () => []);
    list.add(listener);
    return () => list.remove(listener);
  }
}

/// Draw item descriptor for queue & sorting-layer ordering (`[S4-E]`).
final class RenderQueueDrawItem {
  final String id;
  final int renderQueue;
  final int sortingLayer;
  final int sortingOrder;
  final double cameraDistance;

  const RenderQueueDrawItem({
    required this.id,
    required this.renderQueue,
    this.sortingLayer = 0,
    this.sortingOrder = 0,
    this.cameraDistance = 0.0,
  });
}

/// Sorts draw items by `(renderQueue, sortingLayer, sortingOrder, distance)`.
/// Opaque queues (`< 3000`) sort front-to-back; transparent queues (`>= 3000`)
/// sort back-to-front (`[S4-E]`).
abstract final class RenderQueueSorter {
  static List<RenderQueueDrawItem> sort(Iterable<RenderQueueDrawItem> items) {
    final list = items.toList();
    list.sort((a, b) {
      final byQueue = a.renderQueue.compareTo(b.renderQueue);
      if (byQueue != 0) return byQueue;
      final byLayer = a.sortingLayer.compareTo(b.sortingLayer);
      if (byLayer != 0) return byLayer;
      final byOrder = a.sortingOrder.compareTo(b.sortingOrder);
      if (byOrder != 0) return byOrder;
      if (RenderQueue.isTransparent(a.renderQueue)) {
        // Transparent: back-to-front (larger distance first)
        return b.cameraDistance.compareTo(a.cameraDistance);
      }
      // Opaque: front-to-back (smaller distance first)
      return a.cameraDistance.compareTo(b.cameraDistance);
    });
    return list;
  }
}
