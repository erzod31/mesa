import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mesa/photos.dart';
import 'package:mesa/store.dart';

import 'photos_test.dart' show photoBytes;
import 'store_test.dart' show recipe;

void main() {
  test(
    'Legacy cover, every valid URL and credits survive without image bytes',
    () {
      final data = recipe('Pan')
        ..addAll({
          'image': 'cover-bytes',
          'photos': [
            {
              'url': 'https://example.org/one.jpg',
              'image': 'first',
              'artist': 'Ana',
            },
            {
              'url': 'https://example.org/two.jpg',
              'image': 'cover-bytes',
              'artist': 'Bea',
            },
            {'image': 'personal'},
            {'url': 'https://127.0.0.1/private.jpg', 'image': 'unsafe'},
          ],
        });
      final clean = onlineRecipeData(data);
      expect(coverImage(clean), 'https://example.org/two.jpg');
      expect(recipePhotos(clean), hasLength(2));
      expect(recipePhotos(clean)[1]['artist'], 'Bea');
      expect(jsonEncode(clean), isNot(contains('bytes')));
      expect(clean.containsKey('image'), false);
      expect(data['image'], 'cover-bytes');
    },
  );

  test('Migration cleans recipes, drafts, catalog cache and conflicts; retried receipts remain immutable', () async {
    final db = LocalDb(NativeDatabase.memory());
    final legacy = recipe('Receta conservada')
      ..addAll({
        'image': 'legacy-bytes',
        'photos': [
          {'url': 'https://example.org/pan.jpg', 'image': 'legacy-bytes'},
        ],
      });
    await db.customStatement('INSERT INTO entities VALUES (?,?,?,?,?)', [
      'saved',
      'recipe',
      2,
      jsonEncode(legacy),
      0,
    ]);
    final rawOp = jsonEncode({'id': 'retry', 'kind': 'recipe', 'data': legacy});
    await db.customStatement(
      'INSERT INTO outbox(id,entity_id,payload,attempted) VALUES (?,?,?,?)',
      ['retry', 'saved', rawOp, 1],
    );
    await db.customStatement(
      'INSERT INTO outbox(id,entity_id,payload) VALUES (?,?,?)',
      ['unsent', 'other', rawOp],
    );
    await db.customStatement('INSERT INTO conflicts VALUES (?,?)', [
      'conflict',
      jsonEncode({'kind': 'recipe', 'data': legacy}),
    ]);
    await db.customStatement('INSERT INTO prefs VALUES (?,?)', [
      'draft:new',
      jsonEncode(legacy),
    ]);
    await db.customStatement('INSERT INTO prefs VALUES (?,?)', [
      'catalog-cache',
      jsonEncode({
        'detail': legacy,
        'search': {
          'items': [
            {
              'image_data': 'legacy-bytes',
              'image': 'https://example.org/pan.jpg',
            },
          ],
        },
      }),
    ]);
    final store = Cookbook(db);
    await store.load(readSecrets: false);
    expect(store.get('saved')!.title, 'Receta conservada');
    expect(coverImage(store.get('saved')!.data), 'https://example.org/pan.jpg');
    for (final table in ['entities', 'conflicts', 'prefs']) {
      final rows = await db.customSelect('SELECT * FROM $table').get();
      expect(
        jsonEncode(rows.map((r) => r.data).toList()),
        isNot(contains('legacy-bytes')),
      );
    }
    final queued = await db
        .customSelect('SELECT payload,attempted FROM outbox ORDER BY seq')
        .get();
    expect(queued.first.read<String>('payload'), rawOp);
    expect(
      queued.last.read<String>('payload'),
      isNot(contains('legacy-bytes')),
    );
    await store.preference('draft:new', jsonEncode(legacy));
    expect(store.prefs['draft:new'], isNot(contains('legacy-bytes')));
    store.dispose();
  });

  test('New saves, queues and exports contain references only', () async {
    final store = Cookbook(LocalDb(NativeDatabase.memory()));
    await store.load(readSecrets: false);
    await store.save(
      'recipe',
      recipe('Pan')..addAll({
        'image': 'old-inline-bytes',
        'photos': [
          {'url': 'https://example.org/pan.jpg', 'image': 'old-inline-bytes'},
        ],
      }),
      id: 'recipe',
    );
    final queued = await store.db
        .customSelect('SELECT payload FROM outbox')
        .getSingle();
    expect(queued.read<String>('payload'), isNot(contains('old-inline-bytes')));
    expect(jsonEncode(store.exportData()), isNot(contains('old-inline-bytes')));
    store.dispose();
  });

  test('Photos never send family credentials, cookies or conditional cache headers', () async {
    var calls = 0;
    final client = MockClient((request) async {
      calls++;
      expect(
        request.headers.keys.map((k) => k.toLowerCase()),
        isNot(contains('authorization')),
      );
      expect(
        request.headers.keys.map((k) => k.toLowerCase()),
        isNot(contains('cookie')),
      );
      expect(request.headers['cache-control'], 'no-cache, no-store');
      expect(request.followRedirects, false);
      return http.Response.bytes(photoBytes(), 200);
    });
    for (var i = 0; i < 2; i++) {
      expect(
        await fetchOnlinePhoto(client, 'https://example.org/pan.jpg'),
        isNotEmpty,
      );
    }
    expect(calls, 2);
    client.close();
  });

  test(
    'Photo redirects cannot access private addresses; response size is bounded',
    () async {
      var calls = 0;
      final redirect = MockClient((_) async {
        calls++;
        return http.Response(
          '',
          302,
          headers: {'location': 'https://192.168.1.1/photo.jpg'},
        );
      });
      await expectLater(
        fetchOnlinePhoto(redirect, 'https://example.org/pan.jpg'),
        throwsException,
      );
      expect(calls, 1);
      redirect.close();
      final large = MockClient(
        (_) async => http.Response.bytes(Uint8List(10000001), 200),
      );
      await expectLater(
        fetchOnlinePhoto(large, 'https://example.org/pan.jpg'),
        throwsException,
      );
      large.close();
    },
  );

  test('Public DNS address policy excludes loopback, LAN and Tailscale', () {
    for (final ip in [
      '127.0.0.1',
      '10.0.0.1',
      '192.168.1.1',
      '169.254.1.1',
      '100.100.100.100',
      '::1',
      'fc00::1',
      '::ffff:127.0.0.1',
      '2001:db8::1',
    ]) {
      expect(publicPhotoAddress(InternetAddress(ip)), false, reason: ip);
    }
    expect(publicPhotoAddress(InternetAddress('8.8.8.8')), true);
    expect(publicPhotoAddress(InternetAddress('192.0.78.13')), true);
    expect(publicPhotoAddress(InternetAddress('198.51.100.1')), false);
    expect(publicPhotoAddress(InternetAddress('192.0.2.1')), false);
    expect(publicPhotoAddress(InternetAddress('2606:4700::1111')), true);
    expect(
      onlinePhotoUrl('https://starfly.tailc69897.ts.net/photo.jpg'),
      false,
    );
  });

  testWidgets(
    'Display bypasses image cache, releases images on background/dispose and refetches',
    (tester) async {
      var calls = 0;
      final cache = PaintingBinding.instance.imageCache;
      final before = cache.currentSize;
      Widget photo() => MaterialApp(
        home: SizedBox(
          width: 100,
          height: 100,
          child: RecipePhoto(
            {'url': 'https://example.org/pan.jpg'},
            clientFactory: () => MockClient((_) async {
              calls++;
              return http.Response.bytes(photoBytes(), 200);
            }),
          ),
        ),
      );
      Future<void> waitImage() async {
        for (var attempt = 0; attempt < 20; attempt++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)),
          );
          await tester.pump();
          if (find.byType(RawImage).evaluate().isNotEmpty) return;
        }
        fail('The transient image did not finish decoding.');
      }

      await tester.pumpWidget(photo());
      await waitImage();
      final image = tester.widget<RawImage>(find.byType(RawImage)).image!;
      expect(cache.currentSize, before);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      expect(image.debugDisposed, true);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await waitImage();
      expect(calls, 2);
      final fresh = tester.widget<RawImage>(find.byType(RawImage)).image!;
      await tester.pumpWidget(const SizedBox());
      expect(fresh.debugDisposed, true);
      await tester.pumpWidget(photo());
      await waitImage();
      expect(calls, 3);
      expect(cache.currentSize, before);
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    },
  );
}
