import 'action_menu.dart';

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import 'catalogs.dart';
import 'measurements.dart';
import 'models.dart';
import 'organization.dart';
import 'photos.dart';
import 'recipe_opening.dart';
import 'recipe_presentation.dart';
import 'store.dart';
import 'pages.dart' show CookingPage;
import 'timers.dart';

class RecipePreview extends StatefulWidget {
  const RecipePreview({
    super.key,
    required this.item,
    required this.store,
    required this.api,
    required this.remember,
    required this.openSource,
    required this.saveLabel,
    this.cached,
    this.timers,
  });
  final CatalogItem item;
  final Cookbook store;
  final CatalogApi api;
  final Map<String, dynamic>? cached;
  final KitchenTimers? timers;
  final Future<void> Function(Map<String, dynamic>) remember;
  final Future<void> Function(String) openSource;
  final String saveLabel;
  @override
  State<RecipePreview> createState() => _RecipePreviewState();
}

class _RecipePreviewState extends State<RecipePreview> {
  late final RecipeOpening opening;
  bool originalMeasures = false;
  @override
  void initState() {
    super.initState();
    opening = RecipeOpening(
      cached: widget.cached,
      remember: widget.remember,
      loadDetail: (onText) =>
          widget.api.detail(widget.item, onTextReady: onText),
      translate: (recipe, {bool force = false}) =>
          widget.store.translateImportedRecipe(recipe, force: force),
    );
    opening.addListener(changed);
    unawaited(Future<void>.microtask(() => opening.start()));
  }

  void changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    opening.removeListener(changed);
    opening.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final data = opening.data;
    final duplicates = data == null
        ? <Entry>[]
        : similarRecipes(widget.store, data);
    final actualPhotos = data == null
        ? <Map<String, dynamic>>[]
        : recipePhotos(data);
    final displayPhotos = actualPhotos.isNotEmpty
        ? actualPhotos
        : widget.item.hasPhoto
        ? [
            <String, dynamic>{'url': widget.item.image},
          ]
        : <Map<String, dynamic>>[];
    final sourceUrl =
        '${data?['origin']?['url'] ?? (widget.item.id.startsWith('https://')
                ? widget.item.id
                : wikiEditions.containsKey(widget.item.provider)
                ? Uri.https('${widget.item.provider.substring(5)}.wikibooks.org', '/wiki/${widget.item.id}')
                : '')}';
    final title = Row(
      children: [
        Expanded(
          child: Text(
            opening.failure != null && data == null
                ? 'No se pudo abrir la receta'
                : '${data?['title'] ?? widget.item.title}',
          ),
        ),
        MesaActionMenuButton(
          title: 'Fuente de la receta',
          tooltip: 'Opciones de receta',
          onSelected: (value) {
            if (value == 'source') unawaited(widget.openSource(sourceUrl));
            if (value == 'refresh') unawaited(opening.start(refresh: true));
          },
          actions: [
            MesaMenuAction(
              id: 'source',
              label: 'Ver fuente original',
              icon: Icons.open_in_new,
              enabled: sourceUrl.isNotEmpty,
            ),
            MesaMenuAction(
              id: 'refresh',
              label: 'Actualizar desde la fuente',
              icon: Icons.refresh,
              enabled: !opening.loading,
            ),
          ],
        ),
      ],
    );
    final content = ListView(
      key: const ValueKey('recipe-preview-content'),
      children: [
        if (opening.loading || opening.translating) ...[
          Text(
            opening.translating
                ? 'Traduciendo al español…'
                : 'Cargando receta…',
          ),
          const SizedBox(height: 8),
          const LinearProgressIndicator(),
          const SizedBox(height: 12),
        ],
        if (opening.translationFailure != null) ...[
          const Text('No se pudo traducir. Se muestra el original.'),
          TextButton.icon(
            onPressed: opening.retryTranslation,
            icon: const Icon(Icons.translate),
            label: const Text('Reintentar traducción'),
          ),
          ExpansionTile(
            title: const Text('Detalle del problema'),
            children: [Text(opening.translationFailure!)],
          ),
        ],
        if (opening.failure != null) ...[
          Text(
            data == null
                ? 'No se pudo abrir la receta. ${opening.failure}'
                : 'No se pudo actualizar la receta. ${opening.failure}',
          ),
          TextButton(
            onPressed: () => opening.start(refresh: true),
            child: const Text('Reintentar'),
          ),
        ],
        PhotoGallery(
          key: const ValueKey('preview-photo-gallery'),
          photos: displayPhotos,
        ),
        if (data != null) ...[
          const SizedBox(height: 12),
          if (data['origin'] is Map)
            Text(
              [
                '${data['origin']['attribution'] ?? ''}',
                '${data['origin']['license'] ?? ''}',
              ].where((s) => s.isNotEmpty).join(' · '),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          if (duplicates.isNotEmpty && widget.saveLabel == 'Revisar y guardar')
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'Ya tienes ${duplicates.length} receta(s) con ese origen o título. Se guardará una copia si continúas.',
              ),
            ),
          const SizedBox(height: 12),
          Text(
            data['servings_declared'] == false
                ? 'Rendimiento por confirmar · cantidades originales'
                : 'Rendimiento: ${data['servings']} ${data['yield_unit'] ?? 'raciones'}',
          ),
          const SizedBox(height: 16),
          if (missingQuantities(data).isNotEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  'Faltan cantidades o necesitan revisión: ${missingQuantities(data).join(', ')}. No se han inventado cantidades.',
                ),
              ),
            ),
          const Text(
            'Ingredientes',
            style: TextStyle(fontSize: 21, fontWeight: FontWeight.w700),
          ),
          if ((data['ingredients'] as List? ?? []).isEmpty)
            const Text(
              'La fuente no tiene una sección reconocible. Revisa el texto original en las notas.',
            ),
          for (final text in recipeDisplayLines(
            data,
            'ingredients',
            originalMeasures: originalMeasures,
          ))
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                '• $text',
                style: const TextStyle(fontSize: 17, height: 1.5),
              ),
            ),
          const SizedBox(height: 18),
          const Text(
            'Preparación',
            style: TextStyle(fontSize: 21, fontWeight: FontWeight.w700),
          ),
          for (final text in recipeDisplayLines(
            data,
            'steps',
            originalMeasures: originalMeasures,
          ))
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                text,
                style: const TextStyle(fontSize: 17, height: 1.65),
              ),
            ),
          const SizedBox(height: 18),
          RecipeOptions(
            data: data,
            originalMeasures: originalMeasures,
            onMeasuresChanged: (value) =>
                setState(() => originalMeasures = value),
            translationAction: opening.complete && !opening.translating
                ? RecipeTranslationAction(
                    data: data,
                    translate: () =>
                        widget.store.translateImportedRecipe(data, force: true),
                    apply: (value) async => opening.apply(value),
                  )
                : null,
          ),
        ],
      ],
    );
    final actions = <Widget>[
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cerrar'),
      ),
      if (data != null && (data['steps'] as List? ?? []).isNotEmpty)
        OutlinedButton.icon(
          key: const ValueKey('preview-step-by-step'),
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => CookingPage(
                store: widget.store,
                timers: widget.timers,
                recipe: Entry(
                  'preview:${widget.item.provider}:${widget.item.id}',
                  'recipe',
                  0,
                  Map<String, dynamic>.from(jsonDecode(jsonEncode(data))),
                ),
                portions: (data['servings'] as num? ?? 1).toDouble(),
              ),
            ),
          ),
          icon: const Icon(Icons.play_circle_outline),
          label: const Text('Paso a paso'),
        ),
      if (widget.store.editable)
        FilledButton.icon(
          onPressed: opening.complete && data != null
              ? () => Navigator.pop(
                  context,
                  Map<String, dynamic>.from(jsonDecode(jsonEncode(data))),
                )
              : null,
          icon: const Icon(Icons.add),
          label: Text(
            opening.translating && widget.saveLabel == 'Revisar y guardar'
                ? 'Revisar original'
                : duplicates.isNotEmpty &&
                      widget.saveLabel == 'Revisar y guardar'
                ? 'Revisar como copia'
                : widget.saveLabel,
          ),
        ),
    ];
    final size = MediaQuery.sizeOf(context);
    if (size.width < 600) {
      return Dialog.fullscreen(
        child: Scaffold(
          appBar: AppBar(
            automaticallyImplyLeading: false,
            title: title,
            toolbarHeight: 80,
          ),
          body: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: content,
          ),
          bottomNavigationBar: Material(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: OverflowBar(
                  alignment: MainAxisAlignment.end,
                  spacing: 12,
                  overflowSpacing: 8,
                  children: actions,
                ),
              ),
            ),
          ),
        ),
      );
    }
    return AlertDialog(
      title: title,
      content: SizedBox(
        width: 680,
        height: (size.height * .62).clamp(140, 640),
        child: content,
      ),
      actions: actions,
    );
  }
}
