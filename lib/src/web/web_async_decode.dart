import 'dart:async';
import 'dart:typed_data';

/// Web-compatible cooperative chunked async decoder for [StreamingAssetLoader]
/// (P3-W11-D).
///
/// Processes [rawBytes] in bounded slices of [chunkSize] bytes and yields back
/// to the host event loop (`Future<void>.delayed(Duration.zero)`) between
/// chunks so large decodes never monopolize a browser frame.
Future<Uint8List> decodeBytesCooperatively(
  Uint8List rawBytes, {
  int chunkSize = 65536,
  void Function(Uint8List chunk)? onChunk,
  void Function(int bytesProcessed, int totalBytes)? onProgress,
}) async {
  if (chunkSize <= 0) {
    throw RangeError.value(chunkSize, 'chunkSize', 'Must be positive');
  }
  final length = rawBytes.length;
  if (length == 0) {
    await Future<void>.delayed(Duration.zero);
    onProgress?.call(0, 0);
    return Uint8List(0);
  }

  final output = Uint8List(length);
  for (var offset = 0; offset < length; offset += chunkSize) {
    final end = offset + chunkSize < length ? offset + chunkSize : length;
    output.setRange(offset, end, rawBytes, offset);
    if (onChunk != null) {
      onChunk(Uint8List.sublistView(output, offset, end));
    }
    onProgress?.call(end, length);
    await Future<void>.delayed(Duration.zero);
  }
  return output;
}
