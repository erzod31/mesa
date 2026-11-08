import 'dart:async';

import 'package:flutter/material.dart';

import 'discover.dart';
export 'discover.dart';
import 'design.dart';
import 'brand.dart';
import 'models.dart';
import 'organization.dart';
import 'organization_widgets.dart';
import 'store.dart';
import 'timers.dart';
import 'ui.dart' show RecipeCard, Empty;

typedef EditRecipe = Future<void> Function({
  Entry? entry,
  Map<String, dynamic>? initial,
});

class RecipeLibrary extends StatefulWidget {
  const RecipeLibrary({
    super.key,
    required this.store,
    required this.onOpen,
    required this.onEdit,
    required this.wide,
    this.onDiscoveryChanged,
    this.timers,
  });
  final Cookbook store;
  final ValueChanged<Entry> onOpen;
  final EditRecipe onEdit;
  final bool wide;
  final ValueChanged<bool>? onDiscoveryChanged;
  final KitchenTimers? timers;
  @override
  State<RecipeLibrary> createState() => _RecipeLibraryState();
}

class _RecipeLibraryState extends State<RecipeLibrary> {
  final search = TextEditingController(), exclusion = TextEditingController();
  String query = '', sort = 'title';
  String? category, catalog, tag;
  int? maxMinutes;
  bool favorites = false, explore = false, compact = false;
  Cookbook get s => widget.store;
  void showDiscovery(bool value) {
    setState(() => explore = value);
    widget.onDiscoveryChanged?.call(value);
  }

  @override
  void dispose() {
    search.dispose();
    exclusion.dispose();
    super.dispose();
  }

  Future<void> filters() async {
    var nextCategory = category, nextCatalog = catalog, nextTag = tag;
    var nextFavorites = favorites, nextCompact = compact;
    var nextMinutes = maxMinutes;
    var nextSort = sort;
    var omitted = exclusion.text;
    final categories = recipeGroups(s, 'category');
    final catalogs = recipeGroups(s, 'catalog');
    final tags = s.of('recipe').expand((e) => e.lines('tags')).toSet().toList()
      ..sort();
    final apply = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, update) => AlertDialog(
          title: const Text('Filtrar y ordenar'),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Solo favoritas'),
                    value: nextFavorites,
                    onChanged: (v) => update(() => nextFavorites = v),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Hasta 30 minutos'),
                    value: nextMinutes == 30,
                    onChanged: (v) => update(() => nextMinutes = v ? 30 : null),
                  ),
                  DropdownButtonFormField<String>(
                    initialValue: nextCategory,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Categoría'),
                    items: [
                      const DropdownMenuItem<String>(
                        value: null,
                        child: Text('Todas las categorías'),
                      ),
                      for (final g in categories)
                        DropdownMenuItem(value: g.id, child: Text(g.title)),
                    ],
                    onChanged: (v) => update(() => nextCategory = v),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    initialValue: nextCatalog,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Catálogo'),
                    items: [
                      const DropdownMenuItem<String>(
                        value: null,
                        child: Text('Todos los catálogos'),
                      ),
                      for (final g in catalogs)
                        DropdownMenuItem(value: g.id, child: Text(g.title)),
                    ],
                    onChanged: (v) => update(() => nextCatalog = v),
                  ),
                  if (tags.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      initialValue: nextTag,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Etiqueta'),
                      items: [
                        const DropdownMenuItem<String>(
                          value: null,
                          child: Text('Todas las etiquetas'),
                        ),
                        for (final t in tags)
                          DropdownMenuItem(value: t, child: Text(t)),
                      ],
                      onChanged: (v) => update(() => nextTag = v),
                    ),
                  ],
                  const SizedBox(height: 16),
                  TextFormField(
                    initialValue: omitted,
                    onChanged: (v) => omitted = v,
                    decoration: const InputDecoration(
                      labelText: 'Omitir ingredientes',
                      hintText: 'Cebolla, cilantro…',
                      helperText: 'Filtra texto; no comprueba alergias.',
                    ),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    initialValue: nextSort,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Ordenar por'),
                    items: const [
                      DropdownMenuItem(value: 'title', child: Text('Nombre')),
                      DropdownMenuItem(
                        value: 'time',
                        child: Text('Más rápidas'),
                      ),
                      DropdownMenuItem(
                        value: 'rating',
                        child: Text('Mejor valoradas'),
                      ),
                    ],
                    onChanged: (v) => update(() => nextSort = v!),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Vista de lista'),
                    value: nextCompact,
                    onChanged: (v) => update(() => nextCompact = v),
                  ),
                  TextButton.icon(
                    onPressed: () {
                      Navigator.pop(c, false);
                      organizeDialog(context, s);
                    },
                    icon: const Icon(Icons.folder_outlined),
                    label: const Text('Organizar categorías y catálogos'),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Aplicar'),
            ),
          ],
        ),
      ),
    );
    if (apply == true && mounted) {
      setState(() {
        category = nextCategory;
        catalog = nextCatalog;
        tag = nextTag;
        favorites = nextFavorites;
        compact = nextCompact;
        maxMinutes = nextMinutes;
        sort = nextSort;
        exclusion.text = omitted;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final all = s.of('recipe');
    final categories = recipeGroups(s, 'category'),
        catalogs = recipeGroups(s, 'catalog');
    if (!categories.any((e) => e.id == category)) category = null;
    if (!catalogs.any((e) => e.id == catalog)) catalog = null;
    final tags = all.expand((e) => e.lines('tags')).toSet().toList()..sort();
    if (!tags.contains(tag)) tag = null;
    final visible = all
        .where(
          (e) => matchesRecipe(
            e,
            s,
            query: query,
            category: category,
            catalog: catalog,
            tag: tag,
            favorites: favorites,
            maxMinutes: maxMinutes,
            exclude: exclusion.text,
          ),
        )
        .toList();
    visible.sort(
      (a, b) => switch (sort) {
        'time' =>
          (a.data['minutes'] == 0 || a.data['minutes'] == null
                  ? 100001
                  : a.data['minutes'] as int)
              .compareTo(
                b.data['minutes'] == 0 || b.data['minutes'] == null
                    ? 100001
                    : b.data['minutes'] as int,
              ),
        'rating' => (b.data['rating'] as int? ?? 0).compareTo(
          a.data['rating'] as int? ?? 0,
        ),
        _ => searchKey(a.title).compareTo(searchKey(b.title)),
      },
    );
    final padding = widget.wide ? MesaSpace.page : MesaSpace.card;
    return Column(
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(
            padding,
            widget.wide ? 24 : 8,
            padding,
            16,
          ),
          child: LayoutBuilder(
            builder: (context, bounds) {
              if (bounds.maxWidth < 330 ||
                  MediaQuery.textScalerOf(context).scale(14) > 18) {
                return Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    ChoiceChip(
                      label: const Text('Mi recetario'),
                      selected: !explore,
                      onSelected: (_) => showDiscovery(false),
                    ),
                    ChoiceChip(
                      label: const Text('Descubrir'),
                      selected: explore,
                      onSelected: (_) => showDiscovery(true),
                    ),
                  ],
                );
              }
              final colors = Theme.of(context).colorScheme;
              return Container(
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  color: colors.surface,
                  borderRadius: BorderRadius.circular(32),
                ),
                child: Row(
                  children: [
                    for (final discovering in [false, true])
                      Expanded(
                        child: Semantics(
                          selected: explore == discovering,
                          button: true,
                          child: AnimatedContainer(
                            duration: MesaMotion.duration(context),
                            decoration: BoxDecoration(
                              color: explore == discovering
                                  ? colors.primaryContainer
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(28),
                            ),
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(28),
                                onTap: () => showDiscovery(discovering),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 14,
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        discovering
                                            ? Icons.explore_outlined
                                            : Icons.menu_book_outlined,
                                        size: 20,
                                        color: explore == discovering
                                            ? colors.primary
                                            : colors.onSurfaceVariant,
                                      ),
                                      const SizedBox(width: 8),
                                      Flexible(
                                        child: Text(
                                          discovering
                                              ? 'Descubrir'
                                              : 'Mi recetario',
                                          style: TextStyle(
                                            fontWeight: explore == discovering
                                                ? FontWeight.w700
                                                : FontWeight.w500,
                                            color: explore == discovering
                                                ? colors.primary
                                                : colors.onSurfaceVariant,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
        Expanded(
          child: explore
              ? DiscoverRecipes(
                  store: s,
                  onEdit: widget.onEdit,
                  timers: widget.timers,
                )
              : CustomScrollView(
                  slivers: [
                    SliverPadding(
                      padding: EdgeInsets.symmetric(horizontal: padding),
                      sliver: SliverToBoxAdapter(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            MesaPageHeader(
                              title: 'Tu recetario',
                              subtitle:
                                  '${visible.length} ${visible.length == 1 ? 'receta' : 'recetas'}',
                              action: TextButton.icon(
                                onPressed: filters,
                                icon: const Icon(Icons.tune_rounded, size: 20),
                                label: const Text('Filtros'),
                              ),
                            ),
                            TextField(
                              controller: search,
                              onChanged: (v) => setState(() => query = v),
                              decoration: InputDecoration(
                                hintText: 'Receta, ingredientes o notas',
                                prefixIcon: const Icon(Icons.search),
                                suffixIcon: query.isEmpty
                                    ? null
                                    : IconButton(
                                        tooltip: 'Limpiar búsqueda',
                                        icon: const Icon(Icons.close),
                                        onPressed: () {
                                          search.clear();
                                          setState(() => query = '');
                                        },
                                      ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                FilterChip(
                                  label: const Text('Favoritas'),
                                  avatar: const Icon(
                                    Icons.favorite_outline_rounded,
                                    size: 18,
                                  ),
                                  selected: favorites,
                                  onSelected: (value) =>
                                      setState(() => favorites = value),
                                ),
                                FilterChip(
                                  label: const Text('Hasta 30 min'),
                                  avatar: const Icon(
                                    Icons.schedule_rounded,
                                    size: 18,
                                  ),
                                  selected: maxMinutes == 30,
                                  onSelected: (value) => setState(
                                    () => maxMinutes = value ? 30 : null,
                                  ),
                                ),
                              ],
                            ),
                            if (category != null ||
                                catalog != null ||
                                tag != null ||
                                favorites ||
                                maxMinutes != null ||
                                query.isNotEmpty ||
                                exclusion.text.isNotEmpty)
                              TextButton(
                                onPressed: () {
                                  search.clear();
                                  exclusion.clear();
                                  setState(() {
                                    category = catalog = tag = null;
                                    favorites = false;
                                    maxMinutes = null;
                                    query = '';
                                  });
                                },
                                child: const Text('Limpiar todos los filtros'),
                              ),
                            const SizedBox(height: 10),
                          ],
                        ),
                      ),
                    ),
                    if (visible.isEmpty)
                      SliverPadding(
                        padding: const EdgeInsets.only(bottom: 100),
                        sliver: SliverToBoxAdapter(
                          child: Empty(
                            illustration: all.isEmpty
                                ? const MesaBrandMark(size: 72)
                                : null,
                            icon: Icons.menu_book_outlined,
                            title: all.isEmpty
                                ? 'Tu cocina empieza aquí'
                                : 'No hay recetas con esos filtros',
                            text: all.isEmpty
                                ? 'Guarda una receta familiar o descubre\nlos catálogos abiertos.'
                                : 'Prueba otro ingrediente o limpia los filtros.',
                          ),
                        ),
                      )
                    else if (compact)
                      SliverPadding(
                        padding: EdgeInsets.fromLTRB(padding, 0, padding, 100),
                        sliver: SliverList.builder(
                          itemCount: visible.length,
                          itemBuilder: (c, i) => Card(
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 8,
                              ),
                              leading: const Icon(Icons.restaurant_menu),
                              title: Text(visible[i].title),
                              subtitle: Text(
                                '${visible[i].data['minutes'] == null || visible[i].data['minutes'] == 0 ? 'Tiempo pendiente' : '${visible[i].data['minutes']} min'} · ${recipeYieldText(visible[i].data)}',
                              ),
                              trailing: IconButton(
                                tooltip: 'Favorita',
                                icon: Icon(
                                  s.favorite(visible[i].id)
                                      ? Icons.favorite
                                      : Icons.favorite_border,
                                ),
                                onPressed: () => s.toggleFavorite(visible[i]),
                              ),
                              onTap: () => widget.onOpen(visible[i]),
                            ),
                          ),
                        ),
                      )
                    else
                      SliverPadding(
                        padding: EdgeInsets.fromLTRB(padding, 0, padding, 100),
                        sliver: SliverLayoutBuilder(
                          builder: (c, bounds) => SliverGrid.builder(
                            itemCount: visible.length,
                            gridDelegate:
                                SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: bounds.crossAxisExtent < 600
                                      ? (bounds.crossAxisExtent >= 400 &&
                                                MediaQuery.textScalerOf(context)
                                                        .scale(17) <=
                                                    22
                                            ? 2
                                            : 1)
                                      : (bounds.crossAxisExtent / 250)
                                            .floor()
                                            .clamp(2, 4),
                                  mainAxisSpacing: 16,
                                  crossAxisSpacing: 16,
                                  mainAxisExtent:
                                      (bounds.crossAxisExtent < 600
                                          ? 280
                                          : 300) +
                                      (MediaQuery.textScalerOf(context)
                                                  .scale(17) -
                                              17) *
                                          5,
                                ),
                            itemBuilder: (c, i) => RecipeCard(
                              entry: visible[i],
                              favorite: s.favorite(visible[i].id),
                              onFavorite: () => s.toggleFavorite(visible[i]),
                              onTap: () => widget.onOpen(visible[i]),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

// Discovery has one country filter and federates all licensed catalogues.
