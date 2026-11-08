import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'licensed_photos.dart';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import 'models.dart';
import 'photo_data.dart';
import 'translation.dart';

class LocalDb extends GeneratedDatabase {
  LocalDb(super.executor);
  @override
  int get schemaVersion => 1;
  @override
  Iterable<TableInfo<Table, Object?>> get allTables => [];
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [];
  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await customStatement(
        'CREATE TABLE entities (id TEXT PRIMARY KEY,kind TEXT NOT NULL,revision INTEGER NOT NULL,data TEXT NOT NULL,deleted INTEGER NOT NULL DEFAULT 0)',
      );
      await customStatement(
        'CREATE TABLE outbox (seq INTEGER PRIMARY KEY AUTOINCREMENT,id TEXT UNIQUE NOT NULL,entity_id TEXT NOT NULL,payload TEXT NOT NULL,attempted INTEGER NOT NULL DEFAULT 0)',
      );
      await customStatement(
        'CREATE TABLE conflicts (id TEXT PRIMARY KEY,payload TEXT NOT NULL)',
      );
      await customStatement(
        'CREATE TABLE prefs (key TEXT PRIMARY KEY,value TEXT NOT NULL)',
      );
    },
  );
}

class Cookbook extends ChangeNotifier {
  final LocalDb db;
  final http.Client client;
  final FlutterSecureStorage secrets;
  final String Function() newId;
  // Explicit laboratory profiles never access the user's credential vault.
  final bool ephemeralSecrets;
  Cookbook(
    this.db, {
    http.Client? client,
    FlutterSecureStorage? secrets,
    String Function()? newId,
    this.ephemeralSecrets = false,
  }) : client =
           client ??
           IOClient(
             HttpClient()..connectionTimeout = const Duration(seconds: 5),
           ),
       secrets = secrets ?? const FlutterSecureStorage(),
       newId = newId ?? const Uuid().v4;
  static Future<Cookbook> open({Directory? profileDirectory}) async {
    final directory =
        profileDirectory ?? await getApplicationSupportDirectory();
    await directory.create(recursive: true);
    final store = Cookbook(
      LocalDb(
        NativeDatabase.createInBackground(
          File(p.join(directory.path, 'mesa.sqlite')),
        ),
      ),
      ephemeralSecrets: profileDirectory != null,
    );
    await store.load();
    return store;
  }

  List<Entry> entries = [];
  List<Map<String, dynamic>> conflicts = [];
  Map<String, String> prefs = {};
  String token = '',
      role = 'editor',
      profile = 'Mi recetario',
      status = 'Guardado en este dispositivo';
  bool syncing = false;
  int pending = 0;
  String? inFlight;
  Future<void> _writes = Future.value();
  Timer? _timer;
  bool _indexesReady = false;
  String get url => prefs['url'] ?? '';
  String get generation => prefs['generation'] ?? '';
  bool get editable => role != 'reader';
  bool get dark => prefs['dark'] == 'true';
  Future<void> flushForAppUpdate() => locked(() async {
    await db.customStatement('PRAGMA wal_checkpoint(FULL)');
  });
  Future<String> recognizeImage(Uint8List bytes) async {
    if (bytes.isEmpty) throw Exception('Selecciona una foto con texto.');
    if (bytes.length > 10000000) throw Exception('La foto supera 10 MB.');
    if (url.isEmpty || token.isEmpty) {
      throw Exception(
        'Conecta con el ordenador de Mesa para leer fotos con Indra OCR.',
      );
    }
    final value = await request(
      'POST',
      '/v1/ocr',
      binaryBody: bytes,
      responseTimeout: const Duration(seconds: 90),
    );
    if (value is! Map ||
        value['engine'] != 'indra-ocr' ||
        value['text'] is! String) {
      throw Exception('Actualiza el servidor de Mesa para usar Indra OCR.');
    }
    final text = (value['text'] as String).trim();
    if (text.isEmpty) {
      throw Exception(
        'No se detectó texto. Prueba una foto más clara o recorta la receta.',
      );
    }
    if (text.length > 100000) {
      throw Exception('Hay demasiado texto. Recorta la receta.');
    }
    // Keep attribution and the output licence with copied/exported OCR text.
    return '$text\n\nTexto reconocido con Indra OCR · Datalab · modelos sin modificar.\n'
        'Texto OCR sujeto a AI PUBS Open RAIL-M (modified).\n'
        'https://huggingface.co/datalab-to/indra-ocr\n'
        'https://huggingface.co/datalab-to/indra-ocr/blob/bd02167fdf2005a19962cc15188f8496a2c87d3b/LICENSE';
  }

  Future<void> prepareTranslation() async {
    if (url.isEmpty || token.isEmpty) return;
    try {
      await request(
        'POST',
        '/v1/translation/warm',
        responseTimeout: const Duration(seconds: 3),
      );
    } catch (_) {}
  }

  Future<Map<String, dynamic>> translateImportedRecipe(
    Map<String, dynamic> recipe, {
    String? language,
    bool force = false,
  }) async {
    final source = language ?? translationSource(recipe, force: force);
    if (source == 'es' ||
        (!force && recipe['translation']?['target_language'] == 'es')) {
      return recipe;
    }
    if (url.isNotEmpty && token.isNotEmpty) {
      try {
        final wait = Duration(
          seconds: defaultTargetPlatform == TargetPlatform.android ? 30 : 180,
        );
        final translated = Map<String, dynamic>.from(
          await request(
            'POST',
            '/v1/translate-recipe',
            body: {'recipe': recipe, 'source': source, 'force': force},
            responseTimeout: wait,
          ).timeout(wait),
        );
        validateSpanishTranslation(recipe, translated);
        return translated;
      } catch (_) {
        if (defaultTargetPlatform != TargetPlatform.android) rethrow;
      }
    }
    if (defaultTargetPlatform == TargetPlatform.android) {
      return translateRecipeLocally(
        recipe,
        androidRecipeTranslation,
        language: source,
        force: force,
      );
    }
    throw Exception('Conecta Mesa al ordenador para traducir esta receta.');
  }

  List<Entry> of(String kind, {bool trash = false}) =>
      entries.where((x) => x.kind == kind && x.deleted == trash).toList();
  Entry? get(String id) {
    for (final entry in entries) {
      if (entry.id == id) return entry;
    }
    return null;
  }

  bool favorite(String id) => prefs['favorite:$id'] == 'true';

  Future<T> locked<T>(Future<T> Function() action) {
    final next = _writes.then((_) => action());
    _writes = next.then((_) {}, onError: (Object _, StackTrace _) {});
    return next;
  }

  Future<void> load({bool readSecrets = true}) async {
    if (!_indexesReady) {
      await db.customStatement(
        'CREATE INDEX IF NOT EXISTS outbox_entity_seq ON outbox(entity_id,seq)',
      );
      _indexesReady = true;
    }
    await migratePhotos();
    entries = (await db.customSelect('SELECT * FROM entities').get())
        .map(
          (x) => Entry(
            x.read<String>('id'),
            x.read<String>('kind'),
            x.read<int>('revision'),
            jsonDecode(x.read<String>('data')),
            deleted: x.read<int>('deleted') == 1,
          ),
        )
        .toList();
    prefs = {
      for (final row in await db.customSelect('SELECT * FROM prefs').get())
        row.read<String>('key'): row.read<String>('value'),
    };
    conflicts = (await db.customSelect('SELECT payload FROM conflicts').get())
        .map(
          (x) =>
              Map<String, dynamic>.from(jsonDecode(x.read<String>('payload'))),
        )
        .toList();
    pending =
        (await db.customSelect('SELECT COUNT(*) AS n FROM outbox').getSingle())
            .read<int>('n');
    if (readSecrets && !ephemeralSecrets) {
      token = await secrets.read(key: 'mesa-token') ?? '';
    }
    role = prefs['role'] ?? 'editor';
    profile = prefs['profile'] ?? 'Mi recetario';
    notifyListeners();
  }

  Future<void> migratePhotos() async {
    final done = await db
        .customSelect("SELECT 1 FROM prefs WHERE key='online-photos-v1'")
        .getSingleOrNull();
    if (done != null) return;
    await db.transaction(() async {
      for (final table in ['entities', 'conflicts', 'prefs', 'outbox']) {
        final rows = await db.customSelect('SELECT * FROM $table').get();
        for (final row in rows) {
          // Retried operations must retain their original fingerprint until
          // acknowledged, otherwise a lost response would become a conflict.
          if (table == 'outbox' && row.read<int>('attempted') != 0) continue;
          final column = table == 'entities'
              ? 'data'
              : table == 'prefs'
              ? 'value'
              : 'payload';
          final key = table == 'prefs' ? 'key' : 'id';
          final original = row.read<String>(column);
          dynamic value;
          try {
            value = jsonDecode(original);
          } catch (_) {
            continue;
          }
          if (value is! Map && value is! List) continue;
          final normalized = jsonEncode(onlinePhotoTree(value));
          if (normalized != original) {
            await db.customStatement(
              'UPDATE $table SET $column=? WHERE $key=?',
              [normalized, row.read<String>(key)],
            );
          }
        }
      }
      await _pref('online-photos-v1', 'true');
    });
  }

  Future<void> _pref(String key, String value) => db.customStatement(
    'INSERT OR REPLACE INTO prefs VALUES (?,?)',
    [key, value],
  );
  Future<void> preference(String key, String value) => locked(() async {
    var clean = value;
    if (key.startsWith('draft:') || key == 'catalog-cache') {
      try {
        clean = jsonEncode(onlinePhotoTree(jsonDecode(value)));
      } catch (_) {}
    }
    await _pref(key, clean);
    await load(readSecrets: false);
  });
  Future<void> _put(Entry entry) =>
      db.customStatement('INSERT OR REPLACE INTO entities VALUES (?,?,?,?,?)', [
        entry.id,
        entry.kind,
        entry.revision,
        jsonEncode(
          entry.kind == 'recipe' ? onlineRecipeData(entry.data) : entry.data,
        ),
        entry.deleted ? 1 : 0,
      ]);

  Future<void> save(
    String kind,
    Map<String, dynamic> data, {
    String? id,
    bool deleted = false,
    String action = 'save',
  }) => locked(() async {
    if (!editable) throw Exception('Tu perfil tiene acceso de lectura.');
    final eid = id ?? newId();
    await db.transaction(() async {
      final row = await db
          .customSelect(
            'SELECT * FROM entities WHERE id=?',
            variables: [Variable(eid)],
          )
          .getSingleOrNull();
      if (row != null && row.read<String>('kind') != kind) {
        throw Exception('No se puede cambiar el tipo de un elemento guardado.');
      }
      final revision = row?.read<int>('revision') ?? 0;
      final old = row == null
          ? <String, dynamic>{}
          : Map<String, dynamic>.from(jsonDecode(row.read<String>('data')));
      final rawValue = action == 'check' ? {...old, ...data} : data;
      final value = kind == 'recipe' ? onlineRecipeData(rawValue) : rawValue;
      validateEntryData(kind, value);
      final queued = await db
          .customSelect(
            'SELECT * FROM outbox WHERE entity_id=? ORDER BY seq DESC LIMIT 1',
            variables: [Variable(eid)],
          )
          .getSingleOrNull();
      final reuse =
          queued != null &&
          queued.read<int>('attempted') == 0 &&
          queued.read<String>('id') != inFlight;
      final prior = queued == null
          ? null
          : Map<String, dynamic>.from(
              jsonDecode(queued.read<String>('payload')),
            );
      // A check merged into an unsent create/edit must still send the complete record.
      final full = action != 'check' || (reuse && prior?['action'] != 'check');
      final op = {
        'id': reuse ? queued.read<String>('id') : newId(),
        'entity_id': eid,
        'kind': kind,
        'base': reuse
            ? prior!['base']
            : revision + (queued != null && !reuse ? 1 : 0),
        'data': full ? value : data,
        'deleted': deleted,
        'action': full ? 'save' : 'check',
      };
      await _put(Entry(eid, kind, revision, value, deleted: deleted));
      if (reuse) {
        await db.customStatement('UPDATE outbox SET payload=? WHERE id=?', [
          jsonEncode(op),
          op['id'],
        ]);
      } else {
        await db.customStatement(
          'INSERT INTO outbox(id,entity_id,payload) VALUES (?,?,?)',
          [op['id'], eid, jsonEncode(op)],
        );
      }
    });
    await load(readSecrets: false);
    unawaited(sync());
  });

  Future<void> delete(Entry entry) =>
      save(entry.kind, entry.copyData(), id: entry.id, deleted: true);
  Future<void> restore(Entry entry) =>
      save(entry.kind, entry.copyData(), id: entry.id);
  Future<void> toggleFavorite(Entry entry) =>
      preference('favorite:${entry.id}', (!favorite(entry.id)).toString());

  Future<Uint8List> fetchDocumentPhoto(String provider, int page) async {
    final base = url;
    if (base.isEmpty || token.isEmpty) {
      throw Exception(
        'Conecta el ordenador para ver las fotos del recetario PDF.',
      );
    }
    final source = provider == 'book-polaca'
        ? 'https://bunkatura.pl/pdf/mesa_polaca.pdf'
        : '';
    if (documentPhotoReference('$source?mesa_recipe_image=$page') == null) {
      throw Exception('Foto no revisada.');
    }
    final request = http.Request(
      'GET',
      Uri.parse('$base/v1/source-photo/$provider/$page'),
    )..followRedirects = false;
    request.headers.addAll({
      'Authorization': 'Bearer $token',
      'Cache-Control': 'no-store',
    });
    final response = await client
        .send(request)
        .timeout(const Duration(seconds: 55));
    if (response.statusCode != 200 ||
        !(response.headers['content-type'] ?? '').startsWith('image/jpeg') ||
        (response.contentLength ?? 0) > 10000000) {
      await response.stream.listen((_) {}).cancel();
      throw Exception(
        'No se pudo consultar la foto del documento. Revisa la conexión con el ordenador.',
      );
    }
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in response.stream.timeout(
      const Duration(seconds: 15),
    )) {
      if (bytes.length + chunk.length > 10000000) {
        throw Exception('Foto demasiado grande.');
      }
      bytes.add(chunk);
    }
    return bytes.takeBytes();
  }

  Future<dynamic> request(
    String method,
    String path, {
    Object? body,
    Uint8List? binaryBody,
    bool authorized = true,
    String? target,
    Duration? responseTimeout,
  }) async {
    final base = target ?? url;
    if (base.isEmpty) {
      throw Exception(
        'Conecta el ordenador con Mesa para consultar o importar esta fuente.',
      );
    }
    final retryable = method == 'GET' || path == '/v1/push';
    final encoded = body == null ? null : jsonEncode(body);
    http.Response? res;
    for (var attempt = 0; attempt < (retryable ? 3 : 1); attempt++) {
      try {
        final req = http.Request(method, Uri.parse('$base$path'))
          ..followRedirects = false;
        req.headers['Content-Type'] = binaryBody == null
            ? 'application/json'
            : 'application/octet-stream';
        if (authorized) req.headers['Authorization'] = 'Bearer $token';
        if (binaryBody != null) {
          req.bodyBytes = binaryBody;
        } else if (encoded != null) {
          req.body = encoded;
        }
        final streamed = await client
            .send(req)
            .timeout(
              responseTimeout ??
                  Duration(
                    seconds: path == '/v1/translate-recipe'
                        ? 180
                        : path == '/v1/import-url'
                        ? 35
                        : path.startsWith('/v1/catalog/')
                        ? 35
                        : 20,
                  ),
            );
        final bytes = <int>[];
        await for (final chunk in streamed.stream.timeout(
          const Duration(seconds: 30),
        )) {
          if (bytes.length + chunk.length > 32_000_000) {
            throw Exception(
              'La respuesta es demasiado grande. Reintenta para descargarla por partes.',
            );
          }
          bytes.addAll(chunk);
        }
        res = http.Response.bytes(
          bytes,
          streamed.statusCode,
          headers: streamed.headers,
        );
        if (retryable &&
            [429, 502, 503, 504].contains(res.statusCode) &&
            attempt < 2) {
          await Future<void>.delayed(
            Duration(milliseconds: 400 * (attempt + 1)),
          );
          continue;
        }
        break;
      } on TimeoutException {
        if (!retryable || attempt == 2) rethrow;
        await Future<void>.delayed(Duration(milliseconds: 400 * (attempt + 1)));
      } on http.ClientException {
        if (!retryable || attempt == 2) rethrow;
        await Future<void>.delayed(Duration(milliseconds: 400 * (attempt + 1)));
      }
    }
    if (res == null) throw Exception('No se pudo recibir la receta.');
    dynamic value;
    try {
      value = jsonDecode(res.body);
    } catch (_) {
      throw Exception('El servidor devolvió una respuesta no válida.');
    }
    if (res.statusCode >= 400) {
      throw ApiError(
        res.statusCode,
        value is Map ? '${value['detail']}' : 'Error de conexión',
      );
    }
    return value;
  }

  String validateUrl(String value) {
    final clean = value.trim().replaceAll(RegExp(r'/+$'), '');
    final uri = Uri.tryParse(clean);
    if (uri == null ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        (uri.path.isNotEmpty && uri.path != '/') ||
        uri.hasQuery ||
        uri.hasFragment ||
        (uri.scheme != 'https' &&
            !(uri.scheme == 'http' &&
                ['127.0.0.1', 'localhost', '10.0.2.2'].contains(uri.host)))) {
      throw Exception(
        'Usa la dirección HTTPS de Tailscale. HTTP solo se permite en este ordenador o en el emulador.',
      );
    }
    return clean;
  }

  Future<void> connect(
    String target,
    String credential, {
    bool invitation = true,
    String name = 'Familiar',
  }) async {
    final clean = validateUrl(target);
    if (url.isNotEmpty && clean != url) {
      throw Exception(
        'Para cambiar de servidor, exporta y desconecta primero.',
      );
    }
    String nextToken = credential.trim();
    Map<String, dynamic> identity;
    if (invitation) {
      final paired = await request(
        'POST',
        '/v1/pair',
        body: {
          'code': credential.trim(),
          'name': name.trim().isEmpty ? 'Familiar' : name.trim(),
        },
        authorized: false,
        target: clean,
      );
      nextToken = paired['token'];
      identity = Map<String, dynamic>.from(paired);
    } else {
      final oldToken = token;
      token = nextToken;
      try {
        identity = Map<String, dynamic>.from(
          await request('GET', '/v1/me', target: clean),
        );
      } catch (_) {
        token = oldToken;
        rethrow;
      }
    }
    if (!ephemeralSecrets) {
      await secrets.write(key: 'mesa-token', value: nextToken);
    }
    token = nextToken;
    await locked(() async {
      await db.transaction(() async {
        await _pref('url', clean);
        await _pref('profile', identity['name']);
        await _pref('role', identity['role']);
        await _pref('generation', '');
        await _pref('cursor', '0');
      });
      await load(readSecrets: false);
    });
    startSync();
    await sync();
  }

  Future<void> disconnect() async {
    if (syncing || pending > 0) {
      throw Exception(
        'Sincroniza o exporta los cambios pendientes antes de desconectar.',
      );
    }
    if (!ephemeralSecrets) await secrets.delete(key: 'mesa-token');
    token = '';
    await locked(() async {
      await _pref('url', '');
      await _pref('generation', '');
      await _pref('role', 'editor');
      await load(readSecrets: false);
    });
    status = 'Recetario local · sin servidor';
    notifyListeners();
  }

  void startSync() {
    _timer?.cancel();
    _timer = Timer.periodic(
      const Duration(seconds: 15),
      (_) => unawaited(sync()),
    );
    unawaited(sync());
  }

  Future<void> _snapshot() async {
    final first = await request('GET', '/v1/snapshot?limit=50');
    final value = Map<String, dynamic>.from(first);
    final entities = List<dynamic>.from(first['entities']);
    var next = first['next'];
    final visited = <String>{};
    while (next != null) {
      if (!visited.add('$next') || visited.length > 2000) {
        throw Exception(
          'La descarga no pudo avanzar. Los datos locales siguen guardados.',
        );
      }
      final query = Uri(
        queryParameters: {
          'limit': '50',
          'after': '$next',
          'epoch': '${first['generation']}',
          'start_cursor': '${first['cursor']}',
        },
      ).query;
      final page = await request('GET', '/v1/snapshot?$query');
      if (page['generation'] != first['generation'] ||
          page['cursor'] != first['cursor']) {
        throw Exception('El recetario cambió durante la descarga. Reintenta.');
      }
      entities.addAll(page['entities']);
      next = page['next'];
    }
    value['entities'] = entities;
    await locked(() async {
      await db.transaction(() async {
        // Never erase local work during a full download or after a server restore.
        await db.customStatement(
          'DELETE FROM entities WHERE id NOT IN (SELECT entity_id FROM outbox)',
        );
        for (final raw in value['entities']) {
          final entry = Entry.fromJson(Map<String, dynamic>.from(raw));
          final queued = await db
              .customSelect(
                'SELECT 1 FROM outbox WHERE entity_id=?',
                variables: [Variable(entry.id)],
              )
              .get();
          if (queued.isEmpty) await _put(entry);
        }
        await _pref('generation', value['generation']);
        await _pref('cursor', '${value['cursor']}');
      });
      await load(readSecrets: false);
    });
  }

  Future<void> sync() async {
    if (syncing || url.isEmpty || token.isEmpty) return;
    syncing = true;
    status = 'Actualizando…';
    notifyListeners();
    try {
      if (generation.isEmpty) await _snapshot();
      var count = 0;
      var resets = 0;
      while (count++ < 100) {
        final batch = await locked(() async {
          final rows = await db
              .customSelect(
                'SELECT o.payload FROM outbox o WHERE NOT EXISTS '
                '(SELECT 1 FROM outbox prior WHERE prior.entity_id=o.entity_id AND prior.seq<o.seq) '
                'ORDER BY o.seq LIMIT 25',
              )
              .get();
          final selected = <Map<String, dynamic>>[];
          var bytes = 0;
          await db.transaction(() async {
            for (final row in rows) {
              final text = row.read<String>('payload');
              final size = utf8.encode(text).length;
              if (selected.isNotEmpty && bytes + size > 10000000) break;
              final op = Map<String, dynamic>.from(jsonDecode(text));
              selected.add(op);
              bytes += size;
              await db.customStatement(
                'UPDATE outbox SET attempted=1 WHERE id=?',
                [op['id']],
              );
            }
          });
          inFlight = selected.isEmpty ? null : selected.first['id'];
          return selected;
        });
        if (batch.isEmpty) break;
        dynamic response;
        try {
          response = await request(
            'POST',
            '/v1/push',
            body: {'generation': generation, 'operations': batch},
          );
        } on ApiError catch (error) {
          if (error.code == 409) {
            if (++resets > 3) {
              throw ApiError(
                409,
                'El servidor cambia continuamente. Los cambios locales siguen guardados; reintenta más tarde.',
              );
            }
            inFlight = null;
            await _snapshot();
            continue;
          }
          rethrow;
        }
        final results = response is Map ? response['results'] : null;
        if (results is! List || results.length != batch.length) {
          throw ApiError(
            502,
            'Confirmación incompleta del servidor. Los cambios siguen guardados aquí.',
          );
        }
        for (var i = 0; i < batch.length; i++) {
          final next = batch[i];
          final result = results[i];
          if (result is! Map ||
              !['applied', 'conflict'].contains(result['status']) ||
              (result['id'] != null && result['id'] != next['id'])) {
            throw ApiError(
              502,
              'El servidor no confirmó el cambio solicitado.',
            );
          }
          final acknowledged = result['status'] == 'applied'
              ? result['entity']
              : result['server'];
          if ((result['status'] == 'applied' && acknowledged == null) ||
              (acknowledged != null &&
                  (acknowledged is! Map ||
                      acknowledged['id'] != next['entity_id'] ||
                      acknowledged['kind'] != next['kind']))) {
            throw ApiError(
              502,
              'La confirmación corresponde a otro elemento. El cambio sigue guardado aquí.',
            );
          }
        }
        await locked(() async {
          await db.transaction(() async {
            for (var i = 0; i < batch.length; i++) {
              final next = batch[i];
              final result = results[i];
              await db.customStatement('DELETE FROM outbox WHERE id=?', [
                next['id'],
              ]);
              final rest = await db
                  .customSelect(
                    'SELECT * FROM outbox WHERE entity_id=? ORDER BY seq',
                    variables: [Variable(next['entity_id'] as String)],
                  )
                  .get();
              if (result['status'] == 'conflict') {
                // Preserve the newest local proposal, including edits made during the request.
                final local = get(next['entity_id']);
                final proposal = {
                  'id': newId(),
                  'kind': next['kind'],
                  'entity_id': next['entity_id'],
                  'data': local?.data ?? next['data'],
                  'deleted': local?.deleted ?? next['deleted'],
                  'server': result['server'],
                };
                await db.customStatement('INSERT INTO conflicts VALUES (?,?)', [
                  proposal['id'],
                  jsonEncode(onlinePhotoTree(proposal)),
                ]);
                await db.customStatement(
                  'DELETE FROM outbox WHERE entity_id=?',
                  [next['entity_id']],
                );
                if (result['server'] != null) {
                  await _put(
                    Entry.fromJson(Map<String, dynamic>.from(result['server'])),
                  );
                } else {
                  await db.customStatement('DELETE FROM entities WHERE id=?', [
                    next['entity_id'],
                  ]);
                }
              } else {
                final remote = Entry.fromJson(
                  Map<String, dynamic>.from(result['entity']),
                );
                if (rest.isEmpty) {
                  await _put(remote);
                } else {
                  final local = get(remote.id)!;
                  await _put(
                    Entry(
                      local.id,
                      local.kind,
                      remote.revision,
                      local.data,
                      deleted: local.deleted,
                    ),
                  );
                  final following = Map<String, dynamic>.from(
                    jsonDecode(rest.first.read<String>('payload')),
                  );
                  following['base'] = remote.revision;
                  await db.customStatement(
                    'UPDATE outbox SET payload=? WHERE id=?',
                    [jsonEncode(following), following['id']],
                  );
                }
              }
            }
          });
          inFlight = null;
          await load(readSecrets: false);
        });
      }
      var more = true;
      while (more) {
        dynamic value;
        try {
          value = await request(
            'GET',
            '/v1/changes?cursor=${prefs['cursor'] ?? '0'}&epoch=$generation',
          );
        } on ApiError catch (error) {
          if (error.code == 409) {
            if (++resets > 3) {
              throw ApiError(
                409,
                'El servidor cambia continuamente. Los cambios locales siguen guardados; reintenta más tarde.',
              );
            }
            await _snapshot();
            continue;
          }
          rethrow;
        }
        final previousCursor = int.tryParse(prefs['cursor'] ?? '0') ?? 0;
        if (value is! Map ||
            value['entities'] is! List ||
            value['cursor'] is! int ||
            value['cursor'] < previousCursor ||
            (value['more'] == true && value['cursor'] <= previousCursor)) {
          throw ApiError(
            502,
            'La descarga no avanza. Los datos locales siguen guardados; vuelve a intentar.',
          );
        }
        await locked(() async {
          await db.transaction(() async {
            for (final raw in value['entities']) {
              final entry = Entry.fromJson(Map<String, dynamic>.from(raw));
              final queued = await db
                  .customSelect(
                    'SELECT 1 FROM outbox WHERE entity_id=?',
                    variables: [Variable(entry.id)],
                  )
                  .get();
              if (queued.isEmpty) await _put(entry);
            }
            await _pref('cursor', '${value['cursor']}');
            await _pref('last_sync', DateTime.now().toIso8601String());
          });
          await load(readSecrets: false);
        });
        more = value['more'] == true;
      }
      status = pending == 0
          ? 'Todo actualizado'
          : '$pending cambios pendientes';
    } on ApiError catch (error) {
      status = error.code == 401
          ? 'Acceso caducado o revocado · revisa la conexión'
          : error.code == 403
          ? 'Perfil de lectura · cambios locales conservados'
          : 'No se pudo actualizar: ${error.message}';
    } catch (_) {
      status = 'Sin conexión con el servidor · cambios guardados aquí';
    } finally {
      inFlight = null;
      syncing = false;
      notifyListeners();
    }
  }

  Future<void> resolve(Map<String, dynamic> conflict, String choice) async {
    if (choice == 'replace') {
      await save(
        conflict['kind'],
        Map<String, dynamic>.from(conflict['data']),
        id: conflict['entity_id'],
        deleted: conflict['deleted'] == true,
      );
    } else if (choice == 'copy') {
      final data = Map<String, dynamic>.from(conflict['data']);
      if (conflict['kind'] == 'recipe') {
        final title = '${data['title']}';
        data['title'] =
            '${title.substring(0, title.length.clamp(0, 239))} · variante';
      }
      await save(conflict['kind'], data);
    }
    await locked(() async {
      await db.customStatement('DELETE FROM conflicts WHERE id=?', [
        conflict['id'],
      ]);
      await load(readSecrets: false);
    });
  }

  Map<String, dynamic> exportData() => {
    'format': 'mesa-recetario',
    'version': 1,
    'exported': DateTime.now().toIso8601String(),
    'entities': entries.map((x) => x.toJson()).toList(),
    'conflicts': conflicts,
  };
  Future<int> importData(String text) async {
    final value = jsonDecode(text);
    if (value is! Map ||
        value['format'] != 'mesa-recetario' ||
        value['version'] != 1 ||
        value['entities'] is! List) {
      throw Exception('El archivo no es una exportación de Mesa versión 1.');
    }
    if ((value['entities'] as List).any((x) => x is! Map)) {
      throw Exception('Hay elementos incorrectos en el archivo.');
    }
    final originalIds = <String>{};
    for (final raw in value['entities']) {
      final id = raw['id'];
      if (id is! String ||
          id.isEmpty ||
          id.length > 80 ||
          !originalIds.add(id)) {
        throw Exception(
          'El archivo contiene identificadores ausentes o repetidos.',
        );
      }
    }
    final items = (value['entities'] as List)
        .where((x) => x['deleted'] != true)
        .toList();
    // Validate the entire file before writing anything.
    for (final raw in items) {
      if (raw is! Map ||
          !['recipe', 'shopping', 'meal', 'collection'].contains(raw['kind']) ||
          raw['data'] is! Map) {
        throw Exception('Hay elementos incorrectos en el archivo.');
      }
      validateEntryData(
        raw['kind'],
        raw['kind'] == 'recipe'
            ? onlineRecipeData(Map<String, dynamic>.from(raw['data']))
            : Map<String, dynamic>.from(raw['data']),
      );
    }
    final ids = {for (final raw in items) raw['id']: newId()};
    final prepared = <Entry>[];
    for (final raw in items) {
      final data = Map<String, dynamic>.from(raw['data']);
      if (data['recipe_id'] != null) {
        data['recipe_id'] = ids[data['recipe_id']] ?? data['recipe_id'];
      }
      for (final field in ['category_ids', 'catalog_ids']) {
        if (data[field] is List) {
          data[field] = (data[field] as List)
              .map((id) => ids[id] ?? id)
              .toList();
        }
      }
      if (data['source'] is String) {
        for (final prefix in ['recipe:', 'meal:']) {
          final original = (data['source'] as String).replaceFirst(prefix, '');
          if ((data['source'] as String).startsWith(prefix) &&
              ids.containsKey(original)) {
            data['source'] = '$prefix${ids[original]}';
            break;
          }
        }
      }
      final clean = raw['kind'] == 'recipe' ? onlineRecipeData(data) : data;
      validateEntryData(raw['kind'], clean);
      prepared.add(Entry(ids[raw['id']]!, raw['kind'], 0, clean));
    }
    await locked(() async {
      if (!editable) throw Exception('Tu perfil tiene acceso de lectura.');
      await db.transaction(() async {
        for (final entry in prepared) {
          await _put(entry);
          final opId = newId();
          await db.customStatement(
            'INSERT INTO outbox(id,entity_id,payload) VALUES (?,?,?)',
            [
              opId,
              entry.id,
              jsonEncode({
                'id': opId,
                'entity_id': entry.id,
                'kind': entry.kind,
                'base': 0,
                'data': entry.data,
                'deleted': false,
                'action': 'save',
              }),
            ],
          );
        }
      });
      await load(readSecrets: false);
    });
    unawaited(sync());
    return items.length;
  }

  @override
  void dispose() {
    _timer?.cancel();
    client.close();
    unawaited(db.close());
    super.dispose();
  }
}

class ApiError implements Exception {
  final int code;
  final String message;
  ApiError(this.code, this.message);
  @override
  String toString() => message;
}
