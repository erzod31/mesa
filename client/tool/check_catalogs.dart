import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:mesa/catalogs.dart';
import 'package:mesa/models.dart';

Future<void> main() async {
  final client = http.Client();
  final api = CatalogApi(client);
  final results = <String, dynamic>{};
  try {
    for (final source in catalogSources) {
      final list = await api.search(
        source.id,
        query: source.id == 'wiki-es' ? 'Gazpacho andaluz' : 'Gazpacho',
      );
      if (list.items.isEmpty) {
        throw StateError('No results from ${source.id}');
      }
      final item = source.id == 'wiki-es'
          ? const CatalogItem(
              id: 'Artes culinarias/Recetas/Gazpacho andaluz',
              title: 'Gazpacho andaluz',
              provider: 'wiki-es',
            )
          : list.items.first;
      final data = await api.detail(item);
      validateEntryData('recipe', data);
      results[source.id] = {
        'results': list.items.length,
        'recipe': data['title'],
        'ingredients': (data['ingredients'] as List).length,
        'steps': (data['steps'] as List).length,
        'license': data['origin']['license'],
        'language': data['origin']['language'],
        'quantities': data['ingredients'],
        'photos': (data['photos'] as List).length,
      };
      if ((data['ingredients'] as List).isEmpty ||
          (data['steps'] as List).isEmpty) {
        throw StateError('No usable recipe from ${source.id}');
      }
    }
    final tortilla = await api.detail(
      const CatalogItem(
        id: 'Artes culinarias/Recetas/Tortilla de patatas',
        title: 'Tortilla de patatas',
        provider: 'wiki-es',
      ),
    );
    validateEntryData('recipe', tortilla);
    final photos = tortilla['photos'] as List;
    await File('../output/tortilla-gallery-preview.json')
        .writeAsString(jsonEncode(tortilla));
    results['tortilla-photo-check'] = {
      'recipe': tortilla['title'],
      'quantities': tortilla['ingredients'],
      'servings': tortilla['servings'],
      'photos': photos.length,
      'online_photo_links': photos
          .where((p) => (p['url'] as String? ?? '').isNotEmpty)
          .length,
      'credits': photos
          .map(
            (p) => {
              'artist': p['artist'],
              'license': p['license'],
              'source': p['source'],
              'error': p['error'],
            },
          )
          .toList(),
    };
    if (photos.isEmpty ||
        photos.every((p) => (p['url'] as String? ?? '').isEmpty)) {
      throw StateError('No online recipe photo URL: ${jsonEncode(results)}');
    }
    await File('../output/catalog-live-client-check.json')
        .writeAsString(const JsonEncoder.withIndent('  ').convert(results));
    stdout.writeln(jsonEncode(results));
  } finally {
    client.close();
  }
}
