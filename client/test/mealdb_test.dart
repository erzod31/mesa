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
}
