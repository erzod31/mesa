import 'dart:async';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mesa/pages.dart';
import 'package:mesa/store.dart';
import 'package:mesa/timers.dart';

Map<String,dynamic> foreignRecipe()=>{'title':'Bread','language':'en','ingredients':['2 eggs'],'steps':['Mix.'],
  'servings':2,'minutes':0,'notes':'','tags':<String>[]};

void main() {
  testWidgets('Android starts its local translator after a PC stalls, and ignores a late PC answer',(tester)async {
    debugDefaultTargetPlatformOverride=TargetPlatform.android;
    addTearDown(()=>debugDefaultTargetPlatformOverride=null);
    final pc=Completer<http.Response>();var nativeCalls=0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('mesa/native'),(call)async {
      nativeCalls++;return (call.arguments['texts'] as List).map((t)=>(t as String).replaceAll('Bread','Pan').replaceAll('eggs','huevos').replaceAll('Mix','Mezclar')).toList();
    });
    addTearDown(()=>TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('mesa/native'),null));
    final store=(await tester.runAsync(()async {
      final s=Cookbook(LocalDb(NativeDatabase.memory()),client:MockClient((_)=>pc.future));
      await s.load(readSecrets:false);await s.preference('url','http://127.0.0.1:8765');s.token='test-token';return s;
    }))!;
    Map<String,dynamic>? result;
    unawaited(store.translateImportedRecipe(foreignRecipe()).then((value)=>result=value));
    await tester.pump();await tester.pump(const Duration(seconds:31));await tester.pump();
    await tester.runAsync(()=>Future<void>.delayed(const Duration(milliseconds:20)));await tester.pump();
    expect(nativeCalls,1);expect(result?['title'],'Pan');
    pc.complete(http.Response('{}',200));await tester.runAsync(()=>Future<void>.delayed(const Duration(milliseconds:20)));await tester.pump();
    expect(result?['title'],'Pan');store.dispose();debugDefaultTargetPlatformOverride=null;
  });
  for(final reader in [false,true]) {
    testWidgets('Android translates a saved recipe automatically for ${reader?'reader':'editor'} and cooking uses Spanish',(tester)async {
      debugDefaultTargetPlatformOverride=TargetPlatform.android;
      addTearDown(()=>debugDefaultTargetPlatformOverride=null);
      tester.view.physicalSize=const Size(390,844);tester.view.devicePixelRatio=1;
      addTearDown(tester.view.resetPhysicalSize);addTearDown(tester.view.resetDevicePixelRatio);
      final pending=Completer<List<String>>();List<String>? sent;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('mesa/native'),(call)async {
        if(call.method=='translateRecipeTexts'){sent=List<String>.from(call.arguments['texts']);return pending.future;}
        return null;
      });
      addTearDown(()=>TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('mesa/native'),null));
      final store=(await tester.runAsync(()async {
        final s=Cookbook(LocalDb(NativeDatabase.memory()));await s.load(readSecrets:false);
        await s.save('recipe',foreignRecipe(),id:'saved');if(reader)s.role='reader';return s;
      }))!;
      final queue=store.pending;
      final timers=KitchenTimers(store);
      await tester.pumpWidget(MaterialApp(home:Scaffold(body:RecipeView(store:store,timers:timers,id:'saved',onEdit:(){}))));
      await tester.runAsync(()=>Future<void>.delayed(const Duration(milliseconds:20)));await tester.pump();
      expect(sent,isNotNull);expect(find.text('Traduciendo al español…'),findsOneWidget);
      pending.complete(sent!.map((t)=>t.replaceAll('Bread','Pan').replaceAll('eggs','huevos').replaceAll('Mix','Mezclar')).toList());
      await tester.pumpAndSettle();
      expect(find.text('Pan'),findsOneWidget);expect(find.text('Traduciendo al español…'),findsNothing);
      expect(store.get('saved')!.title,'Bread');expect(store.pending,queue);
      await tester.tap(find.text('Paso a paso'));await tester.pumpAndSettle();
      expect(find.text('Pan'),findsOneWidget);expect(find.text('Mezclar.'),findsOneWidget);
      await tester.pumpWidget(const SizedBox());timers.dispose();store.dispose();debugDefaultTargetPlatformOverride=null;
    });
  }
  testWidgets('A local edit during translation prevents the old result replacing the saved view',(tester)async {
    debugDefaultTargetPlatformOverride=TargetPlatform.android;
    addTearDown(()=>debugDefaultTargetPlatformOverride=null);
    final pending=Completer<List<String>>();List<String>? sent;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('mesa/native'),(call)async {
      sent=List<String>.from(call.arguments['texts']);return pending.future;
    });
    addTearDown(()=>TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('mesa/native'),null));
    final store=(await tester.runAsync(()async {
      final s=Cookbook(LocalDb(NativeDatabase.memory()));await s.load(readSecrets:false);await s.save('recipe',foreignRecipe(),id:'saved');return s;
    }))!;
    final timers=KitchenTimers(store);
    await tester.pumpWidget(MaterialApp(home:Scaffold(body:RecipeView(store:store,timers:timers,id:'saved',onEdit:(){}))));
    await tester.runAsync(()=>Future<void>.delayed(const Duration(milliseconds:20)));await tester.pump();expect(sent,isNotNull);
    await tester.runAsync(()=>store.save('recipe',{...foreignRecipe(),'language':'es','title':'Mi pan editado'},id:'saved'));
    await tester.pump();pending.complete(sent!.map((t)=>t.replaceAll('Bread','Pan').replaceAll('eggs','huevos').replaceAll('Mix','Mezclar')).toList());
    await tester.pumpAndSettle();expect(find.text('Mi pan editado'),findsOneWidget);expect(find.text('Pan'),findsNothing);
    await tester.pumpWidget(const SizedBox());timers.dispose();store.dispose();debugDefaultTargetPlatformOverride=null;
  });
}
