import 'package:flutter/material.dart';

import 'models.dart' show searchKey;
import 'source_registry.dart';

enum SourceOrder { recipes, country, availability, name }

String sourceAvailability(CatalogSource source) => source.browseable
    ? 'Catálogo operativo'
    : source.consultationOnly
    ? 'Pendiente de autorización'
    : 'Web solo de consulta';

String groupedNumber(int number) => number.toString().replaceAllMapped(
  RegExp(r'(\d)(?=(\d{3})+$)'),
  (match) => '${match[1]}.',
);

String sourceCountLabel(CatalogSource source) {
  final count = source.recipeCount;
  if (count == null) {
    return source.countKind == 'not_applicable'
        ? 'No es un recetario'
        : 'Total sin verificar';
  }
  final value = groupedNumber(count);
  return switch (source.countKind) {
    'more_than' => 'Más de $value recetas',
    'at_least' => '$value+ recetas',
    'indexed_entries' => '$value fichas en el índice',
    'recipe_records' => '$value fichas de receta',
    'catalog_entries' => '$value entradas de recetas',
    'minimum_entries' => '≥ $value fichas identificadas',
    'reviewed_selection' => '$value recetas revisadas en Mesa',
    'document_count' => '$value recetas en el libro',
    _ => '$value recetas',
  };
}

List<CatalogSource> classifiedSources({
  String query = '',
  String country = '',
  SourceOrder order = SourceOrder.recipes,
}) {
  final key = searchKey(query.trim());
  final rows = catalogSources
      .where(
        (source) =>
            (country.isEmpty || source.country == country) &&
            searchKey(
              '${source.name} ${source.country} ${sourceAvailability(source)}',
            ).contains(key),
      )
      .toList();
  rows.sort((a, b) {
    final comparison = switch (order) {
      SourceOrder.recipes =>
        a.recipeCount == null
            ? (b.recipeCount == null ? 0 : 1)
            : b.recipeCount == null
            ? -1
            : b.recipeCount!.compareTo(a.recipeCount!),
      SourceOrder.country => searchKey(
        a.country,
      ).compareTo(searchKey(b.country)),
      SourceOrder.availability => sourceAvailability(
        a,
      ).compareTo(sourceAvailability(b)),
      SourceOrder.name => 0,
    };
    return comparison != 0
        ? comparison
        : searchKey(a.name).compareTo(searchKey(b.name));
  });
  return rows;
}

int? sourceRankingPosition(String id) {
  final ranked = classifiedSources()
      .where((s) => s.recipeCount != null)
      .toList();
  final index = ranked.indexWhere((s) => s.id == id);
  return index < 0 ? null : index + 1;
}

/// Includes every registered source; recipe totals and access are independent.
class SourceDirectory extends StatefulWidget {
  const SourceDirectory({super.key, required this.onOpenUrl});
  final Future<void> Function(String url) onOpenUrl;
  @override
  State<SourceDirectory> createState() => _SourceDirectoryState();
}

class _SourceDirectoryState extends State<SourceDirectory> {
  String query = '', country = '';
  SourceOrder order = SourceOrder.recipes;
  final scroll = ScrollController();
  @override
  void dispose() {
    scroll.dispose();
    super.dispose();
  }

  void update(VoidCallback action) {
    setState(action);
    if (scroll.hasClients) scroll.jumpTo(0);
  }

  String group(CatalogSource source) => switch (order) {
    SourceOrder.recipes =>
      source.recipeCount == null
          ? (source.countKind == 'not_applicable'
                ? 'Fuera del ranking'
                : 'Sin posición: total sin verificar')
          : 'Ranking orientativo',
    SourceOrder.country => source.country,
    SourceOrder.availability => sourceAvailability(source),
    SourceOrder.name => 'Todas las fuentes',
  };

  Future<void> evidence(CatalogSource source) => showDialog<void>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(source.name),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              sourceCountLabel(source),
              style: Theme.of(c).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            Text(source.countNote),
            const SizedBox(height: 12),
            Text('Revisión: ${source.countCheckedAt}'),
            Text(sourceAvailability(source)),
            const SizedBox(height: 12),
            Text(source.description),
            if(source.licenseName.isEmpty) const Text('No se ha verificado un permiso general para reutilizar el catálogo y sus fotos.'),
            if (source.licenseName.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text('Licencia: ${source.licenseName}'),
            ],
            if (source.countEvidence.isNotEmpty) ...[
              const SizedBox(height: 12),
              SelectableText(source.countEvidence),
            ],
          ],
        ),
      ),
      actions: [
        if (source.licenseUrl.isNotEmpty)
          TextButton(
            onPressed: () => widget.onOpenUrl(source.licenseUrl),
            child: const Text('Ver licencia'),
          ),
        if (source.countEvidence.isNotEmpty)
          TextButton(
            onPressed: () => widget.onOpenUrl(source.countEvidence),
            child: const Text('Abrir comprobación'),
          ),
        TextButton(
          onPressed: () => Navigator.pop(c),
          child: const Text('Cerrar'),
        ),
      ],
    ),
  );

  Future<void> explainRanking() => showDialog<void>(
    context: context,
    builder: (c) => AlertDialog(
      title: const Text('Cómo se ordenan las fuentes'),
      content: const SingleChildScrollView(
        child: Text(
          'Se ordenan de mayor a menor por la cifra disponible de cada fuente. '
          '«Más de» y «+» indican un mínimo: no permiten saber el total exacto '
          'ni garantizar el orden real entre dos sitios.\n\n'
          'Las cifras pueden ser recetas declaradas por el editor, fichas de un índice o recetas de un libro. '
          'La etiqueta de cada fila indica qué se contó. «≥» es un mínimo de fichas identificadas; puede haber más. '
          'El ranking es orientativo: las fuentes sin una cifra comprobable aparecen sin posición, nunca como cero. '
          'Las cifras no indican recetas importadas en Mesa ni garantizan que todas tengan foto y cantidades. '
          'Se conservan únicamente fuentes con catálogo integrado o licencia libre comprobada. Las nuevas aparecen sin posición cuando su total no está verificado.',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(c),
          child: const Text('Cerrar'),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final rows = classifiedSources(
      query: query,
      country: country,
      order: order,
    );
    final groups = <String, List<CatalogSource>>{};
    for (final row in rows) {
      (groups[group(row)] ??= []).add(row);
    }
    final countries = catalogSources.map((s) => s.country).toSet().toList()
      ..sort();
    final known = catalogSources.where((s) => s.recipeCount != null).length;
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: SizedBox(
        width: 780,
        height: 720,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      MediaQuery.sizeOf(context).width < 600
                          ? 'Ranking'
                          : 'Ranking de recetas',
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Cómo se calcula el ranking',
                    onPressed: explainRanking,
                    icon: const Icon(Icons.help_outline),
                  ),
                  IconButton(
                    tooltip: 'Cerrar fuentes',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              Expanded(
                child: ListView(
                  controller: scroll,
                  children: [
                    if (MediaQuery.sizeOf(context).width < 480)
                      Text(
                        '${catalogSources.length} fuentes · $known con recuento',
                      )
                    else ...[
                      Text(
                        '${catalogSources.length} actuales · ${originalSourceCount - retiredSourceCount} conservadas + $addedOpenSourceCount libres añadidas',
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '$known con recuento · ${catalogSources.length - known} sin posición',
                      ),
                    ],
                    const SizedBox(height: 8),
                    TextField(
                      decoration: const InputDecoration(
                        labelText: 'Buscar fuente o país',
                        prefixIcon: Icon(Icons.search),
                      ),
                      onChanged: (value) => update(() => query = value),
                    ),
                    const SizedBox(height: 12),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final sorting = DropdownButtonFormField<SourceOrder>(
                          initialValue: order,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Ordenar fuentes',
                          ),
                          items: [
                            for (final entry in const {
                              SourceOrder.recipes: 'Más a menos recetas',
                              SourceOrder.country: 'País',
                              SourceOrder.availability: 'Disponibilidad',
                              SourceOrder.name: 'Nombre',
                            }.entries)
                              DropdownMenuItem(
                                value: entry.key,
                                child: Text(
                                  entry.value,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                          ],
                          onChanged: (value) {
                            if (value != null) update(() => order = value);
                          },
                        );
                        final countryFilter = DropdownButtonFormField<String>(
                          initialValue: country,
                          isExpanded: true,
                          decoration: const InputDecoration(labelText: 'País'),
                          items: [
                            const DropdownMenuItem(
                              value: '',
                              child: Text('Todos'),
                            ),
                            for (final name in countries)
                              DropdownMenuItem(
                                value: name,
                                child: Text(
                                  name,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                          ],
                          onChanged: (value) =>
                              update(() => country = value ?? ''),
                        );
                        return constraints.maxWidth < 480
                            ? Column(
                                children: [
                                  sorting,
                                  const SizedBox(height: 12),
                                  countryFilter,
                                ],
                              )
                            : Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(flex: 3, child: sorting),
                                  const SizedBox(width: 10),
                                  Expanded(flex: 2, child: countryFilter),
                                ],
                              );
                      },
                    ),
                    const SizedBox(height: 8),
                    Text('${rows.length} de ${catalogSources.length} fuentes'),
                    const SizedBox(height: 8),
                    if (rows.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(24),
                        child: Text('No hay fuentes para este filtro.'),
                      )
                    else ...[
                      for (final entry in groups.entries) ...[
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          child: Text(
                            '${entry.key} · ${entry.value.length}',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                        for (final source in entry.value)
                          Card(
                            key: ValueKey('source:${source.id}'),
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              leading:
                                  MediaQuery.sizeOf(context).width >= 480 &&
                                      order == SourceOrder.recipes &&
                                      sourceRankingPosition(source.id) != null
                                  ? Semantics(
                                      label:
                                          'Posición ${sourceRankingPosition(source.id)} del ranking orientativo',
                                      child: CircleAvatar(
                                        radius: 18,
                                        child: Text(
                                          '${sourceRankingPosition(source.id)}',
                                          style: const TextStyle(fontSize: 14),
                                        ),
                                      ),
                                    )
                                  : null,
                              title: Text(
                                MediaQuery.sizeOf(context).width < 480 &&
                                        order == SourceOrder.recipes &&
                                        sourceRankingPosition(source.id) != null
                                    ? '${sourceRankingPosition(source.id)}. ${source.name}'
                                    : source.name,
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${source.country} · ${sourceAvailability(source)}',
                                  ),
                                  Text(
                                    sourceCountLabel(source),
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .primary,
                                    ),
                                  ),
                                  if (MediaQuery.sizeOf(context).width < 480)
                                    Align(
                                      alignment: Alignment.centerRight,
                                      child: IconButton(
                                        tooltip:
                                            'Ver recuento y estado de ${source.name}',
                                        onPressed: () => evidence(source),
                                        icon: const Icon(Icons.info_outline),
                                      ),
                                    ),
                                ],
                              ),
                              trailing: MediaQuery.sizeOf(context).width < 480
                                  ? null
                                  : IconButton(
                                      tooltip:
                                          'Ver recuento y estado de ${source.name}',
                                      onPressed: () => evidence(source),
                                      icon: const Icon(Icons.info_outline),
                                    ),
                              onTap: () => Navigator.pop(context, source.id),
                            ),
                          ),
                      ],
                    ],
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'Toca una fuente para abrirla.',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
