import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:mesa/catalogs.dart';
import 'package:mesa/models.dart';
import 'package:mesa/photo_data.dart';

// Public source checks only. No family connection or account is used.
Future<void> main() async {
  final client = http.Client();
  final evidence = <Map<String, dynamic>>[];
  try {
    final api = CatalogApi(client);
    for (final source in catalogSources) {
      final result = await api.search(source.id);
      if (result.items.isEmpty || result.items.any((item) => !item.hasPhoto)) {
        throw StateError(
          '${source.id}: no hay una muestra válida de recetas con foto.',
        );
      }
      final record = <String, dynamic>{
        'provider': source.id,
        'first_page_count': result.items.length,
        'cursor': result.cursor,
        'items': [
          for (final item in result.items)
            {'id': item.id, 'title': item.title, 'has_photo': item.hasPhoto},
        ],
      };
      if (source.id != 'wiki-es') {
        final detail = await api.detail(result.items.first);
        validateEntryData('recipe', detail);
        record.addAll({
          'detail_title': detail['title'],
          'ingredients': detail['ingredients'],
          'step_count': (detail['steps'] as List).length,
          'photo_count': recipePhotos(detail).length,
          'stored_photo_count': recipePhotos(detail)
              .where((p) => '${p['image'] ?? ''}'.isNotEmpty)
              .length,
          'license': detail['origin']['license'],
        });
        if (record['stored_photo_count'] != record['photo_count']) {
          throw StateError(
            '${source.id}: no se pudo guardar toda la galería de la muestra.',
          );
        }
      }
      evidence.add(record);
      stdout.writeln(
        '${source.name}: ${result.items.length} resultados, todos con foto.',
      );
    }
    await File('../output/connected-catalogs-live.json').writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'version': '1.3.0+6',
        'checked_at': DateTime.now().toUtc().toIso8601String(),
        'sources': evidence,
      }),
    );
  } finally {
    client.close();
  }
}
