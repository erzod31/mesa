import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:mesa/catalogs.dart';
import 'package:mesa/photo_data.dart';

Future<void> main() async {
  final metadata = http.Client();
  final result = <String, dynamic>{};
  try {
    final api = CatalogApi(metadata);
    for (final source in ['wiki-es', 'delokos-es']) {
      final page = await api.search(
        source,
        query: source == 'wiki-es' ? 'tortilla' : '',
      );
      if (page.items.isEmpty) throw StateError('No results for $source');
      final recipe = await api.detail(page.items.first);
      final photos = recipePhotos(recipe);
      if (photos.isEmpty || photos.any((p) => p.containsKey('image'))) {
        throw StateError('Only references expected for $source');
      }
      final sizes = <int>[];
      for (final photo in photos) {
        final client = directPhotoClient();
        try {
          sizes.add(
            (await fetchOnlinePhoto(
              client,
              photo['url'],
            ).timeout(const Duration(seconds: 30))).length,
          );
        } finally {
          client.close();
        }
      }
      result[source] = {
        'recipe': recipe['title'],
        'photos': photos.length,
        'image_sizes': sizes,
        'reference_only_metadata': true,
        'direct_public_dns_tls': true,
      };
    }
    await File('../output/online-photos-live-160.json')
        .writeAsString(const JsonEncoder.withIndent('  ').convert(result));
    stdout.writeln(jsonEncode(result));
  } finally {
    metadata.close();
  }
}
