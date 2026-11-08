import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mesa/editor.dart';
import 'package:mesa/input_files.dart';
import 'package:mesa/store.dart';

void main() {
  test(
    'Oversized input is cancelled without reading subsequent chunks',
    () async {
      var visited = 0, closed = false;
      Stream<List<int>> content() async* {
        try {
          for (var i = 0; i < 20; i++) {
            visited++;
            yield [1, 2, 3, 4];
          }
        } finally {
          closed = true;
        }
      }

      await expectLater(
        readLimitedBytes(content(), maxBytes: 6),
        throwsException,
      );
      expect(visited, 2);
      expect(closed, isTrue);
    },
  );
  test('A file at the exact byte limit is preserved', () async {
    expect(
      await readLimitedBytes(
        Stream.fromIterable([
          [1, 2],
          [3, 4],
        ]),
        maxBytes: 4,
      ),
      [1, 2, 3, 4],
    );
  });
  testWidgets(
    'Nonfinite servings preserve draft without an asynchronous crash',
    (tester) async {
      final s = Cookbook(LocalDb(NativeDatabase.memory()));
      await tester.runAsync(() => s.load(readSecrets: false));
      await tester.pumpWidget(MaterialApp(home: RecipeEditor(store: s)));
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Nombre de la receta'),
        'Prueba',
      );
      final servings = find.widgetWithText(TextFormField, 'Raciones');
      await tester.ensureVisible(servings);
      await tester.enterText(servings, 'NaN');
      await tester.pump(const Duration(milliseconds: 500));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();
      expect(find.text('Introduce raciones entre 1 y 10.000.'), findsOneWidget);
      expect(s.entries, isEmpty);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      s.dispose();
    },
  );
  testWidgets(
    'An import finishing after dismissal does not update a dead dialog',
    (tester) async {
      final gate = Completer<http.Response>();
      final s = Cookbook(
        LocalDb(NativeDatabase.memory()),
        client: MockClient((req) => gate.future),
      );
      await tester.runAsync(() => s.load(readSecrets: false));
      await tester.runAsync(() => s.preference('url', 'http://127.0.0.1:8765'));
      s.token = 'synthetic';
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (c) => Scaffold(
              body: TextButton(
                onPressed: () => importRecipeDialog(
                  c,
                  s,
                  (_) =>
                      throw StateError('Dismissed import cannot open editor'),
                ),
                child: const Text('Abrir importación'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Abrir importación'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'texto de receta');
      await tester.tap(find.text('Revisar receta'));
      await tester.pump();
      final dialogContext = tester.element(find.byType(AlertDialog));
      Navigator.of(dialogContext).pop();
      await tester.pumpAndSettle();
      gate.complete(http.Response('not json', 500));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      s.dispose();
    },
  );
}
