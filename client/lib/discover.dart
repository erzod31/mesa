import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'catalogs.dart';
import 'design.dart';
import 'discovery_catalog.dart';
import 'models.dart';
import 'photos.dart';
import 'recipe_preview.dart';
import 'store.dart';
import 'ui.dart' show guard;
import 'timers.dart';

class DiscoverRecipes extends StatefulWidget {
  const DiscoverRecipes({
    super.key,
    required this.store,
    required this.onEdit,
    this.initialQuery = '',
    this.saveLabel = 'Revisar y guardar',
    this.timers,
  });
  final Cookbook store;
  final Future<void> Function({Entry? entry, Map<String, dynamic>? initial})
  onEdit;
  final String initialQuery, saveLabel;
  final KitchenTimers? timers;
  @override
  State<DiscoverRecipes> createState() => _DiscoverRecipesState();
}

class _DiscoverRecipesState extends State<DiscoverRecipes> {
  final query = TextEditingController();
  final scroll = ScrollController();
  late final api = CatalogApi(
    widget.store.client,
    externalDetail: widget.store.url.isEmpty || widget.store.token.isEmpty
        ? null
        : (provider, url) async => Map<String, dynamic>.from(
            await widget.store.request(
              'POST',
              '/v1/import-url',
              body: {'provider': provider, 'url': url},
            ),
          ),
  );
  late final discovery = DiscoveryCatalog(api);
  String country = 'España', submitted = '', error = '';
  String? cursor;
  List<CatalogItem> items = [];
  List<String> failures = [];
  bool busy = false, cached = false;
  int generation = 0;
  @override
  void initState() {
    super.initState();
    final saved = widget.store.prefs['discovery-country'];
    if (saved != null &&
        (saved.isEmpty || discovery.countries.contains(saved))) {
      country = saved;
    }
    query.text = submitted = widget.initialQuery;
    load();
  }

  @override
  void dispose() {
    generation++;
    query.dispose();
    scroll.dispose();
    super.dispose();
  }

  Map<String, dynamic> cache() {
    try {
      return Map<String, dynamic>.from(
        jsonDecode(widget.store.prefs['catalog-cache'] ?? '{}'),
      );
    } catch (_) {
      return {};
    }
  }

  Future<void> remember(String key, Map<String, dynamic> value) async {
    final data = cache()..remove(key);
    data[key] = onlinePhotoTree(value);
    while (data.length > 20) {
      data.remove(data.keys.first);
    }
    await widget.store.preference('catalog-cache', jsonEncode(data));
  }

  Future<void> load({bool more = false}) async {
    if (more && (busy || cursor == null)) return;
    final request = ++generation;
    final selected = country, term = submitted;
    final previous = more ? cursor : null;
    final key = 'discovery-v1:$selected:$term:${previous ?? ''}';
    setState(() {
      busy = true;
      error = '';
      cached = false;
      if (!more) {
        items = [];
        cursor = null;
        failures = [];
      }
    });
    try {
      final result = await discovery.search(
        country: selected,
        query: term,
        cursor: previous,
        isCurrent: () => mounted && request == generation,
      );
      if (!mounted || request != generation) return;
      var incoming = result.items;
      // Only recover a matching query, and filter it through today's permission registry.
      if (incoming.isEmpty &&
          result.failedSources.isNotEmpty &&
          cache()[key] is Map) {
        final saved = CatalogResult.fromJson(
          Map<String, dynamic>.from(cache()[key]),
        );
        final allowed = discovery.eligible(selected).map((s) => s.id).toSet();
        incoming = saved.items
            .where((i) => allowed.contains(i.provider))
            .toList();
        cached = incoming.isNotEmpty;
      }
      setState(() {
        items = {
          for (final i in [if (more) ...items, ...incoming])
            '${i.provider}:${i.id}': i,
        }.values.toList();
        cursor = result.cursor;
        failures = result.failedSources;
        busy = false;
      });
      if (result.items.isNotEmpty) {
        await remember(
          key,
          CatalogResult(result.items, cursor: result.cursor).toJson(),
        );
      }
    } catch (_) {
      if (!mounted || request != generation) return;
      setState(() {
        busy = false;
        error = 'No se pudo completar la búsqueda. Revisa la conexión y vuelve a intentarlo.';
      });
    }
  }

  void search() {
    FocusScope.of(context).unfocus();
    submitted = query.text.trim();
    if (scroll.hasClients) scroll.jumpTo(0);
    load();
  }

  Future<void> chooseCountry(String value) async {
    if (value == country) return;
    setState(() => country = value);
    if (scroll.hasClients) scroll.jumpTo(0);
    // Keep the same submitted search when changing countries.
    load();
    await widget.store.preference('discovery-country', value);
  }

  Future<void> openSource(String url) => guard(context, () async {
    final u = Uri.parse(url);
    if (u.scheme != 'https' ||
        u.userInfo.isNotEmpty ||
        (u.hasPort && u.port != 443)) {
      throw Exception('Enlace incorrecto.');
    }
    await const MethodChannel('mesa/native').invokeMethod('openUrl', '$u');
  });
  Future<void> credits() => showDialog<void>(
    context: context,
    builder: (c) => AlertDialog(
      title: const Text('Fuentes y condiciones de uso'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'El país corresponde a la ubicación o edición de la publicación, no al origen de cada plato. Las búsquedas reúnen las fuentes con licencia disponible.',
              ),
              const SizedBox(height: 16),
              for (final s in catalogSources) ...[
                Text(
                  s.name,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                Text(
                  '${s.country} · ${s.browseable ? s.licenseName : 'Solo sitio original; permiso de integración pendiente'}',
                ),
                Wrap(
                  spacing: 8,
                  children: [
                    TextButton(
                      onPressed: () => openSource(s.url),
                      child: const Text('Sitio original'),
                    ),
                    if (s.licenseUrl.isNotEmpty)
                      TextButton(
                        onPressed: () => openSource(s.licenseUrl),
                        child: const Text('Licencia'),
                      ),
                  ],
                ),
                const Divider(),
              ],
              const Text(
                'Se conservan autoría, licencias y cantidades originales. Las adaptaciones se identifican. Las fotos se consultan en línea, sin guardar archivos en el dispositivo. Las de documentos necesitan el ordenador conectado.',
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
      ],
    ),
  );
  Future<void> preview(CatalogItem item) => guard(context, () async {
    final key = 'detail:${item.provider}:${item.id}',
        saved = cache()['detail:${item.provider}:${item.id}'];
    final value = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => RecipePreview(
        item: item,
        store: widget.store,
        api: api,
        cached: saved is Map ? Map<String, dynamic>.from(saved) : null,
        remember: (data) => remember(key, data),
        openSource: openSource,
        saveLabel: widget.saveLabel,
        timers: widget.timers,
      ),
    );
    if (value != null && mounted) await widget.onEdit(initial: value);
  });

  Widget controls() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const MesaPageHeader(
        title: 'Descubre sabores',
        subtitle: 'Todas tus fuentes, reunidas en una sola búsqueda.',
      ),
      LayoutBuilder(
        builder: (c, b) {
          final selector = DropdownButtonFormField<String>(
            key: ValueKey('discovery-country:$country'),
            initialValue: country,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'País de la publicación',
              prefixIcon: Icon(Icons.public),
            ),
            items: [
              const DropdownMenuItem(
                value: '',
                child: Text('Todos los países'),
              ),
              for (final v in discovery.countries)
                DropdownMenuItem(
                  value: v,
                  child: Text(v, overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: (v) {
              if (v != null) chooseCountry(v);
            },
          );
          final field = TextField(
            controller: query,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => search(),
            decoration: InputDecoration(
              labelText: 'Buscar recetas',
              hintText: 'Nombre del plato o ingrediente',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: IconButton(
                tooltip: 'Buscar recetas',
                onPressed: search,
                icon: const Icon(Icons.arrow_forward),
              ),
            ),
          );
          if (b.maxWidth < 700 || MediaQuery.textScalerOf(c).scale(1) > 1.4) {
            return Column(
              children: [selector, const SizedBox(height: 14), field],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: 280, child: selector),
              const SizedBox(width: 16),
              Expanded(child: field),
            ],
          );
        },
      ),
      const SizedBox(height: 8),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          key: const ValueKey('catalog-source-details'),
          onPressed: credits,
          icon: const Icon(Icons.info_outline),
          label: const Text('Fuentes y licencias'),
        ),
      ),
      if (busy)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: LinearProgressIndicator(semanticsLabel: 'Buscando recetas'),
        ),
      if (cached)
        const Padding(
          padding: EdgeInsets.all(12),
          child: Text('Sin conexión: se muestra la consulta guardada.'),
        ),
      if (failures.isNotEmpty || error.isNotEmpty)
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  error.isNotEmpty
                      ? error
                      : 'No respondieron: ${failures.join(', ')}. Las demás fuentes siguen disponibles.',
                ),
                TextButton.icon(
                  onPressed: busy ? null : () => load(more: cursor != null),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Reintentar pendientes'),
                ),
              ],
            ),
          ),
        ),
      if (!busy && items.isEmpty && failures.isEmpty && error.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Text(
            discovery.eligible(country).isEmpty
                ? 'Este país todavía no tiene un catálogo autorizado para integrar. Puedes consultar los sitios originales en Fuentes y licencias.'
                : cursor == null
                ? 'No encontramos recetas con foto. Prueba otro nombre o cambia de país.'
                : 'Estas páginas no contienen recetas completas con foto. Puedes cargar más.',
          ),
        ),
      if (!busy && discovery.eligible(country).isEmpty)
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final source in catalogSources.where(
              (s) =>
                  s.country.split(' / ').contains(country) &&
                  s.consultationOnly,
            ))
              OutlinedButton.icon(
                onPressed: () => openSource(source.url),
                icon: const Icon(Icons.open_in_new),
                label: Text(source.name),
              ),
          ],
        ),
      if (items.isNotEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Text(
            '${items.length} recetas con foto',
            style: Theme.of(context).textTheme.titleSmall,
          ),
        ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final inset = MesaSpace.inset(MediaQuery.sizeOf(context).width);
    return CustomScrollView(
      controller: scroll,
      key: const PageStorageKey('discovery-scroll'),
      slivers: [
        SliverPadding(
          padding: EdgeInsets.fromLTRB(inset, 8, inset, 0),
          sliver: SliverToBoxAdapter(child: controls()),
        ),
        SliverPadding(
          padding: EdgeInsets.symmetric(horizontal: inset),
          sliver: SliverLayoutBuilder(
            builder: (c, b) {
              final columns = (b.crossAxisExtent / 300).floor().clamp(1, 4);
              final width = (b.crossAxisExtent - 16 * (columns - 1)) / columns;
              final scale = MediaQuery.textScalerOf(c);
              return SliverGrid(
                delegate: SliverChildBuilderDelegate((c, index) {
                  final item = items[index],
                      source = catalogSources.firstWhere(
                        (s) => s.id == items[index].provider,
                      );
                  return MesaInteractiveCard(
                    key: ValueKey('discovery:${item.provider}:${item.id}'),
                    onTap: () => preview(item),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        AspectRatio(
                          aspectRatio: 1.7,
                          child: RecipePhoto({
                            'url': item.image,
                            'license': source.licenseName,
                          }, fit: BoxFit.contain),
                        ),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item.title,
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 18,
                                    height: 1.3,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const Spacer(),
                                Text(
                                  source.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Theme.of(c)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  ),
                                ),
                                Text(
                                  source.country,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Theme.of(c)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }, childCount: items.length),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                  mainAxisExtent:
                      width / 1.7 +
                      scale.scale(18) * 3 * 1.3 +
                      scale.scale(13) * 3 +
                      52,
                ),
              );
            },
          ),
        ),
        SliverPadding(
          padding: EdgeInsets.fromLTRB(inset, 20, inset, 100),
          sliver: SliverToBoxAdapter(
            child: cursor != null
                ? Center(
                    child: OutlinedButton.icon(
                      onPressed: busy ? null : () => load(more: true),
                      icon: const Icon(Icons.expand_more),
                      label: Text(busy ? 'Cargando…' : 'Cargar más recetas'),
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ),
      ],
    );
  }
}
