import 'dart:io';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
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
      final loader = FontLoader(entry.key);
      loader.addFont(
        File(entry.value).readAsBytes().then(ByteData.sublistView),
      );
      await loader.load();
    }
  });

  testWidgets(
    'All destinations remain reachable on a narrow phone with large text',
    (tester) async {
      const size = Size(320, 740);
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = (await tester.runAsync(() async {
        final value = Cookbook(LocalDb(NativeDatabase.memory()));
        await value.load(readSecrets: false);
        await value.save('recipe', recipe('Sopa familiar'), id: 'synthetic');
        return value;
      }))!;
      final timers = KitchenTimers(store);
      final key = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: key,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: MesaApp(store: store, timers: timers).theme(Brightness.dark),
            home: MediaQuery(
              data: const MediaQueryData(
                size: size,
                textScaler: TextScaler.linear(1.5),
              ),
              child: Home(store: store, timers: timers),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      for (final entry in {
        1: 'Menú semanal',
        2: 'Lista de compra',
        3: 'Familia y conexión',
      }.entries) {
        await tester.tap(find.byType(NavigationDestination).at(entry.key));
        await tester.pumpAndSettle();
        expect(find.text(entry.value).hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
      await tester.runAsync(() async {
        final image =
            await (key.currentContext!.findRenderObject()
                    as RenderRepaintBoundary)
                .toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await File('../output/screenshots/mesa-modern-320-dark-large.png')
            .writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
      await tester.tap(find.byType(NavigationDestination).first);
      await tester.pumpAndSettle();
      expect(find.byTooltip('Nueva receta').hitTestable(), findsOneWidget);
      expect(store.get('synthetic')!.title, 'Sopa familiar');
      await tester.pumpWidget(const SizedBox());
      timers.dispose();
      store.dispose();
    },
  );

  testWidgets(
    'An empty short phone has one reachable creation action without a floating overlay',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = (await tester.runAsync(() async {
        final value = Cookbook(LocalDb(NativeDatabase.memory()));
        await value.load(readSecrets: false);
        return value;
      }))!;
      final timers = KitchenTimers(store);
      await tester.pumpWidget(MesaApp(store: store, timers: timers));
      await tester.pumpAndSettle();
      expect(find.byType(FloatingActionButton), findsNothing);
      final create = find.byTooltip('Nueva receta');
      await tester.ensureVisible(create);
      await tester.pumpAndSettle();
      expect(create.hitTestable(), findsOneWidget);
      await tester.tap(create);
      await tester.pumpAndSettle();
      expect(find.text('Nombre de la receta'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      timers.dispose();
      store.dispose();
    },
  );

  test('An offline recipe and pending operation survive closing and reopening SQLite', () async {
    final laboratory = Directory(
      '../output/auditoria-mesa-2026-10-12/05_analisis_dinamico',
    );
    await laboratory.create(recursive: true);
    final directory = await laboratory.createTemp('sqlite-');
    final file = File('${directory.path}/test.sqlite');
    final firstDb = LocalDb(NativeDatabase(file));
    final first = Cookbook(firstDb);
    await first.load(readSecrets: false);
    await first.save(
      'recipe',
      recipe('MARCADOR-SINTETICO-20261012'),
      id: 'audit-offline',
    );
    expect(first.pending, 1);
    first.dispose();
    await firstDb.close();
    final secondDb = LocalDb(NativeDatabase(file));
    final second = Cookbook(secondDb);
    try {
      await second.load(readSecrets: false);
      expect(second.get('audit-offline')!.title, 'MARCADOR-SINTETICO-20261012');
      expect(second.pending, 1);
      expect(second.url, isEmpty);
      expect(second.token, isEmpty);
      await File('${laboratory.path}/persistencia-offline.json').writeAsString(
        jsonEncode({
          'status': 'APROBADO',
          'database': file.absolute.path,
          'recipe_after_reopen': second.get('audit-offline')!.title,
          'pending_after_reopen': second.pending,
          'network_used': false,
          'scope': 'Close/reopen SQLite and recreate Cookbook in one Dart process. Native application process restart remains pending.',
        }),
      );
    } finally {
      second.dispose();
      await secondDb.close();
      // Keep the synthetic database as reproducible audit evidence.
    }
  });
}
