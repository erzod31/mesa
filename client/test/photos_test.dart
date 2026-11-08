import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image/image.dart' as img;
import 'package:mesa/catalogs.dart';
import 'package:mesa/models.dart';
import 'package:mesa/photos.dart';
import 'package:mesa/store.dart';

import 'store_test.dart' show recipe;

Uint8List photoBytes() => img.encodePng(img.Image(width: 12, height: 8));

void main() {
  test('Table ingredients preserve amounts and declared portions', () {
    final data = parseWiki('wiki-es', {
      'title': 'Artes culinarias/Recetas/Pan',
      'revid': 456,
      'text': '<p>Cantidad para 6 personas</p><table><tr><th>Ingredientes</th></tr><tr><td>500 g</td><td>de harina</td></tr><tr><td>1½ tazas</td><td>de agua</td></tr></table><h2>Preparación</h2><ol><li>Amasar.</li></ol>',
    });
    expect(data['ingredients'], ['500 g de harina', '1½ tazas de agua']);
    expect(data['servings'], 6);
    expect(missingQuantities(data), isEmpty);
    expect(
      missingQuantities({
        'ingredients': ['Harina', '2 huevos', 'Sal al gusto', '½ l de agua'],
      }),
      ['Harina'],
    );
    expect(catalogSources.take(2).map((s) => s.id), ['wiki-es', 'delokos-es']);
  });

  test('All dish photos retain separate credits, excluding template icons', () async {
    final api = CatalogApi(
      MockClient((req) async {
        expect(req.headers.containsKey('authorization'), false);
        expect(req.followRedirects, false);
        if (req.url.host == 'upload.wikimedia.org') {
          return fail('Metadata import must not fetch image bytes');
        }
        expect(req.url.host, 'es.wikibooks.org');
        if (req.url.queryParameters['action'] == 'parse') {
          return http.Response(
            jsonEncode({
              'parse': {
                'title': 'Artes culinarias/Recetas/Pan',
                'revid': 456,
                'text': '<h2>Ingredientes</h2><ul><li>500 g de harina</li></ul><h2>Preparación</h2><p>Amasar.</p>',
                'images': [
                  'Noia_64_apps_xclock.png',
                  '2o5dots.svg',
                  'Pan.jpg',
                  'Paso.jpg',
                  'Pan.jpg',
                ],
              },
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }
        return http.Response(
          jsonEncode({
            'query': {
              'pages': [
                for (final name in ['Pan.jpg', 'Paso.jpg'])
                  {
                    'title': 'Archivo:$name',
                    'imageinfo': [
                      {
                        'thumburl':
                            'https://upload.wikimedia.org/wikipedia/commons/$name',
                        'descriptionurl':
                            'https://commons.wikimedia.org/wiki/File:$name',
                        'extmetadata': {
                          'Artist': {'value': '<b>Autora</b>'},
                          'LicenseShortName': {'value': 'CC BY 4.0'},
                          'LicenseUrl': {
                            'value':
                                'https://creativecommons.org/licenses/by/4.0/',
                          },
                        },
                      },
                    ],
                  },
              ],
            },
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );
    final data = await api.detail(
      const CatalogItem(
        id: 'Artes culinarias/Recetas/Pan',
        title: 'Pan',
        provider: 'wiki-es',
      ),
    );
    final photos = recipePhotos(data);
    expect(photos.length, 2);
    expect(
      photos.every(
        (p) =>
            p['artist'] == 'Autora' &&
            p['license'] == 'CC BY 4.0' &&
            p['url'].isNotEmpty &&
            !p.containsKey('image'),
      ),
      true,
    );
    validateEntryData('recipe', data);
    expect(coverImage(data), photos.first['url']);
    expect(
      wikimediaPhotoUrl(
        'https://upload.wikimedia.org@127.0.0.1/wikipedia/a.jpg',
      ),
      false,
    );
  });

  test(
    'Export and reimport preserve only photo links, credits and quantities',
    () async {
      final s = Cookbook(LocalDb(NativeDatabase.memory()));
      await s.load(readSecrets: false);
      final data = recipe('Pan')
        ..addAll({
          'ingredients': ['500 g de harina', '1/2 l de agua'],
          'photos': [
            {
              'url': 'https://example.org/pan.jpg',
              'caption': 'Pan',
              'artist': 'Ana',
              'license': 'CC BY 4.0',
            },
            {
              'image': '',
              'url': 'https://example.org/paso.jpg',
              'error': 'Pendiente',
              'caption': 'Paso',
            },
          ],
        });
      await s.save('recipe', data, id: 'first');
      await s.importData(jsonEncode(s.exportData()));
      final copy = s.of('recipe').firstWhere((e) => e.id != 'first');
      expect(copy.data['photos'], recipePhotos(data));
      expect(
        jsonEncode(copy.data),
        isNot(contains(base64Encode(photoBytes()))),
      );
      expect(copy.lines('ingredients'), data['ingredients']);
      s.dispose();
    },
  );

  testWidgets(
    'Gallery swipes, opens zoom and keeps credits attached to selected photo',
    (tester) async {
      final photos = [
        {
          'url': 'https://example.org/pan.jpg',
          'caption': 'Portada',
          'artist': 'Ana',
        },
        {
          'image': '',
          'caption': 'Paso dos',
          'artist': 'Bea',
          'source': 'https://example.org',
        },
      ];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(child: PhotoGallery(photos: photos)),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Foto 1 de 2 · toca para ampliar'), findsOneWidget);
      await tester.drag(find.byType(PageView), const Offset(-650, 0));
      await tester.pumpAndSettle();
      expect(find.text('Foto 2 de 2 · toca para ampliar'), findsOneWidget);
      expect(find.text('Paso dos'), findsOneWidget);
      await tester.tap(find.text('Créditos de esta foto'));
      await tester.pumpAndSettle();
      expect(find.text('Bea\nhttps://example.org'), findsOneWidget);
      await tester.tapAt(
        tester.getTopLeft(find.byType(PageView)) + const Offset(30, 30),
      );
      await tester.pumpAndSettle();
      expect(find.byType(InteractiveViewer), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
