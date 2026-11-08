// Run explicitly with flutter test; it reads public sources and no family data.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mesa/catalogs.dart';
import 'package:mesa/models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('Live CreatiVegan catalogue and full recipe work through the client reader', () async {
    HttpOverrides.global = null;
    final client = http.Client();
    try {
      final api = CatalogApi(client);
      final clock = Stopwatch()..start();
      final result = await api.search('es-creativegan');
      expect(result.items, isNotEmpty);
      expect(result.items.every((r) => r.hasPhoto), true);
      final row = await api.detail(result.items.first);
      validateEntryData('recipe', row);
      expect(row['language'], 'es');
      expect(row['origin']['license'], 'CC BY-NC-SA 3.0 ES');
      expect(row['origin']['attribution'], 'Virginia García · CreatiVegan');
      final evidence = {
        'provider': 'es-creativegan', 'items': result.items.length,
        'title': row['title'], 'ingredients': (row['ingredients'] as List).length,
        'steps': (row['steps'] as List).length, 'photos': (row['photos'] as List).length,
        'seconds_catalogue_and_detail': clock.elapsedMilliseconds / 1000,
        'family_credentials_used': false,
      };
      File('../output/fuentes-fiables-2026-10-16/validacion-cliente-en-vivo.json')
          .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(evidence));
    } finally {
      client.close();
    }
  }, timeout: const Timeout(Duration(seconds: 90)));
}
