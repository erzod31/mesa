import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:mesa/catalogs.dart';

import 'fixture_sources.dart';

void main() {
  test('Retired catalogues are absent and cannot be queried', () async {
    final api = CatalogApi(
      MockClient((_) async => fail('No request to retired sources')),
    );
    expect(catalogSources, hasLength(25));
    for (final id in [
      'agro-caribe',
      'agro-arracacha',
      'sabores-uy',
      'caribe-goya',
      'cu-vero',
      'cl-pilar',
      'us-foodhero',
      'ec-laylita',
      'gt-aprende',
      'mx-mely',
      'co-erica',
      'es-canarias',
      've-tuya',
      'us-bueno-barato',
      'bo-subsidios',
      'ca-alberta',
      'rd-iddi',
      'co-picante',
      'cl-uchile',
      'us-myplate',
      'py-senatur',
      'cr-ucr',
    ]) {
      expect(catalogSources.any((s) => s.id == id), false);
      await expectLater(api.search(id), throwsException);
      await expectLater(
        api.detail(CatalogItem(id: '1', title: 'Retirada', provider: id)),
        throwsException,
      );
    }
    expect(catalogSources.where((s) => s.included).map((s) => s.id), [
      'book-polaca',
    ]);
  });

  test('Publisher pagination and detail use only the supplied family-server callbacks', () async {
    final calls = <String>[];
    final api = CatalogApi(
      MockClient(
        (_) async => throw StateError('No direct external auth requests'),
      ),
      sources: fixtureSources,
      externalSearch: (provider, query, cursor) async {
        calls.add('$provider:$query:$cursor');
        return {
          'items': [
            {
              'id': 'https://www.kiwilimon.com/receta/pan',
              'title': 'Pan',
              'provider': provider,
              'image': 'https://cdn7.kiwilimon.com/pan.jpg',
            },
          ],
          'cursor': '2',
          'notice': 'Consulta web',
        };
      },
      externalDetail: (provider, url) async => {
        'title': 'Pan',
        'source': url,
        'ingredients': ['500 g de harina'],
      },
    );
    final page = await api.search('mx-kiwilimon', query: 'pan', cursor: '2');
    expect(calls, ['mx-kiwilimon:pan:2']);
    expect(page.notice, 'Consulta web');
    expect(page.items, hasLength(1));
    expect((await api.detail(page.items.single))['ingredients'], [
      '500 g de harina',
    ]);
    expect(publisherPhotoUrl('http://127.0.0.1/pan.jpg'), false);
    expect(
      publisherPhotoUrl('https://imgmedia.buenazo.pe/recetas/arroz.webp'),
      true,
    );
    expect(
      publisherPhotoUrl('https://user:secret@cdn7.kiwilimon.com/pan.jpg'),
      false,
    );
    await expectLater(api.search('rd-iddi'), throwsException);
    expect(jsonDecode(jsonEncode(page.toJson()))['notice'], 'Consulta web');
  });
}
