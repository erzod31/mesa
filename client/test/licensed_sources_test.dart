import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:mesa/catalogs.dart';
import 'package:mesa/licensed_photos.dart';
import 'package:mesa/models.dart';
import 'package:mesa/photo_data.dart';
import 'package:mesa/public_recipe.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final source = catalogSources.firstWhere((s) => s.id == 'es-creativegan');
  test(
    'CreatiVegan preserves amounts and excludes the copyright discussion',
    () {
      final value = parseCreativegan(
        File('test/fixtures/creativegan-arroz.html').readAsStringSync(),
        Uri.parse('https://creativegan.net/archives/arroz-con-leche-de-soja/'),
        source,
      );
      validateEntryData('recipe', value);
      expect(value['ingredients'], hasLength(6));
      expect(value['ingredients'][1], '3/4 l. de leche de soja');
      expect(value['steps'], hasLength(2));
      expect(value['servings'], 4);
      expect(value['origin']['attribution'], 'Virginia García · CreatiVegan');
    },
  );
  test('Print cards retain one set of ingredients for the matching recipe', () {
    final posts = jsonDecode(
      File('test/fixtures/creativegan-recipes.json').readAsStringSync(),
    ) as List;
    final rows = <String, Map<String, dynamic>>{};
    for (final p in posts) {
      try {
        final row = parseCreativegan(
          p['content']['rendered'],
          Uri.parse(p['link']),
          source,
          title: p['title']['rendered'],
        );
        validateEntryData('recipe', row);
        rows[p['link']] = row;
        expect(
          (row['ingredients'] as List).any(
            (s) =>
                '$s'.contains('Precalienta') ||
                '$s'.contains('En una cacerola'),
          ),
          false,
        );
      } catch (error) {
        if (error is TestFailure) rethrow;
      }
    }
    expect(rows.length, greaterThanOrEqualTo(9));
    expect(
      rows['https://creativegan.net/archives/flan-de-platano/']!['ingredients'],
      hasLength(3),
    );
    expect(
      (rows['https://creativegan.net/archives/mujaddara/']!['ingredients']
              as List)
          .any((s) => '$s'.contains('sobras de mujaddara')),
      false,
    );
  });
  test('The licensed selection opens offline, searches accents and returns independent copies', () async {
    final api = CatalogApi(
      MockClient((_) async => throw StateError('No network for bundled text')),
    );
    final result = await api.search('book-polaca');
    expect(result.items, hasLength(12));
    expect(result.items.every((r) => r.hasPhoto), true);
    for (final item in result.items) {
      final row = await api.detail(item);
      validateEntryData('recipe', row);
      expect(row['origin']['license'], 'CC BY 4.0');
      expect(row['servings_declared'], false);
    }
    expect(
      (await api.search('book-polaca', query: 'cocteles')).items,
      hasLength(1),
    );
    final row = await api.detail(result.items.first);
    (row['ingredients'] as List).clear();
    expect((await api.detail(result.items.first))['ingredients'], isNotEmpty);
  });
  test(
    'Pending sources cannot fetch, import or expose cached detail',
    () async {
      final api = CatalogApi(
        MockClient((_) async => throw StateError('Network must not be called')),
      );
      for (final source in catalogSources.where((s) => s.consultationOnly)) {
        expect((await api.search(source.id)).items, isEmpty);
        await expectLater(api.importUrl(source.url), throwsException);
        await expectLater(
          api.detail(
            CatalogItem(id: source.url, title: 'Pan', provider: source.id),
          ),
          throwsException,
        );
      }
    },
  );
  test(
    'PDF image selectors accept only exact reviewed public references',
    () async {
      const url =
          'https://bunkatura.pl/pdf/mesa_polaca.pdf?mesa_recipe_image=91';
      expect(documentPhotoReference(url), (provider: 'book-polaca', page: 91));
      for (final value in [
        url.replaceFirst('91', '128'),
        '$url&other=1',
        url.replaceFirst('bunkatura.pl', 'evil.example'),
        '$url#page=91',
        url.replaceFirst('=91', '=091'),
      ]) {
        expect(documentPhotoReference(value), isNull);
      }
      final calls = <String>[];
      documentPhotoLoader = (provider, page) async {
        calls.add('$provider/$page');
        return Uint8List.fromList([1, 2, 3]);
      };
      addTearDown(() => documentPhotoLoader = null);
      final client = MockClient(
        (_) async =>
            throw StateError('No unauthenticated PDF or credential forwarding'),
      );
      expect(await fetchOnlinePhoto(client, url), [1, 2, 3]);
      expect(calls, ['book-polaca/91']);
      await expectLater(
        fetchOnlinePhoto(client, url.replaceFirst('91', '128')),
        throwsException,
      );
    },
  );
}
