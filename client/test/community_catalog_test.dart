import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mesa/catalogs.dart';
import 'package:mesa/models.dart';
import 'package:mesa/photos.dart';

List<Map<String, dynamic>> samplePosts() => (jsonDecode(
  File('test/fixtures/delokos-posts.json').readAsStringSync(),
) as List).map((e) => Map<String, dynamic>.from(e)).toList();

http.Response jsonResponse(dynamic data) => http.Response(
  jsonEncode(data),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

void main() {
  test('Spanish sources retain existing IDs and expose distinct consultation modes', () {
    expect(catalogSources.take(2).map((s) => s.id), ['wiki-es', 'delokos-es']);
    expect(catalogSources.where((s) => s.language == 'Español'), hasLength(19));
    expect(catalogSources.where((s) => s.included).map((s) => s.id), [
      'book-polaca',
    ]);
    expect(catalogSources.where((s) => s.consultationOnly), hasLength(14));
  });

  test('Actual delokos posts preserve amounts, steps and photo credits, excluding signatures', () {
    final rows = samplePosts().map((p) => parseDelokos(p)!).toList();
    for (final row in rows) {
      validateEntryData('recipe', row);
      expect(row['photos'], hasLength(1));
      expect(row['origin']['license'], 'CC BY-NC-SA 2.5 ES');
      expect(row['servings_declared'], false);
      expect(recipeYieldText(row), 'Rendimiento por confirmar');
      expect(
        (row['steps'] as List).any((s) => '$s'.contains('oooOOOooo')),
        false,
      );
      expect(
        (row['photos'] as List).any(
          (p) => '${p['url']}'.contains('signatures'),
        ),
        false,
      );
    }
    expect(rows.first['ingredients'], [
      '800g de raxo de cerdo',
      '8 dientes de ajo',
      'aceite de oliva virgen extra',
      'pimienta negra',
      'sal',
    ]);
    expect(rows.first['steps'], hasLength(2));
    expect(rows[1]['title'], 'Gyudon – Donburi de ternera');
    expect(
      rows.last['ingredients'],
      contains('400g de tomate cherry o dos tomates'),
    );
  });

  test('Articles without identifiable recipe amounts, steps or photos are excluded', () {
    final post = samplePosts().first;
    expect(
      parseDelokos({...post, 'content': '<p>Noticias del blog</p>'}),
      isNull,
    );
    expect(parseDelokos({...post, 'URL': 'https://localhost/private'}), isNull);
    expect(
      parseDelokos({
        ...post,
        'content': '<p>Ingredientes</p><p>Harina – agua</p><p>Mezclar.</p>',
      }),
      isNull,
    );
  });

  test('Ingredient lists preserve declared portions and do not absorb the first cooking step', () {
    final post = samplePosts().first;
    final row = parseDelokos({
      ...post,
      'content':
          '<p><img src="https://delokos.files.wordpress.com/2026/08/sopa.jpg"></p>'
          '<h2>Ingredientes para 4 personas</h2><ul><li>2 zanahorias</li><li>1 l de agua</li></ul>'
          '<p>Cortar las zanahorias.</p><p>Cocer en agua.</p>',
    })!;
    expect(row['ingredients'], ['2 zanahorias', '1 l de agua']);
    expect(row['steps'], ['Cortar las zanahorias.', 'Cocer en agua.']);
    expect(recipeYieldText(row), '4 raciones');
    expect(
      missingQuantities({
        'ingredients': ['Sal a gusto', 'Pimienta al gusto'],
      }),
      isEmpty,
    );
  });

  test('delokos pagination uses only its public site API and never family credentials', () async {
    final api = CatalogApi(
      MockClient((req) async {
        expect(req.url.host, 'public-api.wordpress.com');
        expect(req.url.path, '/rest/v1.1/sites/delokos.wordpress.com/posts/');
        expect(req.url.queryParameters['page'], '2');
        expect(req.url.queryParameters['search'], 'arroz');
        expect(req.headers.containsKey('authorization'), false);
        expect(req.headers.containsKey('cookie'), false);
        expect(req.followRedirects, false);
        return jsonResponse({'found': 33, 'posts': samplePosts()});
      }),
    );
    final result = await api.search('delokos-es', query: 'arroz', cursor: '2');
    expect(result.items, hasLength(3));
    expect(result.cursor, '3');
    expect(result.items.every((r) => r.hasPhoto), true);
    await expectLater(
      api.get(
        Uri.parse(
          'https://public-api.wordpress.com/rest/v1.1/sites/other.wordpress.com/posts/',
        ),
      ),
      throwsException,
    );
  });

  test(
    'delokos detail retains all photo URLs and credits without fetching images',
    () async {
      final post = samplePosts().first;
      post['content'] += '<p><img src="https://delokos.files.wordpress.com/2026/08/paso.jpg" alt="Paso" /></p>';
      var downloads = 0;
      final api = CatalogApi(
        MockClient((req) async {
          expect(req.headers.containsKey('authorization'), false);
          if (req.url.host == 'public-api.wordpress.com') {
            return jsonResponse(post);
          }
          downloads++;
          return fail('Image bytes must not be downloaded during import');
        }),
      );
      final detail = await api.detail(
        CatalogItem(id: '${post['ID']}', title: 'Raxo', provider: 'delokos-es'),
      );
      expect(downloads, 0);
      expect(recipePhotos(detail), hasLength(2));
      expect(
        recipePhotos(detail).every(
          (p) =>
              p['url'].isNotEmpty &&
              !p.containsKey('image') &&
              p['artist'].isNotEmpty,
        ),
        true,
      );
      validateEntryData('recipe', detail);
    },
  );

  test('Photo redirects cannot leave the delokos image hosts or send authorization', () async {
    var requests = 0;
    final client = MockClient((req) async {
      requests++;
      expect(req.headers.containsKey('authorization'), false);
      return http.Response(
        '',
        302,
        headers: {'location': 'https://localhost/private.jpg'},
      );
    });
    await expectLater(
      fetchOnlinePhoto(
        client,
        'https://delokos.wordpress.com/wp-content/uploads/2026/08/raxo.jpg',
      ),
      throwsException,
    );
    expect(requests, 1);
    expect(
      delokosPhotoUrl('https://i0.wp.com/signatures.example.com/photo.jpg'),
      false,
    );
  });
}
