import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mesa/models.dart';
import 'package:mesa/store.dart';

Map<String, dynamic> recipe(String title) => {
  'title': title,
  'ingredients': ['2 huevos'],
  'steps': ['Batir.'],
  'servings': 2,
  'minutes': 10,
  'tags': <String>[],
  'image': '',
};

class Family {
  Map<String, dynamic>? record;
  final receipts = <String, Map<String, dynamic>>{};
  bool lose = false, offline = false;
  String epoch = 'epoch1';
  Completer<void>? gate;
  final started = Completer<void>();
  Future<http.Response> handle(http.Request req) async {
    if (offline) throw http.ClientException('Offline');
    dynamic answer;
    if (req.url.path == '/v1/snapshot') {
      answer = {
        'generation': epoch,
        'cursor': record?['revision'] ?? 0,
        'entities': [if (record != null) record],
      };
    } else if (req.url.path == '/v1/changes') {
      if (req.url.queryParameters['epoch'] != epoch) {
        return http.Response(jsonEncode({'detail': 'epoch'}), 409);
      }
      answer = {
        'cursor': record?['revision'] ?? 0,
        'entities': [if (record != null) record],
        'more': false,
      };
    } else if (req.url.path == '/v1/push') {
      final body = jsonDecode(req.body);
      if (body['generation'] != epoch) {
        return http.Response(jsonEncode({'detail': 'epoch'}), 409);
      }
      final op = Map<String, dynamic>.from(body['operations'][0]);
      if (!started.isCompleted) started.complete();
      if (gate != null) await gate!.future;
      final prior = receipts[op['id']];
      if (prior != null) {
        expect(jsonEncode(op), prior['fingerprint']);
        answer = {
          'results': [prior['result']],
        };
      } else {
        final version = record?['revision'] ?? 0;
        Map<String, dynamic> result;
        if (op['base'] != version) {
          result = {'status': 'conflict', 'server': record};
        } else {
          record = {
            'id': op['entity_id'],
            'kind': op['kind'],
            'revision': version + 1,
            'data': op['data'],
            'deleted': op['deleted'],
          };
          result = {'status': 'applied', 'entity': record};
        }
        receipts[op['id']] = {'fingerprint': jsonEncode(op), 'result': result};
        answer = {
          'results': [result],
        };
      }
      if (lose) {
        lose = false;
        throw http.ClientException('Acknowledgement lost');
      }
    } else {
      throw Exception(req.url);
    }
    return http.Response(
      jsonEncode(answer),
      200,
      headers: {'content-type': 'application/json'},
    );
  }
}

Future<void> settle(Cookbook s) async {
  for (var i = 0; i < 2000 && s.syncing; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 2));
  }
  expect(s.syncing, false);
}

Future<Cookbook> open({Family? family}) async {
  final s = Cookbook(
    LocalDb(NativeDatabase.memory()),
    client: family == null ? null : MockClient(family.handle),
  );
  await s.load(readSecrets: false);
  if (family != null) {
    await s.preference('url', 'http://127.0.0.1:8765');
    await s.preference('generation', family.epoch);
    s.token = 'test-token';
  }
  return s;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('Android uses private PC translation first and can retransate an existing Spanish recipe', () async {
    debugDefaultTargetPlatformOverride=TargetPlatform.android;
    addTearDown(()=>debugDefaultTargetPlatformOverride=null);
    final value={...recipe('Dolor'),'language':'es','original':{...recipe('Bread'),'language':'en','notes':''},'translation':{'target_language':'es'}};
    var nativeCalls=0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('mesa/native'),(call)async {nativeCalls++;throw StateError('Private server should be used first');});
    addTearDown(()=>TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('mesa/native'),null));
    final store=Cookbook(LocalDb(NativeDatabase.memory()),client:MockClient((req)async {
      final body=jsonDecode(req.body);expect(body['source'],'en');expect(body['force'],true);
      return http.Response(jsonEncode({...value,'title':'Pan'}),200,headers:{'content-type':'application/json'});
    }));
    await store.load(readSecrets:false);await store.preference('url','http://127.0.0.1:8765');store.token='test-token';
    final translated=await store.translateImportedRecipe(value,force:true);
    expect(translated['title'],'Pan');expect(nativeCalls,0);store.dispose();
  });
  test('Android can translate locally when the private PC is disconnected', () async {
    debugDefaultTargetPlatformOverride=TargetPlatform.android;
    addTearDown(()=>debugDefaultTargetPlatformOverride=null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('mesa/native'),(call)async {
      expect(call.method,'translateRecipeTexts');return (call.arguments['texts'] as List).map((t)=>(t as String).replaceAll('Bread','Pan').replaceAll('eggs','huevos').replaceAll('Mix','Mezcla')).toList();
    });
    addTearDown(()=>TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('mesa/native'),null));
    final store=Cookbook(LocalDb(NativeDatabase.memory()),client:MockClient((req)async=>throw http.ClientException('PC disconnected')));
    await store.load(readSecrets:false);await store.preference('url','http://127.0.0.1:8765');store.token='test-token';
    final translated=await store.translateImportedRecipe({...recipe('Bread'),'ingredients':['2 eggs'],'steps':['Mix.'],'language':'en'});
    expect(translated['title'],'Pan');expect(translated['ingredients'],['2 huevos']);store.dispose();
  });
  test(
    'Database file retains recipes and queue after closing and reopening',
    () async {
      final folder = await Directory('../output/local-persistence')
          .create(recursive: true);
      final file = File(
        '${folder.path}/${DateTime.now().microsecondsSinceEpoch}.sqlite',
      );
      final first = Cookbook(LocalDb(NativeDatabase(file)));
      await first.load(readSecrets: false);
      await first.save('recipe', recipe('Guardada en disco'), id: 'persist');
      await first.db.close();
      first.dispose();
      final second = Cookbook(LocalDb(NativeDatabase(file)));
      await second.load(readSecrets: false);
      expect(second.of('recipe').single.title, 'Guardada en disco');
      expect(second.pending, 1);
      await second.db.close();
      second.dispose();
      await file.delete();
    },
  );
  test(
    'Ingredient scaling preserves ranges, fractions and informal amounts',
    () {
      expect(scaleIngredient('1 1/2 cucharadas', 2), '3 cucharadas');
      expect(scaleIngredient('½ taza', 2), '1 taza');
      expect(scaleIngredient('2 a 3 huevos', 2), '2 a 3 huevos');
      expect(scaleIngredient('Sal al gusto', 2), 'Sal al gusto');
      expect(scaleIngredient('200 g de arroz', .5), '100 g de arroz');
      expect(searchKey('SOPA de Tomáte'), 'sopa de tomate');
    },
  );
  test('Offline edits coalesce, survive reload and preserve trash', () async {
    final s = await open();
    await s.save('recipe', recipe('Uno'), id: 'r1');
    await s.save('recipe', recipe('Dos'), id: 'r1');
    expect(s.pending, 1);
    await s.delete(s.get('r1')!);
    await s.load(readSecrets: false);
    expect(s.get('r1')!.deleted, true);
    await s.restore(s.get('r1')!);
    expect(s.of('recipe').single.title, 'Dos');
    s.dispose();
  });
  test(
    'A lost acknowledgement never allows mutation of an attempted operation',
    () async {
      final api = Family()..lose = true;
      final s = await open(family: api);
      await s.save('recipe', recipe('Primera'), id: 'r1');
      await settle(s);
      expect(s.pending, 0);
      expect(api.receipts.length, 1);
      expect(api.record!['revision'], 1);
      await s.save('recipe', recipe('Segunda'), id: 'r1');
      await settle(s);
      expect(s.pending, 0);
      expect(api.receipts.length, 2);
      expect(api.record!['revision'], 2);
      expect(s.get('r1')!.title, 'Segunda');
      s.dispose();
    },
  );
  test('An edit while a request is in flight is sent after the immutable first edit', () async {
    final api = Family()..gate = Completer<void>();
    final s = await open(family: api);
    await s.save('recipe', recipe('Primera'), id: 'r1');
    await api.started.future;
    await s.save('recipe', recipe('Segunda'), id: 'r1');
    expect(s.pending, 2);
    api.gate!.complete();
    await settle(s);
    expect(api.record!['data']['title'], 'Segunda');
    expect(s.pending, 0);
    s.dispose();
  });
  test(
    'Concurrent edits preserve local proposal and adopt family version',
    () async {
      final api = Family();
      final s = await open(family: api);
      await s.save('recipe', recipe('Original'), id: 'r1');
      await settle(s);
      api.record = {...api.record!, 'revision': 2, 'data': recipe('Familiar')};
      await s.save('recipe', recipe('Mi propuesta'), id: 'r1');
      await settle(s);
      expect(s.conflicts.single['data']['title'], 'Mi propuesta');
      expect(s.get('r1')!.title, 'Familiar');
      await s.preference('url', '');
      await s.resolve(s.conflicts.single, 'copy');
      expect(s.of('recipe').length, 2);
      expect(s.conflicts, isEmpty);
      s.dispose();
    },
  );
  test('Server generation change downloads snapshot without discarding local edits', () async {
    final api = Family()..offline = true;
    final s = await open(family: api);
    await s.save('recipe', recipe('Sin conexión'), id: 'r1');
    await settle(s);
    api.offline = false;
    api.epoch = 'restored';
    await s.sync();
    expect(s.get('r1')!.title, 'Sin conexión');
    expect(s.pending, 0);
    expect(s.generation, 'restored');
    s.dispose();
  });
  test(
    'Import validates all records and remaps menu recipe references',
    () async {
      final s = await open();
      final invalid = {
        'format': 'mesa-recetario',
        'version': 1,
        'entities': [
          {'id': 'r', 'kind': 'recipe', 'data': recipe('Bien')},
          {'id': 'bad', 'kind': 'recipe', 'data': recipe('')},
        ],
      };
      await expectLater(s.importData(jsonEncode(invalid)), throwsException);
      expect(s.entries, isEmpty);
      final value = {
        'format': 'mesa-recetario',
        'version': 1,
        'entities': [
          {'id': 'r', 'kind': 'recipe', 'data': recipe('Bien')},
          {
            'id': 'm',
            'kind': 'meal',
            'data': {
              'date': '2026-10-10',
              'slot': 'Comida',
              'title': 'Bien',
              'recipe_id': 'r',
              'servings': 2,
            },
          },
        ],
      };
      expect(await s.importData(jsonEncode(value)), 2);
      expect(s.of('meal').single.data['recipe_id'], s.of('recipe').single.id);
      s.dispose();
    },
  );
  test(
    'Reader cannot create edits and connection only allows HTTPS or loopback',
    () async {
      final s = await open();
      s.role = 'reader';
      await expectLater(s.save('recipe', recipe('No')), throwsException);
      expect(() => s.validateUrl('http://100.80.1.1:8765'), throwsException);
      expect(
        s.validateUrl('https://pc.example.ts.net/'),
        'https://pc.example.ts.net',
      );
      s.dispose();
    },
  );
}
