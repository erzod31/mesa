import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:mesa/publisher_catalogs.dart';
import 'package:mesa/source_registry.dart';

Future<void> main(List<String> args) async {
  final results = <Map<String, dynamic>>[];
  final client = http.Client();
  final api = PublicPublisherCatalog(client);
  final sources = catalogSources
      .where(
        (s) =>
            s.external && s.browseable && (args.isEmpty || args.contains(s.id)),
      )
      .toList();
  try {
    // Three independent, bounded catalogue requests, no recipe bulk ingestion.
    for (var i = 0; i < sources.length; i += 3) {
      await Future.wait(
        sources.skip(i).take(3).map((source) async {
          final result = <String, dynamic>{
            'id': source.id,
            'name': source.name,
          };
          try {
            final page = await api.search(source, '', null);
            result['items'] = (page['items'] as List).length;
            result['sample'] = (page['items'] as List).take(1).toList();
            result['notice'] = page['notice'];
          } catch (error) {
            result['error'] = '$error';
          }
          results.add(result);
          stdout.writeln('${source.id}: ${result['items'] ?? result['error']}');
        }),
      );
    }
  } finally {
    client.close();
  }
  final file = File('../output/public-catalogues-live-1.4.1.json');
  await file.writeAsString(
    const JsonEncoder.withIndent('  ').convert({
      'checked_at': DateTime.now().toUtc().toIso8601String(),
      'family_connection_used': false,
      'sources': results,
    }),
  );
}
