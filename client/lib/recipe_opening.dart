import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'catalogs.dart';
import 'photos.dart';
import 'translation.dart';

typedef DetailLoader = Future<Map<String, dynamic>> Function(
  void Function(Map<String, dynamic>) onText,
);
typedef RecipeTranslator = Future<Map<String, dynamic>> Function(
  Map<String, dynamic> recipe, {
  bool force,
});

String recipeTextKey(Map<String, dynamic> recipe) {
  final source = recipe['original'] is Map
      ? Map<String, dynamic>.from(recipe['original'])
      : recipe;
  // Translators may normalize language metadata; only the source text identifies an input.
  return jsonEncode([
    recipeLanguage(source),
    source['title'] ?? '',
    source['ingredients'] ?? [],
    source['steps'] ?? [],
    source['notes'] ?? '',
  ]);
}

Map<String, dynamic> mergeTranslatedRecipe(
  Map<String, dynamic> base,
  Map<String, dynamic> translated,
) => {
  ...base,
  for (final key in [
    'title',
    'ingredients',
    'steps',
    'notes',
    'language',
    'notes_language',
    'original',
    'translation',
  ])
    if (translated.containsKey(key)) key: translated[key],
  if (base['origin'] is Map)
    'origin': {...Map<String, dynamic>.from(base['origin']), 'modified': true},
};

Map<String, dynamic> catalogRecipeLanguage(Map<String, dynamic> recipe) {
  if (recipe['original'] is Map ||
      recipe['translation']?['target_language'] == 'es') {
    return recipe;
  }
  final provider = recipe['origin']?['provider'];
  final language = catalogSources
      .where((s) => s.id == provider)
      .firstOrNull
      ?.languageCode;
  // Old catalogue snapshots defaulted to Spanish when a foreign page omitted lang.
  if (language == null || !translationLanguages.contains(language)) {
    return recipe;
  }
  return {...recipe, 'language': language};
}

/// Owns one preview. Text, photo references and validated translation arrive independently.
/// Persistent storage contains only recipe text and remote image metadata.
class RecipeOpening extends ChangeNotifier {
  RecipeOpening({
    required this.loadDetail,
    required this.translate,
    required this.remember,
    Map<String, dynamic>? cached,
    bool requireCachedPhoto = true,
  }) {
    if (cached != null &&
        (!requireCachedPhoto ||
            recipePhotos(cached)
                .any((p) => catalogPhotoUrl('${p['url'] ?? ''}')))) {
      final snapshot = Map<String, dynamic>.from(onlinePhotoTree(cached));
      data = requireCachedPhoto ? catalogRecipeLanguage(snapshot) : snapshot;
      complete = true;
      fromCache = true;
    }
  }
  final DetailLoader loadDetail;
  final RecipeTranslator translate;
  final Future<void> Function(Map<String, dynamic>) remember;
  Map<String, dynamic>? data;
  bool complete = false,
      fromCache = false,
      loading = false,
      translating = false;
  String? failure, translationFailure;
  bool _closed = false;
  int _loadId = 0, _translationId = 0;
  String? _translationKey;
  Map<String, dynamic>? _translated;
  String? _translatedKey;
  final Stopwatch clock = Stopwatch()..start();
  int? firstTextMs, completeMs, translatedMs;

  void _changed() {
    if (!_closed) notifyListeners();
  }

  Future<void> start({bool refresh = false}) async {
    if (_closed || loading) return;
    if (data != null && !refresh) {
      firstTextMs ??= clock.elapsedMilliseconds;
      _startTranslation(data!);
      return;
    }
    final id = ++_loadId;
    loading = true;
    failure = null;
    _changed();
    try {
      final loaded = await loadDetail((text) {
        if (_closed || id != _loadId) return;
        // An explicit refresh retains the readable previous version until full validation.
        final readable = catalogRecipeLanguage(text);
        if (data == null || !complete) {
          data = readable;
          firstTextMs ??= clock.elapsedMilliseconds;
          _changed();
        }
        _startTranslation(readable);
      });
      if (_closed || id != _loadId) return;
      final value = catalogRecipeLanguage(loaded);
      data = _translated != null && _translatedKey == recipeTextKey(value)
          ? mergeTranslatedRecipe(value, _translated!)
          : value;
      complete = true;
      fromCache = false;
      completeMs = clock.elapsedMilliseconds;
      firstTextMs ??= clock.elapsedMilliseconds;
      _changed();
      _persist();
      _startTranslation(value);
    } catch (error) {
      if (!_closed && id == _loadId) {
        failure = '$error'.replaceFirst('Exception: ', '');
        _changed();
      }
    } finally {
      if (!_closed && id == _loadId) {
        loading = false;
        _changed();
      }
    }
  }

  void _startTranslation(Map<String, dynamic> source) {
    final alreadySpanish = source['translation']?['target_language'] == 'es';
    var invalid = false;
    if (alreadySpanish) {
      try {
        validateSpanishTranslation(source, source);
      } catch (_) {
        invalid = true;
      }
    }
    final old =
        alreadySpanish &&
        (invalid ||
            (source['translation']?['revision'] as num? ?? 0) <
                translationRevision);
    if ((alreadySpanish && !old) || !canTranslateRecipe(source)) return;
    final key = recipeTextKey(source);
    if (_translationKey == key) return;
    _translationKey = key;
    final id = ++_translationId;
    translating = true;
    translationFailure = null;
    _changed();
    unawaited(() async {
      try {
        final value = await translate(source, force: old);
        if (_closed || id != _translationId) return;
        validateSpanishTranslation(source, value);
        _translated = value;
        _translatedKey = key;
        translatedMs = clock.elapsedMilliseconds;
        if (data != null && recipeTextKey(data!) == key) {
          data = mergeTranslatedRecipe(data!, value);
        }
        if (complete) _persist();
      } catch (error) {
        if (!_closed && id == _translationId) {
          translationFailure = '$error'.replaceFirst('Exception: ', '');
          _translationKey = null;
        }
      } finally {
        if (!_closed && id == _translationId) {
          translating = false;
          _changed();
        }
      }
    }());
  }

  void retryTranslation() {
    if (_closed || translating || data == null) return;
    _translationKey = null;
    _startTranslation(data!);
  }

  void apply(Map<String, dynamic> value) {
    if (_closed) return;
    _translationId++;
    translating = false;
    translationFailure = null;
    data = value;
    _translated = value;
    _translationKey = _translatedKey = recipeTextKey(value);
    _changed();
    if (complete) _persist();
  }

  void _persist() {
    if (data == null || !complete) return;
    final snapshot = Map<String, dynamic>.from(
      jsonDecode(jsonEncode(onlinePhotoTree(data))),
    );
    unawaited(remember(snapshot).catchError((Object _) {}));
  }

  @override
  void dispose() {
    _closed = true;
    _loadId++;
    _translationId++;
    super.dispose();
  }
}
