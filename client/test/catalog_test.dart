import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mesa/catalogs.dart';
import 'package:mesa/models.dart';
import 'package:mesa/organization.dart';
import 'package:mesa/store.dart';

import 'store_test.dart' show recipe;

http.Response wikiResponse(Map<String, dynamic> data) => http.Response(
  jsonEncode(data),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

Map<String, dynamic> recipePage(String title, List<String> photos) => {
  'title': 'Artes culinarias/Recetas/$title',
  'images': [
    for (final photo in photos) {'title': 'Archivo:$photo'},
  ],
};

Map<String, dynamic> imagePage(String name) => {
  'title': 'Archivo:$name',
  'imageinfo': [
    {'thumburl': 'https://upload.wikimedia.org/wikipedia/commons/$name', 'extmetadata': {'LicenseShortName': {'value': 'CC BY-SA 4.0'}, 'LicenseUrl': {'value': 'https://creativecommons.org/licenses/by-sa/4.0/'}}},
  ],
};

void main() {
  test('Discovery excludes missing photos and icons, and uses another available photo', () async {
    final api = CatalogApi(
      MockClient((req) async {
        expect(req.headers.containsKey('authorization'), false);
        switch (req.url.queryParameters['prop']) {
          case 'images':
            return wikiResponse({
              'query': {
                'pages': [
                  recipePage('Sin foto', []),
                  recipePage('Solo iconos', [
                    'Noia_64_apps_xclock.png',
                    '2o5dots.svg',
                  ]),
                  recipePage('Foto desaparecida', ['Perdida.jpg']),
                  recipePage('Pan', ['Pan.jpg']),
                  recipePage('Sopa', ['Perdida.jpg', 'Sopa.jpg']),
                ],
              },
            });
          case 'imageinfo':
            return wikiResponse({
              'query': {
                'pages': [imagePage('Pan.jpg'), imagePage('Sopa.jpg')],
              },
            });
          default:
            return wikiResponse({
              'query': {
                'categorymembers': [
                  for (final title in [
                    'Sin foto',
                    'Solo iconos',
                    'Foto desaparecida',
                    'Pan',
                    'Sopa',
                  ])
                    {'title': 'Artes culinarias/Recetas/$title'},
                ],
              },
            });
        }
      }),
    );
    final result = await api.search('wiki-es');
    expect(result.items.map((e) => e.title), ['Pan', 'Sopa']);
    expect(result.items.every((e) => e.hasPhoto), true);
    expect(result.items.last.image, endsWith('/Sopa.jpg'));
  });

  test(
    'Discovery advances past an empty filtered page and preserves continuation',
    () async {
      final cursors = <String?>[];
      final api = CatalogApi(
        MockClient((req) async {
          if (req.url.queryParameters['prop'] == 'images') {
            return wikiResponse({
              'query': {
                'pages': [
                  recipePage('Pan', ['Pan.jpg']),
                ],
              },
            });
          }
          if (req.url.queryParameters['prop'] == 'imageinfo') {
            return wikiResponse({
              'query': {
                'pages': [imagePage('Pan.jpg')],
              },
            });
          }
          final cursor = req.url.queryParameters['cmcontinue'];
          cursors.add(cursor);
          return wikiResponse({
            'query': {
              'categorymembers': cursor == null
                  ? []
                  : [
                      {'title': 'Artes culinarias/Recetas/Pan'},
                    ],
            },
            'continue': {'cmcontinue': cursor == null ? 'next' : 'later'},
          });
        }),
      );
      final result = await api.search('wiki-es');
      expect(cursors, [null, 'next']);
      expect(result.items.single.title, 'Pan');
      expect(result.cursor, 'later');
    },
  );

  test('Old search caches hide recipes without valid photos while preserving pagination', () {
    final result = CatalogResult.fromJson({
      'cursor': 'next',
      'items': [
        for (final image in [
          '',
          'https://localhost/private.jpg',
          'https://upload.wikimedia.org/wikipedia/commons/Pan.jpg',
        ])
          CatalogItem(
            id: image,
            title: 'Pan',
            provider: 'wiki-es',
            image: image,
          ).toJson(),
      ],
    });
    expect(result.items.length, 1);
    expect(result.cursor, 'next');
  });

  test(
    'An old detail reference containing only template icons cannot be imported',
    () async {
      var calls = 0;
      final api = CatalogApi(
        MockClient((req) async {
          calls++;
          return wikiResponse({
            'parse': {
              'title': 'Artes culinarias/Recetas/Pan',
              'revid': 1,
              'text': '<h2>Ingredientes</h2><p>500 g de harina</p><h2>Preparación</h2><p>Amasar.</p>',
              'images': ['Noia_64_apps_xclock.png', '2o5dots.svg'],
            },
          });
        }),
      );
      await expectLater(
        api.detail(
          const CatalogItem(
            id: 'Artes culinarias/Recetas/Pan',
            title: 'Pan',
            provider: 'wiki-es',
          ),
        ),
        throwsA(predicate((e) => e.toString().contains('no tiene fotos'))),
      );
      expect(calls, 1);
    },
  );

  test('A metadata outage is reported without treating recipes as permanently missing photos', () async {
    final api = CatalogApi(
      MockClient((req) async {
        if (req.url.queryParameters['prop'] == 'images') {
          return wikiResponse({
            'query': {
              'pages': [
                recipePage('Pan', ['Pan.jpg']),
              ],
            },
          });
        }
        if (req.url.queryParameters['prop'] == 'imageinfo') {
          return http.Response('', 503);
        }
        return wikiResponse({
          'query': {
            'categorymembers': [
              {'title': 'Artes culinarias/Recetas/Pan'},
            ],
          },
        });
      }),
    );
    await expectLater(api.search('wiki-es'), throwsException);
  });

  test('Wiki extraction preserves attribution and separates ingredients from method', () {
    final data = parseWiki('wiki-es', {
      'title': 'Artes culinarias/Recetas/Sopa propia',
      'revid': 123,
      'text': '<div class="mw-heading"><h2>Ingredientes</h2><span class="mw-editsection">editar</span></div><ul><li>2 zanahorias</li><li>Agua</li></ul><h2>Preparación</h2><ol><li>Cocer durante 15 minutos.</li></ol><h2>Consejos</h2><p>Dejar reposar.</p><script>malicious()</script>',
    });
    expect(data['ingredients'], ['2 zanahorias', 'Agua']);
    expect(data['steps'], ['Cocer durante 15 minutos.']);
    expect(data['origin']['license'], 'CC BY-SA 4.0');
    expect(data['origin']['url'], contains('oldid=123'));
    expect(data['notes'], isNot(contains('malicious')));
    validateEntryData('recipe', data);
  });
  test('Spanish community recipes keep provenance but discard inaccurate diet claims', () {
    final data = parseSpanish({
      'id': 6,
      'nombre': 'Salmorejo',
      'ingredientes': ['tomate', 'jamón'],
      'instrucciones': '1. Triturar. 2. Añadir jamón.',
      'porciones': 4,
      'tiempo_minutos': 15,
      'categoria': 'entrante',
      'dieta': ['vegetariana'],
      'calorias_aprox': 180,
    });
    expect(data['steps'], ['Triturar.', 'Añadir jamón.']);
    expect(data['tags'], isEmpty);
    expect(data.containsKey('calorias_aprox'), false);
    expect(data['origin']['language'], 'es');
    expect(data['category_ids'], ['category:entrantes']);
    validateEntryData('recipe', data);
    expect(catalogSources.where((s) => s.language == 'Español'), hasLength(19));
  });
  test('Catalogues without photos and English providers are rejected before requesting', () async {
    final api = CatalogApi(
      MockClient((req) async {
        fail('A removed catalogue must not make network requests');
      }),
    );
    await expectLater(
      api.search('recetas-es', query: 'ZANAHORIA'),
      throwsException,
    );
    await expectLater(api.search('wiki-en'), throwsException);
    await expectLater(
      api.get(Uri.parse('https://www.themealdb.com/api')),
      throwsException,
    );
  });
  test('Catalogue pagination is forwarded; no family authorization leaves the client', () async {
    final api = CatalogApi(
      MockClient((req) async {
        expect(req.url.host, 'es.wikibooks.org');
        expect(req.headers.containsKey('authorization'), false);
        if (req.url.queryParameters['list'] == 'categorymembers') {
          expect(req.url.queryParameters['cmcontinue'], 'next');
        } else if (req.url.queryParameters['prop'] == 'images') {
          return wikiResponse({
            'query': {
              'pages': [
                recipePage('Pan', ['Pan.jpg']),
              ],
            },
          });
        } else {
          return wikiResponse({
            'query': {
              'pages': [imagePage('Pan.jpg')],
            },
          });
        }
        return http.Response(
          jsonEncode({
            'query': {
              'categorymembers': [
                {'title': 'Artes culinarias/Recetas/Pan', 'pageid': 3},
              ],
            },
            'continue': {'cmcontinue': 'later'},
          }),
          200,
        );
      }),
    );
    final result = await api.search('wiki-es', cursor: 'next');
    expect(result.items.single.title, 'Pan');
    expect(result.cursor, 'later');
    await expectLater(
      api.get(Uri.parse('https://localhost/private')),
      throwsException,
    );
  });
  test('Recipe filters compose, normalize accents and exclude unknown cooking times', () async {
    final s = Cookbook(LocalDb(NativeDatabase.memory()));
    await s.load(readSecrets: false);
    final e = Entry(
      'r',
      'recipe',
      1,
      recipe('Sopa de jardín')..addAll({
        'ingredients': ['2 zanahorias'],
        'category_ids': ['category:sopas'],
        'catalog_ids': ['c1'],
      }),
    );
    expect(
      matchesRecipe(
        e,
        s,
        query: 'JARDIN zanahorias',
        category: 'category:sopas',
        catalog: 'c1',
        maxMinutes: 30,
      ),
      true,
    );
    expect(matchesRecipe(e, s, exclude: 'zanahoria'), false);
    expect(matchesRecipe(e, s, catalog: 'c2'), false);
    expect(
      matchesRecipe(
        Entry('u', 'recipe', 1, recipe('Sin tiempo')..['minutes'] = 0),
        s,
        maxMinutes: 30,
      ),
      false,
    );
    s.dispose();
  });
  test('Export imports catalogs and categories with remapped membership and preserved license', () async {
    final s = Cookbook(LocalDb(NativeDatabase.memory()));
    await s.load(readSecrets: false);
    await s.save('collection', {
      'title': 'En familia',
      'type': 'catalog',
    }, id: 'c1');
    await s.save('collection', {
      'title': 'Horno',
      'type': 'category',
    }, id: 'g1');
    final data = recipe('Pan')
      ..addAll({
        'catalog_ids': ['c1'],
        'category_ids': ['g1', 'category:panes'],
        'origin': {
          'provider': 'wiki-es',
          'id': 'Pan',
          'url': 'https://es.wikibooks.org/wiki/Pan',
          'language': 'es',
          'attribution': 'Autores de Wikilibros',
          'license': 'CC BY-SA 4.0',
          'license_url': 'https://creativecommons.org/licenses/by-sa/4.0/',
          'modified': true,
        },
      });
    await s.save('recipe', data, id: 'r1');
    expect(similarRecipes(s, data).single.id, 'r1');
    await s.importData(jsonEncode(s.exportData()));
    final copy = s.of('recipe').firstWhere((e) => e.id != 'r1');
    expect(copy.lines('catalog_ids').single, isNot('c1'));
    expect(s.get(copy.lines('catalog_ids').single)!.title, 'En familia');
    expect(copy.lines('category_ids'), contains('category:panes'));
    expect(copy.data['origin'], data['origin']);
    final group = s.get(copy.lines('catalog_ids').single)!;
    await s.save('collection', {
      'title': 'Nuestra cocina',
      'type': 'catalog',
    }, id: group.id);
    expect(inGroup(copy, 'catalog_ids', group.id), true);
    await s.delete(s.get(group.id)!);
    expect(recipeGroups(s, 'catalog').any((g) => g.id == group.id), false);
    expect(s.get(copy.id)!.deleted, false);
    s.dispose();
  });
  test('Quick timers only suggest explicit single durations', () {
    expect(stepMinutes('Cocer 15 minutos y reposar 1 hora.'), [15, 60]);
    expect(stepMinutes('Cook 10 to 15 minutes.'), isEmpty);
    expect(stepMinutes('Cocinar 0 minutos o 999 horas.'), isEmpty);
  });
  test('Actual catalogue fixture still has usable ingredients and steps', () {
    final path = File('../output/catalog-es-detail-live.json');
    if (!path.existsSync()) return;
    final data = parseWiki(
      'wiki-es',
      Map<String, dynamic>.from(jsonDecode(path.readAsStringSync())['parse']),
    );
    expect(data['ingredients'], isNotEmpty);
    expect(data['steps'], isNotEmpty);
    validateEntryData('recipe', data);
  });
}
