import 'dart:convert';
import 'dart:typed_data';

import 'package:html/dom.dart';
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
    if (source.id == 'mx-kiwilimon') {
      if (target.host != 'www.kiwilimon.com' ||
          !target.path.startsWith('/receta/')) {
        throw Exception('Usa el enlace de una receta de Kiwilimón.');
      }
      const api = CatalogSource(
        'kiwi-api',
        'Kiwilimón',
        'Español',
        '',
        url: 'https://gr.kiwilimon.com',
      );
      final response = await fetch(
        Uri.parse('https://gr.kiwilimon.com/v6/recipe'),
        api,
        form: {
          'language': 'es',
          'device': 'pc',
          'path': target.path,
          'ingredients': '1',
        },
      );
      final data = jsonDecode(response.text);
      if (data is! Map ||
          data['language'] != 'es' ||
          data['key'] is! int ||
          data['ingredients'] is! List ||
          data['steps'] is! List) {
        throw Exception(
          'La fuente no devuelve esta receta completa en español.',
        );
      }
      final photos = <String, Map<String, dynamic>>{};
      for (final image in [
        data['image'],
        for (final row in data['images'] as List? ?? [])
          if (row is Map) row['image'],
      ]) {
        if (image is! String ||
            !RegExp(
              r'^[\w.-]+\.jpe?g$',
              caseSensitive: false,
            ).hasMatch(image)) {
          continue;
        }
        final photo =
            'https://cdn7.kiwilimon.com/recetaimagen/${data['key']}/960x640/$image.jpg';
        photos.putIfAbsent(
          photo,
          () => {
            'url': photo,
            'source': url,
            'caption': recipeText(data['name'] ?? ''),
            'artist': '',
            'license': '',
            'license_url': '',
            'image': '',
          },
        );
      }
      final portions = data['portions'];
      final declared = portions is num && portions > 0;
      return publicRecipeOrigin({
        'title': recipeText(data['name'] ?? '')
            .substring(0, recipeText(data['name'] ?? '').length.clamp(0, 250)),
        'ingredients': (data['ingredients'] as List)
            .whereType<Map>()
            .map((r) => recipeText(r['text'] ?? ''))
            .where((v) => v.isNotEmpty)
            .take(500)
            .toList(),
        'steps': (data['steps'] as List)
            .whereType<Map>()
            .map((r) => recipeText(r['text'] ?? ''))
            .where((v) => v.isNotEmpty)
            .take(500)
            .toList(),
        'servings': declared ? portions.clamp(1, 10000) : 1,
        'servings_declared': declared,
        'yield_unit': 'porciones',
        'yield_original': declared ? '$portions' : '',
        'minutes': data['totaltime'] is int
            ? (data['totaltime'] as int).clamp(0, 100000)
            : 0,
        'source': url,
        'tags': <String>[],
        'image': '',
        'photos': photos.values.toList(),
        'notes': recipeText(data['description'] ?? ''),
      }, source);
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
    if (source.id == 'mx-kiwilimon' && !query.startsWith('https://')) {
      return kiwilimon(query, cursor);
    }
    if (source.id == 'es-petitchef' && query.isEmpty) {
      final offset = int.tryParse(cursor ?? '0');
      if (offset == null || !{0, 50}.contains(offset)) {
        throw Exception('Página incorrecta.');
      }
      final page = await fetch(
        Uri.parse('https://www.petitchef.es/las-ultimas-recetas'),
        source,
      );
      final cards = parseCards(page.text, page.uri, source, '', limit: 100);
      final items = cards.skip(offset).take(50).toList();
      return {
        'items': items,
        'cursor': offset + items.length < cards.length
            ? '${offset + items.length}'
            : null,
        'notice': items.isEmpty
            ? 'Petitchef no devolvió recetas con foto. Reintenta o abre el sitio original.'
            : '',
      };
    }
    if (cursor != null) {
      throw Exception('Consulta más recetas en el sitio original.');
    }
    var target = Uri.parse(query.startsWith('https://') ? query : source.url);
    if (!allowed(target, source)) {
      throw Exception('Selecciona la fuente de ese enlace.');
    }
    if (query.isNotEmpty && !query.startsWith('https://')) {
      target = source.id == 'es-petitchef'
          ? target
                .resolve('/index.php')
                .replace(
                  queryParameters: {
                    'obj': 'feed',
                    'action': 'list',
                    'q': query,
                  },
                )
          : target.replace(
              queryParameters: {...target.queryParameters, 's': query},
            );
    }
    ({String text, Uri uri}) page;
    try {
      page = await fetch(target, source);
    } catch (_) {
      if (query.startsWith('https://') ||
          source.seed.isEmpty ||
          target.toString() == source.seed) {
        rethrow;
      }
      page = await fetch(Uri.parse(source.seed), source);
    }
    var items = parseCards(page.text, page.uri, source, query);
    var example = false;
    if (items.isEmpty &&
        query.isEmpty &&
        source.seed.isNotEmpty &&
        page.uri.toString() != source.seed) {
      page = await fetch(Uri.parse(source.seed), source);
      items = parseCards(page.text, page.uri, source, query);
      example = true;
    }
    return {
      'items': items,
      'cursor': null,
      'notice': items.isEmpty
          ? 'La fuente no devolvió recetas con foto. Prueba otro nombre o abre el original.'
          : example
          ? 'Receta de ejemplo de la fuente. Busca otro plato o pega su enlace.'
          : '',
    };
  }

  List<Map<String, dynamic>> parseCards(
    String text,
    Uri base,
    CatalogSource source,
    String query, {
    int limit = 24,
  }) {
    final doc = html.parse(text);
    final headings = <String, String>{};
    for (final link in doc.querySelectorAll('a[href]')) {
      if (!['h1', 'h2', 'h3', 'h4'].contains(link.parent?.localName) &&
          link.querySelector('h1,h2,h3,h4') == null) {
        continue;
      }
      final uri = Uri.tryParse(link.attributes['href']!.trim());
      if (uri != null && link.text.trim().isNotEmpty) {
        headings[base.resolveUri(uri).removeFragment().toString()] = link.text
            .trim();
      }
    }
    final items = <String, Map<String, dynamic>>{};
    bool matches(String title) =>
        query.isEmpty ||
        query.startsWith('https://') ||
        searchKey(query).split(' ').every((w) => searchKey(title).contains(w));
    void add(String url, String title, String photo) {
      title = title.replaceAll(RegExp(r'\s+'), ' ').trim();
      if (title.contains('<') ||
          {
            'recetas',
            'receta',
            'cocina',
            'verduras',
            'principal',
            'pescados',
            'comidas para ti',
            'recetario',
            'recetas chilenas',
            'indice de recetas',
            'regístrate',
            'registrate',
            'politica de privacidad',
            'carnes',
            'postres',
            'bebidas',
            'inicio',
            'contacto',
            'leer mas',
            'ver mas',
            'suscribete',
          }.contains(searchKey(title))) {
        return;
      }
      final uri = Uri.tryParse(url);
      if (uri == null ||
          !allowed(uri, source) ||
          uri.hasQuery ||
          title.length < 4 ||
          title.length > 250 ||
          !matches(title) ||
          !publisherPhotoUrl(photo) ||
          items.length >= limit) {
        return;
      }
      final prefix = Uri.parse(source.url).path.replaceFirst(RegExp(r'/$'), '');
      if (prefix.isNotEmpty && !uri.path.startsWith('$prefix/')) return;
      if (source.id == 'es-hogarmania' && !uri.path.endsWith('.html')) return;
      if (source.id == 'es-bonviveur' &&
          !RegExp(r'^/(?:es/)?recetas/[^/]+/?$').hasMatch(uri.path)) {
        return;
      }
      if (source.id == 'es-gratis' && !uri.path.startsWith('/receta-')) return;
      if (source.id == 'ar-cocineros' && !uri.path.startsWith('/recetas/')) {
        return;
      }
      if (source.id == 'mx-nestle' && !uri.path.startsWith('/recetas/')) return;
      if (source.id == 'mx-larousse' && !uri.path.startsWith('/receta/')) {
        return;
      }
      if (source.id == 'es-petitchef' &&
          !RegExp(r'^/recetas/.+-fid-\d+/?$').hasMatch(uri.path)) {
        return;
      }
      if (uri.path.replaceFirst(RegExp(r'/$'), '') == prefix ||
          RegExp(
            r'/(tag|category|categoria|categorias|autor|chef|chefs|noticias|restaurantes|salud|nutricion|dietas|contacto|contact|privacy|wp-content|about|quien-es|politica|aviso-legal|terminos)([/-]|$)',
            caseSensitive: false,
          ).hasMatch(uri.path)) {
        return;
      }
      final canonical = uri.removeFragment().toString();
      items.putIfAbsent(
        canonical,
        () => {
          'id': canonical,
          'title': title,
          'provider': source.id,
          'image': photo,
        },
      );
    }

    for (final image in doc.querySelectorAll('img')) {
      if (excluded(image)) continue;
      final photo = imageUrl(image, base);
      if (photo.isEmpty) continue;
      Element? container = image.parent;
      for (
        var level = 0;
        level < 5 && container != null;
        level++, container = container.parent
      ) {
        final links = [
          if (container.localName == 'a') container,
          ...container.querySelectorAll('a[href]'),
        ];
        var accepted = false;
        for (final link in links) {
          final href = link.attributes['href'];
          if (href == null) continue;
          final fallbackTitle = link.text.trim().isNotEmpty
              ? link.text
              : container.querySelector('h2,h3,h4')?.text ??
                    image.attributes['alt'] ??
                    '';
          final target = Uri.tryParse(href.trim());
          if (target == null) continue;
          final url = base.resolveUri(target).removeFragment().toString();
          add(url, headings[url] ?? fallbackTitle, photo);
          if (items.containsKey(url)) {
            accepted = true;
            break;
          }
        }
        if (accepted) break;
      }
    }
    // Recipe pages can be the only result on a publisher's landing/search page.
    if (items.isEmpty) {
      void schema(dynamic node) {
        if (node is List) {
          for (final child in node) {
            schema(child);
          }
        }
        if (node is! Map) return;
        final type = node['@type'];
        if (type == 'Recipe' || type is List && type.contains('Recipe')) {
          void picture(dynamic value) {
            if (value is List) {
              for (final v in value) {
                picture(v);
              }
            }
            if (value is Map) picture(value['url'] ?? value['contentUrl']);
            if (value is String && Uri.tryParse(value.trim()) != null) {
              add(
                base.toString(),
                '${node['name'] ?? ''}',
                base.resolve(value.trim()).toString(),
              );
            }
          }

          picture(node['image']);
        }
        if (node['@graph'] != null) schema(node['@graph']);
      }

      for (final script in doc.querySelectorAll(
        'script[type="application/ld+json"]',
      )) {
        try {
          schema(jsonDecode(script.text));
        } catch (_) {
          /* malformed publisher schema */
        }
      }
    }
    return items.values.toList();
  }

  bool excluded(Element image) {
    Element? node = image;
    while (node != null) {
      if (['body', 'html'].contains(node.localName)) return false;
      if (['nav', 'footer', 'aside', 'header'].contains(node.localName)) {
        return true;
      }
      if (node.classes.contains('sidebar') ||
          ['sidebar', 'secondary'].contains(node.id) ||
          RegExp(
            r'(related|recommend|comment|author-bio|social|advert|promo)',
            caseSensitive: false,
          ).hasMatch('${node.attributes['class'] ?? ''} ${node.id}')) {
        return true;
      }
      node = node.parent;
    }
    return false;
  }

  String imageUrl(Element image, Uri base) {
    for (final name in [
      'data-orig-file',
      'data-lazy-src',
      'data-src',
      'src',
      'data-srcset',
      'srcset',
    ]) {
      final value = image.attributes[name];
      if (value == null || value.startsWith('data:')) continue;
      final raw = name.endsWith('srcset')
          ? value.split(',').last.trim().split(RegExp(r'\s+')).first
          : value;
      final relative = Uri.tryParse(raw.trim());
      if (relative == null) continue;
      final url = base.resolveUri(relative).toString();
      if (RegExp(
        r'(logo|avatar|favicon|sprite|cropped-recetas)',
        caseSensitive: false,
      ).hasMatch(Uri.parse(url).path)) {
        continue;
      }
      if (publisherPhotoUrl(url)) return url;
    }
    return '';
  }

  Future<Map<String, dynamic>> kiwilimon(String query, String? cursor) async {
    final page = int.tryParse(cursor ?? '1');
    if (page == null || page < 1 || page > 10000) {
      throw Exception('Página incorrecta.');
    }
    const api = CatalogSource(
      'kiwi-api',
      'Kiwilimón',
      'Español',
      '',
      url: 'https://gr.kiwilimon.com',
    );
    final response = await fetch(
      Uri.parse('https://gr.kiwilimon.com/v6/search'),
      api,
      form: {
        'q': query.isEmpty ? 'pollo' : query,
        'language': 'es',
        'device': 'pc',
        'quantity': '24',
        'page': '$page',
      },
    );
    final data = jsonDecode(response.text) as Map;
    final items = <Map<String, dynamic>>[];
    for (final row in data['payload'] as List? ?? []) {
      if (row is! Map || row['t'] != 'receta' || row['c'] is! int) continue;
      final path = '${row['ruta'] ?? ''}', image = '${row['imagen'] ?? ''}';
      if (!path.startsWith('/receta/') ||
          !RegExp(
            r'^[\w.-]+\.(jpe?g|png)$',
            caseSensitive: false,
          ).hasMatch(image)) {
        continue;
      }
      items.add({
        'id': 'https://www.kiwilimon.com$path',
        'title': '${row['nombre'] ?? ''}',
        'provider': 'mx-kiwilimon',
        'image':
            'https://cdn7.kiwilimon.com/recetaimagen/${row['c']}/960x640/$image.jpg',
      });
    }
    return {
      'items': items,
      'cursor': data['more'] == true ? '${page + 1}' : null,
      'notice': query.isEmpty
          ? 'Recetas con pollo para empezar. Busca otro plato o ingrediente.'
          : '',
    };
  }
}
