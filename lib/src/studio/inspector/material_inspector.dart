/// Volition Studio Material Inspector Model (`[S4-E]`):
/// Edits `.vmat` keywords, typed PBR properties, GUID texture slots, render
/// queue/sorting layers, and preview primitive shape with live hot-update
/// fan-out through [VmatImporter].
library;

import 'package:pixeldart/rendering/api/environment.dart';
import 'package:pixeldart/rendering/api/shaders.dart';

import '../assets/importers/material_importer.dart';

enum MaterialPreviewShape { sphere, cube, plane }

/// Pure-Dart view model for the Material Inspector panel (`[S4-E]`).
final class MaterialInspectorModel {
  final VmatImporter importer;
  VmatAsset _asset;
  MaterialPreviewShape previewShape;

  MaterialInspectorModel({
    required this.importer,
    required VmatAsset initialAsset,
    this.previewShape = MaterialPreviewShape.sphere,
  }) : _asset = initialAsset {
    importer.updateAsset(_asset);
  }

  VmatAsset get asset => _asset;

  void setKeyword(ShaderKeyword keyword, bool enabled) {
    final nextKeywords = Set<ShaderKeyword>.of(_asset.keywords);
    if (enabled) {
      nextKeywords.add(keyword);
    } else {
      nextKeywords.remove(keyword);
    }
    _commit(_copyAsset(keywords: nextKeywords));
  }

  void setProperty(String name, Object? value) {
    final nextProps = Map<String, Object?>.of(_asset.properties);
    nextProps[name] = value;
    _commit(_copyAsset(properties: nextProps));
  }

  void setTextureGuid(String slot, String guid) {
    final nextTex = Map<String, String>.of(_asset.textureGuids);
    if (guid.isEmpty) {
      nextTex.remove(slot);
    } else {
      nextTex[slot] = guid;
    }
    _commit(_copyAsset(textureGuids: nextTex));
  }

  void setQueueAndSorting({
    int? renderQueue,
    int? sortingLayer,
    int? sortingOrder,
  }) {
    _commit(
      _copyAsset(
        renderQueue: renderQueue,
        sortingLayer: sortingLayer,
        sortingOrder: sortingOrder,
      ),
    );
  }

  VmatAsset _copyAsset({
    Set<ShaderKeyword>? keywords,
    Map<String, Object?>? properties,
    Map<String, String>? textureGuids,
    int? renderQueue,
    int? sortingLayer,
    int? sortingOrder,
  }) => VmatAsset(
    guid: _asset.guid,
    name: _asset.name,
    shaderId: _asset.shaderId,
    keywords: keywords ?? _asset.keywords,
    properties: properties ?? _asset.properties,
    textureGuids: textureGuids ?? _asset.textureGuids,
    renderQueue: renderQueue ?? _asset.renderQueue,
    sortingLayer: sortingLayer ?? _asset.sortingLayer,
    sortingOrder: sortingOrder ?? _asset.sortingOrder,
  );

  void _commit(VmatAsset next) {
    _asset = importer.updateAsset(next);
  }
}
