import 'dart:convert';

import 'package:cryptography/cryptography.dart';

// Same vendor identity pinned by the Windows updater. Public key only.
const updatePublicKey =
    'cf2aab48e6beb7b6ad7fb2f2e3564cd6b5612ed9d7a47a1f056e539e337d43a1';

String canonicalUpdate(Map<String, dynamic> value) {
  dynamic ordered(dynamic node) {
    if (node is Map) {
      final keys = node.keys.cast<String>().toList()..sort();
      return {for (final key in keys) key: ordered(node[key])};
    }
    if (node is List) return node.map(ordered).toList();
    return node;
  }

  return jsonEncode(ordered(value));
}

Future<void> verifyAndroidUpdate(
  Map<String, dynamic> data, {
  String publicKey = updatePublicKey,
}) async {
  try {
    if (data['product'] != 'com.mesa.mesa' ||
        data['platform'] != 'android' ||
        data['architecture'] != 'arm64-v8a') {
      throw const FormatException();
    }
    final signature = base64Decode(data['signature'] as String);
    if (signature.length != 64 ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(publicKey)) {
      throw const FormatException();
    }
    final release = {...data}..remove('signature');
    final key = [
      for (var i = 0; i < publicKey.length; i += 2)
        int.parse(publicKey.substring(i, i + 2), radix: 16),
    ];
    if (!await Ed25519().verify(
      utf8.encode(canonicalUpdate(release)),
      signature: Signature(
        signature,
        publicKey: SimplePublicKey(key, type: KeyPairType.ed25519),
      ),
    )) {
      throw const FormatException();
    }
  } catch (_) {
    throw Exception(
      'El canal no tiene una firma válida de Mesa. Reintenta cuando se publique el canal firmado; tu aplicación y tus recetas se conservan.',
    );
  }
}
