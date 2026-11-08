import 'dart:convert';

import 'package:html/dom.dart';
import 'package:html/parser.dart' as html;

import 'community_catalogs.dart';
import 'source_registry.dart';

String recipeText(dynamic value) => plainHtml('$value').trim();

List<String> recipeInstructions(dynamic value) {
  if (value is String) {
    return value
        .split('\n')
        .map(recipeText)
        .where((s) => s.isNotEmpty)
        .toList();
  }
  if (value is List) return value.expand(recipeInstructions).toList();
  if (value is Map) {
    return recipeInstructions(value['itemListElement'] ?? value['text'] ?? '');
  }
  return [];
}

int recipeMinutes(dynamic value) {
  final m = RegExp(r'^P(?:(\d+)D)?(?:T(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?)?$')
      .firstMatch('$value');
  if (m == null) return 0;
  int number(int group) => int.tryParse(m.group(group) ?? '') ?? 0;
  return (number(1) * 1440 +
          number(2) * 60 +
          number(3) +
          (number(4) / 60).ceil())
      .clamp(0, 100000);
}

bool excludedRecipeElement(Element node) {
  Element? current = node;
  while (current != null) {
    if (['body', 'html'].contains(current.localName)) return false;
    if (['nav', 'footer', 'aside'].contains(current.localName) ||
        RegExp(
          r'(related|relacionad|recommend|recomendad|comment|comentari|sidebar|author-bio|social|advert|promo)',
          caseSensitive: false,
        ).hasMatch('${current.className} ${current.id}')) {
      return true;
    }
    current = current.parent;
  }
  return false;
}

Map<String, dynamic> publicRecipeOrigin(
  Map<String, dynamic> recipe,
  CatalogSource source,
) {
  if ((recipe['ingredients'] as List).isEmpty ||
      (recipe['steps'] as List).isEmpty) {
    throw Exception(
      'La fuente no devuelve ingredientes y preparación completos. Puedes reintentar o consultar el original.',
    );
  }
  if ((recipe['photos'] as List).isEmpty) {
    throw Exception('Esta receta no tiene una foto verificable.');
  }
  if (!(recipe['ingredients'] as List).any(
    (v) => RegExp(
      r'[0-9½¼¾⅓⅔⅛⅜⅝⅞]|al gusto|a gusto|cantidad necesaria',
      caseSensitive: false,
    ).hasMatch('$v'),
  )) {
    throw Exception(
      'La fuente no indica cantidades. Consulta el original antes de guardar.',
    );
  }
  recipe['origin'] = {
    'provider': source.id,
    'id': recipe['source'],
    'url': recipe['source'],
    'attribution': source.name,
    'license': source.licenseName.isNotEmpty
        ? source.licenseName
        : 'Derechos del editor · consulta e importación individual',
    'license_url': source.licenseUrl.isNotEmpty
        ? source.licenseUrl
        : source.url,
    'language': recipe['language'] ?? source.languageCode,
  };
  recipe['tags'] = [source.country];
  return recipe;
}

/// Read only the requested recipe, retaining its original quantities and photo URLs.
Map<String, dynamic> parsePublicRecipe(
  String text,
  Uri url,
  CatalogSource source,
) {
  if (source.id == 'es-creativegan') return parseCreativegan(text, url, source);
  final doc = html.parse(text);
  final entities = <Map>[];
  void visit(dynamic node) {
    if (node is List) {
      for (final child in node) {
        visit(child);
      }
    } else if (node is Map) {
      final types = node['@type'];
      if (types == 'Recipe' || types is List && types.contains('Recipe')) {
        entities.add(node);
      }
      for (final child in node.values) {
        if (child is Map || child is List) visit(child);
      }
    }
  }

  for (final script in doc.querySelectorAll(
    'script[type="application/ld+json"]',
  )) {
    try {
      visit(jsonDecode(script.text));
    } on FormatException {
      /* Use visible sections. */
    }
  }
  int score(Map v) =>
      (v['recipeIngredient'] is List
          ? (v['recipeIngredient'] as List).length
          : 0) +
      recipeInstructions(v['recipeInstructions']).length;
  entities.sort((a, b) => score(b).compareTo(score(a)));
  final schema = entities.firstOrNull ?? <String, dynamic>{};
  final raw = schema['recipeIngredient'];
  var ingredients =
      (raw is List
              ? raw
              : raw is String
              ? raw.split('\n')
              : <dynamic>[])
          .map(recipeText)
          .where((s) => s.isNotEmpty)
          .toList();
  var steps = recipeInstructions(schema['recipeInstructions']);
  final publisherScope = switch (url.host) {
    'bonviveur.com' ||
    'www.bonviveur.com' => doc.querySelector('article .main .text'),
    'www.recetasgratis.net' ||
    'recetas.elperiodico.com' => doc.querySelector('article.columna-post'),
    'www.hogarmania.com' => doc.querySelector('main.recipe'),
    'based.cooking' => doc.querySelector('main'),
    _ => null,
  };
  final article =
      publisherScope ??
      doc.querySelector('.entry-content,.article-content') ??
      doc
          .querySelectorAll('.elementor-widget-container')
          .where(
            (e) => e
                .querySelectorAll('h2')
                .any((h) => recipeText(h.text) == 'Ingredientes'),
          )
          .firstOrNull;
  final scope = article ?? doc.body ?? doc.documentElement!;
  List<String> rows(String selector) => scope
      .querySelectorAll(selector)
      .where((e) => !excludedRecipeElement(e))
      .map((e) => recipeText(e.text))
      .where((s) => s.isNotEmpty)
      .toSet()
      .toList();
  var visibleIngredients = rows(
    '.wprm-recipe-ingredient,.tasty-recipes-ingredients li,.field_ingredients .ingredient',
  );
  var visibleSteps = rows(
    '.wprm-recipe-instruction-text,.tasty-recipes-instructions li,.field_instructions li',
  );
  final widget = visibleIngredients.isNotEmpty;
  if (visibleIngredients.isEmpty || visibleSteps.isEmpty) {
    final fallbackIngredients = <String>[], fallbackSteps = <String>[];
    var mode = '';
    for (final element in scope.querySelectorAll('h2,h3,h4,p,strong,b,li')) {
      if (excludedRecipeElement(element)) continue;
      final content = recipeText(element.text);
      if (content.isEmpty) continue;
      final heading =
          ['h2', 'h3', 'h4'].contains(element.localName) ||
          RegExp(
            r'^(Ingredientes|Ingredients|Preparaci[oó]n|Procedimiento|Directions)$',
            caseSensitive: false,
          ).hasMatch(content);
      if (heading) {
        if (RegExp(
              r'\b(ingredientes|ingredients)\b',
              caseSensitive: false,
            ).hasMatch(content) &&
            !RegExp(
              r'(otras recetas|m[aá]s recetas|estos ingredientes)',
              caseSensitive: false,
            ).hasMatch(content)) {
          mode = 'ingredients';
        } else if (RegExp(
              r'\b(preparaci[oó]n|instrucciones|elaboraci[oó]n|procedimiento|paso a paso|c[oó]mo (hacer|preparar)|directions|instructions|method|pasos a seguir)\b',
              caseSensitive: false,
            ).hasMatch(content) ||
            mode == 'ingredients' &&
                element.localName == 'h2' &&
                content.toLowerCase().startsWith('receta de')) {
          mode = 'steps';
        } else if (element.localName == 'h2' ||
            RegExp(
              r'(consejos|preguntas|comentarios|video|otras recetas|resumen|summary|contribution)',
              caseSensitive: false,
            ).hasMatch(content)) {
          mode = '';
        }
      } else if (element.localName == 'li' &&
          element.querySelector('li') == null) {
        if (mode == 'ingredients') fallbackIngredients.add(content);
        if (mode == 'steps') fallbackSteps.add(content);
      } else if (element.localName == 'p') {
        if (mode == 'steps' &&
            content.length > 20 &&
            element.querySelector('li') == null) {
          fallbackSteps.add(content);
        }
        if (mode == 'ingredients') {
          final copy = element.clone(true);
          for (final br in copy.querySelectorAll('br')) {
            br.replaceWith(Text('\n'));
          }
          fallbackIngredients.addAll(
            copy.text
                .split('\n')
                .map(recipeText)
                .where(
                  (s) => s.isNotEmpty && !s.toLowerCase().startsWith('para '),
                ),
          );
        }
      }
    }
    if (visibleIngredients.isEmpty) {
      visibleIngredients = fallbackIngredients.toSet().toList();
    }
    if (visibleSteps.isEmpty) visibleSteps = fallbackSteps.toSet().toList();
  }
  if (visibleIngredients.isNotEmpty &&
      (ingredients.isEmpty ||
          widget ||
          url.host.endsWith('paulinacocina.net'))) {
    ingredients = visibleIngredients;
  }
  if (visibleSteps.isNotEmpty &&
      (steps.isEmpty || widget || url.host.endsWith('bonviveur.com'))) {
    steps = visibleSteps;
  }
  var group = '';
  ingredients = ingredients
      .where(
        (v) => !RegExp(r'^Porciones\s*:', caseSensitive: false).hasMatch(v),
      )
      .map((v) => v.replaceFirst(RegExp(r'^[\uf0b7•\s]+'), ''))
      .where((v) {
        if ([
          'relleno',
          'masa',
          'armado',
        ].contains(v.toLowerCase().replaceAll(':', ''))) {
          group = v.toLowerCase().replaceAll(':', '');
          return false;
        }
        return true;
      })
      .map((v) => '$v${group.isEmpty ? '' : ' ($group)'}')
      .toList();
  final title =
      recipeText(
        schema['name'] ?? doc.querySelector('h1')?.text ?? 'Receta',
      ).substring(
        0,
        recipeText(schema['name'] ?? doc.querySelector('h1')?.text ?? 'Receta')
            .length
            .clamp(0, 250),
      );
  dynamic yield = schema['recipeYield'] ?? '';
  if (yield is List) {
    yield =
        yield
            .where(
              (s) => RegExp(r'[a-záéíóú]', caseSensitive: false).hasMatch('$s'),
            )
            .firstOrNull ??
        yield.firstOrNull ??
        '';
  }
  var yieldText = '$yield';
  final declared =
      doc
          .querySelector('.wprm-recipe-servings-container,.tasty-recipes-yield')
          ?.text ??
      '';
  if (declared.isNotEmpty &&
      (yieldText.isEmpty ||
          RegExp(
            r'(unidades|empanadas|arepas|personas|porciones|raciones|tazas)',
            caseSensitive: false,
          ).hasMatch(declared))) {
    yieldText = recipeText(declared);
  }
  if (yieldText.isEmpty) {
    final declared = RegExp(
      r'(?:Da para|Para)\s+(\d+)\s+(raciones|porciones|personas)',
      caseSensitive: false,
    ).firstMatch(scope.text);
    if (declared != null) yieldText = '${declared[1]} ${declared[2]}';
  }
  if (url.host == 'www.paulinacocina.net' || url.host == 'paulinacocina.net') {
    final heading = doc
        .querySelectorAll('h2,h3,h4')
        .map((e) => e.text)
        .where(
          (s) => RegExp(
            r'(\d+\s+empanadas|docena)',
            caseSensitive: false,
          ).hasMatch(s),
        )
        .firstOrNull;
    if (heading != null) {
      yieldText = heading.toLowerCase().contains('docena')
          ? '12 empanadas'
          : heading;
    }
  }
  final portions = RegExp(r'\d+(?:[.,]\d+)?').firstMatch(yieldText);
  final unit =
      RegExp(
        r'(arepas|empanadas|enchiladas|galletas|piezas|unidades|tazas|vasos|panes|porciones|raciones|personas)',
        caseSensitive: false,
      ).firstMatch(yieldText)?[0]?.toLowerCase() ??
      'raciones';
  final photos = <String, Map<String, dynamic>>{};
  void picture(dynamic value) {
    if (value is List) {
      for (final p in value) {
        picture(p);
      }
    }
    if (value is Map) {
      final raw = value['contentUrl'] ?? value['url'];
      picture(raw);
      final photo = raw is String ? photos[url.resolve(raw).toString()] : null;
      if (photo != null) {
        final author = value['creator'] ?? value['author'] ?? '';
        photo['caption'] = recipeText(value['caption'] ?? value['name'] ?? '');
        photo['artist'] = recipeText(
          value['creditText'] ??
              (author is Map ? author['name'] ?? '' : author),
        );
        final license = value['license'];
        photo['license_url'] =
            '${license is Map ? license['url'] ?? '' : license ?? ''}';
      }
    }
    if (value is String) {
      final target = url.resolve(value.trim()).toString();
      if (publisherPhotoUrl(target)) {
        photos.putIfAbsent(
          target,
          () => {
            'url': target,
            'source': url.toString(),
            'caption': '',
            'artist': '',
            'license': '',
            'license_url': '',
            'image': '',
          },
        );
      }
    }
  }

  picture(schema['image']);
  void stepPictures(dynamic node) {
    if (node is List) {
      for (final child in node) {
        stepPictures(child);
      }
    }
    if (node is Map) {
      picture(node['image']);
      stepPictures(node['itemListElement']);
    }
  }

  stepPictures(schema['recipeInstructions']);
  if (article != null) {
    for (final image in article.querySelectorAll('img')) {
      if (excludedRecipeElement(image)) continue;
      Element? link = image.parent;
      while (link != null &&
          link != article &&
          !(link.localName == 'a' && link.attributes.containsKey('href'))) {
        link = link.parent;
      }
      if (link == article) link = null;
      if (link != null) {
        final target = url
            .resolve(link.attributes['href']!)
            .removeFragment()
            .toString()
            .replaceFirst(RegExp(r'/$'), '');
        if (target !=
                url.removeFragment().toString().replaceFirst(
                  RegExp(r'/$'),
                  '',
                ) &&
            !publisherPhotoUrl(target)) {
          continue;
        }
      }
      final raw =
          image.attributes['data-orig-file'] ??
          image.attributes['data-lazy-src'] ??
          image.attributes['data-src'] ??
          image.attributes['src'] ??
          '';
      if (raw.startsWith('data:')) continue;
      if (!RegExp(
        r'(logo|avatar|icon|banner|pixel)',
        caseSensitive: false,
      ).hasMatch(raw)) {
        picture(raw);
      }
    }
  }
  if (photos.isEmpty) {
    picture(
      doc.querySelector('meta[property="og:image"]')?.attributes['content'],
    );
  }
  if (photos.isEmpty && title.isNotEmpty) {
    for (final image in doc.querySelectorAll('img')) {
      if (!excludedRecipeElement(image) &&
          (image.attributes['alt'] ?? '').toLowerCase().contains(
            title.toLowerCase(),
          )) {
        picture(image.attributes['data-src'] ?? image.attributes['src']);
      }
    }
  }
  final unique = <String, Map<String, dynamic>>{};
  for (final photo in photos.values) {
    final key = '${photo['url']}'
        .replaceAll(
          RegExp(r'-\d+x\d+(?=\.(?:jpe?g|png|webp))', caseSensitive: false),
          '',
        )
        .split('.pagespeed.')
        .first;
    unique.putIfAbsent(key, () => photo);
  }
  final visibleMinutes = url.host.endsWith('hogarmania.com')
      ? doc
            .querySelectorAll('.recipe-data-row')
            .map(
              (n) => RegExp(
                r'^Tiempo total\s+(\d+)\s*m$',
                caseSensitive: false,
              ).firstMatch(n.text.trim()),
            )
            .whereType<RegExpMatch>()
            .map((m) => int.parse(m[1]!))
            .firstOrNull
      : null;
  return publicRecipeOrigin({
    'title': title,
    'ingredients': ingredients.take(500).toList(),
    'steps': steps.take(500).toList(),
    'servings': portions == null
        ? 1
        : (double.tryParse(portions[0]!.replaceAll(',', '.')) ?? 1).clamp(
            1,
            10000,
          ),
    'servings_declared': portions != null,
    'yield_unit': unit,
    'yield_original': yieldText,
    'minutes': (visibleMinutes ?? recipeMinutes(schema['totalTime'])),
    'notes': recipeText(schema['description'] ?? ''),
    'source': url.toString(),
    'language':
        '${schema['inLanguage'] ?? doc.documentElement?.attributes['lang'] ?? source.languageCode}'
            .toLowerCase()
            .split(RegExp('[-_]'))
            .first,
    'tags': <String>[],
    'image': '',
    'photos': unique.values.take(500).toList(),
  }, source);
}

Map<String, dynamic> parseCreativegan(
  String text,
  Uri url,
  CatalogSource source, {
  String title = '',
}) {
  final doc = html.parse(text);
  if (url.path == '/archives/parmigiana-vegana-de-zaraida/') {
    throw Exception(
      'Receta de una obra de terceros; autorización específica pendiente.',
    );
  }
  final scope = doc.querySelector('.entry-content') ?? doc.body!;
  title = title.isNotEmpty
      ? title
      : (doc.querySelector('h1')?.text.trim() ?? '');
  final ingredients = <String>[],
      steps = <String>[],
      photos = <Map<String, dynamic>>[];
  final cards = scope.querySelectorAll('.wprm-fallback-recipe');
  final card =
      cards
          .where(
            (c) =>
                (c
                        .querySelector('.wprm-fallback-recipe-name')
                        ?.text
                        .trim()
                        .toLowerCase() ??
                    '') ==
                title.toLowerCase(),
          )
          .firstOrNull ??
      (cards.length == 1 ? cards.first : null);
  if (card != null) {
    ingredients.addAll(
      card
          .querySelectorAll(
            '.wprm-fallback-recipe-ingredients li,.wprm-fallback-recipe-ingredients h4',
          )
          .map((n) => n.text.trim()),
    );
    steps.addAll(
      card
          .querySelectorAll('.wprm-fallback-recipe-instructions li')
          .map((n) => n.text.trim()),
    );
  }
  final structured = ingredients.isNotEmpty && steps.isNotEmpty;
  var mode = '', header = '';
  for (final node in scope.querySelectorAll('p,li,h2,h3,h4,img')) {
    if (node.localName == 'img') {
      final raw = node.attributes['data-src'] ?? node.attributes['src'] ?? '';
      final photo = url.resolve(raw).toString();
      if (publisherPhotoUrl(photo) &&
          !RegExp(
            r'logo|avatar|pixel|pinterest|curso_|bizcochos_veganos|poster_|i_can\.jpg|cooking_school_text_book',
            caseSensitive: false,
          ).hasMatch(photo) &&
          !(url.path == '/archives/mujaddara/' &&
              photo.contains('hamburguesa_')) &&
          !excludedRecipeElement(node) &&
          !photos.any((p) => p['url'] == photo)) {
        photos.add({
          'url': photo,
          'source': url.toString(),
          'caption': node.attributes['alt'] ?? title,
          'artist': 'Virginia García · CreatiVegan',
          'license': source.licenseName,
          'license_url': source.licenseUrl,
        });
      }
      continue;
    }
    if (structured || ['p', 'li'].contains(node.parent?.localName)) continue;
    final value = node.text.trim();
    if (mode == 'steps' &&
        RegExp(
          r'esta foto es|fusilad|licencias? creative commons|comp[aá]rtelo|publicaciones similares|comentarios|https?://',
          caseSensitive: false,
        ).hasMatch(value)) {
      break;
    }
    if (RegExp(r'^ingredientes\b', caseSensitive: false).hasMatch(value) ||
        value.toLowerCase().contains('ingredientes') &&
            RegExp(
              r'^(?:dificultad|tiempo|raciones)\s*:',
              caseSensitive: false,
            ).hasMatch(value) &&
            value.length < 300) {
      header = value;
      mode = 'ingredients';
      continue;
    }
    if (RegExp(
      r'^(preparaci[oó]n|instrucciones|elaboraci[oó]n|procedimiento)',
      caseSensitive: false,
    ).hasMatch(value)) {
      mode = 'steps';
      continue;
    }
    final fragment = html.parseFragment(
      node.innerHtml.replaceAll(
        RegExp(r'<br\s*/?>', caseSensitive: false),
        '\n',
      ),
    );
    final parts = (fragment.text ?? '')
        .split('\n')
        .map(
          (s) => s
              .replaceFirst(RegExp(r'^[♥♡•*\s]+'), '')
              .replaceAll(RegExp(r'\s+'), ' ')
              .trim(),
        )
        .where((s) => s.isNotEmpty)
        .toList();
    if (mode == 'ingredients') {
      if (node.localName == 'p' &&
          parts.isNotEmpty &&
          !node.text.contains('♥') &&
          !node.text.contains('♡') &&
          !RegExp(
            r'^(?:[\d¼½¾⅓⅔⅛]|una?\b)',
            caseSensitive: false,
          ).hasMatch(value)) {
        mode = 'steps';
      } else {
        ingredients.addAll(parts);
        continue;
      }
    }
    if (mode == 'steps' && value.isNotEmpty) {
      if (node.localName!.startsWith('h')) break;
      steps.addAll(parts);
    }
  }
  final preferred = doc
      .querySelector('meta[property="og:image"]')
      ?.attributes['content'];
  final cover = photos.where((p) => p['url'] == preferred).firstOrNull;
  if (cover != null) {
    photos.remove(cover);
    photos.insert(0, cover);
  }
  if (title.isEmpty) {
    throw Exception('La publicación no tiene título de receta.');
  }
  final portions = RegExp(
    r'(?:raciones|porciones)\s*:?\s*(\d+)',
    caseSensitive: false,
  ).firstMatch(header);
  final minutes = RegExp(
    r'(?:preparaci[oó]n|tiempo)\s*:?\s*(\d+)\s*min',
    caseSensitive: false,
  ).firstMatch(header);
  final result = publicRecipeOrigin({
    'title': title,
    'ingredients': ingredients,
    'steps': steps,
    'photos': photos,
    'servings': int.tryParse(portions?.group(1) ?? '') ?? 1,
    'servings_declared': portions != null,
    'yield_unit': 'porciones',
    'yield_original': portions?.group(1) ?? '',
    'minutes': int.tryParse(minutes?.group(1) ?? '') ?? 0,
    'language': 'es',
    'source': url.toString(),
    'notes': 'Virginia García · CreatiVegan. CC BY-NC-SA 3.0 ES. Formato adaptado a Mesa.',
  }, source);
  (result['origin'] as Map)['attribution'] = 'Virginia García · CreatiVegan';
  return result;
}
