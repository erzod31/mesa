import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:mesa/catalogs.dart';
import 'package:mesa/discovery_catalog.dart';
import 'package:mesa/encantar_catalog.dart';
import 'package:mesa/models.dart';

const a = CatalogSource(
  'es-creativegan',
  'A',
  'Español',
  '',
  country: 'España',
  mode: 'web',
  url: 'https://creativegan.net/',
);
const b = CatalogSource(
  'es-encantar',
  'B',
  'Español',
  '',
  country: 'España',
  url: 'https://recetasparaencantar.com/',
);
const pending = CatalogSource(
  'es-petitchef',
  'Pendiente',
  'Español',
  '',
  country: 'España',
  mode: 'book',
);
const intl = CatalogSource(
  'open-based',
  'Internacional',
  'Inglés',
  '',
  country: 'Internacional',
  mode: 'web',
  url: 'https://based.cooking/',
);
typedef Search = Future<CatalogResult> Function(String, String, String?);

class FakeApi extends CatalogApi {
  FakeApi(this.call)
    : super(
        MockClient((_) => throw StateError('No HTTP')),
        sources: [a, b, pending, intl],
      );
  final Search call;
  @override
  Future<CatalogResult> search(
    String provider, {
    String query = '',
    String? cursor,
    String? category,
  }) => call(provider, query, cursor);
}

CatalogItem item(String provider, String id) => CatalogItem(
  id: id,
  title: id,
  provider: provider,
  image: provider == 'es-encantar'
      ? 'https://recetasparaencantar.wordpress.com/wp-content/uploads/2020/04/$id.jpg'
      : 'https://creativegan.net/wp-content/uploads/2020/04/$id.jpg',
);

void main() {
  test(
    'Country combines authorised publishers and interleaves results',
    () async {
      final calls = <String>[];
      final c = DiscoveryCatalog(
        FakeApi((p, q, next) async {
          calls.add(p);
          expect(q, 'arroz');
          return CatalogResult([item(p, '${p}1'), item(p, '${p}2')]);
        }),
      );
      final r = await c.search(country: 'España', query: ' arroz ');
      expect(calls, [a.id, b.id]);
      expect(r.items.map((i) => i.provider), [a.id, b.id, a.id, b.id]);
      expect(r.cursor, isNull);
      expect(r.sourceCount, 2);
    },
  );
  test(
    'A failing publisher preserves good results and retries its original page',
    () async {
      var fail = true;
      final calls = <String>[];
      final c = DiscoveryCatalog(
        FakeApi((p, q, next) async {
          calls.add('$p:${next ?? 'initial'}');
          if (p == a.id) {
            if (fail) throw Exception('offline');
            return CatalogResult([item(p, 'recovered')]);
          }
          return CatalogResult([
            item(p, 'first'),
          ], cursor: next == null ? '2' : null);
        }),
      );
      final first = await c.search(country: 'España');
      expect(first.items.single.provider, b.id);
      expect(first.failedSources, ['A']);
      fail = false;
      final second = await c.search(country: 'España', cursor: first.cursor);
      expect(second.items.map((i) => i.provider), [a.id, b.id]);
      expect(calls, [
        '${a.id}:initial',
        '${b.id}:initial',
        '${a.id}:initial',
        '${b.id}:2',
      ]);
      expect(second.cursor, isNull);
      await expectLater(
        c.search(country: 'Internacional', cursor: first.cursor),
        throwsFormatException,
      );
      await expectLater(
        c.search(country: 'España', query: 'otra', cursor: first.cursor),
        throwsFormatException,
      );
    },
  );
  test(
    'Parallel work is bounded and consultation sources are never called',
    () async {
      var running = 0, max = 0;
      final c = DiscoveryCatalog(
        FakeApi((p, q, c) async {
          expect(p, isNot(pending.id));
          running++;
          if (running > max) max = running;
          await Future<void>.delayed(const Duration(milliseconds: 5));
          running--;
          return const CatalogResult([]);
        }),
      );
      await c.search();
      expect(max, lessThanOrEqualTo(3));
    },
  );
  test('Invalid cursors cannot select unapproved publishers', () async {
    final c = DiscoveryCatalog(
      FakeApi((p, q, n) => throw StateError('Must not call')),
    );
    await expectLater(
      c.search(
        country: 'España',
        cursor: jsonEncode({
          'v': 1,
          'country': 'España',
          'query': '',
          'pending': {'es-petitchef': null},
        }),
      ),
      throwsFormatException,
    );
  });
  test('Encantar retains real sample quantities, photos and licensing', () {
    final p = jsonDecode(
      File('test/fixtures/encantar-post.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    final recipe = parseEncantar(p)!;
    validateEntryData('recipe', recipe);
    expect(recipe['ingredients'], hasLength(4));
    expect(recipe['steps'], hasLength(4));
    expect(recipe['photos'], hasLength(4));
    expect(recipe['servings_declared'], false);
    expect(recipe['origin']['license'], 'CC BY-NC 3.0');
    expect(
      (recipe['ingredients'] as List).first,
      '750g de judías verdes o vainas, muy frescas',
    );
    expect(
      parseEncantar({...p, 'URL': 'https://evil.example/2020/04/26/test/'}),
      isNull,
    );
    final sample = jsonDecode(
      File('test/fixtures/encantar-posts.json').readAsStringSync(),
    );
    final valid = [
      for (final raw in sample['posts'])
        parseEncantar(Map<String, dynamic>.from(raw)),
    ].whereType<Map<String, dynamic>>();
    expect(valid.length, greaterThanOrEqualTo(12));
    for (final row in valid) {
      validateEntryData('recipe', row);
    }
  });
}
