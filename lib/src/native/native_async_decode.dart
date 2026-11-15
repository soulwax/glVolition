import 'dart:isolate';
import 'dart:typed_data';

/// Native `Isolate.run` decoder for [StreamingAssetLoader] (P3-W11-D).
///
/// Offloads copying and optional [transform] onto a worker isolate using
/// [TransferableTypedData] so large asset buffers transfer without extra
/// main-isolate stalls or shared-memory aliasing.
Future<Uint8List> decodeBytesInIsolate(
  Uint8List rawBytes, {
  Uint8List Function(Uint8List bytes)? transform,
}) async {
  final incoming = TransferableTypedData.fromList([rawBytes]);
  final outgoing = await Isolate.run(() {
    final materialized = incoming.materialize().asUint8List();
    final decoded = transform != null ? transform(materialized) : materialized;
    return TransferableTypedData.fromList([decoded]);
  });
  return outgoing.materialize().asUint8List();
}
