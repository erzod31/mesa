import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mesa/store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  Future<Cookbook> store(http.Client client) async {
    final s = Cookbook(
      LocalDb(NativeDatabase.memory()),
      client: client,
      ephemeralSecrets: true,
    );
    await s.load(readSecrets: false);
    await s.preference('url', 'http://127.0.0.1:8765');
    s.token = 'isolated-test-token';
    addTearDown(s.dispose);
    return s;
  }

  test('OCR sends original bytes only to the paired server and retains output licence', () async {
    var calls = 0;
    final bytes = Uint8List.fromList([137, 80, 78, 71, 0, 255]);
    final s = await store(
      MockClient((request) async {
        calls++;
        expect(request.url.toString(), 'http://127.0.0.1:8765/v1/ocr');
        expect(request.bodyBytes, bytes);
        expect(request.headers['Content-Type'], 'application/octet-stream');
        expect(request.headers['Authorization'], 'Bearer isolated-test-token');
        expect(request.followRedirects, isFalse);
        return http.Response(
          jsonEncode({'engine': 'indra-ocr', 'text': '2 huevos\n1. Batir.'}),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    final result = await s.recognizeImage(bytes);
    expect(result, contains('2 huevos\n1. Batir.'));
    expect(result, contains('Datalab'));
    expect(result, contains('Open RAIL-M'));
    expect(calls, 1);
    expect(s.entries, isEmpty);
    expect(s.pending, 0);
  });

  test('OCR validates size and pairing before sending an image', () async {
    final s = await store(
      MockClient((_) async => throw StateError('No request allowed')),
    );
    await expectLater(s.recognizeImage(Uint8List(10000001)), throwsException);
    await expectLater(s.recognizeImage(Uint8List(0)), throwsException);
    s.token = '';
    await expectLater(
      s.recognizeImage(Uint8List.fromList([1])),
      throwsException,
    );
  });

  test('OCR does not retry an image upload when the server is busy', () async {
    var calls = 0;
    final s = await store(
      MockClient((_) async {
        calls++;
        return http.Response(
          jsonEncode({'detail': 'Espera a que termine.'}),
          429,
        );
      }),
    );
    await expectLater(
      s.recognizeImage(Uint8List.fromList([1])),
      throwsException,
    );
    expect(calls, 1);
  });

  test(
    'Empty OCR or an older server preserves manual input with a clear error',
    () async {
      final responses = [
        {'engine': 'indra-ocr', 'text': ''},
        {'text': 'old engine'},
      ];
      final s = await store(
        MockClient(
          (_) async => http.Response(jsonEncode(responses.removeAt(0)), 200),
        ),
      );
      await expectLater(
        s.recognizeImage(Uint8List.fromList([1])),
        throwsException,
      );
      await expectLater(
        s.recognizeImage(Uint8List.fromList([1])),
        throwsException,
      );
      expect(s.entries, isEmpty);
    },
  );
}
