// Reviewed PDF photo references; never accept an arbitrary document or page.
import 'source_registry.dart';

({String provider, int page})? documentPhotoReference(String value) {
  final uri = Uri.tryParse(value);
  if (uri == null ||
      uri.hasFragment ||
      uri.userInfo.isNotEmpty ||
      (uri.hasPort && uri.port != 443) ||
      uri.queryParameters.length != 1) {
    return null;
  }
  final page = int.tryParse(uri.queryParameters['mesa_recipe_image'] ?? '');
  if (page == null || uri.query != 'mesa_recipe_image=$page') return null;
  final base = uri
      .replace(query: '')
      .toString()
      .replaceFirst(RegExp(r'\?$'), '');
  // Match any reviewed document (asset) source by its published URL and its
  // reviewed photo pages. The family server re-checks the page when requested.
  for (final source in catalogSources) {
    if (source.included && source.url == base && source.photoPages.contains(page)) {
      return (provider: source.id, page: page);
    }
  }
  return null;
}

/// Published PDF URL of a reviewed document source, if registered.
String? documentPhotoUrl(String provider) {
  for (final source in catalogSources) {
    if (source.included && source.id == provider) return source.url;
  }
  return null;
}
