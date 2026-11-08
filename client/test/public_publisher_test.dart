import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mesa/catalogs.dart' hide catalogSources;

import 'fixture_sources.dart';

import 'package:mesa/publisher_catalogs.dart';

final catalogSources = fixtureSources;

void main() {
  test('Petitchef initially returns 50 unique photo recipes and another 50 on demand', () async {
    final calls = <Uri>[];
    final api = CatalogApi(
      MockClient((request) async {
        calls.add(request.url);
        expect(
          request.url.toString(),
          'https://www.petitchef.es/las-ultimas-recetas',
        );
        expect(request.headers.containsKey('authorization'), false);
        final cards = List.generate(
          100,
          (i) =>
              '<article><h2><a href="/recetas/plato/receta-fid-${i + 1}">Receta de prueba ${i + 1}</a></h2><a href="/recetas/plato/receta-fid-${i + 1}"><img src="/uploads/foto-${i + 1}.jpg" alt="Receta de prueba ${i + 1}"></a></article>',
        ).join();
        return http.Response(
          '$cards<article><a href="/recetas/plato/receta-fid-1"><img src="/uploads/duplicate.jpg" alt="Receta repetida"></a></article><a href="/articulos/fid-900"><img src="/uploads/article.jpg" alt="Articulo ajeno"></a><a href="/recetas/plato/sin-foto-fid-900">Receta sin foto</a>',
          200,
        );
      }),
      sources: fixtureSources,
    );
    final first = await api.search('es-petitchef');
    expect(first.items, hasLength(50));
    expect(first.items.first.title, 'Receta de prueba 1');
    expect(first.items.last.title, 'Receta de prueba 50');
    expect(first.items.every((item) => item.hasPhoto), true);
    expect(first.cursor, '50');
    final next = await api.search('es-petitchef', cursor: first.cursor);
    expect(next.items, hasLength(50));
    expect(next.items.first.title, 'Receta de prueba 51');
    expect(next.cursor, isNull);
    expect({
      ...first.items.map((i) => i.id),
      ...next.items.map((i) => i.id),
    }, hasLength(100));
    final before = calls.length;
    await expectLater(
      api.search('es-petitchef', cursor: '-1'),
      throwsException,
    );
    await expectLater(
      api.search('es-petitchef', cursor: 'https://example.org'),
      throwsException,
    );
    expect(calls.length, before);
  });

  test('Petitchef searches through its public query form and keeps small or empty results honest', () async {
    final api = CatalogApi(
      MockClient((request) async {
        expect(request.url.path, '/index.php');
        expect(request.url.queryParameters, {
          'obj': 'feed',
          'action': 'list',
          'q': 'pollo',
        });
        return http.Response(
          '<article><a href="/recetas/plato/pollo-fid-42"><img src="/uploads/pollo.jpg" alt="Pollo al horno"></a></article>',
          200,
        );
      }),
      sources: fixtureSources,
    );
    expect(
      (await api.search('es-petitchef', query: 'pollo')).items.single.title,
      'Pollo al horno',
    );
    final empty = CatalogApi(
      MockClient((_) async => http.Response('<main></main>', 200)),
      sources: fixtureSources,
    );
    final result = await empty.search('es-petitchef');
    expect(result.items, isEmpty);
    expect(result.cursor, isNull);
    expect(result.notice, contains('Reintenta'));
  });
  test(
    'Kiwilimon opens with real recipe results without a family connection',
    () async {
      final api = CatalogApi(
        MockClient((request) async {
          expect(request.url.toString(), 'https://gr.kiwilimon.com/v6/search');
          expect(request.method, 'POST');
          expect(request.headers.containsKey('authorization'), false);
          expect(Uri.splitQueryString(request.body)['q'], 'pollo');
          return http.Response(
            jsonEncode({
              'more': true,
              'payload': [
                {
                  't': 'receta',
                  'c': 123,
                  'ruta': '/receta/pollo',
                  'imagen': '123.jpg',
                  'nombre': 'Pollo al horno',
                },
                {
                  't': 'categoria',
                  'c': 456,
                  'ruta': '/tipo-de-cocina/pollo',
                  'imagen': '456.jpg',
                  'nombre': 'Clasificación',
                },
              ],
            }),
            200,
          );
        }),
        sources: fixtureSources,
      );
      final result = await api.search('mx-kiwilimon');
      expect(result.items.single.title, 'Pollo al horno');
      expect(result.items.single.hasPhoto, true);
      expect(result.cursor, '2');
      expect(result.notice, contains('pollo'));
    },
  );

  test('Every selectable web publisher can show its photo cards without family credentials', () async {
    var count = 0;
    for (final source in catalogSources.where(
      (s) =>
          s.external &&
          s.browseable &&
          s.id != 'mx-kiwilimon' &&
          s.id != 'open-based' &&
          s.id != 'es-creativegan',
    )) {
      final api = CatalogApi(
        MockClient((request) async {
          expect(request.headers.containsKey('authorization'), false);
          expect(request.url.host, Uri.parse(source.url).host);
          final path = switch (source.id) {
            'es-petitchef' => '/recetas/plato/pan-familiar-fid-1',
            'es-gratis' => '/receta-pan-familiar.html',
            'mx-larousse' => '/receta/pan-familiar/',
            'ar-cocineros' || 'mx-nestle' => '/recetas/pan-familiar/',
            'es-hogarmania' => '/cocina/recetas/pan-familiar.html',
            'es-bonviveur' => '/es/recetas/pan-familiar',
            _ =>
              '${Uri.parse(source.url).path.replaceFirst(RegExp(r'/$'), '')}/pan-familiar/',
          };
          return http.Response(
            '<body class="content-sidebar comments-open"><div class="content-sidebar-wrap"><div class="elementor-widget-container"><article><a href="$path"><img data-src="${source.url}foto.jpg" alt="Pan familiar con queso"></a></article></div></div><nav><a href="/contacto"><img src="/foto.jpg" alt="Contacto"></a></nav></body>',
            200,
          );
        }),
        sources: fixtureSources,
      );
      final result = await api.search(source.id);
      expect(
        result.items.single.title,
        'Pan familiar con queso',
        reason: source.name,
      );
      expect(result.items.single.hasPhoto, true);
      count++;
    }
    expect(count, 12);
    expect(
      catalogSources
          .where((s) => s.consultationOnly)
          .every((s) => !s.browseable),
      true,
    );
  });

  test('Verified publisher redirects work and foreign redirects stop before fetching', () async {
    final source = catalogSources.firstWhere((s) => s.id == 'es-gratis');
    final seen = <String>[];
    final reader = PublicPublisherCatalog(
      MockClient((request) async {
        seen.add(request.url.host);
        if (request.url.host == 'www.recetasgratis.net') {
          return http.Response(
            '',
            302,
            headers: {
              'location': 'https://recetas.elperiodico.com/receta-pan.html',
            },
          );
        }
        return http.Response(
          '<a href="/receta-pan.html"><img src="https://cdn0.recetasgratis.net/pan.jpg" alt="Pan familiar"></a>',
          200,
        );
      }),
    );
    expect((await reader.search(source, '', null))['items'], hasLength(1));
    expect(seen, ['www.recetasgratis.net', 'recetas.elperiodico.com']);
    var requests = 0;
    final blocked = PublicPublisherCatalog(
      MockClient((request) async {
        requests++;
        return http.Response(
          '',
          302,
          headers: {'location': 'https://127.0.0.1/privado'},
        );
      }),
    );
    await expectLater(
      blocked.fetch(Uri.parse(source.url), source),
      throwsException,
    );
    expect(requests, 1);
  });

  test('Malformed links and site logos do not erase recipe results', () {
    final source = catalogSources.firstWhere((s) => s.id == 'ar-paulina');
    final reader = PublicPublisherCatalog(
      MockClient((_) async => http.Response('', 500)),
    );
    final items = reader.parseCards(
      '''<header><a href="/cocina/quien-es-autora"><img src="/logo.jpg" alt="Autora del recetario"></a></header>
      <a href=" http://www.recetasmexicanas.org/"><img src="/logo.jpg" alt="Otra página"></a>
      <article><a href=" /cocina/arepas.htm "><img src=" /cocina/arepas.jpg " alt="Arepas venezolanas"></a></article>''',
      Uri.parse(source.url),
      source,
      '',
    );
    expect(items.single['title'], 'Arepas venezolanas');
    expect(
      items.single['id'],
      'https://www.paulinacocina.net/cocina/arepas.htm',
    );
  });
}
