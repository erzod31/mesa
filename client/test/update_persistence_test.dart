import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mesa/store.dart';

Map<String, dynamic> recipe(String title) => {
  'title': title,
  'ingredients': ['2 huevos'],
  'steps': ['Batir.'],
  'servings': 2,
  'tags': <String>[],
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('Populated SQLite queue survives fake update, lost ack, restart and idempotent replay', () async {
    final directory = await Directory('../output/implementation-DG-0033/queue')
        .create(recursive: true);
    final profile = await directory.createTemp('profile-');
    final dbFile = File('${profile.path}/mesa.sqlite');
    // File-backed fake vault, never invokes Windows Credential Manager.
    final vault = File('${profile.path}/synthetic-vault.json');
    await vault.writeAsString(
      jsonEncode({'mesa-token': 'SYNTHETIC-DG-0033-TOKEN'}),
    );
    var vaultWrites = 0;
    const channel = MethodChannel(
      'plugins.it_nomads.com/flutter_secure_storage',
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'read') {
            return (jsonDecode(await vault.readAsString())
                as Map)[call.arguments['key']];
          }
          vaultWrites++;
          throw StateError('Update must not mutate credentials');
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );
    var offline = false, loseAck = true;
    final started = Completer<void>(), gate = Completer<void>();
    final records = <String, Map<String, dynamic>>{},
        receipts = <String, Map<String, dynamic>>{};
    final attempts = <String, List<String>>{};
    Future<http.Response> handle(http.Request req) async {
      if (offline) throw http.ClientException('Synthetic offline');
      expect(req.headers['Authorization'], 'Bearer SYNTHETIC-DG-0033-TOKEN');
      dynamic answer;
      if (req.url.path == '/v1/push') {
        if (!started.isCompleted) started.complete();
        await gate.future;
        final results = <dynamic>[];
        for (final op in jsonDecode(req.body)['operations']) {
          final id = op['id'] as String;
          attempts.putIfAbsent(id, () => []).add(jsonEncode(op));
          if (!receipts.containsKey(id)) {
            final prior = records[op['entity_id']];
            expect(op['base'], prior?['revision'] ?? 0);
            final entity = <String, dynamic>{
              'id': op['entity_id'],
              'kind': op['kind'],
              'revision': (prior?['revision'] ?? 0) + 1,
              'data': op['data'],
              'deleted': op['deleted'],
            };
            records[op['entity_id']] = entity;
            receipts[id] = {'status': 'applied', 'entity': entity};
          }
          results.add(receipts[id]);
        }
        if (loseAck) {
          loseAck = false;
          offline = true;
          throw http.ClientException('Lost acknowledgement');
        }
        answer = {'results': results};
      } else {
        answer = {
          'generation': 'epoch-fixture',
          'cursor': 10,
          'entities': records.values.toList(),
          'more': false,
        };
      }
      return http.Response(
        jsonEncode(answer),
        200,
        headers: {'content-type': 'application/json'},
      );
    }

    Future<Cookbook> open() async {
      final value = Cookbook(
        LocalDb(NativeDatabase(dbFile)),
        client: MockClient(handle),
        secrets: const FlutterSecureStorage(),
      );
      await value.load();
      return value;
    }

    final first = await open();
    await first.preference('url', 'http://127.0.0.1:54321');
    await first.preference('generation', 'epoch-fixture');
    await first.preference('profile', 'Familia sintética');
    await first.save('recipe', recipe('Antes de perder respuesta'), id: 'r1');
    await started.future;
    await first.save('recipe', recipe('Edición mientras se envía'), id: 'r1');
    await first.save('recipe', recipe('Segunda receta pendiente'), id: 'r2');
    gate.complete();
    for (var i = 0; i < 1500 && first.syncing; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 3));
    }
    expect(first.syncing, false);
    expect(first.pending, 3);
    final before =
        (await first.db.customSelect('SELECT * FROM outbox ORDER BY seq').get())
            .map((r) => r.data)
            .toList();
    expect(before.first['attempted'], 1);
    expect(before.skip(1).every((r) => r['attempted'] == 0), true);
    await first.db.customStatement('INSERT INTO conflicts VALUES (?,?)', [
      'conflict-fixture',
      jsonEncode({'data': recipe('Propuesta pendiente')}),
    ]);
    // The installer/launcher adapter replaces only a dummy binary, not profile.
    final binary = File('${profile.path}/fake-app.bin');
    await binary.writeAsString('old');
    await first.flushForAppUpdate();
    await binary.writeAsString('new');
    await first.db.close();
    first.dispose();
    final second = await open();
    expect(second.token, 'SYNTHETIC-DG-0033-TOKEN');
    expect(vaultWrites, 0);
    expect(second.url, 'http://127.0.0.1:54321');
    expect(second.pending, 3);
    expect(second.of('recipe').length, 2);
    expect(second.conflicts.length, 1);
    final after =
        (await second.db
                .customSelect('SELECT * FROM outbox ORDER BY seq')
                .get())
            .map((r) => r.data)
            .toList();
    expect(after, before);
    expect(
      (await second.db.customSelect('PRAGMA quick_check').getSingle())
          .data
          .values
          .single,
      'ok',
    );
    offline = false;
    await second.sync();
    expect(second.pending, 0);
    expect(receipts.length, 3);
    expect(records['r1']!['revision'], 2);
    expect(records['r1']!['data']['title'], 'Edición mientras se envía');
    expect(
      attempts.values.every((payloads) => payloads.toSet().length == 1),
      true,
    );
    final summary = {
      'taskId': 'DG-0033',
      'testLevel':
          'real SQLite; file-backed fake vault; mock network and installer',
      'pendingBefore': 3,
      'attemptedBefore': 1,
      'unsentBefore': 2,
      'byteIdenticalQueueAfterRestart': true,
      'credentialPreserved': true,
      'conflictPreserved': true,
      'deduplicatedReplay': true,
      'pendingAfterReplay': second.pending,
      'realInstallerExecuted': false,
      'profile': profile.absolute.path,
    };
    await File('${directory.path}/result.json')
        .writeAsString(const JsonEncoder.withIndent('  ').convert(summary));
    await second.db.close();
    second.dispose();
  });
}
