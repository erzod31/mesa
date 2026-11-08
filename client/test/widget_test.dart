import 'dart:io';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mesa/store.dart';
import 'package:mesa/library.dart';
import 'package:mesa/editor.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mesa/timers.dart';
import 'package:mesa/pages.dart';
import 'package:mesa/photos.dart';
import 'package:mesa/ui.dart';

import 'store_test.dart' show recipe;
import 'photos_test.dart' show photoBytes;

void main() {
  setUpAll(() async {
    final font = FontLoader('Segoe UI');
    font.addFont(
      File('C:/Windows/Fonts/segoeui.ttf')
          .readAsBytes()
          .then((b) => ByteData.sublistView(b)),
    );
    await font.load();
    final icons = FontLoader('MaterialIcons');
    icons.addFont(
      File(
        '../.tools/flutter/bin/cache/artifacts/material_fonts/materialicons-regular.otf',
      ).readAsBytes().then((b) => ByteData.sublistView(b)),
    );
    await icons.load();
  });
  testWidgets(
    'Pending catalogues stay out of discovery and saved family recipes remain available',
    (tester) async {
      final store = (await tester.runAsync(() async {
        final value = Cookbook(
          LocalDb(NativeDatabase.memory()),
          client: MockClient((request) async {
            expect(
              request.url.host,
              isIn(['public-api.wordpress.com', 'creativegan.net']),
            );
            return http.Response('{"found":0,"posts":[]}', 200);
          }),
        );
        await value.load(readSecrets: false);
        await value.save('recipe', recipe('Mi receta guardada'), id: 'saved');
        return value;
      }))!;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DiscoverRecipes(
              store: store,
              onEdit: ({entry, initial}) async {},
            ),
          ),
        ),
      );
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 60)),
        );
      }
      await tester.pumpAndSettle();
      final dropdown = tester.widget<DropdownButton<String>>(
        find.byType(DropdownButton<String>),
      );
      final options = dropdown.items!.map((item) => item.value).toList();
      expect(options, containsAll(['', 'España', 'Polonia', 'Internacional']));
      expect(options, isNot(contains('es-petitchef')));
      expect(find.byType(DropdownButtonFormField<String>), findsOneWidget);
      expect(store.of('recipe').single.data['title'], 'Mi receta guardada');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      store.dispose();
    },
  );
  testWidgets(
    'Discovery opens the licensed delokos source and reads recipes inside Mesa',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var requests = 0;
      final opened = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('mesa/native'),
        (call) async {
          if (call.method == 'openUrl') opened.add(call.arguments as String);
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          const MethodChannel('mesa/native'),
          null,
        ),
      );
      final store = await tester.runAsync(() async {
        final s = Cookbook(
          LocalDb(NativeDatabase.memory()),
          client: MockClient((request) async {
            expect(request.headers.containsKey('authorization'), false);
            requests++;
            if (!request.url.path.contains('delokos.wordpress.com')) {
              return http.Response('{"posts":[],"found":0}', 200);
            }
            Map<String, dynamic> post(int id) => {
              'ID': id,
              'URL': 'https://delokos.wordpress.com/2026/10/16/receta-$id/',
              'title': 'Receta delokos $id',
              'categories': {},
              'content':
                  '<p>Ingredientes</p><ul><li>200 g de arroz</li><li>500 ml de agua</li></ul><p>Preparación</p><p>Cocer durante 20 minutos.</p><img src="https://delokos.files.wordpress.com/2026/10/foto-$id.jpg"><img src="https://delokos.files.wordpress.com/2026/10/paso-$id.jpg">',
            };
            if (request.url.path.endsWith('/posts/1')) {
              return http.Response(
                jsonEncode(post(1)),
                200,
                headers: {'content-type': 'application/json; charset=utf-8'},
              );
            }
            return http.Response(
              jsonEncode({
                'posts': List.generate(16, (i) => post(i + 1)),
                'found': 16,
              }),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          }),
        );
        await s.load(readSecrets: false);
        return s;
      });
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DiscoverRecipes(
              store: store!,
              onEdit: ({entry, initial}) async {},
            ),
          ),
        ),
      );
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 150));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 75)),
        );
      }
      await tester.pumpAndSettle();
      expect(requests, 3);
      expect(find.text('16 recetas con foto'), findsOneWidget);
      expect(find.text('Receta delokos 1'), findsOneWidget);
      expect(find.text('Receta delokos 16'), findsNothing); // Lazy cards.
      final picker = tester.widget<DropdownButtonFormField<String>>(
        find.byType(DropdownButtonFormField<String>),
      );
      expect(picker.initialValue, 'España');
      await tester.ensureVisible(find.text('Receta delokos 1'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Receta delokos 1'));
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 75)),
        );
      }
      await tester.pumpAndSettle();
      expect(requests, 4);
      expect(opened, isEmpty);
      expect(
        tester.widget<PhotoGallery>(find.byType(PhotoGallery)).photos,
        hasLength(2),
      );
      await tester.scrollUntilVisible(
        find.text('• 200 g de arroz'),
        200,
        scrollable: find
            .descendant(
              of: find.byKey(const ValueKey('recipe-preview-content')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(find.text('• 200 g de arroz'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Cocer durante 20 minutos.'),
        150,
        scrollable: find
            .descendant(
              of: find.byKey(const ValueKey('recipe-preview-content')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(find.text('Cocer durante 20 minutos.'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      store.dispose();
    },
  );

  testWidgets(
    'An unreadable public recipe stays inside Mesa and offers retry',
    (tester) async {
      final opened = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('mesa/native'),
        (call) async {
          if (call.method == 'openUrl') opened.add(call.arguments as String);
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          const MethodChannel('mesa/native'),
          null,
        ),
      );
      final store = (await tester.runAsync(() async {
        final s = Cookbook(
          LocalDb(NativeDatabase.memory()),
          client: MockClient(
            (request) async => http.Response(
              jsonEncode(
                request.url.path.endsWith('/posts/1')
                    ? {'error': 'not_found'}
                    : {
                        'found': 1,
                        'posts': [
                          {
                            'ID': 1,
                            'URL': 'https://delokos.wordpress.com/2026/10/16/bloqueada/',
                            'title': 'Receta bloqueada',
                            'categories': {},
                            'content': '<p>Ingredientes</p><ul><li>200 g de arroz</li></ul><p>Preparación</p><p>Cocer.</p><img src="https://delokos.files.wordpress.com/2026/10/foto.jpg">',
                          },
                        ],
                      },
              ),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            ),
          ),
        );
        await s.load(readSecrets: false);
        return s;
      }))!;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DiscoverRecipes(
              store: store,
              onEdit: ({entry, initial}) async {},
            ),
          ),
        ),
      );
      Future<void> settle() async {
        for (var i = 0; i < 4; i++) {
          await tester.pump(const Duration(milliseconds: 100));
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 70)),
          );
        }
        await tester.pumpAndSettle();
      }

      await settle();
      await tester.ensureVisible(find.text('Receta bloqueada'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Receta bloqueada'));
      await settle();
      expect(find.text('No se pudo abrir la receta'), findsOneWidget);
      expect(opened, isEmpty);
      expect(find.text('Reintentar').hitTestable(), findsOneWidget);
      await tester.tap(find.text('Reintentar'));
      await settle();
      expect(find.text('No se pudo abrir la receta'), findsOneWidget);
      expect(opened, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      store.dispose();
    },
  );

  testWidgets('Imported recipe displays quantities and gallery on phone', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final live = File('../output/tortilla-gallery-preview.json');
    final data = live.existsSync()
        ? Map<String, dynamic>.from(jsonDecode(live.readAsStringSync()))
        : (recipe('Tortilla')..addAll({
            'ingredients': ['8 huevos', '1 kg de patatas', 'Sal'],
            'photos': <Map<String, dynamic>>[],
          }));
    final s = await tester.runAsync(() async {
      final value = Cookbook(LocalDb(NativeDatabase.memory()));
      await value.load(readSecrets: false);
      await value.save('recipe', data, id: 'gallery');
      return value;
    });
    final timers = KitchenTimers(s!);
    final key = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            colorSchemeSeed: const Color(0xff285b44),
            fontFamily: 'Segoe UI',
          ),
          home: Scaffold(
            appBar: AppBar(title: const Text('Mesa · Receta')),
            body: RecipeView(
              store: s,
              timers: timers,
              id: 'gallery',
              onEdit: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(PhotoGallery), findsOneWidget);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.runAsync(() async {
      final image =
          await (key.currentContext!.findRenderObject()
                  as RenderRepaintBoundary)
              .toImage();
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      await Directory('../output/screenshots').create(recursive: true);
      await File('../output/screenshots/mesa-gallery-android.png')
          .writeAsBytes(png!.buffer.asUint8List());
      image.dispose();
    });
    final firstAmount = (data['ingredients'] as List).first as String;
    await tester.scrollUntilVisible(
      find.text(firstAmount),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text(firstAmount), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(CheckboxListTile),
        matching: find.textContaining('1 kg de patatas'),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    timers.dispose();
    s.dispose();
  });
  testWidgets(
    'Phone can create a recipe, search it and navigate shared lists',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final s = await tester.runAsync(() async {
        final v = Cookbook(LocalDb(NativeDatabase.memory()));
        await v.load(readSecrets: false);
        return v;
      });
      final timers = KitchenTimers(s!);
      await tester.pumpWidget(MesaApp(store: s, timers: timers));
      await tester.pumpAndSettle();
      expect(find.text('Tu cocina empieza aquí'), findsOneWidget);
      final create = find.byTooltip('Nueva receta');
      await tester.ensureVisible(create);
      await tester.pumpAndSettle();
      await tester.tap(create);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextFormField).first,
        'Sopa de la abuela',
      );
      await tester.runAsync(() async {
        await tester.tap(find.text('Guardar'));
        await Future<void>.delayed(const Duration(milliseconds: 180));
      });
      await tester.pumpAndSettle();
      expect(s.of('recipe').single.title, 'Sopa de la abuela');
      await tester.scrollUntilVisible(
        find.text('Sopa de la abuela'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Sopa de la abuela'), findsOneWidget);
      await tester.drag(
        find.byType(CustomScrollView).first,
        const Offset(0, 800),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'ABUELA');
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Sopa de la abuela'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Sopa de la abuela'), findsOneWidget);
      await tester.tap(find.text('Semana').last);
      await tester.pumpAndSettle();
      expect(find.text('Menú semanal'), findsOneWidget);
      await tester.tap(find.text('Compra').last);
      await tester.pumpAndSettle();
      expect(find.text('Lista de compra'), findsOneWidget);
      expect(tester.takeException(), null);
      await tester.pumpWidget(const SizedBox());
      timers.dispose();
      s.dispose();
    },
  );
  testWidgets('Spanish discovery previews and saves recipe with provenance', (
    tester,
  ) async {
    final s = await tester.runAsync(() async {
      final v = Cookbook(
        LocalDb(NativeDatabase.memory()),
        client: MockClient((req) async {
          if (req.url.host != 'es.wikibooks.org' &&
              req.url.host != 'upload.wikimedia.org') {
            return http.Response('{}', 200);
          }
          if (req.url.host == 'www.petitchef.es') {
            return http.Response('<main></main>', 200);
          }
          if (req.url.host == 'upload.wikimedia.org') {
            return http.Response.bytes(photoBytes(), 200);
          }
          if (req.url.queryParameters['prop'] == 'images') {
            return http.Response(
              jsonEncode({
                'query': {
                  'pages': [
                    {
                      'title': 'Artes culinarias/Recetas/Sopa de prueba',
                      'images': [
                        {'title': 'Archivo:Sopa.jpg'},
                      ],
                    },
                  ],
                },
              }),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          }
          if (req.url.queryParameters['prop'] == 'imageinfo') {
            return http.Response(
              jsonEncode({
                'query': {
                  'pages': [
                    {
                      'title': 'Archivo:Sopa.jpg',
                      'imageinfo': [
                        {
                          'thumburl': 'https://upload.wikimedia.org/wikipedia/commons/Sopa.jpg',
                          'extmetadata': {
                            'LicenseShortName': {'value': 'CC BY-SA 4.0'},
                            'LicenseUrl': {
                              'value': 'https://creativecommons.org/licenses/by-sa/4.0/',
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
          }
          final detail = req.url.queryParameters['action'] == 'parse';
          return http.Response(
            jsonEncode(
              detail
                  ? {
                      'parse': {
                        'title': 'Artes culinarias/Recetas/Sopa de prueba',
                        'revid': 17,
                        'images': ['Sopa.jpg'],
                        'text': '<h2>Ingredientes</h2><ul><li>2 zanahorias</li></ul><h2>Preparación</h2><p>Cocer 15 minutos.</p>',
                      },
                    }
                  : {
                      'query': {
                        'categorymembers': [
                          {'title': 'Artes culinarias/Recetas/Sopa de prueba'},
                        ],
                      },
                    },
            ),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );
      await v.load(readSecrets: false);
      await v.preference('discovery-country', 'Internacional');
      return v;
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: DiscoverRecipes(
              store: s!,
              onEdit: ({entry, initial}) async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => RecipeEditor(store: s, initial: initial),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 200));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
    }
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Sopa de prueba'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await Scrollable.ensureVisible(
      tester.element(find.text('Sopa de prueba')),
      alignment: 0.5,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sopa de prueba'));
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 200));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
    }
    await tester.pumpAndSettle();
    final previewScroll = find
        .descendant(
          of: find.byKey(const ValueKey('recipe-preview-content')),
          matching: find.byType(Scrollable),
        )
        .first;
    await tester.scrollUntilVisible(
      find.text('Original, medidas y fuente'),
      150,
      scrollable: previewScroll,
    );
    await Scrollable.ensureVisible(
      tester.element(find.text('Original, medidas y fuente')),
      alignment: 0.5,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Original, medidas y fuente'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.textContaining('CC BY-SA 4.0').last,
      150,
      scrollable: previewScroll,
    );
    expect(find.textContaining('CC BY-SA 4.0'), findsWidgets);
    await tester.scrollUntilVisible(
      find.text('• 2 zanahorias'),
      200,
      scrollable: find
          .descendant(
            of: find.byKey(const ValueKey('recipe-preview-content')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(find.text('• 2 zanahorias'), findsOneWidget);
    await tester.tap(find.text('Revisar y guardar'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Guardar'));
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 200));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
    }
    await tester.pumpAndSettle();
    expect(s!.of('recipe').single.data['origin']['language'], 'es');
    expect(s.of('recipe').single.data['origin']['url'], contains('oldid=17'));
    expect(tester.takeException(), null);
    await tester.pumpWidget(const SizedBox());
    s.dispose();
  });
  testWidgets(
    'Discovery offers remaining catalogues and excludes all three retired sources',
    (tester) async {
      final s = await tester.runAsync(() async {
        final store = Cookbook(
          LocalDb(NativeDatabase.memory()),
          client: MockClient((req) async {
            return http.Response('', 503);
          }),
        );
        await store.load(readSecrets: false);
        return store;
      });
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DiscoverRecipes(
              store: s!,
              onEdit: ({entry, initial}) async {
                await s.save('recipe', initial!, id: 'offline-uruguay');
              },
            ),
          ),
        ),
      );
      Future<void> waitRequests() async {
        for (var i = 0; i < 4; i++) {
          await tester.pump(const Duration(milliseconds: 100));
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 75)),
          );
        }
        await tester.pumpAndSettle();
      }

      await waitRequests();
      final options = tester
          .widget<DropdownButton<String>>(find.byType(DropdownButton<String>))
          .items!
          .map((i) => i.value)
          .toList();
      expect(options, containsAll(['España', 'Polonia', 'Internacional']));
      expect(options.every((v) => v == '' || !v!.contains('-')), true);
      expect(find.byType(DropdownButtonFormField<String>), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      s.dispose();
    },
  );

  testWidgets('Library supports a narrow phone with large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final s = await tester.runAsync(() async {
      final v = Cookbook(LocalDb(NativeDatabase.memory()));
      await v.load(readSecrets: false);
      await v.save('recipe', recipe('Sopa familiar'));
      return v;
    });
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(320, 800),
            textScaler: TextScaler.linear(1.5),
          ),
          child: Scaffold(
            body: RecipeLibrary(
              store: s!,
              wide: false,
              onOpen: (_) {},
              onEdit: ({entry, initial}) async {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Sopa familiar'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(tester.takeException(), null);
    await tester.pumpWidget(const SizedBox());
    s.dispose();
  });
  for (final size in [const Size(1360, 900), const Size(390, 844)]) {
    testWidgets('Responsive recipe screen at ${size.width} px and preview', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final s = await tester.runAsync(() async {
        final v = Cookbook(LocalDb(NativeDatabase.memory()));
        await v.load(readSecrets: false);
        for (final title in [
          'Tortilla de patatas',
          'Pasta con tomate y albahaca',
          'Ensalada de garbanzos',
        ]) {
          await v.save('recipe', recipe(title));
        }
        return v;
      });
      final timers = KitchenTimers(s!);
      final key = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: key,
          child: MesaApp(store: s, timers: timers),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), null);
      await tester.runAsync(() async {
        final image =
            await (key.currentContext!.findRenderObject()
                    as RenderRepaintBoundary)
                .toImage();
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        final directory = Directory('../output/screenshots');
        await directory.create(recursive: true);
        await File(
          '${directory.path}/mesa-${size.width > 1000 ? 'windows' : 'android'}.png',
        ).writeAsBytes(data!.buffer.asUint8List());
        image.dispose();
      });
      {
        await tester.scrollUntilVisible(
          find.text('Tortilla de patatas'),
          300,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.ensureVisible(find.text('Tortilla de patatas'));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.text('Tortilla de patatas'));
      await tester.pumpAndSettle();
      expect(find.text('Ingredientes'), findsOneWidget);
      expect(tester.takeException(), null);
      await tester.pumpWidget(const SizedBox());
      timers.dispose();
      s.dispose();
    });
  }
}
