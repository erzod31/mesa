import 'package:html/parser.dart' as html;

const encantarSite = 'recetasparaencantar.wordpress.com';
const encantarHosts = {'recetasparaencantar.com', encantarSite};
const encantarLicense = 'https://creativecommons.org/licenses/by-nc/3.0/';

bool encantarPhotoUrl(String raw) {
  final u = Uri.tryParse(raw);
  return u != null &&
      u.scheme == 'https' &&
      u.userInfo.isEmpty &&
      (!u.hasPort || u.port == 443) &&
      {
        encantarSite,
        'recetasparaencantar.files.wordpress.com',
        'recetasparaencantar.com',
      }.contains(u.host) &&
      RegExp(
        r'/(?:wp-content/uploads/)?\d{4}/\d{2}/.+\.(?:jpe?g|png|webp)$',
        caseSensitive: false,
      ).hasMatch(u.path);
}

Map<String, dynamic>? parseEncantar(Map<String, dynamic> post) {
  final raw = Uri.tryParse('${post['URL'] ?? ''}');
  if (raw == null ||
      !{'http', 'https'}.contains(raw.scheme) ||
      !encantarHosts.contains(raw.host) ||
      raw.userInfo.isNotEmpty ||
      raw.hasPort ||
      !RegExp(r'^/\d{4}/\d{2}/\d{2}/[^/]+/$').hasMatch(raw.path)) {
    return null;
  }
  final url = raw.replace(scheme: 'https', host: 'recetasparaencantar.com');
  final doc = html.parse('${post['content'] ?? ''}');
  for (final e in doc.querySelectorAll(
    'script,style,.sharedaddy,.wp-caption-text',
  )) {
    e.remove();
  }
  var section = '';
  int? portions;
  final ingredients = <String>[], steps = <String>[];
  for (final e in doc.querySelectorAll('h1,h2,h3,h4,p,li')) {
    var parent = e.parent;
    var nested = false;
    while (parent != null) {
      if (parent.localName == 'li') {
        nested = true;
        break;
      }
      parent = parent.parent;
    }
    if (nested || e.querySelector('li') != null) {
      continue;
    }
    final text = e.text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (text.isEmpty) continue;
    if (RegExp(r'^ingredientes\b', caseSensitive: false).hasMatch(text)) {
      section = 'ingredients';
      final m = RegExp(
        r'para\s+(\d+)\s+(?:personas|raciones|porciones)',
        caseSensitive: false,
      ).firstMatch(text);
      portions = int.tryParse(m?.group(1) ?? '');
    } else if (RegExp(
      r'^(preparaci[oó]n|elaboraci[oó]n)\b',
      caseSensitive: false,
    ).hasMatch(text)) {
      section = 'steps';
    } else if (e.localName!.startsWith('h')) {
      section = '';
    } else if (section == 'ingredients' && e.localName == 'li') {
      ingredients.add(text);
    } else if (section == 'steps') {
      steps.add(text);
    }
  }
  final photos = <String, Map<String, dynamic>>{};
  for (final image in doc.querySelectorAll('img')) {
    final raw =
        image.attributes['data-orig-file'] ?? image.attributes['src'] ?? '';
    if (!encantarPhotoUrl(raw)) continue;
    final photo = Uri.parse(raw).replace(query: '').toString();
    photos[photo] = {
      'url': photo,
      'source': '$url',
      'caption': image.attributes['alt'] ?? '',
      'artist': 'Dana Madiana · Recetas para encantar',
      'license': 'CC BY-NC 3.0',
      'license_url': encantarLicense,
    };
  }
  if (ingredients.isEmpty ||
      steps.isEmpty ||
      photos.isEmpty ||
      !ingredients.any((s) => RegExp(r'[0-9½¼¾⅓⅔]').hasMatch(s))) {
    return null;
  }
  return {
    'title': html.parseFragment('${post['title'] ?? ''}').text?.trim() ?? '',
    'ingredients': ingredients,
    'steps': steps,
    'servings': portions ?? 1,
    'servings_declared': portions != null,
    'minutes': 0,
    'language': 'es',
    'yield_unit': 'raciones',
    'tags': <String>[],
    'image': '',
    'photos': photos.values.toList(),
    'source': '$url',
    'notes':
        'Uso no comercial. Conserva autoría, licencia y enlace original. '
        'Cantidades y pasos originales; rendimiento y duración no declarados cuando no constan en la ficha.',
    'origin': {
      'provider': 'es-encantar',
      'id': '$url',
      'url': '$url',
      'language': 'es',
      'attribution': 'Dana Madiana · Recetas para encantar',
      'license': 'CC BY-NC 3.0',
      'license_url': encantarLicense,
      'modified': true,
    },
  };
}
