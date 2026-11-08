import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:mesa/publisher_catalogs.dart';
import 'package:mesa/source_registry.dart';

Future<void> main() async {
  final client = http.Client();
  try {
    final source = catalogSources.firstWhere((s) => s.id == 'es-petitchef');
    final reader = PublicPublisherCatalog(client);
    final first = await reader.search(source, '', null);
    final second = await reader.search(source, '', first['cursor'] as String?);
    final initial = first['items'] as List;
    final more = second['items'] as List;
    if (initial.length != 50 ||
        more.length != 50 ||
        first['cursor'] != '50' ||
        second['cursor'] != null) {
      throw StateError('Petitchef did not provide the expected two pages.');
    }
    if ({...initial.map((e) => e['id']), ...more.map((e) => e['id'])}.length !=
        100) {
      throw StateError('Duplicate recipes between pages.');
    }
    final data = {
      'checked_at': DateTime.now().toUtc().toIso8601String(),
      'initial_count': initial.length,
      'more_count': more.length,
      'unique_count': 100,
      'initial_cursor': first['cursor'],
      'final_cursor': second['cursor'],
      'family_connection_used': false,
      'photos_downloaded': false,
      'initial_items': initial,
    };
    await File('../output/petitchef-default-live-client.json')
        .writeAsString(const JsonEncoder.withIndent('  ').convert(data));
    stdout.writeln(
      jsonEncode({
        'initial_count': initial.length,
        'more_count': more.length,
        'unique_count': 100,
        'photos_downloaded': false,
      }),
    );
  } finally {
    client.close();
  }
}
