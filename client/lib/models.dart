import 'dart:convert';

import 'photo_data.dart';

void validateEntryData(String kind, Map<String, dynamic> data) {
  if (utf8.encode(jsonEncode(data)).length >
      (kind == 'recipe' ? 8000000 : 900000)) {
    throw Exception('El elemento es demasiado grande.');
  }
  if (kind == 'recipe') {
    if (data['title'] is! String ||
        (data['title'] as String).trim().isEmpty ||
        (data['title'] as String).length > 250) {
      throw Exception('La receta necesita un título de hasta 250 caracteres.');
    }
    for (final key in [
      'ingredients',
      'steps',
      'tags',
      'category_ids',
      'catalog_ids',
    ]) {
      final v = data[key] ?? [];
      if (v is! List ||
          v.length > 500 ||
          v.any((x) => x is! String || x.length > 10000)) {
        throw Exception('Revisa el campo $key.');
      }
    }
    final original = data['original'];
    if (original != null) {
      if (original is! Map ||
          original['language'] is! String ||
          original['title'] is! String ||
          original['title'].length > 250 ||
          original['notes'] is! String ||
          original['notes'].length > 120000 ||
          ['ingredients', 'steps'].any(
            (key) =>
                original[key] is! List ||
                original[key].length > 500 ||
                original[key].any((v) => v is! String || v.length > 10000),
          )) {
        throw Exception('El texto original de la traducción no es válido.');
      }
    }
    final translation = data['translation'];
    if (translation != null &&
        (translation is! Map ||
            ['source_language', 'target_language', 'engine'].any(
              (key) =>
                  translation[key] is! String || translation[key].length > 100,
            ))) {
      throw Exception('Los datos de traducción no son válidos.');
    }
    final n = data['servings'] ?? 4;
    if (n is! num || !n.isFinite || n <= 0 || n > 10000) {
      throw Exception('Revisa las raciones.');
    }
    final t = data['minutes'] ?? 0;
    if (t is! int || t < 0 || t > 100000) {
      throw Exception('Revisa el tiempo de preparación.');
    }
    final rating = data['rating'] ?? 0;
    if (rating is! int || rating < 0 || rating > 5) {
      throw Exception('La valoración debe estar entre 0 y 5.');
    }
    for (final key in ['notes', 'source', 'image']) {
      if (data.containsKey(key) && data[key] is! String) {
        throw Exception('Revisa el campo $key.');
      }
    }
    if ((data['notes'] as String? ?? '').length > 120000 ||
        (data['source'] as String? ?? '').length > 4000) {
      throw Exception(
        'Las notas o el enlace de la receta son demasiado largos.',
      );
    }
    if ((data['image'] ?? '') != '') {
      throw Exception('Las fotos se añaden por enlace; no se guardan copias.');
    }
    if (data['image_url'] != null &&
        (data['image_url'] is! String || !onlinePhotoUrl(data['image_url']))) {
      throw Exception('Revisa el enlace de la portada.');
    }
    final photos = data['photos'] ?? [];
    if (photos is! List || photos.length > 500) {
      throw Exception('La galería no es válida.');
    }
    for (final photo in photos) {
      if (photo is! Map ||
          photo.entries.any(
            (e) =>
                e.value is! String ||
                e.value.length > (e.key == 'image' ? 800000 : 10000),
          )) {
        throw Exception('Revisa los datos de la foto.');
      }
      if ((photo['image'] ?? '') != '' ||
          (photo['url'] != null && !onlinePhotoUrl(photo['url']))) {
        throw Exception('La foto necesita un enlace HTTPS público.');
      }
    }
    final origin = data['origin'];
    if (origin != null &&
        (origin is! Map ||
            [
              'provider',
              'id',
              'attribution',
              'license',
              'license_url',
              'url',
              'language',
            ].any((k) => origin[k] is! String) ||
            origin.values.any((v) => v is String && v.length > 4000))) {
      throw Exception('Revisa la atribución de la receta.');
    }
  } else if (kind == 'collection') {
    if (!['category', 'catalog'].contains(data['type']) ||
        data['title'] is! String ||
        data['title'].trim().isEmpty ||
        data['title'].length > 80) {
      throw Exception(
        'La categoría o catálogo necesita un nombre de hasta 80 caracteres.',
      );
    }
  } else if (kind == 'shopping') {
    for (final field in ['recipe_title', 'source']) {
      if (data[field] != null &&
          (data[field] is! String ||
              data[field].length > (field == 'recipe_title' ? 250 : 4000))) {
        throw Exception('Revisa la referencia del producto.');
      }
    }
    if (data['name'] is! String ||
        data['name'].trim().isEmpty ||
        data['name'].length > 1000 ||
        (data['checked'] != null && data['checked'] is! bool)) {
      throw Exception('Revisa el producto de la compra.');
    }
  } else if (kind == 'meal') {
    final date = data['date'];
    final parsed = date is String ? DateTime.tryParse(date) : null;
    if (date is! String ||
        !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(date) ||
        parsed == null ||
        parsed.year < 1 ||
        '${parsed.year.toString().padLeft(4, '0')}-${parsed.month.toString().padLeft(2, '0')}-${parsed.day.toString().padLeft(2, '0')}' !=
            date ||
        !['Comida', 'Cena'].contains(data['slot']) ||
        data['title'] is! String ||
        data['title'].trim().isEmpty ||
        data['title'].length > 250 ||
        (data['recipe_id'] != null &&
            (data['recipe_id'] is! String || data['recipe_id'].length > 80))) {
      throw Exception('Revisa el plato del menú.');
    }
    final n = data['servings'] ?? 4;
    if (n is! num || !n.isFinite || n <= 0 || n > 10000) {
      throw Exception('Revisa las raciones del menú.');
    }
  } else {
    throw Exception('Tipo de elemento no reconocido.');
  }
}

class Entry {
  final String id, kind;
  final int revision;
  final Map<String, dynamic> data;
  final bool deleted;
  Entry(this.id, this.kind, this.revision, this.data, {this.deleted = false});
  factory Entry.fromJson(Map<String, dynamic> json) => Entry(
    json['id'],
    json['kind'],
    json['revision'] ?? 0,
    Map<String, dynamic>.from(json['data']),
    deleted: json['deleted'] == true,
  );
  Map<String, dynamic> toJson() => {
    'id': id,
    'kind': kind,
    'revision': revision,
    'data': data,
    'deleted': deleted,
  };
  String get title => data['title'] ?? data['name'] ?? 'Sin título';
  List<String> lines(String key) => List<String>.from(data[key] ?? []);
  Map<String, dynamic> copyData() => jsonDecode(jsonEncode(data));
}

String searchKey(String value) {
  const from = 'áàäâéèëêíìïîóòöôúùüûãõç';
  const to = 'aaaaeeeeiiiioooouuuuaoc';
  var result = value.toLowerCase();
  for (var i = 0; i < from.length; i++) {
    result = result.replaceAll(from[i], to[i]);
  }
  return result;
}

/// Scale only a leading, unambiguous amount. Preserve the original line otherwise.
String scaleIngredient(String line, double factor) {
  if (factor == 1 || !factor.isFinite || factor <= 0) return line;
  final match = RegExp(
    r'^(\d+\s+\d+/\d+|\d+/\d+|\d+[.,]\d+|\d+|[½¼¾⅓⅔⅛⅜⅝⅞])(?=\s)(.*)$',
  ).firstMatch(line.trim());
  if (match == null) return line;
  final amount = match[1]!;
  final rest = match[2]!;
  // A range like "2 a 3 huevos" is not interpreted as a single amount.
  if (RegExp(r'^\s*(?:a\s+\d|[-–]\s*\d)').hasMatch(rest)) return line;
  const fractions = {
    '½': .5,
    '¼': .25,
    '¾': .75,
    '⅓': 1 / 3,
    '⅔': 2 / 3,
    '⅛': .125,
    '⅜': .375,
    '⅝': .625,
    '⅞': .875,
  };
  double? quantity = fractions[amount];
  if (quantity == null && amount.contains('/')) {
    final parts = amount.split(' ');
    final fraction = parts.last.split('/');
    final denominator = double.tryParse(fraction[1]);
    if (denominator == null || denominator == 0) return line;
    quantity = double.parse(fraction[0]) / denominator;
    if (parts.length == 2) quantity += double.parse(parts.first);
  }
  quantity ??= double.tryParse(amount.replaceAll(',', '.'));
  if (quantity == null) return line;
  final scaled = quantity * factor;
  final formatted = scaled
      .toStringAsFixed(2)
      .replaceAll(RegExp(r'\.?0+$'), '')
      .replaceAll('.', ',');
  return '$formatted$rest';
}

String dayKey(DateTime date) =>
    '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

List<int> stepMinutes(String text) {
  final values = <int>{};
  for (final match in RegExp(
    r'\b(\d{1,3})\s*(minutos?|minutes?|mins?|horas?|hours?)\b',
    caseSensitive: false,
  ).allMatches(text)) {
    if (RegExp(r'\d+\s*(?:a|to|[-–])\s*$')
        .hasMatch(text.substring(0, match.start))) {
      continue;
    }
    final hours = match[2]!.toLowerCase().startsWith('h');
    final value = int.parse(match[1]!) * (hours ? 60 : 1);
    if (value > 0 && value <= 1440) values.add(value);
  }
  return values.toList();
}

String recipeYieldUnit(Map<String, dynamic> data) =>
    '${data['yield_unit'] ?? 'raciones'}';

String recipeYieldText(Map<String, dynamic> data) =>
    data['servings_declared'] == false
    ? 'Rendimiento por confirmar'
    : '${data['servings'] ?? 4} ${recipeYieldUnit(data)}';

List<String> missingQuantities(Map<String, dynamic> data) =>
    List<String>.from(data['ingredients'] ?? [])
        .where(
          (line) => !RegExp(
            r'[0-9½¼¾⅓⅔⅛⅜⅝⅞]|\b(un|una|uno|dos|tres|cuatro|cinco|seis|siete|ocho|nueve|diez|media|medio)\b|\b(?:a|al) gusto\b|cantidad necesaria|c/s',
            caseSensitive: false,
          ).hasMatch(line),
        )
        .toList();
