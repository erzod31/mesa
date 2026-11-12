import 'dart:convert';
import 'dart:typed_data';

import 'package:html/parser.dart' as html;
import 'package:http/http.dart' as http;

import 'community_catalogs.dart';
import 'models.dart' show searchKey;
import 'source_registry.dart';
import 'public_recipe.dart';

// Public browsing deliberately has no family-server URL, token or cookies.
class PublicPublisherCatalog {
  PublicPublisherCatalog(this.client);
  final http.Client client;
  Future<Map<String, dynamic>> basedSearch(
    CatalogSource source,
    String query,
    String? cursor,
  ) async {
    final offset = int.tryParse(cursor ?? '0');
    if (offset == null || offset < 0 || offset > 10000) {
      throw Exception('Página incorrecta.');
    }
    const api = CatalogSource(
      'based-tree',
      'Based Cooking',
      'Inglés',
      '',
      url: 'https://api.github.com',
    );
    final pages = await Future.wait([
      fetch(Uri.parse(source.url), source),
      fetch(
        Uri.parse(
          'https://api.github.com/repos/LukeSmithxyz/based.cooking/git/trees/master?recursive=1',
        ),
        api,
      ),
    ]);
    final tree = jsonDecode(pages[1].text);
    if (tree is! Map || tree['truncated'] == true || tree['tree'] is! List) {
      throw Exception('El índice libre está incompleto; reintenta.');
    }
    final photos = <String>{
      for (final row in tree['tree'] as List)
        if (row is Map && '${row['path']}'.startsWith('static/pix/'))
          '${row['path']}'.substring('static'.length),
    };
    final rows = <String, Map<String, dynamic>>{};
    for (final link in html.parse(pages[0].text).querySelectorAll('a[href]')) {
      final uri = Uri.parse(source.url).resolve(link.attributes['href']!);
      if (!allowed(uri, source) ||
          uri.hasQuery ||
          uri.hasFragment ||
          !RegExp(r'^/[a-z0-9-]+/$').hasMatch(uri.path)) {
        continue;
      }
      final title = recipeText(link.text);
      if (title.isEmpty) continue;
      if (query.trim().isNotEmpty &&
          !searchKey(title).contains(searchKey(query.trim()))) {
        continue;
      }
      final slug = uri.path.replaceAll('/', '');
      final photo = [
        '/pix/$slug.webp',
        '/pix/$slug.jpg',
        '/pix/$slug.png',
        '/pix/$slug.jpeg',
      ].where(photos.contains).firstOrNull;
      if (photo == null) continue;
      rows.putIfAbsent(
        uri.toString(),
        () => {
          'id': uri.toString(),
          'title': title,
          'provider': source.id,
          'image': Uri.parse(source.url).resolve(photo).toString(),
        },
      );
    }
    final all = rows.values.toList();
    return {
      'items': all.skip(offset).take(24).toList(),
      'cursor': offset + 24 < all.length ? '${offset + 24}' : null,
      'notice': 'Catálogo de dominio público. Las recetas sin foto se excluyen. Busca por el nombre original en inglés.',
    };
  }

  Future<Map<String, dynamic>> mealdbSearch(
    CatalogSource source,
    String query,
    String? cursor,
  ) async {
    const letters = 'abcdefghijklmnopqrstuvwxyz';
    List<dynamic> meals(dynamic data) =>
        data is Map ? data['meals'] as List? ?? [] : <dynamic>[];
    if (query.isNotEmpty) {
      final data = jsonDecode(
        (await fetch(
          Uri.parse(
            'https://www.themealdb.com/api/json/v1/1/search.php?s=${Uri.encodeQueryComponent(query)}',
          ),
          source,
        )).text,
      );
      final items = [
        for (final m in meals(data).whereType<Map>())
          if (m['idMeal'] is String &&
              m['strMeal'] is String &&
              m['strMealThumb'] is String)
            {
              'id':
                  'https://www.themealdb.com/api/json/v1/1/lookup.php?i=${m['idMeal']}',
              'title': '${m['strMeal']}',
              'provider': source.id,
              'image': '${m['strMealThumb']}',
            },
      ];
      return {
        'items': items,
        'cursor': null,
        'notice': items.isEmpty
            ? 'No hay recetas con ese nombre en inglés. Prueba otra búsqueda.'
            : '',
      };
    }
    final current = switch (cursor) {
      null || '' => 0,
      final letter => letters.indexOf(letter),
    };
    if (current < 0 || current >= letters.length) {
      throw Exception('Página incorrecta.');
    }
    final data = jsonDecode(
      (await fetch(
        Uri.parse(
          'https://www.themealdb.com/api/json/v1/1/search.php?f=${letters[current]}',
        ),
        source,
      )).text,
    );
    final items = [
      for (final m in meals(data).whereType<Map>())
        if (m['idMeal'] is String &&
            m['strMeal'] is String &&
            m['strMealThumb'] is String)
          {
            'id':
                'https://www.themealdb.com/api/json/v1/1/lookup.php?i=${m['idMeal']}',
            'title': '${m['strMeal']}',
            'provider': source.id,
            'image': '${m['strMealThumb']}',
          },
    ];
    return {
      'items': items,
      'cursor': current + 1 < letters.length ? letters[current + 1] : null,
      'notice':
          'Catálogo internacional en inglés; se traduce al español al abrir la receta.',
    };
  }

  Future<Map<String, dynamic>> creativeganSearch(
    CatalogSource source,
    String query,
    String? cursor,
  ) async {
    final page = int.tryParse(cursor ?? '1');
    if (page == null || page < 1 || page > 10000) {
      throw Exception('Página incorrecta.');
    }
    final response = await fetch(
      Uri.https('creativegan.net', '/wp-json/wp/v2/posts', {
        'per_page': '12',
        'page': '$page',
        'categories':
            '3,4,5,13,6,7,816,8,958,815,2119,10,11,12,742,14,15,16,817,18',
        '_fields': 'id,link,title,content,_links,_embedded',
        '_embed': 'wp:featuredmedia',
        'search': query.trim(),
      }),
      source,
    );
    final posts = jsonDecode(response.text);
    if (posts is! List || posts.length > 12) {
      throw Exception('Índice de recetas incorrecto.');
    }
    final items = <Map<String, dynamic>>[];
    for (final p in posts) {
      try {
        final uri = Uri.parse(p['link']);
        if (!allowed(uri, source)) continue;
        final r = parseCreativegan(
          p['content']['rendered'],
          uri,
          source,
          title: plainHtml(p['title']['rendered']),
        );
        final media = p['_embedded']?['wp:featuredmedia'];
        final featured = media is List && media.isNotEmpty
            ? '${media.first['source_url'] ?? ''}'
            : '';
        items.add({
          'id': p['link'],
          'title': r['title'],
          'provider': source.id,
          'image': publisherPhotoUrl(featured)
              ? featured
              : r['photos'][0]['url'],
        });
      } catch (_) {
        /* Non-recipe posts never enter the catalogue. */
      }
    }
    return {
      'items': items,
      'cursor': posts.length == 12 ? '${page + 1}' : null,
      'notice': 'Virginia García · CC BY-NC-SA 3.0 ES. Solo recetas completas con foto.',
    };
  }

  Future<Map<String, dynamic>> detail(CatalogSource source, String url) async {
    final target = Uri.tryParse(url);
    if (!source.external ||
        !source.browseable ||
        target == null ||
        !allowed(target, source)) {
      throw Exception(
        'El enlace no pertenece a una fuente de recetas disponible.',
      );
    }
    if (source.id == 'open-mealdb') {
      final mealId = target.queryParameters['i'];
      if (mealId == null || !RegExp(r'^\d+$').hasMatch(mealId)) {
        throw Exception('Receta de TheMealDB incorrecta.');
      }
      final data = jsonDecode(
        (await fetch(
          Uri.parse(
            'https://www.themealdb.com/api/json/v1/1/lookup.php?i=$mealId',
          ),
          source,
        )).text,
      );
      final meals = data is Map ? data['meals'] as List? ?? [] : <dynamic>[];
      final meal = meals.whereType<Map>().firstOrNull;
      if (meal == null ||
          meal['strMealThumb'] is! String ||
          (meal['strMealThumb'] as String).isEmpty) {
        throw Exception('La receta no está completa en TheMealDB.');
      }
      final ingredients = <String>[];
      for (var index = 1; index <= 20; index++) {
        final ingredient = '${meal['strIngredient$index'] ?? ''}'.trim();
        if (ingredient.isEmpty) continue;
        final measure = '${meal['strMeasure$index'] ?? ''}'.trim();
        ingredients.add('$measure $ingredient'.trim());
      }
      final steps = ('${meal['strInstructions'] ?? ''}')
          .split('\r\n')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
      if (ingredients.isEmpty || steps.isEmpty) {
        throw Exception('La receta no está completa en TheMealDB.');
      }
      return {
        'title': '${meal['strMeal'] ?? ''}'.trim(),
        'language': 'en',
        'ingredients': ingredients,
        'steps': steps,
        'tags': const ['Internacional'],
        'servings': 4,
        'servings_declared': false,
        'minutes': 0,
        'notes': '',
        'source': target.toString(),
        'image': '',
        'photos': [
          {
            'url': meal['strMealThumb'],
            'source': target.toString(),
            'caption': '',
            'artist': '',
            'license': '',
            'license_url': '',
            'image': '',
          },
        ],
        'origin': {
          'provider': 'open-mealdb',
          'id': mealId,
          'url': target.toString(),
          'language': 'en',
          'attribution': 'TheMealDB',
          'license': 'Gratuita · atribución requerida',
          'license_url': 'https://www.themealdb.com/api.php',
        },
      };
    }
    final page = await fetch(target, source);
    return parsePublicRecipe(page.text, page.uri, source);
  }

  bool allowed(Uri uri, CatalogSource source) =>
      uri.scheme == 'https' &&
      uri.userInfo.isEmpty &&
      (!uri.hasPort || uri.port == 443) &&
      {Uri.parse(source.url).host, ...source.aliases}.contains(uri.host);

  Future<({String text, Uri uri})> fetch(
    Uri uri,
    CatalogSource source, {
    Map<String, String>? form,
  }) async {
    final clock = Stopwatch()..start();
    for (var redirects = 0; redirects <= 3; redirects++) {
      if (!allowed(uri, source)) {
        throw Exception('La fuente redirige a un dominio no reconocido.');
      }
      final request = http.Request(form == null ? 'GET' : 'POST', uri)
        ..followRedirects = false;
      request.headers['User-Agent'] = 'MesaRecipeApp/1.4.1';
      if (form != null) request.bodyFields = form;
      final response = await client
          .send(request)
          .timeout(const Duration(seconds: 10));
      final bytes = BytesBuilder(copy: false);
      await for (final part in response.stream.timeout(
        const Duration(seconds: 8),
      )) {
        if (bytes.length + part.length > 4000000 ||
            clock.elapsed.inSeconds > 20) {
          throw Exception(
            'La página es demasiado grande o tarda en responder.',
          );
        }
        bytes.add(part);
      }
      if ([301, 302, 303, 307, 308].contains(response.statusCode)) {
        final location = response.headers['location'];
        if (location == null) throw Exception('Redirección sin destino.');
        uri = uri.resolve(location);
        if (response.statusCode == 303) form = null;
        continue;
      }
      if (response.statusCode != 200) {
        throw Exception(
          'La fuente no permite esta consulta (HTTP ${response.statusCode}).',
        );
      }
      final raw = bytes.takeBytes();
      final latin = (response.headers['content-type'] ?? '').toLowerCase();
      return (
        text: latin.contains('iso-8859-1') || latin.contains('windows-1252')
            ? latin1.decode(raw)
            : utf8.decode(raw, allowMalformed: true),
        uri: uri,
      );
    }
    throw Exception('La fuente redirige demasiadas veces.');
  }

  Future<Map<String, dynamic>> search(
    CatalogSource source,
    String query,
    String? cursor,
  ) async {
    query = query.trim();
    if (!source.external || !source.browseable) {
      throw Exception('Esta fuente se consulta en su sitio original.');
    }
    if (source.id == 'es-creativegan' && !query.startsWith('https://')) {
      return creativeganSearch(source, query, cursor);
    }
    if (source.id == 'open-based' && !query.startsWith('https://')) {
      return basedSearch(source, query, cursor);
    }
    if (source.id == 'open-mealdb' && !query.startsWith('https://')) {
      return mealdbSearch(source, query, cursor);
    }
    throw Exception('Esta fuente no ofrece búsqueda en Mesa. Pega el enlace de una receta.');
  }


}
