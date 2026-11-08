import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mesa/brand.dart';
import 'package:mesa/design.dart';
import 'package:mesa/store.dart';
import 'package:mesa/timers.dart';
import 'package:mesa/ui.dart';

import 'store_test.dart' show recipe;

void main() {
  setUpAll(() async {
    for (final entry in {
      'Segoe UI': 'C:/Windows/Fonts/segoeui.ttf',
      'MaterialIcons': '../.tools/flutter/bin/cache/artifacts/material_fonts/materialicons-regular.otf',
    }.entries) {
      final font = FontLoader(entry.key);
      font.addFont(File(entry.value).readAsBytes().then(ByteData.sublistView));
      await font.load();
    }
  });
  Future<void> capture(WidgetTester tester, GlobalKey key, String name) async {
    await tester.runAsync(() async {
      final boundary =
          key.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final image = await boundary.toImage();
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await File('../output/screenshots/$name.png')
          .writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }

  for (final size in [
    const Size(320, 640),
    const Size(390, 844),
    const Size(1360, 900),
  ]) {
    testWidgets(
      'Brand launch remains legible and respects reduced motion at ${size.width}',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final key = GlobalKey();
        final store = Cookbook(LocalDb(NativeDatabase.memory()));
        final timers = KitchenTimers(store);
        await tester.pumpWidget(
          RepaintBoundary(
            key: key,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: MesaApp(
                store: store,
                timers: timers,
              ).theme(size.width == 320 ? Brightness.dark : Brightness.light),
              home: MediaQuery(
                data: MediaQueryData(
                  size: size,
                  textScaler: TextScaler.linear(size.width == 320 ? 1.5 : 1),
                  disableAnimations: true,
                ),
                child: const MesaLaunchPage(),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('mesa').hitTestable(), findsOneWidget);
        expect(
          find.text('La cocina que compartes').hitTestable(),
          findsOneWidget,
        );
        expect(find.byType(LinearProgressIndicator), findsNothing);
        expect(tester.takeException(), isNull);
        await capture(tester, key, 'mesa-brand-launch-${size.width.toInt()}');
        await tester.pumpWidget(const SizedBox());
        timers.dispose();
        store.dispose();
      },
    );
  }
  testWidgets(
    'Rounded card distinguishes its action from the nested favourite button and keyboard activation',
    (tester) async {
      var opened = 0, favorited = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 280,
                height: 180,
                child: MesaInteractiveCard(
                  onTap: () => opened++,
                  child: Column(
                    children: [
                      Align(
                        alignment: Alignment.topRight,
                        child: IconButton(
                          tooltip: 'Favorita de prueba',
                          onPressed: () => favorited++,
                          icon: const Icon(Icons.favorite_outline),
                        ),
                      ),
                      const Expanded(
                        child: Center(child: Text('Abrir receta')),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Favorita de prueba'));
      expect(favorited, 1);
      expect(opened, 0);
      await tester.tap(find.text('Abrir receta'));
      expect(opened, 1);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(opened + favorited, 3);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'Phone navigation and filter touch zones stay distinct from docked creation',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = (await tester.runAsync(() async {
        final value = Cookbook(LocalDb(NativeDatabase.memory()));
        await value.load(readSecrets: false);
        await value.save('recipe', recipe('Sopa de prueba'), id: 'geometry');
        return value;
      }))!;
      final timers = KitchenTimers(store);
      await tester.pumpWidget(MesaApp(store: store, timers: timers));
      await tester.pumpAndSettle();
      final nav = find.byType(NavigationDestination);
      final rects = [for (var i = 0; i < 4; i++) tester.getRect(nav.at(i))];
      for (var i = 0; i < rects.length; i++) {
        expect(rects[i].width, greaterThanOrEqualTo(48));
        expect(rects[i].height, greaterThanOrEqualTo(48));
        for (var j = i + 1; j < rects.length; j++) {
          expect(rects[i].overlaps(rects[j]), false);
        }
      }
      final create = tester.getRect(
        find.byKey(const ValueKey('recipe-creation-controls')),
      );
      expect(create.height, greaterThanOrEqualTo(48));
      for (final rect in rects) {
        expect(create.overlaps(rect), false);
      }
      final chips = [
        for (var i = 0; i < 2; i++)
          tester.getRect(find.byType(FilterChip).at(i)),
      ];
      expect(chips[0].overlaps(chips[1]), false);
      for (final rect in chips) {
        expect(rect.height, greaterThanOrEqualTo(48));
      }
      await tester.tap(find.text('Favoritas'));
      await tester.pumpAndSettle();
      expect(find.text('No hay recetas con esos filtros'), findsOneWidget);
      await tester.tap(find.text('Favoritas'));
      await tester.pumpAndSettle();
      final measured = {
        'screen': '320x640',
        'density': 1,
        'nav_targets': [
          for (final r in rects)
            {'x': r.left, 'y': r.top, 'w': r.width, 'h': r.height},
        ],
        'creation_target': {
          'x': create.left,
          'y': create.top,
          'w': create.width,
          'h': create.height,
        },
        'filter_targets': [
          for (final r in chips)
            {'x': r.left, 'y': r.top, 'w': r.width, 'h': r.height},
        ],
        'status': 'APROBADO',
        'limits': 'Current widgets at this size, not all controls or physical hardware.',
      };
      await tester.runAsync(
        () =>
            File('../output/brand-click-geometry.json')
                .writeAsString(jsonEncode(measured)),
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      timers.dispose();
      store.dispose();
    },
  );
}
