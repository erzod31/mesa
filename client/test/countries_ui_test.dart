import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mesa/discover.dart';
import 'package:mesa/pages.dart';
import 'package:mesa/models.dart';
import 'package:mesa/store.dart';
import 'package:mesa/timers.dart';
import 'package:mesa/ui.dart';

Future<void> settleRequests(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    for (final e in {
      'Segoe UI': 'C:/Windows/Fonts/segoeui.ttf',
      'MaterialIcons': '../.tools/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    }.entries) {
      final font = FontLoader(e.key);
      font.addFont(File(e.value).readAsBytes().then(ByteData.sublistView));
      await font.load();
    }
  });
  for (final width in [320.0, 390.0, 1360.0]) {
    testWidgets(
      'Country controls and guided cooking remain usable at $width with large text',
      (tester) async {
        tester.view.physicalSize = Size(width, 850);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final post = jsonDecode(
          File('test/fixtures/encantar-post.json').readAsStringSync(),
        );
        final store = (await tester.runAsync(() async {
          final s = Cookbook(
            LocalDb(NativeDatabase.memory()),
            client: MockClient((r) async {
              if (r.url.path.contains('recetasparaencantar')) {
                return http.Response(
                  jsonEncode(
                    r.url.path.contains('slug:')
                        ? post
                        : {
                            'posts': [post],
                            'found': 1,
                          },
                  ),
                  200,
                  headers: {'content-type': 'application/json; charset=utf-8'},
                );
              }
              return http.Response(
                r.url.host == 'creativegan.net'
                    ? '[]'
                    : '{"posts":[],"found":0}',
                200,
              );
            }),
          );
          await s.load(readSecrets: false);
          return s;
        }))!;
        final timers = KitchenTimers(store);
        await tester.pumpWidget(
          MaterialApp(
            theme: MesaApp(
              store: store,
              timers: timers,
            ).theme(Brightness.light),
            builder: (c, child) => MediaQuery(
              data: MediaQuery.of(c).copyWith(
                textScaler: TextScaler.linear(width == 1360 ? 1.5 : 2),
              ),
              child: child!,
            ),
            home: Scaffold(
              body: DiscoverRecipes(
                store: store,
                timers: timers,
                onEdit: ({entry, initial}) async {},
              ),
            ),
          ),
        );
        await settleRequests(tester);
        expect(find.byType(DropdownButtonFormField<String>), findsOneWidget);
        expect(find.text('Cambiar fuente'), findsNothing);
        await tester.scrollUntilVisible(
          find.text('Judías verdes a la japonesa'),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.tap(find.text('Judías verdes a la japonesa'));
        await settleRequests(tester);
        final start = find.byKey(const ValueKey('preview-step-by-step'));
        await tester.ensureVisible(start);
        await tester.tap(start);
        await tester.pumpAndSettle();
        expect(find.text('PASO 1 DE 4'), findsOneWidget);
        await tester.tap(find.text('Siguiente'));
        await tester.pumpAndSettle();
        expect(find.text('PASO 2 DE 4'), findsOneWidget);
        await tester.tap(find.byTooltip('Ver todos los pasos'));
        await tester.pumpAndSettle();
        expect(find.text('Todos los pasos'), findsOneWidget);
        await tester.tap(find.widgetWithText(ListTile, '3'));
        await tester.pumpAndSettle();
        expect(find.text('PASO 3 DE 4'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        timers.dispose();
        store.dispose();
      },
    );
  }
  testWidgets(
    'Changing country during a slow search discards obsolete results',
    (tester) async {
      final slow = Completer<http.Response>();
      final store = (await tester.runAsync(() async {
        final s = Cookbook(
          LocalDb(NativeDatabase.memory()),
          client: MockClient((_) => slow.future),
        );
        await s.load(readSecrets: false);
        return s;
      }))!;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DiscoverRecipes(
              store: store,
              onEdit: ({entry, initial}) async {},
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text('Polonia').last);
      await settleRequests(tester);
      expect(find.text('12 recetas con foto'), findsOneWidget);
      slow.complete(http.Response('{"posts":[],"found":0}', 200));
      await settleRequests(tester);
      expect(find.text('12 recetas con foto'), findsOneWidget);
      expect(store.prefs['discovery-country'], 'Polonia');
      await tester.pumpWidget(const SizedBox());
      store.dispose();
    },
  );
  testWidgets(
    'An unfinished recipe resumes; finishing resets the guided progress',
    (tester) async {
      final store = (await tester.runAsync(() async {
        final s = Cookbook(LocalDb(NativeDatabase.memory()));
        await s.load(readSecrets: false);
        return s;
      }))!;
      final recipe = Entry('guided', 'recipe', 1, {
        'title': 'Arroz familiar',
        'ingredients': ['200 g de arroz'],
        'steps': ['Lavar el arroz.', 'Cocer durante 20 minutos.'],
        'servings': 2,
      });
      Widget app() => MaterialApp(
        home: Builder(
          builder: (c) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.push(
                c,
                MaterialPageRoute(
                  builder: (_) =>
                      CookingPage(store: store, recipe: recipe, portions: 2),
                ),
              ),
              child: const Text('Abrir'),
            ),
          ),
        ),
      );
      await tester.pumpWidget(app());
      await tester.tap(find.text('Abrir'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Siguiente'));
      await settleRequests(tester);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Abrir'));
      await tester.pumpAndSettle();
      expect(find.text('PASO 2 DE 2'), findsOneWidget);
      await tester.tap(find.text('Terminar'));
      await settleRequests(tester);
      await tester.tap(find.text('Abrir'));
      await tester.pumpAndSettle();
      expect(find.text('PASO 1 DE 2'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      store.dispose();
    },
  );
}
