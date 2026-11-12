import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mesa/catalogs.dart';

import 'fixture_sources.dart';

void main() {
  test('TheMealDB search and detail work without family credentials', () async {
    final api = CatalogApi(
      MockClient((request) async {
        expect(request.headers.containsKey('authorization'), false);
        expect(request.url.host, 'www.themealdb.com');
        if (request.url.path.endsWith('/search.php')) {
          return http.Response(
            jsonEncode({
              'meals': [
                {
                  'idMeal': '52772',
                  'strMeal': 'Spicy Arrabiata Penne',
                  'strMealThumb':
                      'https://www.themealdb.com/images/media/meals/llcbn01574260722.jpg',
                },
              ],
            }),
            200,
          );
        }
        expect(request.url.queryParameters['i'], '52772');
        return http.Response(
          jsonEncode({
            'meals': [
              {
                'idMeal': '52772',
                'strMeal': 'Spicy Arrabiata Penne',
                'strMealThumb':
                    'https://www.themealdb.com/images/media/meals/llcbn01574260722.jpg',
                'strIngredient1': 'Penne rigate',
                'strMeasure1': '1 pound',
                'strIngredient2': 'Olive oil',
                'strMeasure2': '1/4 cup',
                'strIngredient3': '',
                'strMeasure3': '',
                'strInstructions':
                    'Heat the oil in a large pan.\r\nAdd the pasta and cook.',
              },
            ],
          }),
          200,
        );
      }),
      sources: fixtureSources,
    );
    final page = await api.search('open-mealdb', query: 'pasta');
    expect(page.items.single.title, 'Spicy Arrabiata Penne');
    expect(page.items.single.hasPhoto, true);
    expect(page.cursor, isNull);
    final recipe = await api.detail(page.items.single);
    expect(recipe['language'], 'en');
    expect(
      recipe['ingredients'],
      ['1 pound Penne rigate', '1/4 cup Olive oil'],
    );
    expect(recipe['steps'], [
      'Heat the oil in a large pan.',
      'Add the pasta and cook.',
    ]);
    expect(recipe['origin']['provider'], 'open-mealdb');
    expect(recipe['origin']['license'], 'Gratuita · atribución requerida');
  });

  test('TheMealDB browse paginates by letter and excludes meals without photo', () async {
    final api = CatalogApi(
      MockClient((request) async {
        expect(request.url.queryParameters['f'], 'a');
        return http.Response(
          jsonEncode({
            'meals': [
              {
                'idMeal': '52893',
                'strMeal': 'Apple Frangipan Tart',
                'strMealThumb': '',
              },
            ],
          }),
          200,
        );
      }),
      sources: fixtureSources,
    );
    final page = await api.search('open-mealdb');
    expect(page.items, isEmpty);
    expect(page.cursor, 'b');
  });

  test('TheCocktailDB search and detail build cocktails with measures', () async {
    final api = CatalogApi(
      MockClient((request) async {
        expect(request.url.host, 'www.thecocktaildb.com');
        if (request.url.path.endsWith('/search.php')) {
          return http.Response(
            jsonEncode({
              'drinks': [
                {
                  'idDrink': '11007',
                  'strDrink': 'Margarita',
                  'strDrinkThumb':
                      'https://www.thecocktaildb.com/images/media/drink/5noda61589575158.jpg',
                },
              ],
            }),
            200,
          );
        }
        expect(request.url.queryParameters['i'], '11007');
        return http.Response(
          jsonEncode({
            'drinks': [
              {
                'idDrink': '11007',
                'strDrink': 'Margarita',
                'strDrinkThumb':
                    'https://www.thecocktaildb.com/images/media/drink/5noda61589575158.jpg',
                'strIngredient1': 'Tequila',
                'strMeasure1': '1 1/2 oz',
                'strIngredient2': 'Lime juice',
                'strMeasure2': '1 oz',
                'strIngredient3': '',
                'strMeasure3': '',
                'strInstructions':
                    'Rub the rim of the glass with the lime slice.\r\nShake the other ingredients.',
              },
            ],
          }),
          200,
        );
      }),
      sources: fixtureSources,
    );
    final page = await api.search('open-cocktaildb', query: 'margarita');
    expect(page.items.single.title, 'Margarita');
    expect(page.items.single.hasPhoto, true);
    final recipe = await api.detail(page.items.single);
    expect(recipe['ingredients'], ['1 1/2 oz Tequila', '1 oz Lime juice']);
    expect(recipe['steps'], [
      'Rub the rim of the glass with the lime slice.',
      'Shake the other ingredients.',
    ]);
    expect(recipe['origin']['provider'], 'open-cocktaildb');
    expect(recipe['origin']['license'], 'Gratuita · atribución requerida');
    expect(recipe['servings'], 1);
  });

  test('Chowdown browses its repository and parses front matter locally', () async {
    final api = CatalogApi(
      MockClient((request) async {
        if (request.url.host == 'api.github.com') {
          return http.Response(
            jsonEncode({
              'tree': [
                {'path': '_recipes/banana-bread.md', 'type': 'blob'},
                {'path': 'images/banana-bread.jpg', 'type': 'blob'},
              ],
            }),
            200,
          );
        }
        expect(request.url.host, 'raw.githubusercontent.com');
        return http.Response(
          '---\ntitle: "Banana Bread"\nimage: banana-bread.jpg\ningredients:\n- 4 bananas\n- 2 cups flour\ndirections:\n- Mash and mix.\n---',
          200,
          headers: {'content-type': 'text/plain'},
        );
      }),
      sources: fixtureSources,
    );
    final page = await api.search('open-chowdown');
    expect(page.items.single.title, 'Banana Bread');
    final recipe = await api.detail(page.items.single);
    expect(recipe['ingredients'], ['4 bananas', '2 cups flour']);
    expect(recipe['steps'], ['Mash and mix.']);
    expect(recipe['origin']['license'], 'Unlicense · dominio público');
  });

  test('FreeAPI Meals browses pages and opens recipes with measures', () async {
    final api = CatalogApi(
      MockClient((request) async {
        expect(
          request.url.host,
          'prod-main-api-704464-00tre1p1erm.compute.instacloud-edge.com',
        );
        return http.Response(
          jsonEncode({
            'data': {
              'data': [
                {
                  'idMeal': '52785',
                  'strMeal': 'Dal fry',
                  'strMealThumb':
                      'https://www.themealdb.com/images/media/meals/x.jpg',
                  'strIngredient1': 'Toor dal',
                  'strMeasure1': '1 cup',
                  'strIngredient2': '',
                  'strMeasure2': '',
                  'strInstructions': 'Wash the dal.\r\nBoil it.',
                },
              ],
              'nextPage': false,
            },
          }),
          200,
        );
      }),
      sources: fixtureSources,
    );
    final page = await api.search('open-freemeals');
    expect(page.items.single.title, 'Dal fry');
    expect(page.items.single.hasPhoto, true);
    final recipe = await api.detail(page.items.single);
    expect(recipe['ingredients'], ['1 cup Toor dal']);
    expect(recipe['origin']['provider'], 'open-freemeals');
  });
}
