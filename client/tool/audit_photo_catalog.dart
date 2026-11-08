import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:mesa/catalogs.dart';

// Checks the production catalogue filter against the public Spanish source.
// No family account or server connection is used.
Future<void> main() async {
  final client = http.Client();
  try {
    final result = await CatalogApi(client).search('wiki-es');
    if (result.items.isEmpty || result.items.any((item) => !item.hasPhoto)) {
      throw StateError('La muestra no contiene recetas con fotos verificadas.');
    }
    final evidence = {
      'checked_at': DateTime.now().toUtc().toIso8601String(),
      'version': '1.2.1+5',
      'provider': 'wiki-es',
      'count': result.items.length,
      ...result.toJson(),
    };
    final file = File('../output/catalog-only-photos-live.json');
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(evidence),
    );
    stdout.writeln(
      '${result.items.length} recetas; todas con foto. Evidencia: ${file.path}',
    );
  } finally {
    client.close();
  }
}
