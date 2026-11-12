import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mesa/source_directory.dart';
import 'package:mesa/source_registry.dart';

void main() {
  setUpAll(() async {
    final font = FontLoader('Segoe UI');
    font.addFont(
      File('C:/Windows/Fonts/segoeui.ttf')
          .readAsBytes()
          .then((bytes) => ByteData.sublistView(bytes)),
    );
    await font.load();
    final icons = FontLoader('MaterialIcons');
    icons.addFont(
      File(
        '../.tools/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
      ).readAsBytes().then((bytes) => ByteData.sublistView(bytes)),
    );
    await icons.load();
  });

  test(
    'All current sources are classified; unverified totals are never zero',
    () {
      final rows = classifiedSources();
      expect(rows, hasLength(22));
      expect(
        rows.map((s) => s.id).toSet(),
        catalogSources.map((s) => s.id).toSet(),
      );
      expect(rows.where((s) => s.recipeCount != null), hasLength(11));
      expect(rows.where((s) => s.recipeCount == null), hasLength(11));
      expect(rows.take(3).map((s) => s.id), [
        'delokos-es',
        'wiki-ja',
        'wiki-pl',
      ]);
      final counts = rows
          .where((s) => s.recipeCount != null)
          .map((s) => s.recipeCount!)
          .toList();
      expect(
        counts,
        orderedEquals([...counts]..sort((a, b) => b.compareTo(a))),
      );
      expect(sourceCountLabel(rows.first), '1.745 recetas');
      expect(sourceCountLabel(rows[1]), '1.419 fichas en el índice');
      expect(sourceRankingPosition('delokos-es'), 1);
      expect(sourceRankingPosition('wiki-es'), 4);
      expect(sourceRankingPosition('es-petitchef'), isNull);
      expect(sourceRankingPosition('us-myplate'), isNull);
      expect(rows.where((s) => s.recipeCount != null).last.id, 'book-polaca');
      expect(rows.any((s) => s.id == 'caribe-goya'), false);
      expect(rows.any((s) => s.id == 'mx-kiwilimon'), false);
    },
  );

  test('Country and availability classify only sources with in-app content', () {
    expect(classifiedSources(country: 'México'), isEmpty);
    expect(classifiedSources(query: 'delokos').single.id, 'delokos-es');
    final available = classifiedSources(order: SourceOrder.availability);
    expect(available.where((s) => s.browseable), hasLength(22));
    expect(available.where((s) => s.consultationOnly), hasLength(0));
    expect(available.map((s) => s.id), isNot(contains('agro-caribe')));
    expect(available.map((s) => s.id), isNot(contains('agro-arracacha')));
    expect(available.map((s) => s.id), isNot(contains('sabores-uy')));
    expect(classifiedSources(query: 'inexistente'), isEmpty);
  });

  Widget home({required Future<void> Function(String) open, Key? captureKey}) =>
      RepaintBoundary(
        key: captureKey,
        child: MaterialApp(
          theme: ThemeData(fontFamily: 'Segoe UI'),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showDialog<String>(
                  context: context,
                  builder: (_) => SourceDirectory(onOpenUrl: open),
                ),
                child: const Text('Abrir fuentes'),
              ),
            ),
          ),
        ),
      );

  testWidgets(
    'Ranking exposes its evidence and searches a licensed catalogue source',
    (tester) async {
      final opened = <String>[];
      await tester.pumpWidget(
        home(
          open: (url) async {
            opened.add(url);
          },
        ),
      );
      await tester.tap(find.text('Abrir fuentes'));
      await tester.pumpAndSettle();
      expect(find.text('22 de 22 fuentes'), findsOneWidget);
      expect(
        find.text('22 actuales · 2 conservadas + 20 libres añadidas'),
        findsOneWidget,
      );
      await tester.ensureVisible(
        find.byTooltip('Ver recuento y estado de La cocina delokos'),
      );
      await tester.tap(find.byTooltip('Ver recuento y estado de La cocina delokos'));
      await tester.pumpAndSettle();
      expect(find.text('Revisión: 2026-10-11'), findsOneWidget);
      await tester.tap(find.text('Abrir comprobación'));
      expect(
        opened.single,
        catalogSources.firstWhere((s) => s.id == 'delokos-es').countEvidence,
      );
      await tester.tap(find.text('Cerrar'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.byType(TextField), -200);
      await tester.enterText(find.byType(TextField), 'delokos');
      await tester.pumpAndSettle();
      expect(find.text('1 de 22 fuentes'), findsOneWidget);
      expect(find.text('La cocina delokos'), findsOneWidget);
      expect(find.text('1.745 recetas'), findsOneWidget);
      expect(find.textContaining('Catálogo operativo'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'inexistente');
      await tester.pumpAndSettle();
      expect(find.text('No hay fuentes para este filtro.'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'delokos');
      await tester.pumpAndSettle();
      expect(
        find.text('1'),
        findsOneWidget,
      ); // The original position survives filtering.
      expect(find.text('1.745 recetas'), findsOneWidget);
      await tester.tap(find.byType(DropdownButtonFormField<SourceOrder>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Nombre').last);
      await tester.pumpAndSettle();
      expect(find.text('Todas las fuentes · 1'), findsOneWidget);
      expect(find.text('2'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  for (final size in [const Size(320, 640), const Size(1360, 900)]) {
    testWidgets('Classified directory fits $size with accessible text', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      tester.platformDispatcher.textScaleFactorTestValue = size.width < 400
          ? 1.5
          : 1;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final key = GlobalKey();
      await tester.pumpWidget(home(open: (_) async {}, captureKey: key));
      await tester.tap(find.text('Abrir fuentes'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      if (size.width < 400) {
        tester.view.viewInsets = const FakeViewPadding(bottom: 280);
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), 'Wikilibros');
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        tester.view.resetViewInsets();
        addTearDown(tester.view.resetViewInsets);
        await tester.pumpAndSettle();
      }
      await tester.enterText(find.byType(TextField), 'Wikilibros');
      await tester.pumpAndSettle();
      expect(find.text('1 de 22 fuentes'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.enterText(find.byType(TextField), '');
      await tester.pumpAndSettle();
      if (size.width < 400) {
        await tester.ensureVisible(
          find.byKey(const ValueKey('source:delokos-es')),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('1. La cocina delokos'), findsOneWidget);
      }
      await tester.runAsync(() async {
        final boundary =
            key.currentContext!.findRenderObject() as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 1);
        final png = await image.toByteData(format: ui.ImageByteFormat.png);
        final file = File(
          '../output/screenshots/source-directory-${size.width.toInt()}.png',
        );
        await file.parent.create(recursive: true);
        await file.writeAsBytes(png!.buffer.asUint8List());
        image.dispose();
      });
      await tester.pumpWidget(const SizedBox());
    });
  }
}
