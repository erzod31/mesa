import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:html/dom.dart' show Element;

import 'package:html/parser.dart' as html;
import 'package:http/http.dart' as http;

import 'models.dart';
import 'photo_data.dart';
import 'licensed_photos.dart';
import 'community_catalogs.dart';
import 'source_registry.dart';
import 'publisher_catalogs.dart';
import 'encantar_catalog.dart';
export 'source_registry.dart';

export 'community_catalogs.dart'
    show catalogPhotoUrl, delokosPhotoUrl, publisherPhotoUrl, parseDelokos;

const spanishRevision = 'f109aa858a57cf10218a747a286530f9a602b07b';
const spanishSourceUrl =
    'https://huggingface.co/datasets/belenarbizu/recetas-espanolas/blob/$spanishRevision/recetas.json';
const wikiEditions = <String, ({String prefix, int namespace})>{
  'wiki-es': (prefix: 'Artes culinarias/Recetas/', namespace: 0),
  'wiki-en': (prefix: 'Cookbook:', namespace: 102),
  'wiki-fr': (prefix: 'Livre de cuisine/', namespace: 0),
  'wiki-it': (prefix: 'Libro di cucina/Ricette/', namespace: 0),
  'wiki-pt': (prefix: 'Livro de receitas/', namespace: 0),
  'wiki-de': (prefix: 'Kochbuch/', namespace: 0),
};
const wikiCategories = <String, String>{
  'Recetas': 'Todas',
  'Aperitivo': 'Aperitivos',
  'Primer plato': 'Primeros',
  'Segundo plato': 'Segundos',
  'Postre': 'Postres',
  'Salsa': 'Salsas',
  'Sopas': 'Sopas',
  'Recetas de pan': 'Pan',
};

class CatalogItem {
  const CatalogItem({
    required this.id,
    required this.title,
    required this.provider,
    this.image = '',
  });
  final String id, title, provider, image;
  bool get hasPhoto => switch (provider) {
    'es-encantar' => encantarPhotoUrl(image.trim()),
    final id when wikiEditions.containsKey(id) => wikimediaPhotoUrl(
      image.trim(),
    ),
    'delokos-es' => delokosPhotoUrl(image.trim()),
    _ =>
      catalogSources.any(
            (s) =>
                s.id == provider &&
                (s.external || s.included || s.consultationOnly),
          ) &&
          (publisherPhotoUrl(image.trim()) ||
              documentPhotoReference(image.trim()) != null),
  };
  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'provider': provider,
    'image': image,
  };
  factory CatalogItem.fromJson(Map<String, dynamic> j) => CatalogItem(
    id: j['id'],
    title: j['title'],
    provider: j['provider'],
    image: j['image'] ?? '',
  );
}

class CatalogResult {
  const CatalogResult(this.items, {this.cursor, this.notice = ''});
  final List<CatalogItem> items;
  final String? cursor;
  final String notice;
  Map<String, dynamic> toJson() => {
    'items': items.map((e) => e.toJson()).toList(),
    'cursor': cursor,
    'notice': notice,
  };
  factory CatalogResult.fromJson(Map<String, dynamic> j) => CatalogResult(
    (j['items'] as List)
        .map((e) => CatalogItem.fromJson(Map<String, dynamic>.from(e)))
        .where((e) => e.hasPhoto)
        .toList(),
    cursor: j['cursor'],
    notice: j['notice'] ?? '',
  );
}

class CatalogApi {
  CatalogApi(
    this.client, {
    this.externalSearch,
    this.externalDetail,
    this.sources = catalogSources,
  });
  final List<CatalogSource> sources;
  final http.Client client;
  Future<Map<String, dynamic>> importUrl(String value) async {
    final uri = Uri.tryParse(value);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.userInfo.isNotEmpty ||
        uri.hasPort && uri.port != 443) {
      throw Exception('Usa un enlace público HTTPS.');
    }
    final source = sources
        .where(
          (s) =>
              Uri.parse(s.url).host == uri.host || s.aliases.contains(uri.host),
        )
        .firstOrNull;
    if (source == null || !source.browseable) {
      throw Exception('Este enlace no pertenece a una fuente disponible.');
    }
    if (source.id == 'delokos-es') {
      final slug = uri.path.split('/').where((v) => v.isNotEmpty).last;
      if (!RegExp(r'^[a-zA-Z0-9%_-]+$').hasMatch(slug)) {
        throw Exception('El enlace no es una receta válida.');
      }
      final post = await get(
        Uri.https(
          'public-api.wordpress.com',
          '/rest/v1.1/sites/delokos.wordpress.com/posts/slug:$slug',
        ),
      );
      final recipe = parseDelokos(post);
      if (recipe == null) {
        throw Exception(
          'La publicación no contiene una receta completa con foto.',
        );
      }
      return recipe;
    }
    return detail(CatalogItem(id: value, title: 'Receta', provider: source.id));
  }

  final Future<Map<String, dynamic>> Function(
    String provider,
    String query,
    String? cursor,
  )?
  externalSearch;
  final Future<Map<String, dynamic>> Function(String provider, String url)?
  externalDetail;
  final _collections = <String, Future<List<Map<String, dynamic>>>>{};
  Future<List<Map<String, dynamic>>> collection(CatalogSource source) =>
      _collections.putIfAbsent(source.id, () async {
        final value =
            jsonDecode(await rootBundle.loadString(source.asset)) as Map;
        return (value['recipes'] as List)
            .map((r) => Map<String, dynamic>.from(r))
            .toList();
      });
  List<Map<String, dynamic>>? spanishRows;
  Future<dynamic> request(Uri uri) async {
    final allowedHost =
        ([
              'es',
              'en',
              'fr',
              'it',
              'pt',
              'de',
            ].any((code) => uri.host == '$code.wikibooks.org') &&
            uri.path == '/w/api.php') ||
        uri.host == 'huggingface.co' ||
        (uri.host == 'public-api.wordpress.com' &&
            RegExp(
              r'^/rest/v1\.1/sites/(delokos|recetasparaencantar)\.wordpress\.com/posts/(\d+/?|slug:[a-zA-Z0-9%_-]+|)$',
            ).hasMatch(uri.path));
    if (uri.scheme != 'https' ||
        uri.userInfo.isNotEmpty ||
        (uri.hasPort && uri.port != 443) ||
        !allowedHost) {
      throw Exception('La dirección del catálogo no es válida.');
    }
    final req = http.Request('GET', uri)..followRedirects = false;
    req.headers['User-Agent'] = 'MesaRecipeApp/1.3 (private family cookbook)';
    final response = await client
        .send(req)
        .timeout(const Duration(seconds: 12));
    if (response.statusCode != 200) {
      throw Exception(
        response.statusCode == 429
            ? 'El catálogo está ocupado. Vuelve a intentarlo más tarde.'
            : 'No se pudo consultar el catálogo (${response.statusCode}).',
      );
    }
    final bytes = <int>[];
    await for (final part in response.stream.timeout(
      const Duration(seconds: 12),
    )) {
      if (bytes.length + part.length > 2000000) {
        throw Exception('La respuesta del catálogo es demasiado grande.');
      }
      bytes.addAll(part);
    }
    return jsonDecode(utf8.decode(bytes));
  }

  Future<Map<String, dynamic>> get(Uri uri) async {
    final result = await request(uri);
    if (result is! Map<String, dynamic> || result.containsKey('error')) {
      throw Exception('El catálogo no pudo completar la consulta.');
    }
    return result;
  }

  Uri wiki(Map<String, String> params, {String provider = 'wiki-es'}) =>
      Uri.https('${provider.substring(5)}.wikibooks.org', '/w/api.php', {
        'format': 'json',
        'formatversion': '2',
        ...params,
      });
  Future<List<Map<String, dynamic>>> spanish() async {
    if (spanishRows != null) {
      return spanishRows!;
    }
    // A reviewed revision prevents silent content changes. No translations, diet labels or nutrition estimates.
    final data = await request(
      Uri.https(
        'huggingface.co',
        '/datasets/belenarbizu/recetas-espanolas/raw/$spanishRevision/recetas.json',
      ),
    );
    if (data is! List || data.length > 500) {
      throw Exception('El catálogo ha cambiado de formato.');
    }
    spanishRows = data.map((e) => Map<String, dynamic>.from(e)).toList();
    return spanishRows!;
  }

  Future<CatalogResult> search(
    String provider, {
    String query = '',
    String? cursor,
    String? category,
  }) async {
    final selected = sources.where((s) => s.id == provider).firstOrNull;
    if (selected == null) throw Exception('Esta fuente se ha retirado.');
    if (selected.consultationOnly) {
      return const CatalogResult(
        [],
        notice: 'Catálogo pendiente de autorización del editor. Puedes consultar el sitio original.',
      );
    }
    if (provider == 'es-encantar') {
      final page = int.tryParse(cursor ?? '1');
      if (page == null || page < 1 || page > 10000) {
        throw Exception('Página incorrecta.');
      }
      final data = await get(
        Uri.https(
          'public-api.wordpress.com',
          '/rest/v1.1/sites/$encantarSite/posts/',
          {
            'number': '16',
            'page': '$page',
            'search': query.trim(),
            'type': 'post',
          },
        ),
      );
      final recipes = [
        for (final p in data['posts'] as List? ?? [])
          parseEncantar(Map<String, dynamic>.from(p)),
      ].whereType<Map<String, dynamic>>();
      return CatalogResult(
        [
          for (final r in recipes)
            CatalogItem(
              id: r['source'],
              title: r['title'],
              provider: provider,
              image: r['photos'][0]['url'],
            ),
        ],
        cursor: page * 16 < (data['found'] as int? ?? 0) ? '${page + 1}' : null,
      );
    }
    if (selected.included) {
      final terms = searchKey(query).split(' ').where((s) => s.isNotEmpty);
      final rows = await collection(selected);
      return CatalogResult(
        rows
            .where(
              (r) => terms.every(
                (t) => searchKey(
                  '${r['title']} ${(r['ingredients'] as List).join(' ')}',
                ).contains(t),
              ),
            )
            .map(
              (r) => CatalogItem(
                id: r['origin']['id'],
                title: r['title'],
                provider: provider,
                image: r['photos'][0]['url'],
              ),
            )
            .toList(),
        notice: 'Texto disponible sin conexión. Las fotos del PDF necesitan el ordenador conectado; no se guardan en disco.',
      );
    }
    if (selected.external) {
      if (externalSearch == null) {
        return CatalogResult.fromJson(
          await PublicPublisherCatalog(client).search(selected, query, cursor),
        );
      }
      return CatalogResult.fromJson(
        await externalSearch!(provider, query, cursor),
      );
    }
    if (!wikiEditions.containsKey(provider) && provider != 'delokos-es') {
      throw Exception('Ese catálogo no ofrece recetas con fotos.');
    }
    var next = cursor;
    final visited = <String?>{};
    for (var page = 0; page < 3; page++) {
      if (!visited.add(next)) {
        throw Exception('El catálogo no pudo avanzar a la siguiente página.');
      }
      final result = provider == 'delokos-es'
          ? await _delokosSearchPage(query, next)
          : await _wikiSearchPage(query, next, category, provider: provider);
      if (result.items.isNotEmpty || result.cursor == null || page == 2) {
        return result;
      }
      next = result.cursor;
    }
    throw StateError('No se pudo completar la búsqueda.');
  }

  Future<CatalogResult> _delokosSearchPage(String query, String? cursor) async {
    final page = int.tryParse(cursor ?? '1');
    if (page == null || page < 1 || page > 10000) {
      throw Exception('Página incorrecta.');
    }
    final data = await get(
      Uri.https(
        'public-api.wordpress.com',
        '/rest/v1.1/sites/delokos.wordpress.com/posts/',
        {
          'number': '16',
          'page': '$page',
          'search': query.trim(),
          'order': 'DESC',
          'type': 'post',
        },
      ),
    );
    final items = <CatalogItem>[];
    for (final raw in data['posts'] as List? ?? []) {
      final recipe = parseDelokos(Map<String, dynamic>.from(raw));
      if (recipe == null) continue;
      items.add(
        CatalogItem(
          id: recipe['origin']['id'],
          title: recipe['title'],
          provider: 'delokos-es',
          image: recipe['photos'][0]['url'],
        ),
      );
    }
    final found = data['found'] as int? ?? 0;
    return CatalogResult(
      items,
      cursor: page * 16 < found ? '${page + 1}' : null,
    );
  }

  Future<CatalogResult> _wikiSearchPage(
    String query,
    String? cursor,
    String? category, {
    String provider = 'wiki-es',
  }) async {
    final edition = wikiEditions[provider]!;
    final prefix = edition.prefix;
    if (category != null && !wikiCategories.containsKey(category)) {
      throw Exception('Categoría incorrecta.');
    }
    final params = query.trim().isNotEmpty
        ? <String, String>{
            'action': 'query',
            'list': 'search',
            'srsearch': '${query.trim()} prefix:"$prefix"',
            'srnamespace': '${edition.namespace}',
            'srlimit': '24',
            'sroffset': ?cursor,
          }
        : provider != 'wiki-es'
        ? <String, String>{
            'action': 'query',
            'list': 'allpages',
            'apnamespace': '${edition.namespace}',
            'apprefix': provider == 'wiki-en' ? '' : prefix,
            'apfilterredir': 'nonredirects',
            'aplimit': '24',
            'apcontinue': ?cursor,
          }
        : <String, String>{
            'action': 'query',
            'list': 'categorymembers',
            'cmtitle': 'Categoría:${category ?? 'Recetas'}',
            'cmtype': 'page',
            'cmlimit': '24',
            'cmcontinue': ?cursor,
          };
    final data = await get(wiki(params, provider: provider));
    final list =
        data['query']?[query.trim().isEmpty
                ? (provider == 'wiki-es' ? 'categorymembers' : 'allpages')
                : 'search']
            as List? ??
        [];
    var items = list
        .where((e) => (e['title'] as String).startsWith(prefix))
        .map(
          (e) => CatalogItem(
            id: e['title'],
            title: (e['title'] as String).substring(prefix.length),
            provider: provider,
          ),
        )
        .toList();
    if (items.isNotEmpty) {
      final pages = await get(
        wiki({
          'action': 'query',
          'titles': items.map((e) => e.id).join('|'),
          'prop': 'images',
          'imlimit': 'max',
        }, provider: provider),
      );
      final covers = <String, List<String>>{};
      for (final page in pages['query']?['pages'] as List? ?? []) {
        final names = wikiPhotoNames({
          'images': (page['images'] as List? ?? [])
              .map((e) => e['title'])
              .toList(),
        });
        if (names.isNotEmpty) {
          covers[page['title']] = names;
        }
      }
      final names = covers.values.expand((names) => names).toSet().toList();
      final photos = await wikiPhotos(names, provider: provider);
      final urls = {
        for (var i = 0; i < names.length; i++)
          names[i]: photos[i]['url'] as String? ?? '',
      };
      items = items
          .map(
            (e) => CatalogItem(
              id: e.id,
              title: e.title,
              provider: e.provider,
              image: (covers[e.id] ?? [])
                  .map((name) => urls[name] ?? '')
                  .firstWhere(wikimediaPhotoUrl, orElse: () => ''),
            ),
          )
          .where((e) => e.hasPhoto)
          .toList();
    }
    return CatalogResult(
      items,
      cursor:
          (data['continue']?[query.trim().isEmpty
                  ? (provider == 'wiki-es' ? 'cmcontinue' : 'apcontinue')
                  : 'sroffset'])
              ?.toString(),
    );
  }

  final _pendingDetails = <String, Future<Map<String, dynamic>>>{};
  final _detailListeners =
      <String, List<void Function(Map<String, dynamic>)>>{};
  final _earlyDetails = <String, Map<String, dynamic>>{};
  Future<Map<String, dynamic>> detail(
    CatalogItem item, {
    void Function(Map<String, dynamic>)? onTextReady,
  }) {
    final key = '${item.provider}:${item.id}';
    if (onTextReady != null) {
      _detailListeners.putIfAbsent(key, () => []).add(onTextReady);
      final early = _earlyDetails[key];
      if (early != null) {
        onTextReady(Map<String, dynamic>.from(jsonDecode(jsonEncode(early))));
      }
    }
    return _pendingDetails.putIfAbsent(
      key,
      () =>
          _detail(item, (value) {
            _earlyDetails[key] = value;
            for (final listener
                in _detailListeners[key] ??
                    <void Function(Map<String, dynamic>)>[]) {
              try {
                listener(
                  Map<String, dynamic>.from(jsonDecode(jsonEncode(value))),
                );
              } catch (_) {}
            }
          }).whenComplete(() {
            _pendingDetails.remove(key);
            _detailListeners.remove(key);
            _earlyDetails.remove(key);
          }),
    );
  }

  Future<Map<String, dynamic>> _detail(
    CatalogItem item,
    void Function(Map<String, dynamic>) onTextReady,
  ) async {
    final selected = sources.where((s) => s.id == item.provider).firstOrNull;
    if (selected?.consultationOnly == true) {
      throw Exception('Importación pendiente de autorización del editor.');
    }
    if (item.provider == 'es-encantar' && selected != null) {
      final uri = Uri.tryParse(item.id);
      if (uri == null ||
          uri.scheme != 'https' ||
          !encantarHosts.contains(uri.host) ||
          uri.userInfo.isNotEmpty ||
          uri.hasPort ||
          !RegExp(r'^/\d{4}/\d{2}/\d{2}/[^/]+/$').hasMatch(uri.path)) {
        throw Exception('El enlace no pertenece a una receta de esta fuente.');
      }
      final post = await get(
        Uri.https(
          'public-api.wordpress.com',
          '/rest/v1.1/sites/$encantarSite/posts/slug:${uri.pathSegments.where((s) => s.isNotEmpty).last}',
        ),
      );
      final result = parseEncantar(post);
      if (result == null) {
        throw Exception(
          'La publicación no contiene una receta completa con foto.',
        );
      }
      return result;
    }
    if (selected?.included == true) {
      final rows = await collection(selected!);
      final row = rows
          .where((r) => r['origin']['id'] == item.id || r['source'] == item.id)
          .firstOrNull;
      if (row == null) {
        throw Exception('La página no pertenece a la selección revisada.');
      }
      return Map<String, dynamic>.from(jsonDecode(jsonEncode(row)));
    }
    if (selected?.external == true) {
      // Public reading first avoids waiting for an unavailable family PC.
      try {
        return await PublicPublisherCatalog(client).detail(selected!, item.id);
      } catch (_) {
        if (externalDetail == null) rethrow;
        return externalDetail!(item.provider, item.id);
      }
    }
    if (item.provider == 'delokos-es') {
      if (!RegExp(r'^\d+$').hasMatch(item.id)) {
        throw Exception('Receta incorrecta.');
      }
      final post = await get(
        Uri.https(
          'public-api.wordpress.com',
          '/rest/v1.1/sites/delokos.wordpress.com/posts/${item.id}',
        ),
      );
      final result = parseDelokos(post);
      if (result == null) {
        throw Exception(
          'Esta publicación no es una receta con fotos y cantidades.',
        );
      }
      return result;
    }
    var wikiTitle = item.id;
    String? oldid;
    if (wikiTitle.startsWith('https://')) {
      final uri = Uri.parse(wikiTitle);
      if (uri.host != '${item.provider.substring(5)}.wikibooks.org') {
        throw Exception('El enlace pertenece a otra fuente.');
      }
      wikiTitle =
          uri.queryParameters['title'] ??
          Uri.decodeComponent(uri.path.replaceFirst('/wiki/', ''))
              .replaceAll('_', ' ');
      oldid = uri.queryParameters['oldid'];
      if (oldid != null && !RegExp(r'^\d+$').hasMatch(oldid)) {
        throw Exception('Revisión incorrecta.');
      }
    }
    if (!wikiEditions.containsKey(item.provider) ||
        !wikiTitle.startsWith(wikiEditions[item.provider]!.prefix)) {
      throw Exception('La receta no pertenece a un recetario disponible.');
    }
    final data = await get(
      wiki({
        'action': 'parse',
        if (oldid == null) 'page': wikiTitle,
        'oldid': ?oldid,
        'prop': 'text|images|revid',
        'redirects': '1',
      }, provider: item.provider),
    );
    final page = Map<String, dynamic>.from(data['parse']);
    final result = parseWiki(item.provider, page);
    if ((result['ingredients'] as List).isEmpty ||
        (result['steps'] as List).isEmpty ||
        !(result['ingredients'] as List).any(
          (v) => RegExp(r'[0-9½¼¾⅓⅔⅛⅜⅝⅞]').hasMatch('$v'),
        )) {
      throw Exception(
        'Esta página no es una receta completa con cantidades. Elige otra ficha.',
      );
    }
    final names = wikiPhotoNames(page);
    if (names.isEmpty) {
      throw Exception(
        'Esta receta no tiene fotos y se ha retirado del catálogo.',
      );
    }
    onTextReady(result);
    result['photos'] = await wikiPhotos(names, provider: item.provider);
    if (!(result['photos'] as List).any(
      (photo) => wikimediaPhotoUrl('${photo['url'] ?? ''}'),
    )) {
      throw Exception(
        'No se pudo comprobar la foto de esta receta. Reintenta más tarde.',
      );
    }
    return result;
  }

  Future<List<Map<String, dynamic>>> wikiPhotos(
    List<String> names, {
    String provider = 'wiki-es',
  }) async {
    final photos = <Map<String, dynamic>>[];
    for (var start = 0; start < names.length; start += 20) {
      final group = names.skip(start).take(20).toList();
      try {
        final data = await get(
          wiki({
            'action': 'query',
            'titles': group.map((n) => 'File:$n').join('|'),
            'prop': 'imageinfo',
            'iiprop': 'url|extmetadata|mime',
            'iiurlwidth': '960',
            'iiextmetadatalanguage': 'es',
          }, provider: provider),
        );
        final found = <String, Map<String, dynamic>>{};
        for (final page in data['query']?['pages'] as List? ?? []) {
          final info = (page['imageinfo'] as List? ?? []).firstOrNull;
          if (info is! Map) {
            continue;
          }
          final photo = wikiPhotoMetadata(Map<String, dynamic>.from(info));
          if (photo != null) {
            found[(page['title'] as String)
                    .replaceFirst(RegExp(r'^[^:]+:'), '')
                    .replaceAll('_', ' ')] =
                photo;
          }
        }
        for (final name in group) {
          final photo =
              found[name.replaceAll('_', ' ')] ??
              {
                'url': '',
                'source':
                    'https://commons.wikimedia.org/wiki/File:${Uri.encodeComponent(name)}',
                'caption': name,
                'error': 'La fuente no devolvió los datos de esta foto.',
              };
          photos.add(photo);
        }
      } catch (_) {
        rethrow;
      }
    }
    return photos;
  }
}

Map<String, dynamic> parseSpanish(Map<String, dynamic> row) {
  final instructions = '${row['instrucciones'] ?? ''}';
  final category = {
    'desayuno': 'desayunos',
    'entrante': 'entrantes',
    'tapa': 'entrantes',
    'postre': 'postres',
    'salsa': 'salsas',
  }[row['categoria']];
  return {
    'title': row['nombre'],
    'ingredients': List<String>.from(row['ingredientes']),
    'steps': instructions
        .split(RegExp(r'\s+(?=\d+\.\s)'))
        .map((s) => s.replaceFirst(RegExp(r'^\d+\.\s*'), '').trim())
        .where((s) => s.isNotEmpty)
        .toList(),
    'servings': row['porciones'] is int && row['porciones'] > 0
        ? row['porciones']
        : 4,
    'minutes': row['tiempo_minutos'] is int && row['tiempo_minutos'] > 0
        ? row['tiempo_minutos']
        : 0,
    'tags': <String>[],
    'category_ids': [if (category != null) 'category:$category'],
    'catalog_ids': <String>[],
    'image': '',
    'source': spanishSourceUrl,
    'notes': 'Colección comunitaria: faltan cantidades en muchas recetas. Completa las cantidades y comprueba si las porciones indican personas o unidades. Los tiempos son los declarados por la fuente; pueden omitir reposo o enfriado. No se importan sus etiquetas dietéticas ni estimaciones nutricionales.',
    'origin': {
      'provider': 'recetas-es',
      'id': '${row['id']}',
      'url': spanishSourceUrl,
      'language': 'es',
      'attribution':
          'belenarbizu · Recetas Españolas · revisión $spanishRevision',
      'license': 'CC BY 4.0',
      'license_url': 'https://creativecommons.org/licenses/by/4.0/deed.es',
      'modified': true,
    },
  };
}

Map<String, dynamic> parseWiki(String provider, Map<String, dynamic> page) {
  final doc = html.parse(page['text'] as String);
  bool pictureCaption(Element node) {
    Element? ancestor = node;
    while (ancestor != null) {
      if (ancestor.localName == 'figure' ||
          ancestor.classes.contains('gallery') ||
          ancestor.classes.contains('thumb')) {
        return true;
      }
      ancestor = ancestor.parent;
    }
    return false;
  }

  for (final element in doc.querySelectorAll(
    'script,style,.mw-editsection,.toc,.noprint,.metadata,.catlinks,table.infobox',
  )) {
    element.remove();
  }
  final pageText = doc.body?.text ?? '';
  final servingsMatch = RegExp(
    r'(?:cantidad\s+para|serves|servings\s*:?|portions?\s*:?|para|pour|per|fur)\s+(\d+|six)\s*(?:personas|comensales|raciones|people|persone|personnes|pessoas|personen)?',
    caseSensitive: false,
  ).firstMatch(searchKey(pageText));
  var minutes = 0;
  for (final cell in doc.querySelectorAll('td')) {
    if (cell.querySelector('img[src*="xclock"]') != null) {
      final m = RegExp(
        r'(\d+)\s*(minutos|min)',
        caseSensitive: false,
      ).firstMatch(cell.text);
      if (m != null) {
        minutes = int.parse(m[1]!);
        break;
      }
    }
  }
  final ingredients = <String>[], steps = <String>[], original = <String>[];
  var section = '';
  for (final element in doc.querySelectorAll('h1,h2,h3,h4,li,p,tr')) {
    if (element.localName == 'li' && element.querySelector('li') != null) {
      continue;
    }
    if (element.localName == 'p' && element.parent?.localName == 'li') {
      continue;
    }
    if (element.localName == 'tr' &&
        element.querySelector('p,li,h1,h2,h3,h4,table') != null) {
      continue;
    }
    final rawText = element.localName == 'tr'
        ? element.children.map((e) => e.text.trim()).join(' ')
        : element.text;
    final text = rawText.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (text.isEmpty) continue;
    if (RegExp(
      r'^(pour|para|per|fur)\s+(\d+|six)\s+(personnes|personas|persone|personen)',
      caseSensitive: false,
    ).hasMatch(searchKey(text))) {
      continue;
    }
    original.add(text);
    final paragraphHeading =
        ['p', 'tr'].contains(element.localName) &&
        (element.localName == 'tr' ||
            element.querySelector('b,strong') != null) &&
        RegExp(
          r'^(ingredientes|ingredients|ingredienti|zutaten|preparacion|preparation|preparazione|zubereitung|modo de preparo|elaboracion|procedimiento|instructions|directions|method)\s*:?(\s*\(.*\))?$',
          caseSensitive: false,
        ).hasMatch(searchKey(text));
    if (element.localName!.startsWith('h') || paragraphHeading) {
      final heading = searchKey(text);
      if (RegExp(r'ingredientes|ingredients|ingredienti|zutaten')
          .hasMatch(heading)) {
        section = 'ingredients';
      } else if (RegExp(
        r'preparacion|preparation|preparazione|preparo|confeccao|zubereitung|elaboracion|procedimiento|instructions|directions|method',
      ).hasMatch(heading)) {
        section = 'steps';
      } else if (['h1', 'h2'].contains(element.localName)) {
        section = '';
      }
    } else if (section == 'ingredients' &&
        ingredients.length < 200 &&
        !pictureCaption(element)) {
      ingredients.add(text.substring(0, text.length.clamp(0, 10000)));
    } else if (section == 'steps' && steps.length < 200) {
      steps.add(text.substring(0, text.length.clamp(0, 10000)));
    }
  }
  final title = page['title'] as String;
  final prefix = wikiEditions[provider]!.prefix;
  final language = provider.substring(5);
  final url = Uri.https('$language.wikibooks.org', '/w/index.php', {
    'title': title,
    'oldid': '${page['revid']}',
  }).toString();
  return {
    'title': (title.startsWith(prefix) ? title.substring(prefix.length) : title)
        .substring(
          0,
          (title.startsWith(prefix)
                  ? title.length - prefix.length
                  : title.length)
              .clamp(0, 250),
        )
        .trim(),
    'ingredients': ingredients,
    'steps': steps,
    'servings': servingsMatch?[1] == 'six'
        ? 6
        : int.tryParse(servingsMatch?[1] ?? '') ?? 1,
    'servings_declared': servingsMatch != null,
    'yield_unit': 'raciones',
    'language': language,
    'minutes': minutes,
    'tags': <String>[],
    'category_ids': <String>[],
    'catalog_ids': <String>[],
    'image': '',
    'photos': <Map<String, dynamic>>[],
    'source': url,
    'notes_language': 'es',
    'notes':
        '${servingsMatch == null ? 'Rendimiento no declarado: se conserva la receta como base 1, sin inventar raciones.' : 'Raciones declaradas por la fuente: ${servingsMatch[1]}.'} Revisa el tiempo y las unidades.',
    'origin': {
      'provider': provider,
      'id': title,
      'url': url,
      'language': language,
      'attribution': 'Autores de Wikilibros · historial de la página original',
      'license': 'CC BY-SA 4.0',
      'license_url': 'https://creativecommons.org/licenses/by-sa/4.0/deed.es',
      'modified': true,
    },
  };
}

List<String> wikiPhotoNames(Map<String, dynamic> page) {
  final names = <String>{};
  for (final name in page['images'] as List? ?? []) {
    final text = '$name'.replaceFirst(
      RegExp(r'^(Archivo|File|Imagen):', caseSensitive: false),
      '',
    );
    if (RegExp(
          r'\.(jpg|jpeg|png|webp|gif)$',
          caseSensitive: false,
        ).hasMatch(text) &&
        !RegExp(
          r'^(Noia[ _]|Stock[ _]|Wikipedia[ _-]logo|Wikibooks[ _-])|[ _]icon[ _.]',
          caseSensitive: false,
        ).hasMatch(text)) {
      names.add(text);
    }
  }
  return names.toList();
}

Map<String, dynamic>? wikiPhotoMetadata(Map<String, dynamic> info) {
  final url = '${info['thumburl'] ?? info['url'] ?? ''}';
  if (!wikimediaPhotoUrl(url)) {
    return null;
  }
  final meta = info['extmetadata'] as Map? ?? {};
  String field(String key) {
    final value =
        (html.parseFragment('${meta[key]?['value'] ?? ''}').text ?? '').trim();
    return value.substring(0, value.length.clamp(0, 10000));
  }

  final license = field('LicenseShortName').toLowerCase();
  final licenseHost = Uri.tryParse(field('LicenseUrl'))?.host;
  if (!{
        'public domain',
        'cc0',
        'cc0 1.0',
        'pd',
        'dominio público',
      }.contains(license) &&
      !((license.startsWith('cc by ') || license.startsWith('cc by-sa ')) &&
          {
            'creativecommons.org',
            'www.creativecommons.org',
          }.contains(licenseHost))) {
    return null;
  }
  return {
    'url': url,
    'source': '${info['descriptionurl'] ?? ''}',
    'caption': field('ImageDescription'),
    'artist': field('Artist').isNotEmpty ? field('Artist') : field('Credit'),
    'license': field('LicenseShortName'),
    'license_url': field('LicenseUrl'),
    'image': '',
  };
}
