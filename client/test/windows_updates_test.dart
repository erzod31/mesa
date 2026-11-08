import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mesa/updates.dart';
import 'package:mesa/windows_updates.dart';

// Synthetic next-release metadata; it does not claim a live remote version.
Map<String, dynamic> sample() => {
  'product': 'com.mesa.mesa.windows',
  'platform': 'windows',
  'architecture': 'x64',
  'version': '1.18.1',
  'version_code': 36,
  'size': 1000000,
  'sha256': 'a' * 64,
  'url': 'https://family.example/descargar/Mesa-Setup-1.18.1-36-x64.exe',
  'notes': ['Muestra de prueba.'],
};

class FakeBridge implements DesktopUpdateBridge {
  final calls = <String>[];
  int code = 35;
  bool managed = true;
  bool badCheck = false, badDownload = false;
  Completer<void>? pending;
  void Function(int, int)? handler;
  @override
  void progress(void Function(int, int)? callback) => handler = callback;
  @override
  Future<dynamic> invoke(
    String method, [
    Map<String, dynamic>? arguments,
  ]) async {
    calls.add(method);
    switch (method) {
      case 'info':
        return {
          'version': '1.18.0',
          'version_code': code,
          'platform': 'windows',
          'sdk': 999,
          'abis': ['x64'],
          'can_install': managed,
          'managed_install': managed,
        };
      case 'check':
        if (badCheck) {
          throw PlatformException(
            code: 'feed',
            message: 'El canal Windows no está publicado.',
          );
        }
        return sample();
      case 'download':
        if (badDownload) {
          throw PlatformException(
            code: 'verify',
            message: 'Firma o SHA-256 incorrectos.',
          );
        }
        await pending?.future;
        return null;
      case 'cancel':
        pending?.completeError(PlatformException(code: 'cancelled'));
        return null;
      case 'install':
        return {'close_app': true};
    }
    throw StateError(method);
  }

  @override
  Future<void> closeForUpdate() async {
    calls.add('close_fake');
  }
}

void main() {
  Future<void> open(WidgetTester tester, FakeBridge bridge) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AppUpdatePage(
          client: MockClient(
            (_) async => throw StateError('No Android feed allowed'),
          ),
          platform: TargetPlatform.windows,
          desktopBridge: bridge,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'Windows shows installed version and newer verified release before handoff',
    (tester) async {
      final bridge = FakeBridge();
      await open(tester, bridge);
      expect(find.text('Versión instalada: 1.18.0'), findsOneWidget);
      expect(find.text('Descargar actualización'), findsOneWidget);
      expect(bridge.calls.contains('install'), isFalse);
      await tester.tap(find.text('Descargar actualización'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Instalar actualización'));
      await tester.pumpAndSettle();
      expect(find.text('Actualizar y reabrir Mesa'), findsOneWidget);
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(bridge.calls.contains('install'), isFalse);
      expect(bridge.calls.contains('close_fake'), isFalse);
      await tester.tap(find.text('Instalar actualización'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continuar'));
      await tester.pumpAndSettle();
      expect(bridge.calls.where((e) => e == 'install').length, 1);
      expect(bridge.calls.last, 'close_fake');
    },
  );
  testWidgets('Windows older channel does not offer downgrade', (tester) async {
    final bridge = FakeBridge()..code = 40;
    await open(tester, bridge);
    expect(find.text('Descargar actualización'), findsNothing);
    expect(
      find.text('Ya tienes la versión más reciente disponible.'),
      findsOneWidget,
    );
  });
  testWidgets('Missing channel preserves installed version and retry', (
    tester,
  ) async {
    final bridge = FakeBridge()..badCheck = true;
    await open(tester, bridge);
    expect(find.text('Versión instalada: 1.18.0'), findsOneWidget);
    expect(find.text('El canal Windows no está publicado.'), findsOneWidget);
    expect(find.text('Buscar actualizaciones'), findsOneWidget);
    expect(find.text('Descargar actualización'), findsNothing);
  });
  testWidgets('Verification failure never offers installation', (tester) async {
    final bridge = FakeBridge()..badDownload = true;
    await open(tester, bridge);
    await tester.tap(find.text('Descargar actualización'));
    await tester.pumpAndSettle();
    expect(find.text('Firma o SHA-256 incorrectos.'), findsOneWidget);
    expect(find.text('Instalar actualización'), findsNothing);
    expect(bridge.calls.contains('install'), isFalse);
  });
  testWidgets('Windows download cancellation leaves app open', (tester) async {
    final bridge = FakeBridge()..pending = Completer<void>();
    await open(tester, bridge);
    await tester.tap(find.text('Descargar actualización'));
    await tester.pump();
    bridge.handler?.call(500000, 1000000);
    await tester.pump();
    expect(find.text('0.5 / 1.0 MB'), findsOneWidget);
    await tester.tap(find.text('Cancelar descarga'));
    await tester.pumpAndSettle();
    expect(bridge.calls.contains('cancel'), isTrue);
    expect(bridge.calls.contains('close_fake'), isFalse);
    expect(find.text('Instalar actualización'), findsNothing);
  });
  testWidgets('Portable transition never invokes a Windows installer', (
    tester,
  ) async {
    final bridge = FakeBridge()..managed = false;
    await open(tester, bridge);
    expect(find.textContaining('primera instalación manual'), findsOneWidget);
    await tester.tap(find.text('Descargar actualización'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Instalar actualización'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continuar'));
    await tester.pumpAndSettle();
    expect(bridge.calls.contains('install'), isFalse);
    expect(bridge.calls.contains('close_fake'), isFalse);
  });
  test(
    'Windows bridge restricts local control and sends no family bearer token',
    () async {
      expect(
        () => WindowsUpdateBridge(
          http.Client(),
          Uri.parse('https://attacker.example'),
          's' * 40,
        ),
        throwsFormatException,
      );
      final bridge = WindowsUpdateBridge(
        MockClient((request) async {
          expect(
            request.url.toString(),
            'http://127.0.0.1:12345/v1/app-updates/info',
          );
          expect(request.followRedirects, isFalse);
          expect(request.headers['X-Mesa-Update-Session'], 's' * 40);
          expect(request.headers.containsKey('Authorization'), isFalse);
          return http.Response(jsonEncode({'version_code': 35}), 200);
        }),
        Uri.parse('http://127.0.0.1:12345'),
        's' * 40,
      );
      expect((await bridge.invoke('info'))['version_code'], 35);
    },
  );
}
