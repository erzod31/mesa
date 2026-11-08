import 'dart:io';
import 'dart:ui' as ui;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mesa/action_menu.dart';
import 'package:mesa/pages.dart';
import 'package:mesa/store.dart';
import 'package:mesa/timers.dart';
import 'package:mesa/ui.dart';
import 'package:mesa/photos.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'store_test.dart' show recipe;

void main() {
  testWidgets(
    'Inactive preserved pages do not query photos until visible again',
    (tester) async {
      var calls = 0;
      Widget surface(bool active) => MaterialApp(
        home: TickerMode(
          enabled: active,
          child: RecipePhoto(
            {'url': 'https://example.org/fixture.jpg'},
            clientFactory: () => MockClient((request) async {
              calls++;
              return http.Response('', 404);
            }),
          ),
        ),
      );
      await tester.pumpWidget(surface(false));
      await tester.pumpAndSettle();
      expect(calls, 0);
      await tester.pumpWidget(surface(true));
      await tester.pumpAndSettle();
      expect(calls, 1);
      await tester.pumpWidget(surface(false));
      await tester.pumpAndSettle();
      expect(calls, 1);
      await tester.pumpWidget(surface(true));
      await tester.pumpAndSettle();
      expect(calls, 2);
      await tester.pumpWidget(const SizedBox());
    },
  );
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
  Future<Cookbook> fixture(WidgetTester tester) async =>
      (await tester.runAsync(() async {
        final s = Cookbook(LocalDb(NativeDatabase.memory()));
        await s.load(readSecrets: false);
        await s.save('recipe', recipe('Sopa familiar'), id: 'menu-fixture');
        return s;
      }))!;
  Future<void> shot(WidgetTester tester, GlobalKey key, String name) async {
    await tester.runAsync(() async {
      final frame =
          await (key.currentContext!.findRenderObject()
                  as RenderRepaintBoundary)
              .toImage();
      final bytes = await frame.toByteData(format: ui.ImageByteFormat.png);
      await File('../output/screenshots/$name.png')
          .writeAsBytes(bytes!.buffer.asUint8List());
      frame.dispose();
    });
  }

  testWidgets(
    'Search and filters survive navigation; creation stays outside content',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final s = await fixture(tester);
      final timers = KitchenTimers(s);
      final key = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: key,
          child: MesaApp(store: s, timers: timers),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'Sopa');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Hasta 30 min'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Semana').last);
      await tester.pumpAndSettle();
      expect(find.byTooltip('Nueva receta'), findsNothing);
      await tester.tap(find.text('Recetas').last);
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField).first).controller!.text,
        'Sopa',
      );
      expect(
        tester
            .widget<FilterChip>(find.widgetWithText(FilterChip, 'Hasta 30 min'))
            .selected,
        true,
      );
      final creation = tester.getRect(
        find.byKey(const ValueKey('recipe-creation-controls')),
      );
      expect(
        creation.overlaps(tester.getRect(find.byType(CustomScrollView).first)),
        false,
      );
      expect(
        find.byTooltip('Importar enlace o texto').hitTestable(),
        findsOneWidget,
      );
      await shot(tester, key, 'mesa-menu-dock-390');
      await tester.tap(find.byTooltip('Importar enlace o texto'));
      await tester.pumpAndSettle();
      expect(find.text('Importar receta'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      timers.dispose();
      s.dispose();
    },
  );
  for (final size in [const Size(320, 740), const Size(1360, 900)]) {
    testWidgets(
      'Adaptive menu only activates enabled actions at ${size.width}',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final called = <String>[];
        final key = GlobalKey();
        final store = await fixture(tester);
        final timers = KitchenTimers(store);
        await tester.pumpWidget(
          RepaintBoundary(
            key: key,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: MesaApp(
                store: store,
                timers: timers,
              ).theme(Brightness.light),
              home: Scaffold(
                body: Center(
                  child: MesaActionMenuButton(
                    title: 'Acciones de receta',
                    label: 'Más acciones',
                    actions: const [
                      MesaMenuAction(
                        id: 'buy',
                        label: 'A la compra',
                        icon: Icons.shopping_bag_outlined,
                        group: 'Organizar',
                      ),
                      MesaMenuAction(
                        id: 'disabled',
                        label: 'Acción no disponible',
                        icon: Icons.edit_outlined,
                        enabled: false,
                        group: 'Receta',
                      ),
                      MesaMenuAction(
                        id: 'trash',
                        label: 'Mover a la papelera',
                        icon: Icons.delete_outline,
                        destructive: true,
                        group: 'Papelera',
                      ),
                    ],
                    onSelected: called.add,
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Más acciones'));
        await tester.pumpAndSettle();
        expect(
          find.byType(size.width < 600 ? BottomSheet : MenuAnchor),
          findsOneWidget,
        );
        await shot(tester, key, 'mesa-menu-actions-${size.width.toInt()}');
        if (size.width >= 600) {
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
          await tester.pumpAndSettle();
          expect(called, isEmpty);
          expect(find.text('A la compra'), findsNothing);
          await tester.tap(find.text('Más acciones'));
          await tester.pumpAndSettle();
        }
        await tester.tap(find.text('Acción no disponible'));
        await tester.pumpAndSettle();
        expect(called, isEmpty);
        await tester.tap(find.text('A la compra'));
        await tester.pumpAndSettle();
        expect(called, ['buy']);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        timers.dispose();
        store.dispose();
      },
    );
  }
  testWidgets('Reader menu omits editing and destructive actions', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final s = await fixture(tester);
    s.role = 'reader';
    final timers = KitchenTimers(s);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RecipeView(
            store: s,
            timers: timers,
            id: 'menu-fixture',
            onEdit: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Más acciones'));
    await tester.pumpAndSettle();
    expect(find.text('Añadir a favoritas'), findsOneWidget);
    expect(find.text('Historial'), findsOneWidget);
    for (final text in ['Mover a la papelera', 'Editar', 'Planificar']) {
      expect(find.text(text), findsNothing);
    }
    await tester.pumpWidget(const SizedBox());
    timers.dispose();
    s.dispose();
  });
  testWidgets('Desktop retains direct creation through Ctrl+N', (tester) async {
    tester.view.physicalSize = const Size(1360, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final s = await fixture(tester);
    final timers = KitchenTimers(s);
    await tester.pumpWidget(MesaApp(store: s, timers: timers));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(TextField).first);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(find.text('Nombre de la receta'), findsOneWidget);
    expect(s.of('recipe').length, 1);
    await tester.pumpWidget(const SizedBox());
    timers.dispose();
    s.dispose();
  });
}
