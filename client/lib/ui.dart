import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'models.dart';
import 'photos.dart';
import 'store.dart';
import 'timers.dart';
import 'editor.dart';
import 'pages.dart';
import 'library.dart';
import 'design.dart';
import 'brand.dart';
import 'windows_updates.dart';

const green = MesaPalette.green;
const cream = MesaPalette.cream;

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MesaLaunchApp());
  try {
    if (Platform.isWindows) configureWindowsUpdates(args);
    Directory? isolatedProfile;
    for (final arg in args) {
      if (Platform.isWindows && arg.startsWith('--isolated-profile=')) {
        final path = arg.substring('--isolated-profile='.length);
        if (!File(path).isAbsolute || path.isEmpty) {
          throw const FormatException(
            'El perfil aislado necesita una ruta absoluta.',
          );
        }
        isolatedProfile = Directory(path);
      }
    }
    final store = await Cookbook.open(profileDirectory: isolatedProfile);
    documentPhotoLoader = store.fetchDocumentPhoto;
    final timers = KitchenTimers(store);
    await timers.init(enableNotifications: isolatedProfile == null);
    for (final arg in args) {
      if (arg.startsWith('--connect-json=')) {
        final file = File(arg.substring(15));
        if (await file.exists()) {
          final config = jsonDecode(
            (await file.readAsString()).replaceFirst('\uFEFF', ''),
          );
          if (config['public_url'] is String) {
            await store.preference(
              'public_url',
              store.validateUrl(config['public_url']),
            );
          }
          if (store.url.isEmpty || isolatedProfile != null) {
            try {
              await store.connect(
                config['url'],
                config['token'],
                invitation: false,
              );
            } catch (_) {
              store.status =
                  'Servidor local pendiente · puedes usar tu recetario';
            }
          }
        }
      }
    }
    store.startSync();
    unawaited(store.prepareTranslation());
    runApp(MesaApp(store: store, timers: timers));
    if (isolatedProfile != null) {
      final proof = File('${isolatedProfile.path}/mesa-ready.json');
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(
          proof.writeAsString(
            jsonEncode({
              'ready': true,
              'entries': store.entries.length,
              'pending': store.pending,
              'connected': store.url.isNotEmpty && store.token.isNotEmpty,
              'credentialVaultUsed': false,
              'systemNotificationsUsed': false,
            }),
          ),
        );
      });
    }
  } catch (error) {
    runApp(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: SelectableText(
                'Mesa no pudo abrir sus datos.\nNo se han eliminado archivos.\n\n$error',
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class MesaApp extends StatelessWidget {
  const MesaApp({super.key, required this.store, required this.timers});
  final Cookbook store;
  final KitchenTimers timers;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: store,
    builder: (context, _) => MaterialApp(
      title: 'Mesa · Recetario familiar',
      debugShowCheckedModeBanner: false,
      themeMode: store.dark ? ThemeMode.dark : ThemeMode.light,
      theme: theme(Brightness.light),
      darkTheme: theme(Brightness.dark),
      home: Home(store: store, timers: timers),
    ),
  );
  ThemeData theme(Brightness brightness) {
    final colors = MesaPalette.scheme(brightness);
    return ThemeData(
      useMaterial3: true,
      colorScheme: colors,
      scaffoldBackgroundColor: brightness == Brightness.light
          ? cream
          : const Color(0xFF171D19),
      fontFamily: 'Segoe UI',
      appBarTheme: AppBarTheme(
        backgroundColor: brightness == Brightness.light
            ? cream
            : colors.surface,
        scrolledUnderElevation: 0,
        elevation: 0,
        titleTextStyle: TextStyle(
          fontFamily: 'Segoe UI',
          color: colors.onSurface,
          fontSize: 22,
          fontWeight: FontWeight.w700,
        ),
        actionsPadding: const EdgeInsets.only(right: 12),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colors.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(MesaShape.field),
          borderSide: BorderSide(
            color: colors.outlineVariant.withValues(alpha: .55),
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(MesaShape.field),
          borderSide: BorderSide(
            color: colors.outlineVariant.withValues(alpha: .55),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(MesaShape.field),
          borderSide: BorderSide(color: colors.primary, width: 2),
        ),
        contentPadding: const EdgeInsets.all(16),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(48, 48),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(MesaShape.button),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(48, 48),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(MesaShape.button),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(48, 48),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          shape: const StadiumBorder(),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          minimumSize: const Size(48, 48),
          shape: const CircleBorder(),
        ),
      ),
      chipTheme: ChipThemeData(
        shape: const StadiumBorder(),
        selectedColor: colors.primaryContainer,
        backgroundColor: colors.surface,
        side: BorderSide(color: colors.outlineVariant.withValues(alpha: .35)),
        checkmarkColor: colors.onPrimaryContainer,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          shape: const WidgetStatePropertyAll(StadiumBorder()),
          side: const WidgetStatePropertyAll(BorderSide.none),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          ),
          backgroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? colors.primaryContainer
                : null,
          ),
          foregroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? colors.onPrimaryContainer
                : colors.onSurface,
          ),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        indicatorColor: colors.primaryContainer,
        backgroundColor: colors.surface,
        elevation: 0,
        indicatorShape: const StadiumBorder(),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            fontSize: 12,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w700
                : FontWeight.w500,
            color: states.contains(WidgetState.selected)
                ? colors.primary
                : colors.onSurfaceVariant,
          ),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: colors.primary,
        foregroundColor: colors.onPrimary,
        shape: const StadiumBorder(),
        elevation: 0,
        focusElevation: 0,
        hoverElevation: 2,
        highlightElevation: 0,
        extendedTextStyle: const TextStyle(
          fontFamily: 'Segoe UI',
          fontSize: 15,
          fontWeight: FontWeight.w700,
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: colors.surface,
        elevation: 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(MesaShape.button),
        ),
      ),
      menuTheme: MenuThemeData(
        style: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(colors.surface),
          shape: const WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(24)),
            ),
          ),
          padding: const WidgetStatePropertyAll(EdgeInsets.all(8)),
        ),
      ),
      listTileTheme: const ListTileThemeData(minTileHeight: 56),
      expansionTileTheme: ExpansionTileThemeData(
        backgroundColor: colors.surface,
        collapsedBackgroundColor: colors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        collapsedShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
        tilePadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
        childrenPadding: const EdgeInsets.fromLTRB(18, 0, 18, 20),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: colors.surface,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      dividerTheme: DividerThemeData(
        color: colors.outlineVariant.withValues(alpha: .6),
        thickness: 1,
      ),
      dialogTheme: DialogThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(MesaShape.dialog),
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: colors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(MesaShape.card),
          side: BorderSide(color: colors.outlineVariant.withValues(alpha: .35)),
        ),
      ),
    );
  }
}

void message(BuildContext context, Object text) {
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$text'), behavior: SnackBarBehavior.floating),
    );
  }
}

Future<void> guard(BuildContext context, Future<void> Function() action) async {
  try {
    await action();
  } catch (error) {
    if (context.mounted) {
      message(context, '$error'.replaceFirst('Exception: ', ''));
    }
  }
}

Widget label(String title) => Padding(
  padding: const EdgeInsets.only(top: 22, bottom: 12),
  child: Text(
    title,
    style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
  ),
);

class Home extends StatefulWidget {
  const Home({super.key, required this.store, required this.timers});
  final Cookbook store;
  final KitchenTimers timers;
  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> with WidgetsBindingObserver {
  int page = 0;
  final visitedPages = <int>{0};
  bool libraryDiscovering = false;
  String? selected;
  bool recipeExpanded = false;
  final libraryKey = GlobalKey();
  Cookbook get s => widget.store;
  void selectPage(int value) => setState(() {
    visitedPages.add(value);
    page = value;
  });

  Widget recipeCreationControls() => LayoutBuilder(
    builder: (context, bounds) => Row(
      key: const ValueKey('recipe-creation-controls'),
      children: [
        Expanded(
          child: Tooltip(
            message: 'Nueva receta',
            child: FilledButton(
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
              ),
              onPressed: () => edit(),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (bounds.maxWidth >= 260) ...[
                    const Icon(Icons.add_rounded),
                    const SizedBox(width: 8),
                  ],
                  const Flexible(
                    child: Text('Nueva receta', textAlign: TextAlign.center),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 48,
          height: 48,
          child: IconButton.filledTonal(
            tooltip: 'Importar enlace o texto',
            icon: const Icon(Icons.download_rounded),
            onPressed: () =>
                importRecipeDialog(context, s, (data) => edit(initial: data)),
          ),
        ),
      ],
    ),
  );
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    KitchenTimers.native.setMethodCallHandler((call) async {
      if (call.method == 'shared') {
        await shared(Map<String, dynamic>.from(call.arguments));
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        final value = await KitchenTimers.native
            .invokeMapMethod<String, dynamic>('initialShare');
        if (value != null && mounted) await shared(value);
      } catch (_) {}
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(s.sync());
      unawaited(s.prepareTranslation());
    }
  }

  Future<void> shared(Map<String, dynamic> value) async {
    final text = '${value['text'] ?? ''}';
    if (text.startsWith('mesa://connect')) {
      final uri = Uri.tryParse(text);
      if (uri != null) {
        await connectDialog(
          context,
          s,
          server: uri.queryParameters['server'],
          code: uri.queryParameters['code'],
        );
        return;
      }
    }
    final first = text.split('\n').first;
    final initial = <String, dynamic>{
      'title': text.isEmpty
          ? 'Receta de una foto'
          : first.substring(0, first.length.clamp(0, 100)),
      'notes': text,
      'ingredients': <String>[],
      'steps': <String>[],
      'tags': <String>[],
      'servings': 4,
      'minutes': 0,
      'source': text.startsWith('https://') ? text : '',
      'image': '',
    };
    if (value['image'] is Uint8List) {
      try {
        final recognized = await s.recognizeImage(value['image'] as Uint8List);
        initial['notes'] = [
          text,
          recognized,
        ].where((s) => s.isNotEmpty).join('\n');
      } catch (error) {
        initial['notes'] = [
          text,
          'No se pudo leer la foto con Indra OCR. Comprueba la conexión con el ordenador de Mesa o añade los ingredientes y pasos manualmente.',
        ].where((s) => s.isNotEmpty).join('\n');
      }
    }
    if (mounted) await edit(initial: initial);
  }

  Future<void> edit({Entry? entry, Map<String, dynamic>? initial}) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RecipeEditor(store: s, entry: entry, initial: initial),
      ),
    );
    if (mounted) setState(() {});
  }

  void open(Entry entry, bool wide) {
    if (wide) {
      setState(() => selected = entry.id);
    } else {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => Scaffold(
            appBar: AppBar(title: const Text('Tu receta')),
            body: RecipeView(
              store: s,
              timers: widget.timers,
              id: entry.id,
              onEdit: () => edit(entry: s.get(entry.id)),
            ),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: s,
    builder: (context, _) => LayoutBuilder(
      builder: (context, bounds) {
        final wide = bounds.maxWidth >= 1000;
        final syncNeedsAttention =
            s.conflicts.isNotEmpty ||
            (s.url.isNotEmpty &&
                (s.pending > 0 ||
                    s.status.startsWith('Sin conexión') ||
                    s.status.startsWith('No se pudo') ||
                    s.status.startsWith('Acceso caducado') ||
                    s.status.startsWith('Perfil de lectura')));
        final destinations = const [
          NavigationDestination(
            icon: Icon(Icons.menu_book_outlined),
            selectedIcon: Icon(Icons.menu_book_rounded),
            label: 'Recetas',
          ),
          NavigationDestination(
            icon: Icon(Icons.calendar_month_outlined),
            selectedIcon: Icon(Icons.calendar_month_rounded),
            label: 'Semana',
          ),
          NavigationDestination(
            icon: Icon(Icons.shopping_bag_outlined),
            selectedIcon: Icon(Icons.shopping_bag_rounded),
            label: 'Compra',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline_rounded),
            selectedIcon: Icon(Icons.person_rounded),
            label: 'Mi espacio',
          ),
        ];
        return CallbackShortcuts(
          bindings: {
            if (s.editable)
              const SingleActivator(
                LogicalKeyboardKey.keyN,
                control: true,
              ): () {
                unawaited(edit());
              },
            if (s.editable)
              const SingleActivator(
                LogicalKeyboardKey.keyI,
                control: true,
              ): () {
                unawaited(
                  importRecipeDialog(context, s, (data) => edit(initial: data)),
                );
              },
          },
          child: Scaffold(
            appBar: wide
                ? null
                : AppBar(
                    title: const MesaWordmark(),
                    actions: [
                      if (s.url.isNotEmpty)
                        IconButton(
                          tooltip: 'Actualizar recetario',
                          onPressed: s.syncing ? null : () => s.sync(),
                          icon: const Icon(Icons.cloud_sync_outlined),
                        ),
                    ],
                  ),
            bottomNavigationBar: wide
                ? null
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (page == 0 &&
                          s.editable &&
                          !libraryDiscovering &&
                          MediaQuery.viewInsetsOf(context).bottom == 0)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                          child: SizedBox(
                            width: double.infinity,
                            child: recipeCreationControls(),
                          ),
                        ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(32),
                          child: NavigationBar(
                            height:
                                MediaQuery.textScalerOf(context).scale(12) > 16
                                ? 92
                                : 76,
                            labelBehavior:
                                MediaQuery.textScalerOf(context).scale(12) > 16
                                ? NavigationDestinationLabelBehavior
                                      .onlyShowSelected
                                : NavigationDestinationLabelBehavior.alwaysShow,
                            selectedIndex: page,
                            onDestinationSelected: selectPage,
                            destinations: destinations,
                          ),
                        ),
                      ),
                    ],
                  ),
            body: SafeArea(
              child: Row(
                children: [
                  if (wide)
                    Container(
                      width: 224,
                      margin: const EdgeInsets.fromLTRB(16, 16, 0, 16),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surface,
                        borderRadius: BorderRadius.circular(32),
                        border: Border.all(
                          color: Theme.of(context).colorScheme.outlineVariant
                              .withValues(alpha: .35),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(22, 26, 20, 6),
                            child: const MesaWordmark(
                              iconSize: 48,
                              textSize: 32,
                            ),
                          ),
                          const Padding(
                            padding: EdgeInsets.fromLTRB(24, 4, 20, 26),
                            child: Text(
                              'Recetas para compartir',
                              style: TextStyle(fontSize: 12),
                            ),
                          ),
                          for (var i = 0; i < destinations.length; i++)
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                              ),
                              child: MesaNavigationItem(
                                label: destinations[i].label,
                                icon: page == i
                                    ? destinations[i].selectedIcon!
                                    : destinations[i].icon,
                                selected: page == i,
                                onTap: () => selectPage(i),
                              ),
                            ),
                          if (s.editable)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(18, 22, 18, 0),
                              child: recipeCreationControls(),
                            ),
                          const Spacer(),
                          Padding(
                            padding: const EdgeInsets.all(20),
                            child: Row(
                              children: [
                                CircleAvatar(
                                  backgroundColor: Theme.of(context)
                                      .colorScheme
                                      .primaryContainer,
                                  child: Icon(
                                    Icons.person_outline_rounded,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .primary,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Tooltip(
                                    message: s.profile,
                                    child: Text(
                                      s.profile,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ),
                                if (s.url.isNotEmpty)
                                  IconButton(
                                    tooltip: 'Actualizar recetario',
                                    onPressed: s.syncing
                                        ? null
                                        : () => s.sync(),
                                    icon: const Icon(Icons.sync_rounded),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  Expanded(
                    child: Column(
                      children: [
                        if (syncNeedsAttention)
                          Padding(
                            padding: EdgeInsets.fromLTRB(
                              wide ? 32 : 20,
                              wide ? 26 : 8,
                              wide ? 32 : 20,
                              12,
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    s.pending > 0
                                        ? '${s.status} · ${s.pending} pendientes'
                                        : s.status,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant,
                                    ),
                                    maxLines: 2,
                                  ),
                                ),
                                if (wide)
                                  IconButton(
                                    tooltip: 'Actualizar',
                                    onPressed: s.syncing
                                        ? null
                                        : () => s.sync(),
                                    icon: const Icon(Icons.sync),
                                  ),
                                if (s.conflicts.isNotEmpty)
                                  TextButton.icon(
                                    onPressed: () =>
                                        conflictsDialog(context, s),
                                    icon: const Icon(Icons.compare_arrows),
                                    label: Text(
                                      '${s.conflicts.length} por revisar',
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        Expanded(
                          child: ReadingWidth(
                            child: IndexedStack(
                              index: page,
                              children: [
                                for (var tab = 0; tab < 4; tab++)
                                  ExcludeFocus(
                                    excluding: page != tab,
                                    child: Offstage(
                                      offstage: page != tab,
                                      child: TickerMode(
                                        enabled: page == tab,
                                        child: !visitedPages.contains(tab)
                                            ? const SizedBox.shrink()
                                            : switch (tab) {
                                                0 => recipes(wide),
                                                1 => WeekPage(store: s),
                                                2 => ShoppingPage(store: s),
                                                _ => SettingsPage(
                                                  store: s,
                                                  timers: widget.timers,
                                                  onExample: () =>
                                                      addExamples(context, s),
                                                  onImport: () =>
                                                      importRecipeDialog(
                                                        context,
                                                        s,
                                                        (data) =>
                                                            edit(initial: data),
                                                      ),
                                                ),
                                              },
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    ),
  );
  Widget recipes(bool wide) {
    final list = RecipeLibrary(
      timers: widget.timers,
      key: libraryKey,
      store: s,
      onOpen: (e) => open(e, wide),
      onEdit: edit,
      wide: wide,
      onDiscoveryChanged: (value) => setState(() => libraryDiscovering = value),
    );
    if (wide &&
        selected != null &&
        s.get(selected!) != null &&
        !s.get(selected!)!.deleted) {
      final detail = RecipeView(
        store: s,
        timers: widget.timers,
        id: selected!,
        expanded: recipeExpanded,
        onExpand: () => setState(() => recipeExpanded = !recipeExpanded),
        onClose: () => setState(() {
          selected = null;
          recipeExpanded = false;
        }),
        onEdit: () => edit(entry: s.get(selected!)),
      );
      if (recipeExpanded) return detail;
      return Row(
        children: [
          Expanded(flex: 6, child: list),
          Expanded(
            flex: 5,
            child: Container(
              decoration: BoxDecoration(
                border: Border(
                  left: BorderSide(
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                ),
              ),
              child: detail,
            ),
          ),
        ],
      );
    }
    return list;
  }
}

class Empty extends StatelessWidget {
  const Empty({
    super.key,
    required this.icon,
    required this.title,
    required this.text,
    this.action,
    this.illustration,
  });
  final IconData icon;
  final String title, text;
  final Widget? action;
  final Widget? illustration;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          illustration ??
              Icon(
                icon,
                size: 58,
                color: Theme.of(context).colorScheme.primary,
              ),
          const SizedBox(height: 20),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          Text(
            text,
            textAlign: TextAlign.center,
            style: const TextStyle(height: 1.7),
          ),
          if (action != null)
            Padding(padding: const EdgeInsets.only(top: 24), child: action),
        ],
      ),
    ),
  );
}

class RecipeCard extends StatelessWidget {
  const RecipeCard({
    super.key,
    required this.entry,
    required this.favorite,
    required this.onFavorite,
    required this.onTap,
  });
  final Entry entry;
  final bool favorite;
  final VoidCallback onFavorite, onTap;
  @override
  Widget build(BuildContext context) {
    final image = coverImage(entry.data);
    final tint = [
      const Color(0xFFE6EAD8),
      const Color(0xFFF0DFC8),
      const Color(0xFFDDE9E6),
    ][entry.title.length % 3];
    return MesaInteractiveCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (image.isNotEmpty)
                  RecipePhoto({'url': image})
                else
                  Container(
                    color: tint,
                    child: Center(
                      child: Icon(
                        Icons.restaurant_menu,
                        size: 52,
                        color: green.withValues(alpha: .7),
                      ),
                    ),
                  ),
                Positioned(
                  top: 8,
                  right: 8,
                  child: IconButton.filledTonal(
                    tooltip: favorite
                        ? 'Quitar de favoritas'
                        : 'Guardar en favoritas',
                    onPressed: onFavorite,
                    icon: Icon(
                      favorite ? Icons.favorite : Icons.favorite_border,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.schedule, size: 14),
                        const SizedBox(width: 5),
                        Text(
                          (entry.data['minutes'] ?? 0) > 0
                              ? '${entry.data['minutes']} min'
                              : 'Tiempo pendiente',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ],
                    ),
                    Text(
                      recipeYieldText(entry.data),
                      style: const TextStyle(fontSize: 12),
                    ),
                    if ((entry.data['rating'] as int? ?? 0) > 0)
                      Text(
                        '★ ${entry.data['rating']}/5 · tu valoración',
                        style: const TextStyle(fontSize: 12),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> addExamples(BuildContext context, Cookbook s) => guard(
  context,
  () async {
    if (s.of('recipe').any((x) => x.data['example'] == true)) {
      message(context, 'Los ejemplos ya están en tu recetario.');
      return;
    }
    for (final data in [
      {
        'title': 'Tortilla de patatas',
        'ingredients': [
          '600 g de patatas',
          '6 huevos',
          '1 cebolla',
          'Aceite de oliva',
          'Sal al gusto',
        ],
        'steps': [
          'Pela y corta las patatas y la cebolla.',
          'Cocina lentamente en aceite hasta que estén tiernas.',
          'Escurre y mezcla con los huevos batidos.',
          'Cuaja en una sartén y dale la vuelta con cuidado.',
        ],
        'servings': 4,
        'minutes': 40,
        'tags': ['En familia', 'Clásicos'],
        'notes': 'Una receta de ejemplo que puedes adaptar a tu gusto.',
        'source': 'Mesa · ejemplo',
        'image': '',
        'example': true,
      },
      {
        'title': 'Pasta con tomate y albahaca',
        'ingredients': [
          '400 g de pasta',
          '500 g de tomate triturado',
          '2 dientes de ajo',
          '2 cucharadas de aceite',
          'Albahaca al gusto',
        ],
        'steps': [
          'Calienta el aceite y dora el ajo picado.',
          'Añade el tomate y cocina a fuego suave.',
          'Cuece la pasta siguiendo el tiempo del envase.',
          'Mezcla con la salsa y termina con albahaca.',
        ],
        'servings': 4,
        'minutes': 25,
        'tags': ['Rápidas', 'Pasta'],
        'notes': 'Reserva un poco del agua de la pasta para ligar la salsa.',
        'source': 'Mesa · ejemplo',
        'image': '',
        'example': true,
      },
      {
        'title': 'Ensalada de garbanzos',
        'ingredients': [
          '400 g de garbanzos cocidos',
          '2 tomates',
          '1 pepino',
          '3 cucharadas de aceite',
          '1 cucharada de vinagre',
          'Sal al gusto',
        ],
        'steps': [
          'Enjuaga y escurre los garbanzos.',
          'Corta el tomate y el pepino.',
          'Mezcla todo y aliña al gusto.',
        ],
        'servings': 2,
        'minutes': 15,
        'tags': ['Rápidas', 'Sin horno'],
        'notes': 'Se conserva bien para llevar.',
        'source': 'Mesa · ejemplo',
        'image': '',
        'example': true,
      },
    ]) {
      await s.save('recipe', data);
    }
    if (context.mounted) message(context, 'Tres recetas de ejemplo añadidas.');
  },
);
