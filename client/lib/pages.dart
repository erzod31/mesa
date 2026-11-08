import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform;
import 'package:qr_flutter/qr_flutter.dart';

import 'models.dart';
import 'input_files.dart';
import 'measurements.dart';
import 'recipe_presentation.dart';
import 'recipe_opening.dart';
import 'translation.dart';
import 'photos.dart';
import 'catalogs.dart';
import 'store.dart';
import 'dialogs.dart';
import 'timers.dart';
import 'organization.dart';
import 'ui.dart' show Empty, guard, label, message;
import 'updates.dart';
import 'design.dart';
import 'action_menu.dart';

Future<bool> confirm(BuildContext context, String title, String text) async =>
    await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(title),
        content: Text(text),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Continuar'),
          ),
        ],
      ),
    ) ??
    false;

class RecipeView extends StatefulWidget {
  const RecipeView({
    super.key,
    required this.store,
    required this.timers,
    required this.id,
    required this.onEdit,
    this.onClose,
    this.onExpand,
    this.expanded = false,
  });
  final Cookbook store;
  final KitchenTimers timers;
  final String id;
  final VoidCallback onEdit;
  final VoidCallback? onClose;
  final VoidCallback? onExpand;
  final bool expanded;
  @override
  State<RecipeView> createState() => _RecipeViewState();
}

class _RecipeViewState extends State<RecipeView> {
  @override
  void initState() {
    super.initState();
    widget.store.addListener(updateReadingTranslation);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      updateReadingTranslation();
      recoverSourcePhotos();
    });
  }

  RecipeOpening? readingTranslation;
  String? readingInput;
  void translationChanged() {
    if (mounted) setState(() {});
  }

  void updateReadingTranslation() {
    if (!mounted) return;
    final recipe = widget.store.get(widget.id);
    final input = recipe == null || recipe.deleted
        ? null
        : jsonEncode(recipe.data);
    if (input == readingInput) return;
    readingTranslation?.removeListener(translationChanged);
    readingTranslation?.dispose();
    readingTranslation = null;
    readingInput = input;
    if (recipe != null &&
        !recipe.deleted &&
        recipeLanguage(recipe.data) != 'es' &&
        canTranslateRecipe(recipe.data)) {
      // Translate the reading view; edits and family data remain unchanged until explicitly applied.
      readingTranslation = RecipeOpening(
        cached: recipe.copyData(),
        requireCachedPhoto: false,
        loadDetail: (_) async => recipe.copyData(),
        remember: (_) async {},
        translate: (value, {bool force = false}) =>
            widget.store.translateImportedRecipe(value, force: force),
      );
      readingTranslation!.addListener(translationChanged);
      unawaited(readingTranslation!.start());
    }
    translationChanged();
  }

  Future<void> recoverSourcePhotos() async {
    final store = widget.store;
    final initial = store.get(widget.id);
    if (!store.editable ||
        initial == null ||
        recipePhotos(initial.data).isNotEmpty) {
      return;
    }
    final origin = initial.data['origin'];
    if (origin is! Map || origin['provider'] != 'wiki-es') {
      return;
    }
    try {
      final result = await CatalogApi(store.client).detail(
        CatalogItem(
          id: origin['id'],
          title: initial.title,
          provider: 'wiki-es',
        ),
      );
      if (!mounted) {
        return;
      }
      final current = store.get(widget.id);
      if (current == null ||
          current.deleted ||
          recipePhotos(current.data).isNotEmpty ||
          current.data['origin']?['id'] != origin['id']) {
        return;
      }
      await store.save('recipe', {
        ...current.copyData(),
        'photos': result['photos'] ?? [],
      }, id: current.id);
    } catch (_) {
      /* Preserve the recipe; the editor provides an explicit retry. */
    }
  }

  double? portions;
  bool originalMeasures = false;
  final scroll = ScrollController();
  final ingredientKey = GlobalKey(), preparationKey = GlobalKey();
  final prepared = <int>{};

  @override
  void didUpdateWidget(covariant RecipeView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.store != widget.store) {
      oldWidget.store.removeListener(updateReadingTranslation);
      widget.store.addListener(updateReadingTranslation);
    }
    if (oldWidget.id != widget.id || oldWidget.store != widget.store) {
      readingInput = null;
      readingTranslation?.removeListener(translationChanged);
      readingTranslation?.dispose();
      readingTranslation = null;
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => updateReadingTranslation(),
      );
      portions = null;
      originalMeasures = false;
      prepared.clear();
      if (scroll.hasClients) scroll.jumpTo(0);
    }
  }

  @override
  void dispose() {
    widget.store.removeListener(updateReadingTranslation);
    readingTranslation?.removeListener(translationChanged);
    readingTranslation?.dispose();
    scroll.dispose();
    super.dispose();
  }

  void jump(GlobalKey key) {
    final target = key.currentContext;
    if (target != null) {
      Scrollable.ensureVisible(
        target,
        duration: const Duration(milliseconds: 250),
      );
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.store,
    builder: (c, _) {
      final stored = widget.store.get(widget.id);
      if (stored == null || stored.deleted) {
        return const Empty(
          icon: Icons.menu_book,
          title: 'Receta en la papelera',
          text: 'Puedes recuperarla desde Mi espacio.',
        );
      }
      final translated = readingInput == jsonEncode(stored.data)
          ? readingTranslation?.data
          : null;
      final e = translated == null
          ? stored
          : Entry(stored.id, stored.kind, stored.revision, translated);
      final s = widget.store;
      final base = (e.data['servings'] as num? ?? 4).toDouble();
      final n = portions ?? base;
      final ingredients = presentedIngredients(
        e.data,
        n / base,
        originalMeasures: originalMeasures,
      );
      final steps = recipeDisplayLines(
        e.data,
        'steps',
        originalMeasures: originalMeasures,
      );
      void cook() => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => CookingPage(
            store: s,
            timers: widget.timers,
            recipe: e,
            portions: n,
            initialChecked: prepared,
          ),
        ),
      );
      void buy() => guard(context, () async {
        await addIngredients(s, e, n, 'recipe:${e.id}');
        if (context.mounted) {
          message(context, 'Ingredientes añadidos a Compra.');
        }
      });
      final ingredientSection = RecipeSection(
        key: ingredientKey,
        title: 'Ingredientes',
        icon: Icons.checklist,
        trailing: Text(
          '${prepared.where((i) => i < ingredients.length).length}/${ingredients.length} preparados',
        ),
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(recipeYieldUnit(e.data)),
              IconButton(
                tooltip: 'Menos ${recipeYieldUnit(e.data)}',
                onPressed: n > 1
                    ? () => setState(() => portions = n - 1)
                    : null,
                icon: const Icon(Icons.remove_circle_outline),
              ),
              Text(
                '${n == n.roundToDouble() ? n.toInt() : n}',
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                ),
              ),
              IconButton(
                tooltip: 'Más ${recipeYieldUnit(e.data)}',
                onPressed: n < 10000
                    ? () => setState(() => portions = n + 1)
                    : null,
                icon: const Icon(Icons.add_circle_outline),
              ),
              if (n != base)
                TextButton(
                  onPressed: () => setState(() => portions = null),
                  child: const Text('Restablecer'),
                ),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            'Marca los ingredientes preparados.',
            style: TextStyle(fontSize: 13, height: 1.5),
          ),
          const SizedBox(height: 12),
          for (var i = 0; i < ingredients.length; i++) ...[
            if (i > 0) const Divider(height: 1),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: Text(
                ingredients[i],
                style: TextStyle(
                  fontSize: 17,
                  height: 1.5,
                  decoration: prepared.contains(i)
                      ? TextDecoration.lineThrough
                      : null,
                ),
              ),
              value: prepared.contains(i),
              onChanged: (value) => setState(() {
                if (value == true) {
                  prepared.add(i);
                } else {
                  prepared.remove(i);
                }
              }),
            ),
          ],
        ],
      );
      final preparationSection = RecipeSection(
        key: preparationKey,
        title: 'Preparación',
        icon: Icons.restaurant_menu,
        children: [
          for (var i = 0; i < steps.length; i++) ...[
            if (i > 0)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Divider(height: 1),
              ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor: Theme.of(context)
                      .colorScheme
                      .secondaryContainer,
                  foregroundColor: Theme.of(context)
                      .colorScheme
                      .onSecondaryContainer,
                  child: Text('${i + 1}', style: const TextStyle(fontSize: 14)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: SelectableText(
                    steps[i],
                    style: const TextStyle(fontSize: 17, height: 1.65),
                  ),
                ),
              ],
            ),
          ],
          if (steps.isEmpty)
            const Text('Añade los pasos desde Editar para empezar a cocinar.'),
        ],
      );
      return LayoutBuilder(
        builder: (context, bounds) {
          final inset = MesaSpace.inset(bounds.maxWidth);
          final promoteBuy =
              s.editable &&
              bounds.maxWidth >= 700 &&
              MediaQuery.textScalerOf(context).scale(17) <= 22;
          final promoteEdit =
              s.editable &&
              bounds.maxWidth >= 1000 &&
              MediaQuery.textScalerOf(context).scale(17) <= 22;
          return Column(
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(inset, 12, inset, 0),
                child: Material(
                  borderRadius: BorderRadius.circular(28),
                  color: Theme.of(context).colorScheme.surface,
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Wrap(
                      spacing: 12,
                      runSpacing: 8,
                      children: [
                        TextButton.icon(
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            textStyle: const TextStyle(
                              fontFamily: 'Segoe UI',
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          onPressed: () => jump(ingredientKey),
                          icon: bounds.maxWidth >= 400
                              ? const Icon(Icons.checklist_rounded, size: 18)
                              : null,
                          label: const Text('Ver ingredientes'),
                        ),
                        TextButton.icon(
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            textStyle: const TextStyle(
                              fontFamily: 'Segoe UI',
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          onPressed: () => jump(preparationKey),
                          icon: bounds.maxWidth >= 400
                              ? const Icon(
                                  Icons.format_list_numbered_rounded,
                                  size: 18,
                                )
                              : null,
                          label: const Text('Ver preparación'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  controller: scroll,
                  child: ReadingWidth(
                    child: Padding(
                      padding: EdgeInsets.all(inset),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Semantics(
                                  header: true,
                                  child: Text(
                                    e.title,
                                    style: const TextStyle(
                                      fontSize: 28,
                                      height: 1.2,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ),
                              if (widget.onExpand != null)
                                IconButton(
                                  tooltip: widget.expanded
                                      ? 'Volver al catálogo'
                                      : 'Ampliar receta',
                                  onPressed: widget.onExpand,
                                  icon: Icon(
                                    widget.expanded
                                        ? Icons.close_fullscreen
                                        : Icons.open_in_full,
                                  ),
                                ),
                              if (widget.onClose != null)
                                IconButton(
                                  tooltip: 'Cerrar receta',
                                  onPressed: widget.onClose,
                                  icon: const Icon(Icons.close),
                                ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Text(
                            '${(e.data['minutes'] as int? ?? 0) > 0 ? "${e.data['minutes']} min · " : ""}${recipeYieldText(e.data)}${(e.data['rating'] as int? ?? 0) > 0 ? " · ${e.data['rating']}/5" : ""}',
                            style: TextStyle(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 16),
                          PhotoGallery(photos: recipePhotos(e.data)),
                          if (readingTranslation?.translating == true) ...[
                            const Text('Traduciendo al español…'),
                            const LinearProgressIndicator(),
                          ],
                          if (readingTranslation?.translationFailure !=
                              null) ...[
                            const Text(
                              'No se pudo traducir. Se muestra el original.',
                            ),
                            TextButton(
                              onPressed: readingTranslation!.retryTranslation,
                              child: const Text('Reintentar traducción'),
                            ),
                            ExpansionTile(
                              title: const Text('Detalle del problema'),
                              children: [
                                Text(readingTranslation!.translationFailure!),
                              ],
                            ),
                          ],
                          const SizedBox(height: 16),
                          if (missingQuantities(e.data).isNotEmpty) ...[
                            const SizedBox(height: 24),
                            RecipeSection(
                              title: 'Cantidades pendientes',
                              icon: Icons.info_outline,
                              children: [
                                Text(missingQuantities(e.data).join(', ')),
                                if (s.editable)
                                  TextButton(
                                    onPressed: widget.onEdit,
                                    child: const Text(
                                      'Completar cantidades o recuperar fotos',
                                    ),
                                  ),
                              ],
                            ),
                          ],
                          if (e.lines('category_ids').isNotEmpty ||
                              e.lines('catalog_ids').isNotEmpty) ...[
                            const SizedBox(height: 16),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                for (final type in ['category', 'catalog'])
                                  for (final group
                                      in recipeGroups(s, type).where(
                                        (g) => e
                                            .lines(groupField(type))
                                            .contains(g.id),
                                      ))
                                    Chip(label: Text(group.title)),
                              ],
                            ),
                          ],
                          const SizedBox(height: 24),
                          if (bounds.maxWidth >= 900)
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(flex: 4, child: ingredientSection),
                                const SizedBox(width: 24),
                                Expanded(flex: 6, child: preparationSection),
                              ],
                            )
                          else ...[
                            ingredientSection,
                            const SizedBox(height: 24),
                            preparationSection,
                          ],
                          const SizedBox(height: 24),
                          RecipeOptions(
                            data: e.data,
                            originalMeasures: originalMeasures,
                            onMeasuresChanged: (value) =>
                                setState(() => originalMeasures = value),
                            translationAction:
                                s.editable &&
                                    canTranslateRecipe(e.data) &&
                                    readingTranslation?.translating != true
                                ? RecipeTranslationAction(
                                    data: e.data,
                                    translate: () => s.translateImportedRecipe(
                                      e.copyData(),
                                      force: true,
                                    ),
                                    apply: (value) async {
                                      final current = s.get(e.id);
                                      if (current == null ||
                                          current.deleted ||
                                          jsonEncode(current.data) !=
                                              jsonEncode(stored.data)) {
                                        throw Exception(
                                          'La receta cambió mientras se traducía. Vuelve a abrirla antes de aplicar el resultado.',
                                        );
                                      }
                                      await s.save('recipe', value, id: e.id);
                                    },
                                  )
                                : null,
                          ),
                          const SizedBox(height: 24),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              Material(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(28),
                ),
                color: Theme.of(context).colorScheme.surface,
                child: SafeArea(
                  top: false,
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: inset,
                      vertical: 12,
                    ),
                    child: Wrap(
                      spacing: 12,
                      runSpacing: 8,
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        FilledButton.icon(
                          onPressed: steps.isEmpty ? null : cook,
                          icon: const Icon(Icons.play_arrow),
                          label: const Text('Paso a paso'),
                        ),
                        if (promoteBuy)
                          OutlinedButton.icon(
                            onPressed: ingredients.isEmpty ? null : buy,
                            icon: const Icon(Icons.shopping_bag_outlined),
                            label: const Text('A la compra'),
                          ),
                        if (promoteEdit)
                          TextButton.icon(
                            onPressed: widget.onEdit,
                            icon: const Icon(Icons.edit_outlined),
                            label: const Text('Editar'),
                          ),
                        MesaActionMenuButton(
                          title: 'Acciones de receta',
                          label: 'Más acciones',
                          tooltip: 'Más opciones de receta',
                          onSelected: (value) async {
                            if (value == 'edit') widget.onEdit();
                            if (value == 'favorite') {
                              await s.toggleFavorite(e);
                              return;
                            }
                            if (value == 'buy') buy();
                            if (value == 'plan') {
                              await planDialog(
                                context,
                                s,
                                recipe: e,
                                portions: n,
                              );
                              return;
                            }
                            if (value == 'history') {
                              await historyDialog(context, s, e);
                            }
                            if (value == 'delete' && context.mounted) {
                              await guard(context, () async {
                                if (await confirm(
                                  context,
                                  '¿Mover a la papelera?',
                                  'La receta se podrá recuperar en Mi espacio.',
                                )) {
                                  await s.delete(e);
                                }
                              });
                            }
                          },
                          actions: [
                            if (s.editable && !promoteBuy)
                              MesaMenuAction(
                                id: 'buy',
                                label: 'A la compra',
                                icon: Icons.shopping_bag_outlined,
                                group: 'Organizar',
                                enabled: ingredients.isNotEmpty,
                              ),
                            if (s.editable)
                              const MesaMenuAction(
                                id: 'plan',
                                label: 'Planificar',
                                icon: Icons.calendar_month_outlined,
                                group: 'Organizar',
                              ),
                            if (s.editable && !promoteEdit)
                              const MesaMenuAction(
                                id: 'edit',
                                label: 'Editar',
                                icon: Icons.edit_outlined,
                                group: 'Receta',
                              ),
                            MesaMenuAction(
                              id: 'favorite',
                              label: s.favorite(e.id)
                                  ? 'Quitar de favoritas'
                                  : 'Añadir a favoritas',
                              icon: Icons.favorite_outline,
                              group: 'Receta',
                            ),
                            const MesaMenuAction(
                              id: 'history',
                              label: 'Historial',
                              icon: Icons.history,
                              group: 'Consulta',
                            ),
                            if (s.editable)
                              const MesaMenuAction(
                                id: 'delete',
                                label: 'Mover a la papelera',
                                icon: Icons.delete_outline,
                                group: 'Papelera',
                                destructive: true,
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      );
    },
  );
}

Future<void> addIngredients(
  Cookbook s,
  Entry recipe,
  double portions,
  String source,
) async {
  final base = (recipe.data['servings'] as num? ?? 4).toDouble();
  final lines = recipe.lines('ingredients');
  for (var i = 0; i < lines.length; i++) {
    final id = '$source:$i';
    final old = s.get(id);
    if (old != null && !old.deleted) continue;
    await s.save('shopping', {
      'name': presentedIngredients(recipe.data, portions / base)[i],
      'checked': false,
      'section': 'Ingredientes',
      'source': source,
      'recipe_title': recipe.title,
    }, id: id);
  }
}

class CookingPage extends StatefulWidget {
  const CookingPage({
    super.key,
    required this.store,
    this.timers,
    required this.recipe,
    required this.portions,
    this.initialChecked = const {},
  });
  final Cookbook store;
  final KitchenTimers? timers;
  final Entry recipe;
  final double portions;
  final Set<int> initialChecked;
  @override
  State<CookingPage> createState() => _CookingPageState();
}

class _CookingPageState extends State<CookingPage> {
  int step = 0;
  final scroll = ScrollController();
  Set<int> checked = {};
  bool awake = true;
  bool originalMeasures = false;
  String get key => 'cooking:${widget.recipe.id}';
  @override
  void initState() {
    super.initState();
    checked = {...widget.initialChecked};
    try {
      final saved = jsonDecode(widget.store.prefs[key] ?? '{}');
      if (saved['revision'] == widget.recipe.revision &&
          (saved['steps'] == null ||
              saved['steps'] == jsonEncode(widget.recipe.lines('steps'))) &&
          widget.recipe.lines('steps').isNotEmpty) {
        step = (saved['step'] as int? ?? 0).clamp(
          0,
          widget.recipe.lines('steps').length - 1,
        );
        checked = {
          ...Set<int>.from(saved['checked'] ?? []),
          ...widget.initialChecked,
        };
      }
    } catch (_) {}
    KitchenTimers.awake(true);
  }

  void persist() {
    widget.store.preference(
      key,
      jsonEncode({
        'revision': widget.recipe.revision,
        'steps': jsonEncode(widget.recipe.lines('steps')),
        'step': step,
        'checked': checked.toList(),
      }),
    );
  }

  void selectStep(int value) {
    setState(() => step = value);
    if (scroll.hasClients) scroll.jumpTo(0);
    persist();
  }

  Future<void> stepIndex(List<String> steps) async {
    final chosen = await showDialog<int>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Todos los pasos'),
        content: SizedBox(
          width: 560,
          height: MediaQuery.sizeOf(c).height * .55,
          child: ListView.builder(
            itemCount: steps.length,
            itemBuilder: (c, i) => ListTile(
              selected: i == step,
              leading: Text('${i + 1}'),
              title: Text(
                steps[i],
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
              onTap: () => Navigator.pop(c, i),
            ),
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
    if (chosen != null && mounted) selectStep(chosen);
  }

  @override
  void dispose() {
    KitchenTimers.awake(false);
    scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final steps = recipeDisplayLines(
      widget.recipe.data,
      'steps',
      originalMeasures: originalMeasures,
    );
    final base = (widget.recipe.data['servings'] as num? ?? 4).toDouble();
    final ingredients = presentedIngredients(
      widget.recipe.data,
      widget.portions / base,
      originalMeasures: originalMeasures,
    );
    final timers = widget.timers;
    if (steps.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Paso a paso')),
        body: const Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Esta receta todavía no tiene instrucciones. Completa la preparación para cocinar paso a paso.',
          ),
        ),
      );
    }
    step = step.clamp(0, steps.length - 1);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Paso a paso'),
        actions: [
          IconButton(
            tooltip: 'Ver todos los pasos',
            onPressed: () => stepIndex(steps),
            icon: const Icon(Icons.format_list_numbered),
          ),
          IconButton(
            tooltip: originalMeasures
                ? 'Usar medidas europeas'
                : 'Ver medidas originales',
            onPressed: () =>
                setState(() => originalMeasures = !originalMeasures),
            icon: const Icon(Icons.straighten),
          ),
          IconButton(
            tooltip: awake
                ? 'Permitir apagar pantalla'
                : 'Mantener pantalla encendida',
            onPressed: () {
              setState(() => awake = !awake);
              KitchenTimers.awake(awake);
            },
            icon: Icon(awake ? Icons.light_mode : Icons.bedtime_outlined),
          ),
        ],
      ),
      bottomNavigationBar: Material(
        color: Theme.of(context).colorScheme.surface,
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: ReadingWidth(
              maxWidth: 900,
              child: OverflowBar(
                spacing: 12,
                overflowSpacing: 12,
                alignment: MainAxisAlignment.spaceBetween,
                overflowAlignment: OverflowBarAlignment.end,
                children: [
                  OutlinedButton.icon(
                    onPressed: step == 0
                        ? null
                        : () {
                            selectStep(step - 1);
                          },
                    icon: const Icon(Icons.arrow_back),
                    label: const Text('Anterior'),
                  ),
                  FilledButton.icon(
                    onPressed: () {
                      if (step < steps.length - 1) {
                        selectStep(step + 1);
                      } else {
                        step = 0;
                        checked.clear();
                        persist();
                        message(
                          context,
                          timers != null && timers.items.isNotEmpty
                              ? '¡Receta terminada! Tus temporizadores siguen activos.'
                              : '¡Receta terminada!',
                        );
                        Navigator.pop(context);
                      }
                    },
                    icon: const Icon(Icons.arrow_forward),
                    label: Text(
                      step == steps.length - 1 ? 'Terminar' : 'Siguiente',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: ListView(
            controller: scroll,
            padding: const EdgeInsets.all(24),
            children: [
              Text(
                widget.recipe.title,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              Text(
                'PASO ${step + 1} DE ${steps.length}',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.3,
                ),
              ),
              const SizedBox(height: 18),
              Card(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: AnimatedSwitcher(
                    duration: MesaMotion.duration(context),
                    child: Text(
                      steps[step],
                      key: ValueKey(step),
                      style: const TextStyle(fontSize: 28, height: 1.5),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              LinearProgressIndicator(
                value: (step + 1) / steps.length,
                minHeight: 6,
                borderRadius: BorderRadius.circular(8),
              ),
              if (timers != null && stepMinutes(steps[step]).isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final minutes in stepMinutes(steps[step]))
                        ActionChip(
                          avatar: const Icon(Icons.timer_outlined, size: 18),
                          label: Text('Temporizador · $minutes min'),
                          onPressed: () => timerDialog(
                            context,
                            timers,
                            initialMinutes: minutes,
                            initialName:
                                '${widget.recipe.title} · paso ${step + 1}',
                          ),
                        ),
                    ],
                  ),
                ),
              const SizedBox(height: 24),
              if (timers != null)
                OutlinedButton.icon(
                  onPressed: () => timerDialog(context, timers),
                  icon: const Icon(Icons.timer_outlined),
                  label: const Text('Temporizadores'),
                ),
              if (timers != null) TimerList(timers: timers),
              label('Ingredientes preparados'),
              for (var i = 0; i < ingredients.length; i++)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(ingredients[i]),
                  value: checked.contains(i),
                  onChanged: (v) {
                    setState(() {
                      if (v == true) {
                        checked.add(i);
                      } else {
                        checked.remove(i);
                      }
                    });
                    persist();
                  },
                ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }
}

class TimerList extends StatelessWidget {
  const TimerList({super.key, required this.timers});
  final KitchenTimers timers;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: timers,
    builder: (c, _) => Column(
      children: [
        if (timers.warning.isNotEmpty)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(timers.warning),
          ),
        for (final t in timers.items)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          t['name'],
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      Text(
                        timers.remaining(t) <= 0
                            ? '¡Terminado!'
                            : '${timers.remaining(t) ~/ 60}:${(timers.remaining(t) % 60).toString().padLeft(2, '0')}',
                        style: const TextStyle(fontSize: 24),
                      ),
                      IconButton(
                        tooltip: 'Eliminar temporizador',
                        onPressed: () => timers.remove(t),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      TextButton.icon(
                        onPressed: () => timers.toggle(t),
                        icon: Icon(
                          t['paused'] == true ? Icons.play_arrow : Icons.pause,
                        ),
                        label: Text(t['paused'] == true ? 'Seguir' : 'Pausar'),
                      ),
                      TextButton(
                        onPressed: () => timers.minute(t),
                        child: const Text('+1 min'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
      ],
    ),
  );
}

Future<void> timerDialog(
  BuildContext context,
  KitchenTimers timers, {
  int initialMinutes = 10,
  String initialName = '',
}) async {
  final name = TextEditingController(
        text: initialName.isEmpty ? 'Cocina' : initialName,
      ),
      minutes = TextEditingController(text: '$initialMinutes');
  await showDialog(
    context: context,
    builder: (c) => ManagedDialogBuilder(
      controllers: [name, minutes],
      builder: (c, _) => AlertDialog(
        title: const Text('Nuevo temporizador'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: name,
              decoration: const InputDecoration(labelText: 'Nombre'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: minutes,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Minutos · 1 a 1440',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => guard(c, () async {
              final n = int.tryParse(minutes.text);
              if (n == null || n < 1 || n > 1440) {
                throw Exception('Introduce entre 1 y 1440 minutos.');
              }
              await timers.add(
                name.text.trim().isEmpty ? 'Cocina' : name.text.trim(),
                n * 60,
              );
              if (c.mounted) Navigator.pop(c);
            }),
            child: const Text('Iniciar'),
          ),
        ],
      ),
    ),
  );
}

const weekdays = [
  'Lunes',
  'Martes',
  'Miércoles',
  'Jueves',
  'Viernes',
  'Sábado',
  'Domingo',
];

class WeekPage extends StatefulWidget {
  const WeekPage({super.key, required this.store});
  final Cookbook store;
  @override
  State<WeekPage> createState() => _WeekPageState();
}

class _WeekPageState extends State<WeekPage> {
  late DateTime monday;
  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    monday = DateTime(
      now.year,
      now.month,
      now.day,
    ).subtract(Duration(days: now.weekday - 1));
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.store;
    return ListView(
      padding: EdgeInsets.fromLTRB(
        MesaSpace.inset(MediaQuery.sizeOf(context).width),
        24,
        MesaSpace.inset(MediaQuery.sizeOf(context).width),
        80,
      ),
      children: [
        const MesaPageHeader(
          title: 'Menú semanal',
          subtitle: 'Organiza lo que vais a cocinar',
        ),
        Row(
          children: [
            IconButton(
              tooltip: 'Semana anterior',
              onPressed: () => setState(
                () => monday = monday.subtract(const Duration(days: 7)),
              ),
              icon: const Icon(Icons.chevron_left),
            ),
            Expanded(
              child: Text(
                '${monday.day}/${monday.month} – ${monday.add(const Duration(days: 6)).day}/${monday.add(const Duration(days: 6)).month}/${monday.year}',
                textAlign: TextAlign.center,
              ),
            ),
            IconButton(
              tooltip: 'Semana siguiente',
              onPressed: () =>
                  setState(() => monday = monday.add(const Duration(days: 7))),
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
        if (s.editable)
          OutlinedButton.icon(
            onPressed: () => guard(context, () async {
              var count = 0;
              for (final meal
                  in s
                      .of('meal')
                      .where(
                        (e) =>
                            e.data['date'].compareTo(dayKey(monday)) >= 0 &&
                            e.data['date'].compareTo(
                                  dayKey(monday.add(const Duration(days: 6))),
                                ) <=
                                0,
                      )) {
                final recipe = s.get(meal.data['recipe_id'] ?? '');
                if (recipe != null && !recipe.deleted) {
                  await addIngredients(
                    s,
                    recipe,
                    (meal.data['servings'] as num? ??
                            recipe.data['servings'] ??
                            4)
                        .toDouble(),
                    'meal:${meal.id}',
                  );
                  count++;
                }
              }
              if (context.mounted) {
                message(
                  context,
                  'Ingredientes de $count platos añadidos. Los repetidos se conservan como líneas separadas.',
                );
              }
            }),
            icon: const Icon(Icons.shopping_bag_outlined),
            label: const Text('Añadir semana a la compra'),
          ),
        for (var i = 0; i < 7; i++)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${weekdays[i]} · ${monday.add(Duration(days: i)).day}/${monday.add(Duration(days: i)).month}',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (s.editable)
                    TextButton.icon(
                      onPressed: () => planDialog(
                        context,
                        s,
                        date: monday.add(Duration(days: i)),
                      ),
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('Añadir plato'),
                    ),
                  for (final slot in ['Comida', 'Cena']) ...[
                    for (final meal
                        in s
                            .of('meal')
                            .where(
                              (e) =>
                                  e.data['date'] ==
                                      dayKey(monday.add(Duration(days: i))) &&
                                  e.data['slot'] == slot,
                            ))
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          slot == 'Comida'
                              ? Icons.light_mode_outlined
                              : Icons.nightlight_outlined,
                        ),
                        title: Text('${meal.data['title']}'),
                        subtitle: Text(
                          '$slot · ${meal.data['servings'] ?? 4} raciones',
                        ),
                        trailing: s.editable
                            ? IconButton(
                                tooltip: 'Quitar plato',
                                onPressed: () => guard(context, () async {
                                  if (await confirm(
                                    context,
                                    '¿Quitar del menú?',
                                    'Los ingredientes ya añadidos a la compra se conservan para que puedas revisarlos.',
                                  )) {
                                    await s.delete(meal);
                                  }
                                }),
                                icon: const Icon(Icons.remove_circle_outline),
                              )
                            : null,
                      ),
                  ],
                ],
              ),
            ),
          ),
      ],
    );
  }
}

Future<void> planDialog(
  BuildContext context,
  Cookbook s, {
  Entry? recipe,
  double? portions,
  DateTime? date,
  String slot = 'Comida',
}) async {
  final recipes = s.of('recipe')..sort((a, b) => a.title.compareTo(b.title));
  if (recipes.isEmpty) {
    message(context, 'Guarda una receta antes de preparar tu menú.');
    return;
  }
  var selected = recipe ?? recipes.first;
  var day = date ?? DateTime.now();
  var period = slot;
  final n = TextEditingController(
    text: '${portions ?? selected.data['servings'] ?? 4}',
  );
  await showDialog(
    context: context,
    builder: (c) => ManagedDialogBuilder(
      controllers: [n],
      builder: (c, set) => AlertDialog(
        title: const Text('Añadir al menú'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 450),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: selected.id,
                isExpanded: true,
                items: recipes
                    .map(
                      (e) => DropdownMenuItem(
                        value: e.id,
                        child: Text(e.title, overflow: TextOverflow.ellipsis),
                      ),
                    )
                    .toList(),
                onChanged: (id) =>
                    set(() => selected = recipes.firstWhere((e) => e.id == id)),
                decoration: const InputDecoration(labelText: 'Receta'),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () async {
                  final picked = await showDatePicker(
                    context: c,
                    initialDate: day,
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2100),
                  );
                  if (c.mounted && picked != null) set(() => day = picked);
                },
                icon: const Icon(Icons.calendar_month),
                label: Text(dayKey(day)),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: period,
                items: ['Comida', 'Cena']
                    .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                    .toList(),
                onChanged: (v) => set(() => period = v!),
                decoration: const InputDecoration(labelText: 'Momento'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: n,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Raciones'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => guard(c, () async {
              final servings = double.tryParse(n.text.replaceAll(',', '.'));
              if (servings == null || servings <= 0 || servings > 10000) {
                throw Exception('Revisa las raciones.');
              }
              await s.save('meal', {
                'recipe_id': selected.id,
                'title': selected.title,
                'date': dayKey(day),
                'slot': period,
                'servings': servings,
              });
              if (c.mounted && ModalRoute.of(c)?.isCurrent == true) {
                Navigator.pop(c);
              }
            }),
            child: const Text('Añadir'),
          ),
        ],
      ),
    ),
  );
}

class ShoppingPage extends StatefulWidget {
  const ShoppingPage({super.key, required this.store});
  final Cookbook store;
  @override
  State<ShoppingPage> createState() => _ShoppingPageState();
}

class _ShoppingPageState extends State<ShoppingPage> {
  bool showChecked = true;
  final name = TextEditingController();
  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.store;
    final items = s.of('shopping')
      ..sort((a, b) {
        final check = (a.data['checked'] == true ? 1 : 0).compareTo(
          b.data['checked'] == true ? 1 : 0,
        );
        return check != 0
            ? check
            : '${a.data['section'] ?? ''} ${a.title}'.compareTo(
                '${b.data['section'] ?? ''} ${b.title}',
              );
      });
    final checked = items.where((e) => e.data['checked'] == true).length;
    return ListView(
      padding: EdgeInsets.fromLTRB(
        MesaSpace.inset(MediaQuery.sizeOf(context).width),
        24,
        MesaSpace.inset(MediaQuery.sizeOf(context).width),
        80,
      ),
      children: [
        MesaPageHeader(
          title: 'Lista de compra',
          subtitle:
              '${items.length - checked} por comprar · $checked comprados',
        ),
        if (items.isNotEmpty) ...[
          LinearProgressIndicator(
            value: checked / items.length,
            minHeight: 8,
            borderRadius: BorderRadius.circular(8),
          ),
          const SizedBox(height: 20),
        ],
        if (s.editable)
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: name,
                  onSubmitted: (_) => add(),
                  decoration: const InputDecoration(
                    labelText: 'Añadir un producto',
                    hintText: 'Leche, 2 litros',
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                tooltip: 'Añadir producto',
                onPressed: add,
                icon: const Icon(Icons.add),
              ),
            ],
          ),
        if (checked > 0)
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Mostrar comprados'),
            value: showChecked,
            onChanged: (v) => setState(() => showChecked = v),
          ),
        if (checked > 0 && s.editable)
          TextButton(
            onPressed: () => guard(context, () async {
              if (await confirm(
                context,
                '¿Retirar productos comprados?',
                'Se moverán a la papelera.',
              )) {
                for (final e in items.where((e) => e.data['checked'] == true)) {
                  await s.delete(e);
                }
              }
            }),
            child: const Text('Retirar comprados'),
          ),
        if (items.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 45),
            child: Empty(
              icon: Icons.shopping_bag_outlined,
              title: 'Todo listo para empezar',
              text: 'Añade productos o lleva los ingredientes\nde una receta a la lista.',
            ),
          ),
        for (final e in items.where(
          (e) => showChecked || e.data['checked'] != true,
        ))
          Card(
            child: Row(
              children: [
                Expanded(
                  child: CheckboxListTile(
                    value: e.data['checked'] == true,
                    onChanged: s.editable
                        ? (v) => guard(
                            context,
                            () => s.save(
                              'shopping',
                              {'checked': v == true},
                              id: e.id,
                              action: 'check',
                            ),
                          )
                        : null,
                    title: Text(
                      e.title,
                      style: TextStyle(
                        decoration: e.data['checked'] == true
                            ? TextDecoration.lineThrough
                            : null,
                      ),
                    ),
                    subtitle: '${e.data['recipe_title'] ?? ''}'.isEmpty
                        ? null
                        : Text(e.data['recipe_title']),
                  ),
                ),
                if (s.editable)
                  IconButton(
                    tooltip: 'Quitar producto',
                    onPressed: () => guard(context, () => s.delete(e)),
                    icon: const Icon(Icons.close),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  void add() => guard(context, () async {
    if (name.text.trim().isEmpty) return;
    if (name.text.length > 1000) throw Exception('Usa un nombre más corto.');
    await widget.store.save('shopping', {
      'name': name.text.trim(),
      'checked': false,
      'section': 'Otros',
    });
    name.clear();
  });
}

class SettingsPage extends StatelessWidget {
  const SettingsPage({
    super.key,
    required this.store,
    required this.timers,
    required this.onExample,
    required this.onImport,
  });
  final Cookbook store;
  final KitchenTimers timers;
  final VoidCallback onExample, onImport;
  @override
  Widget build(BuildContext context) {
    final s = store;
    return ListView(
      padding: EdgeInsets.fromLTRB(
        MesaSpace.inset(MediaQuery.sizeOf(context).width),
        24,
        MesaSpace.inset(MediaQuery.sizeOf(context).width),
        80,
      ),
      children: [
        MesaPageHeader(
          title: 'Mi espacio',
          subtitle:
              '${s.profile} · ${s.role == 'admin'
                  ? 'Administrador'
                  : s.role == 'reader'
                  ? 'Lectura'
                  : 'Puede editar'}',
        ),
        if (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.windows) ...[
          label('Aplicación'),
          OutlinedButton.icon(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => AppUpdatePage(
                  client: s.client,
                  beforeClose: s.flushForAppUpdate,
                ),
              ),
            ),
            icon: const Icon(Icons.system_update_alt),
            label: const Text('Actualizar Mesa'),
          ),
          const Text('Busca nuevas versiones de Mesa para este dispositivo.'),
        ],
        ExpansionTile(
          leading: const Icon(Icons.people_outline_rounded),
          title: const Text('Familia y conexión'),
          children: [
            Text(s.status),
            const SizedBox(height: 12),
            SelectableText(
              s.url.isEmpty
                  ? 'Usa Mesa sin conexión o enlaza el servidor familiar con Tailscale.'
                  : s.url,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: () => connectDialog(context, s),
                  icon: const Icon(Icons.link),
                  label: Text(
                    s.url.isEmpty
                        ? 'Conectar con la familia'
                        : 'Revisar conexión',
                  ),
                ),
                if (s.url.isNotEmpty)
                  OutlinedButton(
                    onPressed: () => s.sync(),
                    child: const Text('Actualizar ahora'),
                  ),
                if (s.role == 'admin')
                  OutlinedButton.icon(
                    onPressed: () => inviteDialog(context, s),
                    icon: const Icon(Icons.person_add_alt),
                    label: const Text('Invitar familiar'),
                  ),
                if (s.role == 'admin')
                  OutlinedButton(
                    onPressed: () => membersDialog(context, s),
                    child: const Text('Miembros'),
                  ),
                if (s.url.isNotEmpty)
                  TextButton(
                    onPressed: () => guard(context, () async {
                      if (await confirm(
                        context,
                        '¿Desconectar este dispositivo?',
                        'Las recetas descargadas quedan aquí. Exporta antes de cambiar de familia. Debes sincronizar los cambios pendientes.',
                      )) {
                        await s.disconnect();
                      }
                    }),
                    child: const Text('Desconectar'),
                  ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 12),
        ExpansionTile(
          leading: const Icon(Icons.inventory_2_outlined),
          title: const Text('Guardar y recuperar'),
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: () => exportDialog(context, s),
                  icon: const Icon(Icons.download),
                  label: const Text('Exportar datos'),
                ),
                if (s.editable)
                  OutlinedButton.icon(
                    onPressed: () => importFile(context, s),
                    icon: const Icon(Icons.upload_file),
                    label: const Text('Importar archivo Mesa'),
                  ),
                if (s.editable)
                  OutlinedButton.icon(
                    onPressed: onImport,
                    icon: const Icon(Icons.content_paste),
                    label: const Text('Pegar receta o enlace'),
                  ),
                OutlinedButton.icon(
                  onPressed: () => trashDialog(context, s),
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Papelera'),
                ),
                if (s.role == 'admin')
                  OutlinedButton.icon(
                    onPressed: () => guard(context, () async {
                      await s.request('POST', '/v1/backup');
                      if (context.mounted) {
                        message(
                          context,
                          'Copia completa guardada en data/backups del ordenador servidor.',
                        );
                      }
                    }),
                    icon: const Icon(Icons.backup_outlined),
                    label: const Text('Copia del servidor'),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            const Text(
              'Las exportaciones contienen recetas y enlaces a fotos, sin claves de acceso. La copia del servidor también conserva miembros e historial. Guarda una copia fuera del ordenador.',
              style: TextStyle(fontSize: 13, height: 1.6),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ExpansionTile(
          leading: const Icon(Icons.palette_outlined),
          title: const Text('Apariencia y ejemplos'),
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Tema oscuro'),
              value: s.dark,
              onChanged: (v) => s.preference('dark', v.toString()),
            ),
            if (s.editable)
              TextButton.icon(
                onPressed: onExample,
                icon: const Icon(Icons.restaurant_menu),
                label: const Text('Añadir tres recetas de ejemplo'),
              ),
          ],
        ),
        const SizedBox(height: 12),
        ExpansionTile(
          leading: const Icon(Icons.timer_outlined),
          title: const Text('Temporizadores'),
          initiallyExpanded: timers.items.isNotEmpty,
          children: [
            OutlinedButton.icon(
              onPressed: () => timerDialog(context, timers),
              icon: const Icon(Icons.timer_outlined),
              label: const Text('Nuevo temporizador'),
            ),
            TimerList(timers: timers),
          ],
        ),
        const SizedBox(height: 12),
        const ExpansionTile(
          leading: Icon(Icons.info_outline_rounded),
          title: Text('Acerca de Mesa'),
          children: [
            Text(
              'Las recetas y los borradores se guardan en este dispositivo. La familia se actualiza al abrir la app y cada 15 segundos mientras está abierta. Tailscale debe estar conectado; el ordenador servidor debe estar encendido. Las raciones y la importación automática requieren una revisión humana.',
              style: TextStyle(height: 1.6),
            ),
          ],
        ),
      ],
    );
  }
}

Future<void> connectDialog(
  BuildContext context,
  Cookbook s, {
  String? server,
  String? code,
}) async {
  final address = TextEditingController(text: server ?? s.url),
      credential = TextEditingController(text: code ?? ''),
      name = TextEditingController(
        text: s.profile == 'Mi recetario' ? '' : s.profile,
      );
  var busy = false;
  String? error;
  await showDialog(
    context: context,
    builder: (c) => ManagedDialogBuilder(
      controllers: [address, credential, name],
      builder: (c, set) => AlertDialog(
        title: const Text('Conectar con la familia'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 450),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Activa Tailscale en el teléfono y usa la dirección HTTPS y el código que te entregue el administrador.',
                ),
                const SizedBox(height: 18),
                TextField(
                  controller: address,
                  decoration: const InputDecoration(
                    labelText: 'Dirección del servidor',
                    hintText: 'https://ordenador.familia.ts.net',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: credential,
                  decoration: const InputDecoration(
                    labelText: 'Código de invitación',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: name,
                  decoration: const InputDecoration(labelText: 'Tu nombre'),
                ),
                if (Platform.isWindows)
                  TextButton.icon(
                    onPressed: () => guard(c, () async {
                      final file = await FilePicker.pickFile(
                        type: FileType.custom,
                        allowedExtensions: ['json'],
                      );
                      if (file == null) return;
                      final config = jsonDecode(
                        utf8
                            .decode(
                              (await readLimitedBytes(
                                file.readAsByteStream(),
                                maxBytes: 32000,
                              )),
                            )
                            .replaceFirst('\uFEFF', ''),
                      );
                      await s.connect(
                        config['url'],
                        config['token'],
                        invitation: false,
                      );
                      if (c.mounted && ModalRoute.of(c)?.isCurrent == true) {
                        Navigator.pop(c);
                      }
                    }),
                    icon: const Icon(Icons.computer),
                    label: const Text('Usar archivo de conexión del ordenador'),
                  ),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      error!,
                      style: TextStyle(color: Theme.of(c).colorScheme.error),
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: busy ? null : () => Navigator.pop(c),
            child: const Text('Cerrar'),
          ),
          FilledButton(
            onPressed: busy
                ? null
                : () async {
                    set(() => busy = true);
                    try {
                      await s.connect(
                        address.text,
                        credential.text,
                        name: name.text,
                      );
                      if (c.mounted && ModalRoute.of(c)?.isCurrent == true) {
                        Navigator.pop(c);
                      }
                    } catch (e) {
                      if (c.mounted && ModalRoute.of(c)?.isCurrent == true) {
                        set(() => error = '$e'.replaceFirst('Exception: ', ''));
                      }
                    } finally {
                      if (c.mounted && ModalRoute.of(c)?.isCurrent == true) {
                        set(() => busy = false);
                      }
                    }
                  },
            child: Text(busy ? 'Conectando…' : 'Conectar'),
          ),
        ],
      ),
    ),
  );
}

Future<void> inviteDialog(BuildContext context, Cookbook s) async {
  final name = TextEditingController(),
      address = TextEditingController(
        text:
            s.prefs['public_url'] ??
            (s.url.startsWith('https://') ? s.url : ''),
      );
  var role = 'editor';
  Map<String, dynamic>? invite;
  String? error;
  bool busy = false;
  await showDialog(
    context: context,
    builder: (c) => ManagedDialogBuilder(
      controllers: [name, address],
      builder: (c, set) => AlertDialog(
        title: const Text('Invitar a un familiar'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: invite == null
                  ? [
                      TextField(
                        controller: name,
                        decoration: const InputDecoration(
                          labelText: 'Nombre del familiar',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: address,
                        decoration: const InputDecoration(
                          labelText: 'Dirección HTTPS de Tailscale',
                        ),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: role,
                        items: const [
                          DropdownMenuItem(
                            value: 'editor',
                            child: Text('Puede editar'),
                          ),
                          DropdownMenuItem(
                            value: 'reader',
                            child: Text('Solo lectura'),
                          ),
                        ],
                        onChanged: (v) => set(() => role = v!),
                        decoration: const InputDecoration(labelText: 'Permiso'),
                      ),
                      if (error != null) Text(error!),
                    ]
                  : [
                      const Text(
                        'En el teléfono: conecta Tailscale, abre Mesa e introduce estos datos. El código funciona una sola vez y caduca en 10 minutos.',
                      ),
                      const SizedBox(height: 16),
                      SelectableText(address.text),
                      const SizedBox(height: 10),
                      SelectableText(
                        invite!['code'],
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        color: Colors.white,
                        padding: const EdgeInsets.all(12),
                        child: QrImageView(
                          data: Uri(
                            scheme: 'mesa',
                            host: 'connect',
                            queryParameters: {
                              'server': address.text,
                              'code': invite!['code'],
                            },
                          ).toString(),
                          size: 210,
                        ),
                      ),
                      const Text(
                        'Escanéalo con la cámara del teléfono para abrir Mesa.',
                      ),
                    ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Cerrar'),
          ),
          if (invite == null)
            FilledButton(
              onPressed: busy
                  ? null
                  : () async {
                      set(() => busy = true);
                      try {
                        final target = s.validateUrl(address.text);
                        if (!target.startsWith('https://')) {
                          throw Exception(
                            'El teléfono necesita una dirección HTTPS de Tailscale.',
                          );
                        }
                        final value = await s.request(
                          'POST',
                          '/v1/invites',
                          body: {
                            'name': name.text.trim().isEmpty
                                ? 'Familiar'
                                : name.text.trim(),
                            'role': role,
                          },
                        );
                        await s.preference('public_url', target);
                        if (c.mounted && ModalRoute.of(c)?.isCurrent == true) {
                          set(() => invite = Map<String, dynamic>.from(value));
                        }
                      } catch (e) {
                        if (c.mounted && ModalRoute.of(c)?.isCurrent == true) {
                          set(() => error = '$e');
                        }
                      } finally {
                        if (c.mounted && ModalRoute.of(c)?.isCurrent == true) {
                          set(() => busy = false);
                        }
                      }
                    },
              child: Text(busy ? 'Creando…' : 'Crear invitación'),
            ),
        ],
      ),
    ),
  );
}

Future<void> membersDialog(
  BuildContext context,
  Cookbook s,
) => guard(context, () async {
  final response = await s.request('GET', '/v1/members');
  final items = response is List ? response : response['members'];
  if (!context.mounted) return;
  await showDialog(
    context: context,
    builder: (c) => AlertDialog(
      title: const Text('Miembros de la familia'),
      content: SizedBox(
        width: 450,
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final member in items)
              ListTile(
                title: Text(member['name']),
                subtitle: Text(
                  '${member['role']} ${member['revoked'] == true || member['revoked'] == 1 ? '· revocado' : ''}',
                ),
                trailing: member['role'] == 'admin'
                    ? null
                    : IconButton(
                        tooltip: 'Revocar acceso',
                        onPressed: () => guard(c, () async {
                          if (await confirm(
                            c,
                            '¿Revocar este acceso?',
                            'Los datos descargados en su dispositivo permanecen allí. Ya no podrá sincronizar.',
                          )) {
                            await s.request(
                              'DELETE',
                              '/v1/members/${member['id']}',
                            );
                            if (c.mounted) Navigator.pop(c);
                          }
                        }),
                        icon: const Icon(Icons.person_remove_outlined),
                      ),
              ),
          ],
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
});

Future<void> exportDialog(BuildContext context, Cookbook s) =>
    guard(context, () async {
      final bytes = Uint8List.fromList(
        utf8.encode(const JsonEncoder.withIndent('  ').convert(s.exportData())),
      );
      final path = await FilePicker.saveFile(
        dialogTitle: 'Guardar copia del recetario',
        fileName: 'mesa-${dayKey(DateTime.now())}.json',
        type: FileType.custom,
        allowedExtensions: ['json'],
        bytes: bytes,
      );
      if (path != null) {
        if (context.mounted) message(context, 'Exportación guardada.');
      }
    });
Future<void> importFile(BuildContext context, Cookbook s) =>
    guard(context, () async {
      final file = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );
      if (file == null) return;
      final bytes = (await readLimitedBytes(
        file.readAsByteStream(),
        maxBytes: 50000000,
      ));
      if (bytes.length > 50000000) throw Exception('El archivo supera 50 MB.');
      if (context.mounted &&
          await confirm(
            context,
            '¿Añadir este archivo?',
            'Se crearán copias de las recetas, del menú y de la compra. Las recetas existentes se conservan.',
          )) {
        final n = await s.importData(
          utf8.decode(bytes).replaceFirst('\uFEFF', ''),
        );
        if (context.mounted) message(context, '$n elementos importados.');
      }
    });
Future<void> trashDialog(BuildContext context, Cookbook s) async {
  await showDialog(
    context: context,
    builder: (c) => AnimatedBuilder(
      animation: s,
      builder: (c, _) => AlertDialog(
        title: const Text('Papelera'),
        content: SizedBox(
          width: 500,
          child: s.entries.where((e) => e.deleted).isEmpty
              ? const Text('La papelera está vacía.')
              : ListView(
                  shrinkWrap: true,
                  children: [
                    for (final e in s.entries.where((e) => e.deleted))
                      ListTile(
                        title: Text(e.title),
                        subtitle: Text(
                          e.kind == 'recipe'
                              ? 'Receta'
                              : e.kind == 'meal'
                              ? 'Menú'
                              : 'Compra',
                        ),
                        trailing: s.editable
                            ? TextButton(
                                onPressed: () => guard(c, () => s.restore(e)),
                                child: const Text('Recuperar'),
                              )
                            : null,
                      ),
                  ],
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    ),
  );
}

Future<void> conflictsDialog(BuildContext context, Cookbook s) async {
  await showDialog(
    context: context,
    builder: (c) => AnimatedBuilder(
      animation: s,
      builder: (c, _) => AlertDialog(
        title: const Text('Cambios por revisar'),
        content: SizedBox(
          width: 650,
          child: ListView(
            shrinkWrap: true,
            children: [
              const Text(
                'Dos dispositivos cambiaron el mismo elemento. Tu propuesta sigue guardada hasta que elijas qué conservar.',
              ),
              for (final conflict in s.conflicts)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${conflict['data']['title'] ?? conflict['data']['name'] ?? 'Elemento'}',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 10),
                        ExpansionTile(
                          title: const Text('Comparar cambios'),
                          children: [
                            SelectableText(
                              'MI PROPUESTA\n${const JsonEncoder.withIndent('  ').convert(conflict['data'])}\n\nVERSIÓN FAMILIAR\n${const JsonEncoder.withIndent('  ').convert(conflict['server']?['data'])}',
                            ),
                          ],
                        ),
                        Wrap(
                          spacing: 8,
                          children: [
                            TextButton(
                              onPressed: () => guard(
                                c,
                                () => s.resolve(conflict, 'discard'),
                              ),
                              child: const Text('Conservar familiar'),
                            ),
                            if (s.editable)
                              TextButton(
                                onPressed: () =>
                                    guard(c, () => s.resolve(conflict, 'copy')),
                                child: const Text('Guardar mi copia'),
                              ),
                            if (s.editable)
                              TextButton(
                                onPressed: () => guard(c, () async {
                                  if (await confirm(
                                    c,
                                    '¿Usar tu propuesta?',
                                    'Se sustituirá la versión familiar actual. La versión anterior queda en el historial.',
                                  )) {
                                    await s.resolve(conflict, 'replace');
                                  }
                                }),
                                child: const Text('Usar mi propuesta'),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    ),
  );
}

Future<void> historyDialog(
  BuildContext context,
  Cookbook s,
  Entry e,
) => guard(context, () async {
  if (s.url.isEmpty) {
    throw Exception(
      'Conecta al servidor familiar para consultar versiones anteriores.',
    );
  }
  final response = await s.request('GET', '/v1/history/${e.id}');
  final list = response is List ? response : response['history'];
  if (!context.mounted) return;
  await showDialog(
    context: context,
    builder: (c) => AlertDialog(
      title: const Text('Versiones anteriores'),
      content: SizedBox(
        width: 600,
        child: ListView(
          shrinkWrap: true,
          children: [
            if (list.isEmpty)
              const Text('Todavía no hay versiones anteriores.'),
            for (final item in list)
              ExpansionTile(
                title: Text(
                  'Versión ${item['entity']['revision'] ?? ''} · ${item['at'] ?? ''}',
                ),
                children: [
                  SelectableText(
                    const JsonEncoder.withIndent('  ')
                        .convert(item['entity']['data']),
                  ),
                  if (s.editable)
                    TextButton(
                      onPressed: () => guard(c, () async {
                        if (await confirm(
                          c,
                          '¿Recuperar esta versión?',
                          'Se guardará como una nueva edición de la receta.',
                        )) {
                          await s.save(
                            e.kind,
                            Map<String, dynamic>.from(item['entity']['data']),
                            id: e.id,
                          );
                          if (c.mounted) Navigator.pop(c);
                        }
                      }),
                      child: const Text('Recuperar versión'),
                    ),
                ],
              ),
          ],
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
});
