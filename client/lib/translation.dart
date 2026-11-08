import 'dart:convert';

import 'package:flutter/services.dart';

typedef TranslateTexts = Future<List<String>> Function(
  List<String> texts,
  String source,
);
const translationRevision = 4;
const translationLanguages = {'en', 'fr', 'it', 'de', 'pt'};
final recipeNumbers = RegExp(r'\d+(?:[.,]\d+)?(?:\s*[/⁄]\s*\d+)?|[½¼¾⅓⅔⅛⅜⅝⅞]');
String recipeLanguage(Map<String, dynamic> recipe) =>
    '${recipe['language'] ?? recipe['origin']?['language'] ?? 'es'}'
        .toLowerCase()
        .split(RegExp('[-_]'))
        .first;
String translationSource(Map<String, dynamic> recipe, {bool force = false}) =>
    force && recipe['original'] is Map
    ? recipeLanguage(Map<String, dynamic>.from(recipe['original']))
    : recipeLanguage(recipe);
bool canTranslateRecipe(Map<String, dynamic> recipe) =>
    translationLanguages.contains(translationSource(recipe, force: true));

/// An HTTP 200 or a model response alone is not a completed recipe translation.
void validateSpanishTranslation(
  Map<String, dynamic> source,
  Map<String, dynamic> result,
) {
  final original = source['original'] is Map
      ? Map<String, dynamic>.from(source['original'])
      : source;
  if (recipeLanguage(result) != 'es' ||
      result['translation']?['target_language'] != 'es' ||
      result['original'] is! Map ||
      '${result['title'] ?? ''}'.trim().isEmpty) {
    throw Exception(
      'No se recibió la traducción al español. Puedes reintentar; se conserva el original.',
    );
  }
  for (final key in ['ingredients', 'steps']) {
    final before = original[key] as List? ?? [], after = result[key];
    if (after is! List ||
        after.length != before.length ||
        after.any((t) => t is! String || t.trim().isEmpty)) {
      throw Exception(
        'La traducción está incompleta. Se conserva el original.',
      );
    }
    for (var i = 0; i < before.length; i++) {
      restoreRecipeNumbers('${before[i]}', '${after[i]}');
    }
  }
}

Map<String, dynamic>? _glossary;
Future<Map<String, dynamic>>? _glossaryLoading;
Future<Map<String, dynamic>> culinaryGlossary() async {
  if (_glossary != null) return _glossary!;
  return _glossaryLoading ??= (() async {
    try {
      return _glossary = Map<String, dynamic>.from(
        jsonDecode(
          await rootBundle.loadString(
            'assets/translation/culinary-glossary.json',
          ),
        ),
      );
    } finally {
      _glossaryLoading = null;
    }
  })();
}

double _numberValue(String text) {
  const fractions = {
    '½': '1/2',
    '¼': '1/4',
    '¾': '3/4',
    '⅓': '1/3',
    '⅔': '2/3',
    '⅛': '1/8',
    '⅜': '3/8',
    '⅝': '5/8',
    '⅞': '7/8',
  };
  final parts = (fractions[text] ?? text)
      .replaceAll(',', '.')
      .replaceAll('⁄', '/')
      .replaceAll(RegExp(r'\s'), '')
      .split('/');
  if (parts.length == 1) return double.parse(parts[0]);
  final divisor = double.parse(parts[1]);
  if (divisor == 0) throw Exception('La receta tiene una fracción no válida.');
  return double.parse(parts[0]) / divisor;
}

String restoreRecipeNumbers(String original, String translated) {
  final before = recipeNumbers.allMatches(original).toList(),
      after = recipeNumbers.allMatches(translated).toList();
  if (before.length != after.length) {
    throw Exception(
      'La traducción alteró una cantidad, temperatura o tiempo. Se conserva el original.',
    );
  }
  for (var i = before.length - 1; i >= 0; i--) {
    if ((_numberValue(before[i][0]!) - _numberValue(after[i][0]!)).abs() > 1e-9) {
      throw Exception(
        'La traducción alteró una cantidad, temperatura o tiempo. Se conserva el original.',
      );
    }
    translated = translated.replaceRange(
      after[i].start,
      after[i].end,
      before[i][0]!,
    );
  }
  return translated;
}

typedef _Part = ({bool fixed, String text});
Iterable<_Part> _boundedParts(String text) sync* {
  while (text.length > 1800) {
    final cut = text.lastIndexOf(' ', 1800);
    if (cut < 1) {
      throw Exception(
        'Un texto sin separadores es demasiado largo para traducir.',
      );
    }
    yield (fixed: false, text: text.substring(0, cut));
    yield (fixed: true, text: ' ');
    text = text.substring(cut + 1);
  }
  if (text.isNotEmpty) yield (fixed: false, text: text);
}

Iterable<_Part> _sentenceParts(String text) sync* {
  var start = 0;
  for (final boundary in RegExp(
    r'\n+|(?<=[.!?])\s+(?=[A-ZÀ-ÖØ-Þ])',
  ).allMatches(text)) {
    yield* _boundedParts(text.substring(start, boundary.start));
    yield (fixed: true, text: boundary[0]!);
    start = boundary.end;
  }
  yield* _boundedParts(text.substring(start));
}

Iterable<_Part> _textParts(String text, Map<String, dynamic> terms) sync* {
  const letters = 'A-Za-zÀ-ÖØ-öø-ÿ';
  final keys = terms.keys.toList()
    ..sort((a, b) => b.length.compareTo(a.length));
  final pattern = RegExp(
    '(?<![$letters])(${keys.map(RegExp.escape).join('|')})(?![$letters])',
    caseSensitive: false,
  );
  final lookup = {
    for (final key in keys) key.toLowerCase(): terms[key] as String,
  };
  var start = 0;
  for (final match in pattern.allMatches(text)) {
    yield* _sentenceParts(text.substring(start, match.start));
    yield (fixed: true, text: lookup[match[0]!.toLowerCase()]!);
    start = match.end;
  }
  yield* _sentenceParts(text.substring(start));
}

const _protectedUnits = <String, String>{
  'g': 'g',
  'kg': 'kg',
  'mg': 'mg',
  'ml': 'ml',
  'cl': 'cl',
  'dl': 'dl',
  'l': 'l',
  'cm': 'cm',
  'mm': 'mm',
  'oz': 'oz',
  'lb': 'lb',
  'lbs': 'lbs',
  '°f': '°F',
  '° f': '°F',
  'f': 'F',
  '°c': '°C',
  '° c': '°C',
  'c': 'C',
  'gram': 'g',
  'grams': 'g',
  'gramm': 'g',
  'gramme': 'g',
  'grammes': 'g',
  'grammi': 'g',
  'gramas': 'g',
  'minutes': 'minutos',
  'minute': 'minuto',
  'minuten': 'minutos',
  'minuti': 'minutos',
  'minutos': 'minutos',
  'minuto': 'minuto',
  'hours': 'horas',
  'hour': 'hora',
  'heures': 'horas',
  'heure': 'hora',
  'stunden': 'horas',
  'stunde': 'hora',
  'ore': 'horas',
  'horas': 'horas',
  'seconds': 'segundos',
  'second': 'segundo',
  'secondes': 'segundos',
  'sekunden': 'segundos',
  'secondi': 'segundos',
  'segundos': 'segundos',
  'inches': 'pulgadas',
  'inch': 'pulgada',
  'centimeters': 'cm',
  'centimetres': 'cm',
  'zentimeter': 'cm',
  'pounds': 'libras',
  'pound': 'libra',
  'ounces': 'onzas',
  'ounce': 'onza',
};

String? _recoverRepeatedQuantity(String original, String translated) {
  final units = _protectedUnits.keys.toList()
    ..sort((a, b) => b.length.compareTo(a.length));
  final pattern = RegExp(
    '(?<![\\w])((?:${recipeNumbers.pattern})(?:\\s*(?:${units.map(RegExp.escape).join('|')})(?![A-Za-zÀ-ÖØ-öø-ÿ]))?)(?:\\s+\\1)+(?![\\w])',
    caseSensitive: false,
  );
  final repaired = translated.replaceAllMapped(pattern, (m) => m[1]!);
  if (repaired == translated) return null;
  // Accept only adjacent identical repetition whose removal exactly restores ALL original numbers.
  try {
    return restoreRecipeNumbers(original, repaired);
  } catch (_) {
    return null;
  }
}

/// Retry only a fragment whose numerical validation failed, keeping full sentence context.
/// Opaque tokens protect the original amount and unit; missing/repeated/reordered tokens fail.
Future<String> _translateProtected(
  String original,
  String source,
  TranslateTexts translate,
) async {
  const letters = 'A-Za-zÀ-ÖØ-öø-ÿ';
  final units = _protectedUnits.keys.toList()
    ..sort((a, b) => b.length.compareTo(a.length));
  final pattern = RegExp(
    '(${recipeNumbers.pattern})(?:\\s*(${units.map(RegExp.escape).join('|')})(?![$letters]))?',
    caseSensitive: false,
  );
  final protected = <String, String>{};
  final masked = original.replaceAllMapped(pattern, (m) {
    var index = protected.length;
    final code = List<int>.filled(4, 65);
    for (var i = 3; i >= 0; i--) {
      code[i] += index % 26;
      index ~/= 26;
    }
    final marker = 'ZXQ${String.fromCharCodes(code)}QXZ';
    protected[marker] =
        '${m[1]}${m[2] == null ? '' : ' ${_protectedUnits[m[2]!.toLowerCase()]}'}';
    return marker;
  });
  if (protected.isEmpty) {
    throw Exception(
      'La traducción introdujo una cantidad. Se conserva el original.',
    );
  }
  final response = await translate([masked], source);
  if (response.length != 1) {
    throw Exception('La traducción está incompleta; se conserva el original.');
  }
  final markerPattern = RegExp(r'ZXQ[A-Z]{4}QXZ', caseSensitive: false);
  final markers = markerPattern
      .allMatches(response.single)
      .map((m) => m[0]!.toUpperCase())
      .toList();
  if (jsonEncode(markers) != jsonEncode(protected.keys.toList())) {
    throw Exception(
      'La traducción omitió o repitió una cantidad. Se conserva el original.',
    );
  }
  restoreRecipeNumbers('', response.single);
  final value = response.single.replaceAllMapped(
    markerPattern,
    (m) => protected[m[0]!.toUpperCase()]!,
  );
  return restoreRecipeNumbers(original, value);
}

Future<List<String>> translateCulinaryTexts(
  List<String> texts,
  String source,
  TranslateTexts translate,
) async {
  final glossary = Map<String, dynamic>.from(
    (await culinaryGlossary())[source],
  );
  final fragments = <String>[];
  final layouts = <List<({int? index, String before, String after})>>[];
  for (final text in texts) {
    final layout = <({int? index, String before, String after})>[];
    for (final part in _textParts(text, glossary)) {
      if (part.fixed || !RegExp('[A-Za-zÀ-ÖØ-öø-ÿ]').hasMatch(part.text)) {
        layout.add((index: null, before: part.text, after: ''));
        continue;
      }
      layout.add((
        index: fragments.length,
        before: RegExp(r'^\s*').firstMatch(part.text)![0]!,
        after: RegExp(r'\s*$').firstMatch(part.text)![0]!,
      ));
      fragments.add(part.text.trim());
    }
    layouts.add(layout);
  }
  if (fragments.length > 4000) throw Exception('La receta es demasiado larga.');
  final translated = fragments.isEmpty
      ? <String>[]
      : (await translate(fragments, source)).toList();
  if (translated.length != fragments.length ||
      translated.any((t) => t.trim().isEmpty)) {
    throw Exception('La traducción está incompleta; se conserva el original.');
  }
  for (var i = 0; i < fragments.length; i++) {
    try {
      restoreRecipeNumbers(fragments[i], translated[i]);
    } catch (_) {
      translated[i] =
          _recoverRepeatedQuantity(fragments[i], translated[i]) ??
          await _translateProtected(fragments[i], source, translate);
    }
  }
  return [
    for (var i = 0; i < texts.length; i++)
      polishCulinary(
        texts[i],
        restoreRecipeNumbers(
          texts[i],
          layouts[i]
              .map(
                (p) => p.index == null
                    ? p.before
                    : p.before + translated[p.index!].trim() + p.after,
              )
              .join(),
        ),
      ),
  ];
}

String polishCulinary(String original, String value) {
  value = value.replaceAllMapped(
    RegExp(
      r'\b(tazas?|cucharadas?|cucharaditas?|onzas?|libras?)\s+(?=(?:harina|leche|azúcar|mantequilla|aceite|agua|nata|sal)\b)',
      caseSensitive: false,
    ),
    (m) => '${m[1]} de ',
  );
  value = value.replaceAllMapped(
    RegExp(
      r'(?<=[a-zà-öø-ÿ0-9])\s+(De|La|Las|El|Los|Con|En|Durante|Hasta|Para)\b',
    ),
    (m) => m[0]!.toLowerCase(),
  );
  if (original.isNotEmpty &&
      value.isNotEmpty &&
      RegExp('[A-ZÀ-ÖØ-Þ]').hasMatch(original[0])) {
    value = value[0].toUpperCase() + value.substring(1);
  }
  return value;
}

Future<Map<String, dynamic>> translateRecipeLocally(
  Map<String, dynamic> recipe,
  TranslateTexts translate, {
  String? language,
  bool force = false,
}) async {
  if (!force && recipe['translation']?['target_language'] == 'es') {
    return recipe;
  }
  final base = force && recipe['original'] is Map
      ? Map<String, dynamic>.from(recipe['original'])
      : recipe;
  final source = language ?? translationSource(recipe, force: force);
  if (source == 'es') return recipe;
  if (!translationLanguages.contains(source)) {
    throw Exception(
      'Este idioma aún no tiene traducción. El original está disponible.',
    );
  }
  final original = {
    for (final key in ['title', 'ingredients', 'steps', 'notes'])
      key:
          base[key] ??
          (key == 'ingredients' || key == 'steps' ? <String>[] : ''),
  };
  final note = '${original['notes']}';
  final notesEs =
      base['notes_language'] == 'es' ||
      ('${recipe['origin']?['provider'] ?? ''}'.startsWith('wiki-') &&
          [
            'Comprueba el rendimiento',
            'Rendimiento no declarado:',
            'Raciones declaradas por la fuente:',
          ].any(note.startsWith));
  final input = <String>[
    '${original['title']}',
    ...List<String>.from(original['ingredients'] as List),
    ...List<String>.from(original['steps'] as List),
    notesEs ? '' : note,
  ];
  if (input.length > 1100 ||
      input.fold<int>(0, (n, t) => n + t.length) > 120000) {
    throw Exception(
      'La receta es demasiado larga. Se conserva el texto completo.',
    );
  }
  final translated = await translateCulinaryTexts(input, source, translate);
  if (translated[0].length > 250) {
    throw Exception(
      'El título traducido es demasiado largo; se conserva el original.',
    );
  }
  final ingredients = (original['ingredients'] as List).length,
      steps = (original['steps'] as List).length;
  return <String, dynamic>{
    ...recipe,
    'language': 'es',
    'title': translated[0],
    'ingredients': translated.sublist(1, 1 + ingredients),
    'steps': translated.sublist(1 + ingredients, 1 + ingredients + steps),
    'notes': notesEs ? note : translated.last,
    'notes_language': 'es',
    'original': jsonDecode(
      jsonEncode({
        ...original,
        'language': source,
        if (notesEs) 'notes_language': 'es',
      }),
    ),
    'translation': {
      'source_language': source,
      'target_language': 'es',
      'engine': 'ML Kit local + glosario culinario',
      'revision': translationRevision,
      'review_required': true,
    },
    if (recipe['origin'] is Map)
      'origin': {
        ...Map<String, dynamic>.from(recipe['origin']),
        'modified': true,
      },
  };
}

Future<List<String>> androidRecipeTranslation(
  List<String> texts,
  String source,
) async {
  final value = await const MethodChannel('mesa/native')
      .invokeMethod<List<dynamic>>('translateRecipeTexts', {
        'source': source,
        'texts': texts,
      })
      .timeout(const Duration(minutes: 2));
  if (value == null || value.any((v) => v is! String)) {
    throw Exception('La traducción no devolvió la receta completa.');
  }
  return value.cast<String>();
}
