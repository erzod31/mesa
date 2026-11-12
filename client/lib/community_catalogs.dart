import 'package:html/parser.dart' as html;

import 'models.dart';
import 'photo_data.dart';
import 'source_registry.dart';
import 'encantar_catalog.dart' show encantarPhotoUrl;

const delokosLicenseUrl =
    'https://creativecommons.org/licenses/by-nc-sa/2.5/es/';

bool delokosPhotoUrl(String value) {
  final uri = Uri.tryParse(value);
  if (uri == null ||
      uri.scheme != 'https' ||
      uri.userInfo.isNotEmpty ||
      (uri.hasPort && uri.port != 443)) {
    return false;
  }
  if (uri.host == 'delokos.wordpress.com') {
    return RegExp(r'^/wp-content/uploads/\d{4}/\d{2}/').hasMatch(uri.path);
  }
  if (uri.host == 'delokos.files.wordpress.com') {
    return RegExp(r'^/\d{4}/\d{2}/').hasMatch(uri.path);
  }
  if (['i0.wp.com', 'i1.wp.com', 'i2.wp.com'].contains(uri.host)) {
    return RegExp(
      r'^/(delokos\.files\.wordpress\.com/\d{4}/\d{2}/|delokos\.wordpress\.com/wp-content/uploads/\d{4}/\d{2}/)',
    ).hasMatch(uri.path);
  }
  return false;
}

bool catalogPhotoUrl(String value) =>
    encantarPhotoUrl(value) ||
    wikimediaPhotoUrl(value) ||
    delokosPhotoUrl(value) ||
    publisherPhotoUrl(value);

bool publisherPhotoUrl(String value) {
  final uri = Uri.tryParse(value);
  if (uri == null ||
      uri.scheme != 'https' ||
      uri.userInfo.isNotEmpty ||
      (uri.hasPort && uri.port != 443)) {
    return false;
  }
  final hosts = {
    for (final source in catalogSources.where(
      (s) => s.external || s.consultationOnly,
    ))
      Uri.parse(source.url).host,
    for (final source in catalogSources.where(
      (s) => s.external || s.consultationOnly,
    ))
      ...source.aliases,
    'i0.wp.com',
    'i1.wp.com',
    'i2.wp.com',
  };
  return hosts.contains(uri.host) &&
      RegExp(
        r'\.(jpe?g|png|webp)([/?]|$)',
        caseSensitive: false,
      ).hasMatch(uri.path);
}

String plainHtml(String value) => html.parseFragment(value).text?.trim() ?? '';

Map<String, dynamic>? parseDelokos(Map<String, dynamic> post) {
  final source = Uri.tryParse('${post['URL'] ?? ''}');
  if (source == null ||
      source.scheme != 'https' ||
      source.host != 'delokos.wordpress.com' ||
      source.userInfo.isNotEmpty ||
      (source.hasPort && source.port != 443)) {
    return null;
  }
  final doc = html.parse('${post['content'] ?? ''}');
  for (final unwanted in doc.querySelectorAll(
    'script,style,.blogger-post-footer',
  )) {
    unwanted.remove();
  }
  final ingredients = <String>[], steps = <String>[], notes = <String>[];
  int? declaredServings;
  var section = '';
  for (final element in doc.querySelectorAll('p,h1,h2,h3,h4,h5,h6,li')) {
    if (element.localName == 'li' && element.querySelector('li') != null) {
      continue;
    }
    final text = element.text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (text.isEmpty) continue;
    if (RegExp(r'^ingredientes\b', caseSensitive: false).hasMatch(text)) {
      final portions = RegExp(
        r'\bpara\s+(\d+)\s+(personas|raciones|porciones)',
        caseSensitive: false,
      ).firstMatch(text);
      declaredServings = int.tryParse(portions?.group(1) ?? '');
      section = 'ingredients';
      continue;
    }
    if (RegExp(
      r'^preparaci[oó]n\b|^elaboraci[oó]n\b',
      caseSensitive: false,
    ).hasMatch(text)) {
      section = 'steps';
      continue;
    }
    if (RegExp(r'^o{2,}O{2,}o{2,}$').hasMatch(text)) {
      section = 'notes';
      continue;
    }
    if (section == 'ingredients' &&
        ingredients.isNotEmpty &&
        element.localName != 'li') {
      section = 'steps';
    }
    if (section == 'ingredients') {
      ingredients.addAll(text.split(RegExp(r'\s+[–—-]\s+')));
      // The blog normally uses a single italic paragraph for its ingredients.
      // A list may contain several li elements; instructions follow the list.
      if (element.localName != 'li') section = 'steps';
    } else if (section == 'steps') {
      steps.add(text);
    } else {
      notes.add(text);
    }
  }
  final photos = <Map<String, dynamic>>[];
  final seen = <String>{};
  for (final image in doc.querySelectorAll('img')) {
    final raw =
        image.attributes['data-orig-file'] ?? image.attributes['src'] ?? '';
    if (!delokosPhotoUrl(raw)) continue;
    final uri = Uri.parse(raw);
    final canonical = uri.replace(query: '').toString();
    if (!seen.add(canonical)) continue;
    photos.add({
      'url': canonical,
      'source': source.toString(),
      'caption':
          image.attributes['data-image-title'] ??
          image.attributes['alt'] ??
          plainHtml('${post['title']}'),
      'artist': 'Eugenio García González · La cocina delokos',
      'license': 'CC BY-NC-SA 2.5 ES',
      'license_url': delokosLicenseUrl,
    });
  }
  if (ingredients.isEmpty ||
      steps.isEmpty ||
      photos.isEmpty ||
      !ingredients.any((line) => RegExp(r'[0-9½¼¾⅓⅔⅛]').hasMatch(line))) {
    return null;
  }
  final categoryNames = (post['categories'] as Map? ?? {}).keys
      .map((e) => searchKey('$e'))
      .join(' ');
  final category = switch (categoryNames) {
    final names when names.contains('postre') => 'category:postres',
    final names when names.contains('pescad') => 'category:pescados',
    final names when names.contains('carne') => 'category:carnes',
    final names when names.contains('arroz') || names.contains('pasta') =>
      'category:arroz-pasta',
    final names when names.contains('legumbre') => 'category:legumbres',
    _ => 'category:verduras',
  };
  final yieldNote = declaredServings == null
      ? 'La fuente no declara un rendimiento ni una duración total estructurados. '
            'Se usa 1 como base editable para las cantidades originales: confirma el rendimiento antes de cambiar raciones. '
      : 'Rendimiento declarado: $declaredServings raciones. La duración total no está declarada. ';
  return {
    'title': plainHtml('${post['title'] ?? ''}'),
    'ingredients': ingredients,
    'steps': steps,
    'servings': declaredServings ?? 1,
    'servings_declared': declaredServings != null,
    'minutes': 0,
    'tags': <String>[],
    'category_ids': [category],
    'catalog_ids': <String>[],
    'image': '',
    'photos': photos,
    'source': source.toString(),
    'notes':
        '${yieldNote}Uso no comercial; conservar créditos y marcas de agua.\n\n${notes.join('\n\n')}',
    'origin': {
      'provider': 'delokos-es',
      'id': '${post['ID']}',
      'url': source.toString(),
      'attribution': 'Eugenio García González · La cocina delokos',
      'license': 'CC BY-NC-SA 2.5 ES',
      'license_url': delokosLicenseUrl,
      'language': 'es',
      'modified': true,
    },
  };
}
