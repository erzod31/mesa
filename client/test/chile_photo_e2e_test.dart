import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mesa/licensed_photos.dart';
import 'package:mesa/photo_data.dart';

void main() {
  test('documentPhotoReference recognises every Chilean photo page', () {
    for (final page in const [
      5, 7, 11, 12, 14, 16, 17, 19, 21, 24, 26, 28, 29, 31, 33, 35, 38, 40, 43, 45,
    ]) {
      final url =
          'https://www.cultura.gob.cl/wp-content/uploads/2021/05/recetario-patrimonio-culinario-los-rios-2020.pdf?mesa_recipe_image=$page';
      expect(
        documentPhotoReference(url),
        (provider: 'book-los-rios', page: page),
        reason: 'page $page',
      );
    }
  });

  // Best-effort integration check against the local family server; skips when
  // there is no desktop connection (e.g. CI).
  test('fetchOnlinePhoto loads a Chilean photo end-to-end', () async {
    final config = File(
      '${Platform.environment['LOCALAPPDATA']}/Mesa/server/desktop-connection.json',
    );
    if (!config.existsSync()) return;
    final cfg = jsonDecode(config.readAsStringSync()) as Map<String, dynamic>;
    final base = (cfg['url'] as String).replaceAll(RegExp(r'/$'), '');
    final token = cfg['token'] as String;

    documentPhotoLoader = (provider, page) async {
      final request = http.Request(
        'GET',
        Uri.parse('$base/v1/source-photo/$provider/$page'),
      );
      request.headers['Authorization'] = 'Bearer $token';
      final response = await http.Client()
          .send(request)
          .timeout(const Duration(seconds: 55));
      expect(response.statusCode, 200, reason: '$provider/$page');
      final bytes = <int>[];
      await for (final part in response.stream) {
        bytes.addAll(part);
      }
      return Uint8List.fromList(bytes);
    };
    addTearDown(() => documentPhotoLoader = null);

    try {
      final photo = await fetchOnlinePhoto(
        http.Client(),
        'https://www.cultura.gob.cl/wp-content/uploads/2021/05/recetario-patrimonio-culinario-los-rios-2020.pdf?mesa_recipe_image=5',
      );
      expect(photo.length, greaterThan(1000));
      expect(photo.sublist(0, 3), [0xFF, 0xD8, 0xFF]);
    } on SocketException {
      // Local server not running; the logic is covered by the first test.
    }
  });
}
