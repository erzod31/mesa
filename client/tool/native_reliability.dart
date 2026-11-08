// Isolated native-channel laboratory entry point; never distributed to users.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'large_image_bytes.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    const MaterialApp(
      home: Scaffold(body: Center(child: Text('Comprobando OCR nativo'))),
    ),
  );
  const channel = MethodChannel('mesa/native');
  final results = <String, dynamic>{};
  try {
    for (final entry in {
      'invalid': Uint8List.fromList([1, 2, 3]),
      'oversized': Uint8List(10000001),
    }.entries) {
      try {
        await channel.invokeMethod<String>('ocr', entry.value);
        throw StateError('Invalid image accepted');
      } on PlatformException catch (error) {
        if (error.code != 'image') rethrow;
        results[entry.key] = 'RECHAZADO CORRECTAMENTE';
      }
    }
    final image = base64Decode(largeImageBase64);
    final clock = Stopwatch()..start();
    final text = await channel.invokeMethod<String>('ocr', image);
    clock.stop();
    if (!(text ?? '').toLowerCase().contains('2 huevos')) {
      throw StateError('Native OCR lost recipe text: $text');
    }
    results.addAll({
      'large_image_pixels': 64000000,
      'large_image_bytes': image.length,
      'ocr_ms': clock.elapsedMilliseconds,
      'recognized': text,
      'status': 'APROBADO',
    });
  } catch (error) {
    results.addAll({'status': 'FALLIDO', 'error': '$error'});
  }
  debugPrint('MESA_NATIVE_QA_RESULT ${jsonEncode(results)}');
  runApp(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: SelectableText(
            'MESA_NATIVE_QA_${results['status']}\n${jsonEncode(results)}',
          ),
        ),
      ),
    ),
  );
}
