// Reviewed PDF photo references; never accept an arbitrary document or page.
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
  if (base == "https://bunkatura.pl/pdf/mesa_polaca.pdf" &&
      const [
        91,
        93,
        95,
        97,
        99,
        101,
        103,
        105,
        107,
        109,
        111,
        113,
      ].contains(page)) {
    return (provider: 'book-polaca', page: page);
  }
  return null;
}
