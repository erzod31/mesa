import 'dart:io';
import 'dart:typed_data';

import 'licensed_photos.dart';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

/// Persist references only; legacy image bytes are never exposed or copied.
Map<String, dynamic> onlineRecipeData(Map<String, dynamic> data) {
  final result = Map<String, dynamic>.from(data)..remove('image');
  final legacyCover = data['image'];
  final photos = <Map<String, dynamic>>[];
  String selected = data['image_url'] is String ? data['image_url'] : '';
  if (data['photos'] is List) {
    for (final raw in data['photos']) {
      if (raw is! Map) continue;
      final photo = Map<String, dynamic>.from(raw)..remove('image');
      final url = photo['url'];
      if (url is! String || !onlinePhotoUrl(url)) continue;
      if (legacyCover is String &&
          legacyCover.isNotEmpty &&
          raw['image'] == legacyCover) {
        selected = url;
      }
      photo.remove('error');
      photos.add(photo);
    }
    result['photos'] = photos;
  }
  if (onlinePhotoUrl(selected)) {
    result['image_url'] = selected;
    if (!photos.any((p) => p['url'] == selected)) {
      result['photos'] = [
        {'url': selected, 'caption': 'Foto de la receta'},
        ...photos,
      ];
    }
  } else {
    result.remove('image_url');
  }
  return result;
}

/// Sanitize cached detail/search, conflict snapshots and old drafts too.
dynamic onlinePhotoTree(dynamic value) {
  if (value is List) return value.map(onlinePhotoTree).toList();
  if (value is! Map) return value;
  final data = <String, dynamic>{
    for (final e in value.entries) '${e.key}': onlinePhotoTree(e.value),
  }..remove('image_data');
  return data.containsKey('photos') ||
          data.containsKey('image_url') ||
          (data.containsKey('ingredients') && data.containsKey('image'))
      ? onlineRecipeData(data)
      : data;
}

List<Map<String, dynamic>> recipePhotos(Map<String, dynamic> data) =>
    (onlineRecipeData(data)['photos'] as List? ?? [])
        .map((p) => Map<String, dynamic>.from(p))
        .toList();

String coverImage(Map<String, dynamic> data) {
  final normalized = onlineRecipeData(data);
  final cover = normalized['image_url'] as String? ?? '';
  if (cover.isNotEmpty) return cover;
  return recipePhotos(normalized).firstOrNull?['url'] as String? ?? '';
}

bool publicPhotoAddress(InternetAddress address) {
  final b = address.rawAddress;
  if (b.length == 4) {
    return !(b[0] == 0 ||
        b[0] == 10 ||
        b[0] == 127 ||
        b[0] >= 224 ||
        (b[0] == 100 && b[1] >= 64 && b[1] <= 127) ||
        (b[0] == 169 && b[1] == 254) ||
        (b[0] == 172 && b[1] >= 16 && b[1] <= 31) ||
        (b[0] == 192 &&
            (b[1] == 168 || (b[1] == 0 && [0, 2].contains(b[2])))) ||
        (b[0] == 198 &&
            ([18, 19].contains(b[1]) || (b[1] == 51 && b[2] == 100))) ||
        (b[0] == 203 && b[1] == 0 && b[2] == 113));
  }
  // Only global unicast; exclude private, loopback and mapped IPv4.
  return b.length == 16 &&
      (b[0] & 0xe0) == 0x20 &&
      !(b[0] == 0x20 &&
          b[1] == 0x01 &&
          (b[2] < 2 || (b[2] == 0x0d && b[3] == 0xb8))) &&
      !(b[0] == 0x20 && b[1] == 0x02);
}

bool onlinePhotoUrl(String value) {
  final uri = Uri.tryParse(value);
  if (uri == null ||
      uri.scheme != 'https' ||
      uri.userInfo.isNotEmpty ||
      uri.hasFragment ||
      (uri.hasPort && uri.port != 443) ||
      uri.host.isEmpty ||
      !uri.host.contains('.') ||
      value.length > 10000) {
    return false;
  }
  final host = uri.host.toLowerCase();
  if ([
    'localhost',
    'local',
    'internal',
    'ts.net',
  ].any((suffix) => host == suffix || host.endsWith('.$suffix'))) {
    return false;
  }
  final address = InternetAddress.tryParse(host);
  return address == null || publicPhotoAddress(address);
}

bool wikimediaPhotoUrl(String value) {
  final uri = Uri.tryParse(value);
  return onlinePhotoUrl(value) &&
      uri != null &&
      ['upload.wikimedia.org', 'thumb.wikimedia.org'].contains(uri.host) &&
      uri.path.startsWith('/wikipedia/');
}

/// Separate credential-free connections. Check DNS and pin the approved IP;
/// The secure socket verifies TLS against the original lookup hostname.
http.Client directPhotoClient() {
  final transport = HttpClient()
    ..connectionTimeout = const Duration(seconds: 12)
    ..findProxy = ((_) => 'DIRECT');
  transport.connectionFactory = (uri, proxyHost, proxyPort) async {
    if (!onlinePhotoUrl(uri.toString())) {
      throw Exception('Enlace no público.');
    }
    final addresses = await InternetAddress.lookup(uri.host)
        .timeout(const Duration(seconds: 10));
    if (addresses.isEmpty || addresses.any((a) => !publicPhotoAddress(a))) {
      throw Exception('La foto no está en una dirección pública.');
    }
    if (addresses.first.host != uri.host) {
      throw Exception('El nombre de la foto no coincide con la consulta DNS.');
    }
    return SecureSocket.startConnect(
      addresses.first,
      uri.port,
      supportedProtocols: ['http/1.1'],
    );
  };
  return IOClient(transport);
}

Future<Uint8List> Function(String provider, int page)? documentPhotoLoader;

/// Temporary display bytes only: no disk write, compression or image cache.
Future<Uint8List> fetchOnlinePhoto(http.Client client, String url) async {
  final reference = documentPhotoReference(url);
  if (reference != null) {
    final loader = documentPhotoLoader;
    if (loader == null) {
      throw Exception(
        'Conecta el ordenador para ver las fotos del recetario PDF.',
      );
    }
    return loader(reference.provider, reference.page);
  }
  if (Uri.parse(url).queryParameters.containsKey('mesa_recipe_image')) {
    throw Exception('Foto de documento no revisada.');
  }
  var next = Uri.parse(url);
  for (var attempt = 0; attempt <= 3; attempt++) {
    if (!onlinePhotoUrl(next.toString())) throw Exception('Enlace no público.');
    final request = http.Request('GET', next)..followRedirects = false;
    request.headers.addAll({
      'User-Agent': 'MesaRecipeApp/1.6 (private family cookbook)',
      'Cache-Control': 'no-cache, no-store',
      'Pragma': 'no-cache',
      'Accept': 'image/jpeg,image/png,image/webp,image/gif',
    });
    final response = await client
        .send(request)
        .timeout(const Duration(seconds: 12));
    if ([301, 302, 303, 307, 308].contains(response.statusCode)) {
      await response.stream.listen((_) {}).cancel();
      final location = response.headers['location'];
      if (location == null || attempt == 3) {
        throw Exception('Foto no disponible.');
      }
      next = next.resolve(location);
      continue;
    }
    if (response.statusCode != 200 ||
        (response.contentLength ?? 0) > 10000000) {
      await response.stream.listen((_) {}).cancel();
      throw Exception('Foto no disponible.');
    }
    final bytes = BytesBuilder(copy: false);
    await for (final part in response.stream.timeout(
      const Duration(seconds: 12),
    )) {
      if (bytes.length + part.length > 10000000) {
        throw Exception('Foto demasiado grande.');
      }
      bytes.add(part);
    }
    return bytes.takeBytes();
  }
  throw Exception('Foto no disponible.');
}
