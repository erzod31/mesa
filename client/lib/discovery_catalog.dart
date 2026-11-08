import 'dart:convert';

import 'catalogs.dart';
import 'models.dart' show searchKey;

/// Country is the publication's location/edition, never an inferred recipe origin.
class DiscoveryCatalog {
  DiscoveryCatalog(this.api);
  final CatalogApi api;

  List<CatalogSource> eligible(String country) => api.sources
      .where(
        (s) =>
            s.browseable &&
            (country.isEmpty || s.country.split(' / ').contains(country)),
      )
      .toList();

  List<String> get countries =>
      {for (final s in api.sources) ...s.country.split(' / ')}
          .where((s) => s.isNotEmpty)
          .toList()
        ..sort((a, b) => searchKey(a).compareTo(searchKey(b)));

  Future<DiscoveryResult> search({
    String country = '',
    String query = '',
    String? cursor,
    bool Function()? isCurrent,
  }) async {
    query = query.trim();
    final sources = eligible(country);
    final pending = <String, String?>{for (final s in sources) s.id: null};
    if (cursor != null) {
      try {
        final saved = jsonDecode(cursor) as Map;
        if (saved['v'] != 1 ||
            saved['country'] != country ||
            saved['query'] != query ||
            saved['pending'] is! Map) {
          throw const FormatException();
        }
        pending.clear();
        for (final e in (saved['pending'] as Map).entries) {
          if (!sources.any((s) => s.id == e.key) ||
              (e.value != null && e.value is! String)) {
            throw const FormatException();
          }
          pending[e.key as String] = e.value as String?;
        }
      } catch (_) {
        throw const FormatException(
          'La búsqueda ha cambiado. Vuelve a buscar.',
        );
      }
    }
    final active = sources.where((s) => pending.containsKey(s.id)).toList();
    final pages = <String, List<CatalogItem>>{};
    final failed = <String>[];
    final next = <String, String?>{};
    var position = 0;
    Future<void> worker() async {
      while (position < active.length) {
        if (isCurrent != null && !isCurrent()) return;
        final source = active[position++];
        try {
          final page = await api.search(
            source.id,
            query: query,
            cursor: pending[source.id],
          );
          pages[source.id] = page.items.where((i) => i.hasPhoto).toList();
          if (page.cursor != null) {
            if (page.cursor == pending[source.id]) {
              throw const FormatException('El catálogo no avanzó.');
            }
            next[source.id] = page.cursor;
          }
        } catch (_) {
          failed.add(source.id);
          next[source.id] = pending[source.id];
        }
      }
    }

    await Future.wait(
      List.generate(active.length.clamp(0, 3), (_) => worker()),
    );
    // Interleave publishers fairly; keep each publisher's own ordering.
    final mixed = <CatalogItem>[];
    final seen = <String>{};
    for (var row = 0; pages.values.any((p) => row < p.length); row++) {
      for (final source in sources) {
        final page = pages[source.id];
        if (page == null || row >= page.length) continue;
        final item = page[row];
        final identity = Uri.tryParse(item.id)?.hasScheme == true
            ? item.id
            : '${item.provider}:${item.id}';
        if (seen.add(identity)) mixed.add(item);
      }
    }
    return DiscoveryResult(
      mixed,
      cursor: next.isEmpty
          ? null
          : jsonEncode({
              'v': 1,
              'country': country,
              'query': query,
              'pending': next,
            }),
      failedSources: [
        for (final s in sources)
          if (failed.contains(s.id)) s.name,
      ],
      sourceCount: sources.length,
    );
  }
}

class DiscoveryResult {
  const DiscoveryResult(
    this.items, {
    this.cursor,
    this.failedSources = const [],
    required this.sourceCount,
  });
  final List<CatalogItem> items;
  final String? cursor;
  final List<String> failedSources;
  final int sourceCount;
}
