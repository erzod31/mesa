import 'dart:convert';
import 'dart:io';

import 'package:mesa/update_signature.dart';

Future<void> main(List<String> args) async {
  final data = Map<String, dynamic>.from(
    jsonDecode(await File(args.single).readAsString()),
  );
  await verifyAndroidUpdate(data);
  stdout.writeln(
    jsonEncode({
      'productionPublicKeyVerified': true,
      'version': data['version'],
      'code': data['version_code'],
    }),
  );
}
