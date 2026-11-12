import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mesa/catalogs.dart' hide catalogSources;

import 'fixture_sources.dart';

import 'package:mesa/public_recipe.dart';

final catalogSources = fixtureSources;

const url = 'https://based.cooking/pan-casero/';
final source = catalogSources.firstWhere((s) => s.id == 'open-based');
String schemaPage({String title = 'Pan casero'}) =>
    '<script type="application/ld+json">${jsonEncode({
      '@graph': [
        {'@type': 'WebPage'},
        {
          '@type': ['Recipe'],
          'name': title,
          'recipeIngredient': ['500 g de harina', '250 ml de agua', 'Sal al gusto'],
          'recipeYield': '6 porciones',
          'totalTime': 'PT1H15M',
          'image': [
            '/uploads/pan.jpg',
            {
              'url': '/uploads/pan-2.jpg',
              'caption': 'Pan terminado',
              'author': {'name': 'Autor'},
            },
          ],
          'recipeInstructions': [
            {
              '@type': 'HowToSection',
              'itemListElement': [
                {'text': 'Mezclar los ingredientes.', 'image': '/uploads/paso.jpg'},
                {'text': 'Hornear 30 minutos.'},
              ],
            },
          ],
        },
      ],
    })}</script>';

void main() {
  test('A foreign publisher without HTML language still triggers Spanish translation', () {
    final based = catalogSources.firstWhere((s) => s.id == 'open-based');
    final value = parsePublicRecipe(
      schemaPage(title: 'Bread'),
      Uri.parse('https://based.cooking/bread/'),
      based,
    );
    expect(value['language'], 'en');
    expect(value['origin']['language'], 'en');
  });
  test('Public detail keeps quantities, servings, full steps and every recipe photo URL', () async {
    final api = CatalogApi(
      MockClient((request) async {
        expect(request.url.toString(), url);
        expect(request.headers.containsKey('authorization'), false);
        expect(request.headers.containsKey('cookie'), false);
        return http.Response(schemaPage(), 200);
      }),
      sources: fixtureSources,
    );
    final recipe = await api.detail(
      const CatalogItem(id: url, title: 'Pan', provider: 'open-based'),
    );
    expect(recipe['ingredients'], [
      '500 g de harina',
      '250 ml de agua',
      'Sal al gusto',
    ]);
    expect(recipe['servings'], 6);
    expect(recipe['servings_declared'], true);
    expect(recipe['minutes'], 75);
    expect(recipe['steps'], [
      'Mezclar los ingredientes.',
      'Hornear 30 minutos.',
    ]);
    expect(recipe['photos'], hasLength(3));
    expect(recipe['photos'][1]['artist'], 'Autor');
    expect(recipe['origin']['url'], url);
    expect(recipe['origin']['language'], 'en');
    expect(recipe['image'], isEmpty);
  });

  test('Family server failure falls back to public detail without sending credentials to publisher', () async {
    var calls = 0;
    final api = CatalogApi(
      MockClient((request) async {
        calls++;
        expect(request.url.host, 'based.cooking');
        expect(request.headers.containsKey('authorization'), false);
        return http.Response(schemaPage(), 200);
      }),
      externalDetail: (_, _) async => throw Exception('Server offline'),
      sources: fixtureSources,
    );
    expect(
      (await api.detail(
        const CatalogItem(id: url, title: 'Pan', provider: 'open-based'),
      ))['title'],
      'Pan casero',
    );
    expect(calls, 1);
  });

  test('Visible widgets keep fuller quantities and article photos without related recipes', () {
    final recipe = parsePublicRecipe(
      '''
      <h1>Pan visible</h1><div class="entry-content">
      <div class="wprm-recipe-servings-container">8 unidades</div>
      <div class="wprm-recipe-ingredient">500 g de harina</div>
      <div class="wprm-recipe-ingredient">250 ml de agua</div>
      <div class="wprm-recipe-instruction-text">Amasar y dejar reposar.</div>
      <img src="/uploads/pan.jpg"><img src="/uploads/pan-300x200.jpg">
      <img src="/uploads/paso.jpg"><div class="related"><img src="/uploads/otro.jpg"></div>
      <a href="/otra-receta"><img src="/uploads/otro-2.jpg"></a></div>
    ''',
      Uri.parse(url),
      source,
    );
    expect(recipe['ingredients'], ['500 g de harina', '250 ml de agua']);
    expect(recipe['servings'], 8);
    expect(recipe['yield_unit'], 'unidades');
    expect(recipe['photos'], hasLength(2));
  });

  test('Section fallback handles paragraph ingredients and preserves unknown servings', () {
    final recipe = parsePublicRecipe(
      '''<h1>Sopa</h1><article class="entry-content">
      <h2>Ingredientes</h2><p>200 g de patatas<br>1 litro de agua</p>
      <h2>Preparación</h2><p>Cocer los ingredientes hasta que estén tiernos.</p>
      <img src="/uploads/sopa.jpg"></article>''',
      Uri.parse(url),
      source,
    );
    expect(recipe['ingredients'], ['200 g de patatas', '1 litro de agua']);
    expect(recipe['servings'], 1);
    expect(recipe['servings_declared'], false);
  });

  test(
    'Foreign links and redirects stop before unrecognized hosts are fetched',
    () async {
      final seen = <String>[];
      final api = CatalogApi(
        MockClient((request) async {
          seen.add(request.url.host);
          return http.Response(
            '',
            302,
            headers: {'location': 'https://example.com/recipe'},
          );
        }),
        sources: fixtureSources,
      );
      await expectLater(
        api.detail(
          const CatalogItem(
            id: 'http://127.0.0.1/recipe',
            title: 'Wrong',
            provider: 'open-based',
          ),
        ),
        throwsException,
      );
      expect(seen, isEmpty);
      await expectLater(
        api.detail(
          const CatalogItem(id: url, title: 'Pan', provider: 'open-based'),
        ),
        throwsException,
      );
      expect(seen, ['based.cooking']);
    },
  );

  test('Incomplete pages, missing quantities and missing photos fail without inventing a recipe', () {
    for (final page in [
      '<h1>Acceso bloqueado</h1>',
      '<script type="application/ld+json">{"@type":"Recipe","name":"Pan","recipeIngredient":["harina"],"recipeInstructions":["Amasar"],"image":"/uploads/pan.jpg"}</script>',
      '<script type="application/ld+json">{"@type":"Recipe","name":"Pan","recipeIngredient":["500 g de harina"],"recipeInstructions":["Amasar"]}</script>',
    ]) {
      expect(
        () => parsePublicRecipe(page, Uri.parse(url), source),
        throwsException,
      );
    }
  });
}
