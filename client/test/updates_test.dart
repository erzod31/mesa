import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mesa/updates.dart';
import 'package:mesa/update_signature.dart';
import 'package:cryptography/cryptography.dart';

final feed = Uri.parse('https://family.example:9443/descargar/update.json');
Map<String, dynamic> manifest({int code = 10}) => {
  'package': 'com.mesa.mesa',
  'version': '1.5.1',
  'version_code': code,
  'size': 50000000,
  'sha256': 'a' * 64,
  'apk_path': '/descargar/Mesa-Android-1.5.1-$code.apk',
  'min_sdk': 24,
  'abis': ['arm64-v8a'],
  'notes': ['Mejora de prueba.'],
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Map<String, dynamic> signed;
  late String publicKey;
  setUpAll(() async {
    final algorithm = Ed25519();
    final key = await algorithm.newKeyPairFromSeed(List.filled(32, 7));
    final release = {
      ...manifest(),
      'product': 'com.mesa.mesa',
      'platform': 'android',
      'architecture': 'arm64-v8a',
    };
    final sig = await algorithm.sign(
      utf8.encode(canonicalUpdate(release)),
      keyPair: key,
    );
    publicKey = (await key.extractPublicKey()).bytes
        .map((n) => n.toRadixString(16).padLeft(2, '0'))
        .join();
    signed = {...release, 'signature': base64Encode(sig.bytes)};
  });
  const channel = MethodChannel('mesa/updates');
  var allowed = false;
  var installedCode = 9;
  var sdk = 36;
  var calls = <String>[];
  Future<void> Function()? download;
  setUp(() {
    allowed = false;
    installedCode = 9;
    sdk = 36;
    calls = [];
    download = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call.method);
          switch (call.method) {
            case 'info':
              return {
                'version': '1.5.0',
                'version_code': installedCode,
                'sdk': sdk,
                'abis': ['arm64-v8a'],
                'can_install': allowed,
              };
            case 'permission':
              return allowed;
            case 'download':
              await download?.call();
              return null;
            case 'cancel':
              return null;
            case 'install':
              return null;
          }
          throw MissingPluginException();
        });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('Update metadata uses a fixed same-origin immutable APK', () {
    final release = AndroidRelease.parse(manifest(), feed);
    expect(
      release.url.toString(),
      'https://family.example:9443/descargar/Mesa-Android-1.5.1-10.apk',
    );
    for (final bad in [
      {'package': 'another.app'},
      {'sha256': 'bad'},
      {'size': 120000001},
      {'version_code': 0},
      {'apk_path': 'https://attacker.example/app.apk'},
      {'apk_path': '/descargar/Mesa-Android.apk'},
      {'abis': []},
      {
        'notes': ['a' * 1001],
      },
    ]) {
      expect(
        () => AndroidRelease.parse({...manifest(), ...bad}, feed),
        throwsException,
      );
    }
  });

  test('Feed needs HTTPS and sends no family credentials', () async {
    final client = MockClient((request) async {
      expect(request.headers.containsKey('authorization'), false);
      return http.Response(jsonEncode(signed), 200);
    });
    expect(
      (await UpdateApi(client, feed: feed, publicKey: publicKey).check()).code,
      10,
    );
    await expectLater(
      UpdateApi(
        client,
        feed: Uri.parse('http://family.example/update'),
      ).check(),
      throwsException,
    );
  });
  test('Missing signature, tampering, foreign identity and foreign signer fail closed', () async {
    for (final data in [
      manifest(),
      {...signed, 'size': 123},
      {...signed, 'platform': 'windows'},
    ]) {
      final client = MockClient(
        (_) async => http.Response(jsonEncode(data), 200),
      );
      await expectLater(
        UpdateApi(client, feed: feed, publicKey: publicKey).check(),
        throwsException,
      );
    }
    await expectLater(verifyAndroidUpdate(signed), throwsException);
    await verifyAndroidUpdate(signed, publicKey: publicKey);
  });
  test('Cross-origin redirects and oversized feeds are rejected', () async {
    var requests = 0;
    final client = MockClient((request) async {
      requests++;
      return http.Response(
        '',
        302,
        headers: {'location': 'https://attacker.example/update'},
      );
    });
    await expectLater(UpdateApi(client, feed: feed).check(), throwsException);
    expect(requests, 1);
    await expectLater(
      UpdateApi(
        MockClient((_) async => http.Response('a' * 16001, 200)),
        feed: feed,
      ).check(),
      throwsException,
    );
  });

  Future<void> open(WidgetTester tester, {http.Client? client}) async {
    final httpClient =
        client ??
        MockClient((_) async => http.Response(jsonEncode(signed), 200));
    await tester.runAsync(() async {
      await tester.pumpWidget(
        MaterialApp(
          home: AppUpdatePage(
            platform: TargetPlatform.android,
            client: httpClient,
            api: UpdateApi(httpClient, feed: feed, publicKey: publicKey),
          ),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 30));
    });
    await tester.pumpAndSettle();
  }

  Future<void> downloaded(WidgetTester tester) async {
    await open(tester);
    await tester.tap(find.text('Descargar actualización'));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'Only newer compatible releases offer download; nothing installs automatically',
    (tester) async {
      await open(tester);
      expect(find.text('Descargar actualización'), findsOneWidget);
      expect(calls, ['info']);
      await tester.pumpWidget(const SizedBox());
      installedCode = 10;
      await open(tester);
      expect(find.text('Descargar actualización'), findsNothing);
      expect(
        find.text('Ya tienes la versión más reciente disponible.'),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());
      installedCode = 9;
      sdk = 23;
      await open(tester);
      expect(
        find.text('Esta versión no es compatible con tu teléfono.'),
        findsOneWidget,
      );
      expect(find.text('Descargar actualización'), findsNothing);
    },
  );
  testWidgets(
    'Network failure offers retry instead of claiming current version',
    (tester) async {
      await open(
        tester,
        client: MockClient((_) async => http.Response('', 503)),
      );
      expect(find.textContaining('No se pudo comprobar'), findsOneWidget);
      expect(find.text('Buscar actualizaciones'), findsOneWidget);
      expect(find.text('Descargar actualización'), findsNothing);
    },
  );
  testWidgets(
    'Verification failure prevents install and allows another download',
    (tester) async {
      download = () async => throw PlatformException(
        code: 'download',
        message: 'La firma no coincide.',
      );
      await downloaded(tester);
      expect(find.text('La firma no coincide.'), findsOneWidget);
      expect(find.text('Instalar actualización'), findsNothing);
      expect(find.text('Descargar actualización'), findsOneWidget);
      expect(calls.contains('install'), false);
    },
  );
  testWidgets('Progress and cancellation keep retry available', (tester) async {
    final pending = Completer<void>();
    download = () => pending.future;
    await open(tester);
    await tester.tap(find.text('Descargar actualización'));
    await tester.pump();
    final ByteData data = const StandardMethodCodec().encodeMethodCall(
      const MethodCall('progress', {'received': 25000000, 'total': 50000000}),
    );
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage('mesa/updates', data, (_) {});
    await tester.pump();
    expect(find.text('25.0 / 50.0 MB'), findsOneWidget);
    await tester.tap(find.text('Cancelar descarga'));
    await tester.pump();
    expect(calls.contains('cancel'), true);
    pending.completeError(PlatformException(code: 'cancelled'));
    await tester.pumpAndSettle();
    expect(
      find.text('Descarga cancelada. Puedes volver a intentarlo.'),
      findsOneWidget,
    );
    expect(find.text('Descargar actualización'), findsOneWidget);
  });
  testWidgets('Denied permission does not reopen settings on resume', (
    tester,
  ) async {
    await downloaded(tester);
    await tester.tap(find.text('Instalar actualización'));
    await tester.pumpAndSettle();
    expect(calls.where((v) => v == 'permission').length, 1);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(calls.where((v) => v == 'permission').length, 1);
    expect(calls.contains('install'), false);
    expect(find.textContaining('No se concedió'), findsOneWidget);
  });
  testWidgets(
    'Granted permission opens installer on return and cancellation permits retry',
    (tester) async {
      await downloaded(tester);
      expect(calls.contains('install'), false);
      await tester.tap(find.text('Instalar actualización'));
      await tester.pumpAndSettle();
      allowed = true;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(calls.where((v) => v == 'install').length, 1);
      expect(find.textContaining('Confirma la actualización'), findsOneWidget);
      await tester.tap(find.text('Instalar actualización'));
      await tester.pumpAndSettle();
      expect(calls.where((v) => v == 'install').length, 2);
    },
  );
}
