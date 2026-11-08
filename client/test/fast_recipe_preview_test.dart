import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mesa/catalogs.dart';
import 'package:mesa/recipe_preview.dart';
import 'package:mesa/store.dart';

void main() {
  setUpAll(()async {
    final font=FontLoader('Segoe UI');font.addFont(File('C:/Windows/Fonts/segoeui.ttf').readAsBytes().then(ByteData.sublistView));await font.load();
    final icons=FontLoader('MaterialIcons');icons.addFont(File('../.tools/flutter/bin/cache/artifacts/material_fonts/materialicons-regular.otf').readAsBytes().then(ByteData.sublistView));await icons.load();
  });
  for(final size in [const Size(1360,900),const Size(390,844)]) {
    for(final photosFirst in [true,false]) {
      testWidgets('Spanish title, ingredients and steps survive photo completion at ${size.width}, photos first: $photosFirst',(tester)async {
        tester.view.physicalSize=size;tester.view.devicePixelRatio=1;
        addTearDown(tester.view.resetPhysicalSize);addTearDown(tester.view.resetDevicePixelRatio);
        final photos=Completer<http.Response>(),spanish=Completer<http.Response>();
        final remembered=<Map<String,dynamic>>[];
        Map<String,dynamic>? sent;
        final client=MockClient((req)async {
          if(req.url.path=='/v1/translate-recipe'){sent=jsonDecode(req.body);return spanish.future;}
          if(req.url.queryParameters['action']=='parse'){return http.Response(jsonEncode({'parse':{'title':'Cookbook:Bread','revid':17,'images':['Bread.jpg'],
            'text':'<h2>Ingredients</h2><ul><li>2 eggs</li></ul><h2>Preparation</h2><p>Mix.</p>'}}),200);}
          return photos.future;
        });
        final store=(await tester.runAsync(()async {
          final s=Cookbook(LocalDb(NativeDatabase.memory()),client:client);await s.load(readSecrets:false);
          await s.preference('url','http://127.0.0.1:8765');s.token='test-token';return s;
        }))!;
        final imageKey=GlobalKey();
        await tester.pumpWidget(RepaintBoundary(key:imageKey,child:MaterialApp(debugShowCheckedModeBanner:false,theme:ThemeData(fontFamily:'Segoe UI',colorSchemeSeed:const Color(0xff285b44)),
          home:Builder(builder:(c)=>Scaffold(body:TextButton(onPressed:()=>showDialog(context:c,builder:(_)=>RecipePreview(
            item:const CatalogItem(id:'Cookbook:Bread',title:'Bread',provider:'wiki-en'),store:store,api:CatalogApi(client),
            remember:(value)async{remembered.add(value);},openSource:(_)async{},saveLabel:'Revisar y guardar')),child:const Text('Abrir')))))));
        await tester.tap(find.text('Abrir'));await tester.pump(const Duration(milliseconds:300));
        await tester.runAsync(()=>Future<void>.delayed(const Duration(milliseconds:30)));await tester.pump();
        expect(sent,isNotNull);
        void finishPhotos()=>photos.complete(http.Response(jsonEncode({'query':{'pages':[{'title':'File:Bread.jpg','imageinfo':[{
          'url':'https://upload.wikimedia.org/wikipedia/commons/Bread.jpg','mime':'image/jpeg',
          'extmetadata':{'LicenseShortName':{'value':'CC BY 4.0'},'LicenseUrl':{'value':'https://creativecommons.org/licenses/by/4.0/'}}
        }]}]}}),200));
        if(photosFirst){finishPhotos();await tester.runAsync(()=>Future<void>.delayed(const Duration(milliseconds:30)));await tester.pump(const Duration(milliseconds:50));}
        final raw=Map<String,dynamic>.from(sent!['recipe']);
        spanish.complete(http.Response(jsonEncode({...raw,'title':'Pan','language':'es','ingredients':['2 huevos'],'steps':['Mezclar.'],
          'original':{for(final k in ['title','ingredients','steps','notes','language'])k:raw[k]},
          'translation':{'target_language':'es','revision':3}}),200));
        await tester.runAsync(()=>Future<void>.delayed(const Duration(milliseconds:30)));await tester.pump(const Duration(milliseconds:50));
        if(!photosFirst){expect(find.text('Pan'),findsOneWidget);finishPhotos();await tester.runAsync(()=>Future<void>.delayed(const Duration(milliseconds:30)));await tester.pump(const Duration(milliseconds:50));}
        expect(find.text('Pan'),findsOneWidget,reason:tester.allWidgets.whereType<Text>().map((t)=>t.data).join(' | '));expect(find.textContaining('Traduciendo al español'),findsNothing);
        final scrollable=find.descendant(of:find.byKey(const ValueKey('recipe-preview-content')),matching:find.byType(Scrollable)).first;
        await tester.scrollUntilVisible(find.text('• 2 huevos'),100,scrollable:scrollable);
        expect(find.text('• 2 huevos'),findsOneWidget);expect(find.text('• 2 eggs'),findsNothing);
        await tester.scrollUntilVisible(find.text('Mezclar.'),100,scrollable:scrollable);
        expect(find.text('Mezclar.'),findsOneWidget);expect(find.text('Medidas originales'),findsNothing);
        expect(remembered.last['title'],'Pan');expect((remembered.last['photos'] as List).length,1);
        expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,isNotNull);
        if(photosFirst) {
          await tester.pump(const Duration(milliseconds:300));
          await tester.runAsync(()async {
            final render=imageKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
            final image=await render.toImage();final bytes=await image.toByteData(format:ui.ImageByteFormat.png);
            await File('../output/screenshots/translated-simple-${size.width>1000?'windows':'android'}.png').writeAsBytes(bytes!.buffer.asUint8List());image.dispose();
          });
        }
        await tester.scrollUntilVisible(find.text('Original, medidas y fuente'),100,scrollable:scrollable);
        await Scrollable.ensureVisible(tester.element(find.text('Original, medidas y fuente')),alignment:0.5);await tester.pump(const Duration(milliseconds:100));
        await tester.tap(find.text('Original, medidas y fuente'));await tester.pump(const Duration(milliseconds:300));
        await tester.scrollUntilVisible(find.text('Medidas originales'),100,scrollable:scrollable);expect(find.text('Medidas originales'),findsOneWidget);
        expect(tester.takeException(),isNull);
        await tester.tap(find.text('Cerrar'));await tester.pump(const Duration(milliseconds:300));
        await tester.pumpWidget(const SizedBox());await tester.runAsync(()=>Future<void>.delayed(const Duration(milliseconds:30)));await tester.pump(const Duration(seconds:31));store.dispose();
      });
    }
  }
  for(final size in [const Size(1360,900),const Size(390,844)]) {
    testWidgets('Preview renders in first frame and stays closable while source and translator wait at ${size.width}',(tester)async {
      tester.view.physicalSize=size;tester.view.devicePixelRatio=1;
      addTearDown(tester.view.resetPhysicalSize);addTearDown(tester.view.resetDevicePixelRatio);
      final page=Completer<http.Response>(),photos=Completer<http.Response>(),spanish=Completer<http.Response>();
      final opened=<String>[];
      Map<String,dynamic>? sent;
      final client=MockClient((req)async {
        if(req.url.path=='/v1/translate-recipe'){sent=jsonDecode(req.body);return spanish.future;}
        return req.url.queryParameters['action']=='parse'?page.future:photos.future;
      });
      final store=(await tester.runAsync(()async {final s=Cookbook(LocalDb(NativeDatabase.memory()),client:client);await s.load(readSecrets:false);await s.preference('url','http://127.0.0.1:8765');s.token='test-token';return s;}))!;
      final imageKey=GlobalKey();
      const item=CatalogItem(id:'Cookbook:Bread',title:'Bread',provider:'wiki-en');
      await tester.pumpWidget(RepaintBoundary(key:imageKey,child:MaterialApp(debugShowCheckedModeBanner:false,
        theme:ThemeData(fontFamily:'Segoe UI',colorSchemeSeed:const Color(0xff285b44)),home:Builder(builder:(c)=>Scaffold(body:TextButton(
        onPressed:()=>showDialog<Map<String,dynamic>>(context:c,builder:(_)=>RecipePreview(item:item,store:store,api:CatalogApi(client),remember:(_)async{},openSource:(url)async{opened.add(url);},saveLabel:'Revisar y guardar')),
        child:const Text('Abrir')))))));
      await tester.tap(find.text('Abrir'));await tester.pump(const Duration(milliseconds:16));
      expect(find.text('Bread'),findsOneWidget);expect(find.text('Cerrar'),findsOneWidget);expect(sent,isNull);
      await tester.pump(const Duration(milliseconds:300));
      await tester.tap(find.byTooltip('Opciones de receta'));await tester.pump();await tester.pump(const Duration(milliseconds:300));
      await tester.tap(find.text('Ver fuente original'));await tester.pump();await tester.pump(const Duration(milliseconds:300));await tester.pump();expect(opened.single,startsWith('https://en.wikibooks.org/wiki/Cookbook'));
      page.complete(http.Response(jsonEncode({'parse':{'title':'Cookbook:Bread','revid':17,'images':['Bread.jpg'],
        'text':'<h2>Ingredients</h2><ul><li>2 eggs</li></ul><h2>Preparation</h2><p>Mix.</p>'}}),200));
      await tester.pump(const Duration(milliseconds:40));await tester.runAsync(()=>Future<void>.delayed(const Duration(milliseconds:30)));await tester.pump();
      expect(sent,isNotNull);expect(find.textContaining('Traduciendo al español'),findsOneWidget);
      await tester.scrollUntilVisible(find.text('• 2 eggs'),100,scrollable:find.descendant(of:find.byKey(const ValueKey('recipe-preview-content')),matching:find.byType(Scrollable)).first);
      expect(find.text('• 2 eggs'),findsOneWidget);
      final button=tester.widget<FilledButton>(find.byType(FilledButton));expect(button.onPressed,isNull);
      await tester.pump(const Duration(milliseconds:300));
      await tester.runAsync(()async {
        final render=imageKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
        final image=await render.toImage();final bytes=await image.toByteData(format:ui.ImageByteFormat.png);
        final folder=Directory('../output/screenshots');await folder.create(recursive:true);
        await File('${folder.path}/fast-preview-${size.width>1000?'windows':'android'}.png').writeAsBytes(bytes!.buffer.asUint8List());image.dispose();
      });
      await tester.tap(find.text('Cerrar'));await tester.pumpAndSettle();
      final raw=Map<String,dynamic>.from(sent!['recipe']);
      spanish.complete(http.Response(jsonEncode({...raw,'title':'Pan','language':'es',
        'original':{for(final k in ['title','ingredients','steps','notes','notes_language','language'])if(raw.containsKey(k))k:raw[k]},
        'translation':{'target_language':'es','revision':3}}),200));
      photos.complete(http.Response(jsonEncode({'query':{'pages':[]}}),200));
      await tester.pump(const Duration(milliseconds:50));expect(find.byType(AlertDialog),findsNothing);expect(tester.takeException(),isNull);
      await tester.pumpWidget(const SizedBox());await tester.runAsync(()=>Future<void>.delayed(const Duration(milliseconds:30)));await tester.pump(const Duration(seconds:31));store.dispose();
    });
  }
}
