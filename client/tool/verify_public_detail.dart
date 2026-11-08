import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:mesa/catalogs.dart';
import 'package:mesa/public_recipe.dart';

Future<void> main(List<String> args) async {
  final client = http.Client();
  final api = CatalogApi(client);
  final results = <String, dynamic>{};
  try {
    for (final source in catalogSources.where(
      (s) => s.external && s.browseable,
    )) {
      if (!args.contains('--live') && source.id == 'mx-kiwilimon') continue;
      try {
        final selected = args.contains('--live') && source.seed == source.url
            ? (await api.search(source.id)).items.first
            : CatalogItem(
                id: source.seed,
                title: source.name,
                provider: source.id,
              );
        final data = args.contains('--live')
            ? await api.detail(selected)
            : parsePublicRecipe(
                File('../output/research/source-pages/${source.id}.html')
                    .readAsStringSync(),
                Uri.parse(source.seed),
                source,
              );
        results[source.id] = {
          'ok': true,
          'title': data['title'],
          'ingredients': (data['ingredients'] as List).length,
          'steps': (data['steps'] as List).length,
          'photos': (data['photos'] as List).length,
          'url': data['source'],
        };
      } catch (e) {
        results[source.id] = {'ok': false, 'error': '$e'};
      }
      stdout.writeln(jsonEncode({source.id: results[source.id]}));
    }
    if (args.contains('--live')) {
      final page = await api.search('es-petitchef');
      for (final item in page.items.take(3)) {
        try {
          final data = await api.detail(item);
          results[item.id] = {
            'ok': true,
            'ingredients': (data['ingredients'] as List).length,
            'steps': (data['steps'] as List).length,
            'photos': (data['photos'] as List).length,
          };
        } catch (e) {
          results[item.id] = {'ok': false, 'error': '$e'};
        }
        stdout.writeln(jsonEncode({item.id: results[item.id]}));
      }
    }
    File(
      '../output/public-detail-${args.contains('--live') ? 'live' : 'fixtures'}-results.json',
    ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(results));
  } finally {
    client.close();
  }
}
