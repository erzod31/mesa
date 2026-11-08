import 'models.dart' show searchKey;

const _fractionValues = {
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
const _amount =
    r'(?:\d+\s+\d+/\d+|\d+/\d+|\d+[.,]\d+|\d+[½¼¾⅓⅔⅛⅜⅝⅞]?|[½¼¾⅓⅔⅛⅜⅝⅞])';

double? culinaryNumber(String text) {
  final value = text.trim();
  if (value.isEmpty) return null;
  if (_fractionValues.containsKey(value)) return _fractionValues[value];
  if (value.contains('/')) {
    final parts = value.split(RegExp(r'\s+'));
    final fraction = parts.last.split('/');
    final denominator = double.tryParse(fraction.last);
    final numerator = double.tryParse(fraction.first);
    if (numerator == null || denominator == null || denominator == 0) {
      return null;
    }
    return numerator / denominator +
        (parts.length == 2 ? double.tryParse(parts.first) ?? 0 : 0);
  }
  if (_fractionValues.containsKey(value.substring(value.length - 1))) {
    return (double.tryParse(value.substring(0, value.length - 1)) ?? 0) +
        _fractionValues[value.substring(value.length - 1)]!;
  }
  return double.tryParse(value.replaceAll(',', '.'));
}

String culinaryFormat(double value) => value
    .toStringAsFixed(2)
    .replaceFirst(RegExp(r'\.?0+$'), '')
    .replaceAll('.', ',');

double _practical(
  double value, {
  bool temperature = false,
  bool length = false,
}) {
  final step = temperature
      ? (value >= 120 ? 10.0 : 5.0)
      : length
      ? (value < 10 ? .5 : 1.0)
      : value < .25
      ? .01
      : value < 1
      ? .05
      : value < 5
      ? .25
      : value < 20
      ? 1.0
      : value < 100
      ? 5.0
      : value < 300
      ? 5.0
      : 10.0;
  return (value / step).round() * step;
}

/// Cooking equivalents, with visible approximation and untouched original storage.
String practicalMetric(
  String text, {
  String language = 'es',
  String source = '',
}) {
  var changed = false;
  var result = text;
  final temperature = RegExp(
    r'(\d+(?:[.,]\d+)?)(?:\s*(?:a|to|[-–])\s*(\d+(?:[.,]\d+)?))?\s*(?:°\s*)?(?:F\b|fahrenheit\b|grados Fahrenheit\b)',
    caseSensitive: false,
  );
  result = result.replaceAllMapped(temperature, (m) {
    changed = true;
    String convert(String v) => culinaryFormat(
      _practical(
        (double.parse(v.replaceAll(',', '.')) - 32) * 5 / 9,
        temperature: true,
      ),
    );
    return '${convert(m[1]!)}${m[2] == null ? '' : '–${convert(m[2]!)}'} °C';
  });
  final dimension = RegExp(
    '($_amount)\\s*[x×]\\s*($_amount)\\s*(?:inches?\\b|inch\\b|pulgadas?\\b|["″])',
    caseSensitive: false,
  );
  result = result.replaceAllMapped(dimension, (m) {
    final a = culinaryNumber(m[1]!), b = culinaryNumber(m[2]!);
    if (a == null || b == null) return m[0]!;
    changed = true;
    return '${culinaryFormat(_practical(a * 2.54, length: true))} × ${culinaryFormat(_practical(b * 2.54, length: true))} cm';
  });
  const units =
      r'fl\.?\s*oz\.?|fluid ounces?|onzas? fluidas?|cups?|tazas?|tablespoons?|tbsp\.?|tbs\.?|cucharadas?(?!\s*(?:sopera|cafetera)?\s*colmadas?)|teaspoons?|tsp\.?|cucharaditas?|pounds?|lbs?\.?|libras?|ounces?|oz\.?|onzas?|pints?|pintas?|quarts?|gallons?|galones?|inches?|inch|pulgadas?|sticks?';
  final measure = RegExp(
    '(?<![\\w/])($_amount)(?:\\s*(?:a|to|[-–])\\s*($_amount))?\\s*($units)(?![\\w])',
    caseSensitive: false,
  );
  result = result.replaceAllMapped(measure, (m) {
    final number = culinaryNumber(m[1]!);
    final high = m[2] == null ? null : culinaryNumber(m[2]!);
    if (number == null || m[2] != null && high == null) return m[0]!;
    final unit = searchKey(m[3]!).replaceAll('.', '');
    var factor = 0.0, target = 'ml';
    var length = false;
    final ingredient = searchKey(text.substring(m.end));
    final british = source.contains('.co.uk/');
    if (RegExp(r'^(?:fl|fluid|onzas? fluidas)').hasMatch(unit)) {
      factor = british ? 28.4 : 30;
    } else if (RegExp(r'^(?:cup|taza)').hasMatch(unit)) {
      factor = language == 'es' ? 250 : 240;
      // Only these reviewed ingredient forms have a mass equivalent. Other cups remain volume.
      if (RegExp(r'\b(flour|harina)\b').hasMatch(ingredient) &&
          !RegExp(
            r'almond|coconut|almendra|coco|rice|arroz|centeno|rye|integral|whole',
          ).hasMatch(ingredient)) {
        factor = 120;
        target = 'g';
      } else if (RegExp(r'\b(butter|mantequilla)\b').hasMatch(ingredient)) {
        factor = 225;
        target = 'g';
      } else if (RegExp(r'\b(sugar|azucar)\b').hasMatch(ingredient)) {
        if (RegExp(r'powdered|confection|icing|glas|glace|impalpable')
            .hasMatch(ingredient)) {
          factor = 115;
          target = 'g';
        } else if (RegExp(r'brown|moreno|mascabado').hasMatch(ingredient)) {
          factor = 215;
          target = 'g';
        } else if (!RegExp(r'syrup|sirope|jarabe|coconut|coco')
            .hasMatch(ingredient)) {
          factor = 200;
          target = 'g';
        }
      }
    } else if (RegExp(r'^(?:tablespoon|tbsp|tbs|cucharada)').hasMatch(unit) &&
        !unit.startsWith('cucharadita')) {
      factor = 15;
    } else if (RegExp(r'^(?:teaspoon|tsp|cucharadita)').hasMatch(unit)) {
      factor = 5;
    } else if (RegExp(r'^(?:pound|lb|libra)').hasMatch(unit)) {
      factor = 453.592;
      target = 'g';
    } else if (RegExp(r'^(?:ounce|oz|onza)').hasMatch(unit)) {
      factor = 28.3495;
      target = 'g';
    } else if (unit.startsWith('pint')) {
      factor = british ? 570 : 480;
    } else if (unit.startsWith('quart')) {
      factor = british ? 1140 : 960;
    } else if (RegExp(r'^(?:gallon|galon)').hasMatch(unit)) {
      factor = british ? 4500 : 3800;
    } else if (RegExp(r'^(?:inch|pulgada)').hasMatch(unit)) {
      factor = 2.54;
      target = 'cm';
      length = true;
    } else if (unit.startsWith('stick') &&
        RegExp(r'butter|mantequilla').hasMatch(ingredient)) {
      factor = 113;
      target = 'g';
    }
    if (factor == 0) return m[0]!;
    changed = true;
    String convert(double value) =>
        culinaryFormat(_practical(value * factor, length: length));
    return '${convert(number)}${high == null ? '' : '–${convert(high)}'} $target';
  });
  return changed ? '$result (aprox.)' : result;
}

List<String> recipeDisplayLines(
  Map<String, dynamic> recipe,
  String key, {
  bool originalMeasures = false,
}) {
  final lines = List<String>.from(recipe[key] ?? []);
  if (originalMeasures) return lines;
  final language =
      '${recipe['original']?['language'] ?? recipe['origin']?['language'] ?? recipe['language'] ?? 'es'}';
  return lines
      .map(
        (v) => practicalMetric(
          v,
          language: language,
          source: '${recipe['source'] ?? ''}',
        ),
      )
      .toList();
}
