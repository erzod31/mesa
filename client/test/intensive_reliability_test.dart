import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mesa/models.dart';
import 'package:mesa/store.dart';
import 'package:mesa/timers.dart';

import 'store_test.dart' show recipe, settle;

Map<String, dynamic> archive(List<Map<String, dynamic>> rows) => {
  'format': 'mesa-recetario',
  'version': 1,
  'entities': rows,
};
Map<String, dynamic> row(String id, String title) => {
  'id': id,
  'kind': 'recipe',
  'data': recipe(title),
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'Batches retry the same receipts without duplicating 250 recipes',
    () async {
      final receipts = <String, Map<String, dynamic>>{};
      final records = <String, Map<String, dynamic>>{};
      var pushes = 0;
      final s = Cookbook(
        LocalDb(NativeDatabase.memory()),
        client: MockClient((req) async {
          if (req.url.path == '/v1/push') {
            pushes++;
            final operations = jsonDecode(req.body)['operations'] as List;
            expect(operations.length, lessThanOrEqualTo(25));
            expect(
              operations.map((x) => x['entity_id']).toSet().length,
              operations.length,
            );
            final results = <Map<String, dynamic>>[];
            for (final raw in operations) {
              final id = raw['id'] as String;
              final record = {
                'id': raw['entity_id'],
                'kind': raw['kind'],
                'revision': 1,
                'data': raw['data'],
                'deleted': false,
              };
              if (!receipts.containsKey(id)) {
                receipts[id] = {
                  'id': id,
                  'status': 'applied',
                  'entity': record,
                };
                records[record['id'] as String] = record;
              }
              results.add(receipts[id]!);
            }
            if (pushes == 1) {
              throw http.ClientException('Response lost after commit');
            }
            return http.Response(jsonEncode({'results': results}), 200);
          }
          return http.Response(
            jsonEncode({'entities': [], 'cursor': 0, 'more': false}),
            200,
          );
        }),
      );
      await s.load(readSecrets: false);
      await s.importData(
        jsonEncode(
          archive([for (var i = 0; i < 250; i++) row('r$i', 'Receta $i')]),
        ),
      );
      await s.preference('url', 'http://127.0.0.1:8765');
      await s.preference('generation', 'fixture');
      s.token = 'synthetic';
      await s.sync();
      expect(s.pending, 0);
      expect(records.length, 250);
      expect(receipts.length, 250);
      expect(pushes, 11);
      expect(s.of('recipe').every((r) => r.revision == 1), isTrue);
      s.dispose();
    },
  );
  test('A repeated changes cursor stops instead of looping forever', () async {
    var pulls = 0;
    final s = Cookbook(
      LocalDb(NativeDatabase.memory()),
      client: MockClient((req) async {
        pulls++;
        return http.Response(
          jsonEncode({'entities': [], 'cursor': 0, 'more': true}),
          200,
        );
      }),
    );
    await s.load(readSecrets: false);
    await s.preference('url', 'http://127.0.0.1:8765');
    await s.preference('generation', 'fixture');
    s.token = 'synthetic';
    await s.sync().timeout(const Duration(seconds: 2));
    expect(pulls, 1);
    expect(s.syncing, false);
    expect(s.status, contains('descarga no avanza'));
    s.dispose();
  });
  test('Damaged timers cannot prevent opening the cookbook', () async {
    final s = Cookbook(LocalDb(NativeDatabase.memory()));
    await s.load(readSecrets: false);
    await s.preference('timers', '{invalid json');
    final timers = KitchenTimers(s);
    await timers.init();
    expect(timers.items, isEmpty);
    expect(timers.warning, contains('recuperar'));
    await expectLater(timers.add('Inválido', 0), throwsException);
    timers.dispose();
    s.dispose();
  });
  test(
    'Duplicate and missing archive IDs fail without writing anything',
    () async {
      final s = Cookbook(LocalDb(NativeDatabase.memory()));
      await s.load(readSecrets: false);
      for (final rows in [
        [row('same', 'Primera'), row('same', 'Segunda')],
        [
          row('ok', 'Primera'),
          {...row('bad', 'Segunda')}..remove('id'),
        ],
      ]) {
        await expectLater(
          s.importData(jsonEncode(archive(rows))),
          throwsException,
        );
        expect(s.entries, isEmpty);
        expect(s.pending, 0);
      }
      s.dispose();
    },
  );
  test(
    'A disk write failure rolls back the entire archive and its outbox',
    () async {
      final s = Cookbook(LocalDb(NativeDatabase.memory()));
      await s.load(readSecrets: false);
      await s.db.customStatement(
        "CREATE TRIGGER fail_import BEFORE INSERT ON entities WHEN json_extract(NEW.data,'\$.title')='Fail import' BEGIN SELECT RAISE(ABORT,'simulated disk failure'); END",
      );
      await expectLater(
        s.importData(
          jsonEncode(
            archive([row('r1', 'Correcta'), row('r2', 'Fail import')]),
          ),
        ),
        throwsA(anything),
      );
      expect(
        (await s.db
                .customSelect('SELECT COUNT(*) AS n FROM entities')
                .getSingle())
            .read<int>('n'),
        0,
      );
      expect(
        (await s.db
                .customSelect('SELECT COUNT(*) AS n FROM outbox')
                .getSingle())
            .read<int>('n'),
        0,
      );
      expect(s.entries, isEmpty);
      s.dispose();
    },
  );
  test(
    'Saving a different kind cannot turn a recipe into another entity',
    () async {
      final s = Cookbook(LocalDb(NativeDatabase.memory()));
      await s.load(readSecrets: false);
      await s.save('recipe', recipe('Conservada'), id: 'r1');
      await expectLater(
        s.save('collection', {
          'title': 'Catálogo',
          'type': 'catalog',
        }, id: 'r1'),
        throwsException,
      );
      expect(s.get('r1')!.kind, 'recipe');
      s.dispose();
    },
  );
  test('Impossible dates and malformed shared text are rejected locally', () {
    for (final date in ['2026-02-30', '2026-13-01', '2026-01-01T12:00:00']) {
      expect(
        () => validateEntryData('meal', {
          'date': date,
          'slot': 'Comida',
          'title': 'Sopa',
          'servings': 2,
        }),
        throwsException,
      );
    }
    expect(
      () => validateEntryData('meal', {
        'date': '2026-02-28',
        'slot': 'Cena',
        'title': 'Sopa',
        'servings': 2,
      }),
      returnsNormally,
    );
    expect(
      () => validateEntryData('recipe', {
        ...recipe('Sopa'),
        'notes': 'x' * 120001,
      }),
      throwsException,
    );
  });
  test(
    'A response for a different recipe cannot acknowledge a queued edit',
    () async {
      final s = Cookbook(
        LocalDb(NativeDatabase.memory()),
        client: MockClient((req) async {
          if (req.url.path == '/v1/push') {
            return http.Response(
              jsonEncode({
                'results': [
                  {
                    'status': 'applied',
                    'entity': {
                      'id': 'wrong',
                      'kind': 'recipe',
                      'revision': 1,
                      'data': recipe('Ajena'),
                    },
                  },
                ],
              }),
              200,
            );
          }
          return http.Response(
            jsonEncode({'entities': [], 'cursor': 0, 'more': false}),
            200,
          );
        }),
      );
      await s.load(readSecrets: false);
      await s.preference('url', 'http://127.0.0.1:8765');
      await s.preference('generation', 'fixture');
      s.token = 'synthetic';
      await s.save('recipe', recipe('Mi receta'), id: 'r1');
      await settle(s);
      expect(s.pending, 1);
      expect(s.get('r1')!.title, 'Mi receta');
      expect(s.get('wrong'), isNull);
      s.dispose();
    },
  );
  test(
    'Large archive is durable, preserves links and emits one update',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'mesa-intensive-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/mesa.sqlite');
      final s = Cookbook(LocalDb(NativeDatabase(file)));
      await s.load(readSecrets: false);
      final rows = <Map<String, dynamic>>[
        {
          'id': 'category',
          'kind': 'collection',
          'data': {'type': 'category', 'title': 'Prueba'},
        },
        for (var i = 0; i < 2000; i++)
          {
            'id': 'r$i',
            'kind': 'recipe',
            'data': {
              ...recipe('Receta $i'),
              'category_ids': ['category'],
            },
          },
        for (var i = 0; i < 100; i++)
          {
            'id': 'm$i',
            'kind': 'meal',
            'data': {
              'date': '2026-10-14',
              'slot': 'Comida',
              'title': 'Receta $i',
              'recipe_id': 'r$i',
              'servings': 2,
            },
          },
      ];
      var notifications = 0;
      s.addListener(() => notifications++);
      final clock = Stopwatch()..start();
      expect(await s.importData(jsonEncode(archive(rows))), 2101);
      clock.stop();
      expect(notifications, 1);
      expect(s.entries.length, 2101);
      expect(s.pending, 2101);
      final category = s.of('collection').single.id;
      expect(
        s
            .of('recipe')
            .every((r) => (r.data['category_ids'] as List).single == category),
        isTrue,
      );
      expect(
        s.of('meal').every((m) => s.get(m.data['recipe_id'])!.title == m.title),
        isTrue,
      );
      final exported = jsonEncode(s.exportData());
      s.dispose();
      await s.db.close();
      final reopened = Cookbook(LocalDb(NativeDatabase(file)));
      await reopened.load(readSecrets: false);
      expect(reopened.entries.length, 2101);
      expect(reopened.pending, 2101);
      expect(
        jsonEncode(reopened.exportData()['entities']),
        jsonEncode(jsonDecode(exported)['entities']),
      );
      await File('../output/auditoria-intensiva-2026-10-14/bulk-client.json')
          .writeAsString(
            jsonEncode({
              'items': 2101,
              'recipes': 2000,
              'import_ms': clock.elapsedMilliseconds,
              'notifications': notifications,
              'restart_verified': true,
              'pending_preserved': true,
            }),
          );
      reopened.dispose();
      await reopened.db.close();
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
