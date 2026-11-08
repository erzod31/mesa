import 'dart:io';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mesa/pages.dart';
import 'package:mesa/design.dart';
import 'package:mesa/store.dart';
import 'package:mesa/timers.dart';
import 'package:mesa/ui.dart';

import 'store_test.dart' show recipe;

void main() {
  test('Color roles keep readable contrast in light and dark themes', () {
    double contrast(Color a, Color b) {
      final x = a.computeLuminance(), y = b.computeLuminance();
      return ((x > y ? x : y) + .05) / ((x > y ? y : x) + .05);
    }

    final results = <String, Map<String, double>>{};
    for (final brightness in Brightness.values) {
      final c = MesaPalette.scheme(brightness);
      final values = {
        'primaryButton': contrast(c.onPrimary, c.primary),
        'secondaryButton': contrast(c.onSecondary, c.secondary),
        'selected': contrast(c.onPrimaryContainer, c.primaryContainer),
        'stepNumber': contrast(c.onSecondaryContainer, c.secondaryContainer),
        'body': contrast(c.onSurface, c.surface),
        'secondaryText': contrast(c.onSurfaceVariant, c.surface),
        'primaryText': contrast(c.primary, c.surface),
        'accentText': contrast(c.secondary, c.surface),
      };
      for (final entry in values.entries) {
        expect(
          entry.value,
          greaterThanOrEqualTo(4.5),
          reason: '${brightness.name}: ${entry.key}',
        );
      }
      expect(contrast(c.outline, c.surface), greaterThanOrEqualTo(3));
      results[brightness.name] = values;
    }
    File('../output/design-contrast.json')
        .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(results));
  });
  setUpAll(() async {
    for (final entry in {
      'Segoe UI': 'C:/Windows/Fonts/segoeui.ttf',
      'MaterialIcons': '../.tools/flutter/bin/cache/artifacts/material_fonts/materialicons-regular.otf',
    }.entries) {
      final loader = FontLoader(entry.key);
      loader.addFont(
        File(entry.value).readAsBytes().then(ByteData.sublistView),
      );
      await loader.load();
    }
  });

  Future<Cookbook> cookbook(WidgetTester tester) async =>
      (await tester.runAsync(() async {
        final store = Cookbook(LocalDb(NativeDatabase.memory()));
        await store.load(readSecrets: false);
        await store.save(
          'recipe',
          recipe('Tortilla para compartir')..addAll({
            'ingredients': ['2 huevos', '1 kg de patatas', '1 cebolla'],
            'steps': [
              'Pelar las patatas y cortarlas en trozos pequeños. Cocer durante 15 minutos y comprobar la textura.',
              'Batir los huevos y mezclar con las patatas. Cocinar por ambos lados hasta que esté al gusto.',
            ],
            'notes': 'Esta receta de prueba permite revisar los espacios y el tamaño del texto.',
          }),
          id: 'layout',
        );
        return store;
      }))!;

  Future<void> capture(WidgetTester tester, GlobalKey key, String name) async {
    await tester.runAsync(() async {
      final image =
          await (key.currentContext!.findRenderObject()
                  as RenderRepaintBoundary)
              .toImage();
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      await Directory('../output/screenshots').create(recursive: true);
      await File('../output/screenshots/$name.png')
          .writeAsBytes(data!.buffer.asUint8List());
      image.dispose();
    });
  }

  for (final size in [
    const Size(320, 740),
    const Size(390, 844),
    const Size(1360, 900),
  ]) {
    testWidgets(
      'Recipe anchors, portions and cooking stay usable at ${size.width}',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final store = await cookbook(tester);
        final timers = KitchenTimers(store);
        final key = GlobalKey();
        final large = size.width == 320;
        await tester.pumpWidget(
          RepaintBoundary(
            key: key,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: MesaApp(
                store: store,
                timers: timers,
              ).theme(large ? Brightness.dark : Brightness.light),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(large ? 2 : 1)),
                child: child!,
              ),
              home: Scaffold(
                appBar: AppBar(title: const Text('Mesa · Tu receta')),
                body: RecipeView(
                  store: store,
                  timers: timers,
                  id: 'layout',
                  onEdit: () {},
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('Ver ingredientes'));
        await tester.pumpAndSettle();
        expect(find.text('Ingredientes').hitTestable(), findsOneWidget);
        final ingredients = tester.getTopLeft(find.text('Ingredientes'));
        final preparation = tester.getTopLeft(find.text('Preparación'));
        if (size.width >= 900) {
          expect(preparation.dx, greaterThan(ingredients.dx + 100));
        } else {
          expect(preparation.dy, greaterThan(ingredients.dy));
        }
        if (!large) {
          await tester.tap(find.byTooltip('Más raciones'));
          await tester.pumpAndSettle();
          expect(find.text('3 huevos'), findsOneWidget);
          final checkbox = find.widgetWithText(CheckboxListTile, '3 huevos');
          await tester.ensureVisible(checkbox);
          await tester.pumpAndSettle();
          await tester.tap(checkbox);
          await tester.pumpAndSettle();
          expect(tester.widget<CheckboxListTile>(checkbox).value, true);
          expect(store.get('layout')!.lines('ingredients').first, '2 huevos');
        }
        await tester.tap(find.text('Ver ingredientes'));
        await tester.pumpAndSettle();
        await capture(
          tester,
          key,
          'mesa-layout-${large
              ? '320-letra-grande'
              : size.width > 900
              ? 'windows'
              : 'android'}',
        );
        expect(find.text('Paso a paso').hitTestable(), findsOneWidget);
        expect(
          find.text('A la compra'),
          size.width >= 700 && !large ? findsOneWidget : findsNothing,
        );
        await tester.tap(find.text('Más acciones'));
        await tester.pumpAndSettle();
        if (size.width < 700 || large) {
          expect(find.text('A la compra').hitTestable(), findsOneWidget);
        }
        expect(find.text('Planificar').hitTestable(), findsOneWidget);
        if (size.width < 1000 || large) {
          expect(find.text('Editar').hitTestable(), findsOneWidget);
        }
        if (size.width < 600) {
          await tester.tap(find.byTooltip('Cerrar menú'));
        } else {
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        }
        await tester.pumpAndSettle();
        expect(
          tester.getSize(find.widgetWithText(FilledButton, 'Paso a paso')).height,
          greaterThanOrEqualTo(48),
        );
        await tester.tap(find.text('Ver preparación'));
        await tester.pumpAndSettle();
        expect(find.text('Preparación').hitTestable(), findsOneWidget);
        await tester.tap(find.text('Paso a paso'));
        await tester.pumpAndSettle();
        expect(find.byType(CookingPage), findsOneWidget);
        expect(find.text('Siguiente').hitTestable(), findsOneWidget);
        if (!large) {
          await tester.scrollUntilVisible(
            find.widgetWithText(CheckboxListTile, '3 huevos'),
            200,
            scrollable: find
                .descendant(
                  of: find.byType(CookingPage),
                  matching: find.byType(Scrollable),
                )
                .first,
          );
          await tester.pumpAndSettle();
          expect(
            tester
                .widget<CheckboxListTile>(
                  find.widgetWithText(CheckboxListTile, '3 huevos'),
                )
                .value,
            true,
          );
        }
        await capture(
          tester,
          key,
          'mesa-cocinar-${large
              ? '320-letra-grande'
              : size.width > 900
              ? 'windows'
              : 'android'}',
        );
        await tester.tap(find.text('Siguiente'));
        await tester.pumpAndSettle();
        expect(find.text('PASO 2 DE 2').hitTestable(), findsOneWidget);
        expect(find.text('Terminar').hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        timers.dispose();
        store.dispose();
      },
    );
  }

  for (final size in [
    const Size(320, 740),
    const Size(390, 844),
    const Size(1360, 900),
  ]) {
    testWidgets(
      'Simple library keeps filtering and cancellation at ${size.width}',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final store = await cookbook(tester);
        await tester.runAsync(() async {
          await store.save('recipe', recipe('Zanahorias asadas'), id: 'other');
          await store.toggleFavorite(store.get('layout')!);
        });
        final timers = KitchenTimers(store);
        final key = GlobalKey();
        await tester.pumpWidget(
          RepaintBoundary(
            key: key,
            child: MesaApp(store: store, timers: timers),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('2 recetas').hitTestable(), findsOneWidget);
        expect(find.text('Filtros').hitTestable(), findsOneWidget);
        expect(find.text('Todas las categorías'), findsNothing);
        // Recipes appear in the first viewport without scrolling through controls.
        expect(
          find.text('Tortilla para compartir').hitTestable(),
          findsOneWidget,
        );
        await capture(tester, key, 'mesa-simple-${size.width.toInt()}');
        await tester.tap(find.text('Filtros'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Solo favoritas'));
        await tester.tap(find.text('Aplicar'));
        await tester.pumpAndSettle();
        expect(find.text('1 receta'), findsOneWidget);
        expect(find.text('Tortilla para compartir'), findsOneWidget);
        expect(find.text('Zanahorias asadas'), findsNothing);
        await tester.tap(find.text('Filtros'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Solo favoritas'));
        await tester.tap(find.text('Cancelar'));
        await tester.pumpAndSettle();
        expect(find.text('1 receta'), findsOneWidget);
        await tester.tap(find.text('Limpiar todos los filtros'));
        await tester.pumpAndSettle();
        expect(find.text('2 recetas'), findsOneWidget);
        await tester.tap(find.text('Semana'));
        await tester.pumpAndSettle();
        expect(find.text('Menú semanal').hitTestable(), findsOneWidget);
        expect(find.text('Añadir Comida'), findsNothing);
        expect(find.text('Añadir Cena'), findsNothing);
        await capture(tester, key, 'mesa-simple-menu-${size.width.toInt()}');
        await tester.tap(find.text('Mi espacio'));
        await tester.pumpAndSettle();
        expect(find.text('Exportar datos'), findsNothing);
        await capture(tester, key, 'mesa-simple-ajustes-${size.width.toInt()}');
        await tester.tap(find.text('Guardar y recuperar'));
        await tester.pumpAndSettle();
        expect(find.text('Exportar datos').hitTestable(), findsOneWidget);
        await tester.tap(find.text('Recetas'));
        await tester.pumpAndSettle();
        await tester.tap(
          size.width >= 1000
              ? find.widgetWithText(FilledButton, 'Nueva receta')
              : find.byTooltip('Nueva receta'),
        );
        await tester.pumpAndSettle();
        expect(find.byType(TextFormField).first.hitTestable(), findsOneWidget);
        expect(
          tester
              .widget<TextField>(
                find.descendant(
                  of: find.byType(TextFormField).first,
                  matching: find.byType(TextField),
                ),
              )
              .decoration!
              .labelText,
          'Nombre de la receta',
        );
        expect(find.text('Etiquetas separadas por comas'), findsNothing);
        await capture(tester, key, 'mesa-simple-editor-${size.width.toInt()}');
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        timers.dispose();
        store.dispose();
      },
    );
  }

  testWidgets('Desktop can expand recipe and return to library', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1360, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = await cookbook(tester);
    final timers = KitchenTimers(store);
    await tester.pumpWidget(MesaApp(store: store, timers: timers));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Tortilla para compartir'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tortilla para compartir'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Ampliar receta'));
    await tester.pumpAndSettle();
    expect(find.text('Filtros'), findsNothing);
    expect(find.text('Ingredientes'), findsOneWidget);
    await tester.tap(find.byTooltip('Volver al catálogo'));
    await tester.pumpAndSettle();
    expect(find.text('Filtros'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    timers.dispose();
    store.dispose();
  });
}
