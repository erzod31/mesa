import 'dart:typed_data';

/// Stop reading a picked file at the limit, including providers without sizes.
Future<Uint8List> readLimitedBytes(
  Stream<List<int>> source, {
  required int maxBytes,
}) async {
  final bytes = BytesBuilder(copy: false);
  await for (final chunk in source) {
    if (bytes.length + chunk.length > maxBytes) {
      final limit = maxBytes >= 1000000
          ? '${maxBytes ~/ 1000000} MB'
          : '${(maxBytes / 1000).ceil()} KB';
      throw Exception(
        'El archivo supera el tamaño permitido ($limit).',
      );
    }
    bytes.add(chunk);
  }
  return bytes.takeBytes();
}
