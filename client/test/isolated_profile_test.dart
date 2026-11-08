import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mesa/store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('isolated profile persists only its database and never uses the vault', () async {
    var vaultCalls = 0;
    const vault = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(vault, (_) async {
          vaultCalls++;
          throw StateError(
            'The normal credential vault must remain untouched.',
          );
        });
    final directory = await Directory.systemTemp.createTemp('mesa-isolated-');
    final first = await Cookbook.open(profileDirectory: directory);
    expect(first.token, isEmpty);
    await first.preference('profile', 'Laboratorio');
    first.dispose();
    final second = await Cookbook.open(profileDirectory: directory);
    expect(second.profile, 'Laboratorio');
    expect(second.ephemeralSecrets, isTrue);
    expect(second.token, isEmpty);
    expect(vaultCalls, 0);
    second.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(vault, null);
    // NativeDatabase closes asynchronously; leave only this OS temporary profile
    // for the platform's temporary-file lifecycle rather than race a locked DB.
  });
}
