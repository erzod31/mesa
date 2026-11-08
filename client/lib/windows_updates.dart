import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

abstract class DesktopUpdateBridge {
  Future<dynamic> invoke(String method, [Map<String, dynamic>? arguments]);
  void progress(void Function(int received, int total)? handler);
  Future<void> closeForUpdate();
}

DesktopUpdateBridge? windowsUpdateBridge;

class WindowsUpdateBridge implements DesktopUpdateBridge {
  WindowsUpdateBridge(this.client, this.base, this.session) {
    if (base.scheme != 'http' ||
        base.host != '127.0.0.1' ||
        base.userInfo.isNotEmpty ||
        base.path.isNotEmpty ||
        base.hasQuery ||
        base.hasFragment ||
        session.length < 32) {
      throw const FormatException('Sesión local de actualización incorrecta.');
    }
  }
  final http.Client client;
  final Uri base;
  final String session;
  void Function(int, int)? _progress;

  @override
  void progress(void Function(int, int)? handler) => _progress = handler;

  Future<dynamic> call(String action, [Map<String, dynamic>? arguments]) async {
    final request =
        http.Request('POST', base.resolve('/v1/app-updates/$action'))
          ..followRedirects = false
          ..headers['X-Mesa-Update-Session'] = session
          ..headers['Content-Type'] = 'application/json'
          ..body = jsonEncode(arguments ?? <String, dynamic>{});
    final response = await client
        .send(request)
        .timeout(Duration(seconds: action == 'install' ? 120 : 25));
    final bytes = <int>[];
    await for (final chunk in response.stream.timeout(
      const Duration(seconds: 15),
    )) {
      if (bytes.length + chunk.length > 32000) {
        throw PlatformException(
          code: 'update',
          message: 'Respuesta de actualización demasiado grande.',
        );
      }
      bytes.addAll(chunk);
    }
    final value = jsonDecode(utf8.decode(bytes));
    if (response.statusCode != 200) {
      throw PlatformException(
        code: 'update',
        message: value is Map
            ? '${value['detail']}'
            : 'El canal no está disponible.',
      );
    }
    return value;
  }

  @override
  Future<dynamic> invoke(
    String method, [
    Map<String, dynamic>? arguments,
  ]) async {
    if (method != 'download') return call(method, arguments);
    var state = await call('download', arguments);
    while (true) {
      _progress?.call(
        (state['received'] as num? ?? 0).toInt(),
        (arguments!['size'] as num).toInt(),
      );
      if (state['status'] == 'ready') return null;
      if (state['status'] == 'cancelled' || state['status'] == 'error') {
        throw PlatformException(
          code: state['status'] == 'cancelled' ? 'cancelled' : 'download',
          message: '${state['error']}',
        );
      }
      await Future<void>.delayed(const Duration(milliseconds: 400));
      state = await call('state');
    }
  }

  @override
  Future<void> closeForUpdate() =>
      const MethodChannel('mesa/native').invokeMethod<void>('quitForUpdate');
}

void configureWindowsUpdates(List<String> arguments) {
  for (final arg in arguments) {
    const prefix = '--windows-update-session=';
    if (!arg.startsWith(prefix)) continue;
    final data = jsonDecode(
      utf8.decode(base64Url.decode(arg.substring(prefix.length))),
    ) as Map;
    windowsUpdateBridge = WindowsUpdateBridge(
      http.Client(),
      Uri.parse(data['url'] as String),
      data['session'] as String,
    );
  }
}
