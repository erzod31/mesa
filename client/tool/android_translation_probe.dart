// Dedicated emulator entrypoint, never included in the production APK.
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:drift/native.dart';
import 'package:http/http.dart' as http;
import 'package:mesa/translation.dart';
import 'package:mesa/pages.dart';
import 'package:mesa/store.dart';
import 'package:mesa/timers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MaterialApp(home:Scaffold(body:Center(child:Text('Comprobando traducción nativa…')))));
  final response=await http.get(Uri.parse('http://10.0.2.2:8777/recipes.json'));
  final samples=jsonDecode(response.body) as List;
  final results=<Map<String,dynamic>>[];
  for(final sample in samples) {
    final raw=Map<String,dynamic>.from(sample['original']);
    final started=DateTime.now();
    try {
      final translated=await translateRecipeLocally(raw,(texts,source)async {
        final values=await androidRecipeTranslation(texts,source);
        for(var i=0;i<texts.length;i++) {
          try{restoreRecipeNumbers(texts[i],values[i]);}
          catch(_){debugPrint('MESA_NATIVE_QUANTITY: ${jsonEncode({'language':source,'input':texts[i],'output':values[i]})}');}
        }
        return values;
      });
      validateSpanishTranslation(raw,translated);
      results.add({'language':sample['language'],'success':true,'title':translated['title'],
        'ingredients':(translated['ingredients'] as List).length,'steps':(translated['steps'] as List).length,
        'seconds':DateTime.now().difference(started).inMilliseconds/1000});
    }catch(error){results.add({'language':sample['language'],'success':false,'error':'$error'});}
    debugPrint('MESA_NATIVE_RECIPE: ${jsonEncode(results.last)}');
  }
  final store=Cookbook(LocalDb(NativeDatabase.memory()));await store.load(readSecrets:false);
  final raw=Map<String,dynamic>.from(samples.first['original']);
  await store.save('recipe',raw,id:'native-saved');store.role='reader';
  final queue=store.pending;
  final timers=KitchenTimers(store);
  runApp(MaterialApp(home:Scaffold(body:RecipeView(store:store,timers:timers,id:'native-saved',onEdit:(){}))));
  final expected=results.first['title'];FilledButton? cook;
  var visible=false;
  for(var attempt=0;attempt<60&&!visible;attempt++) {
    await Future<void>.delayed(const Duration(milliseconds:500));
    void inspect(Element element) {
      final widget=element.widget;
      if(widget is Text&&widget.data==expected)visible=true;
      if(widget is Text&&widget.data=='Cocinar') {
        element.visitAncestorElements((ancestor){if(ancestor.widget is FilledButton){cook=ancestor.widget as FilledButton;return false;}return true;});
      }
      element.visitChildren(inspect);
    }
    WidgetsBinding.instance.rootElement?.visitChildren(inspect);
  }
  cook?.onPressed?.call();await Future<void>.delayed(const Duration(milliseconds:500));
  var cookingSpanish=false;
  void inspectCooking(Element element) {
    if(element.widget is CookingPage)cookingSpanish=(element.widget as CookingPage).recipe.title==expected;
    element.visitChildren(inspectCooking);
  }
  WidgetsBinding.instance.rootElement?.visitChildren(inspectCooking);
  results.add({'native_ui_translation':visible,'cooking_uses_translation':cookingSpanish,
    'saved_original_preserved':store.get('native-saved')!.title==raw['title'],'queue_unchanged':store.pending==queue});
  final file=File('/data/user/0/com.mesa.mesa/files/translation-probe.json');
  await file.parent.create(recursive:true);await file.writeAsString(jsonEncode(results));
  debugPrint('MESA_NATIVE_PROBE_DONE: ${jsonEncode(results)}');
  runApp(MaterialApp(home:Scaffold(body:Text(jsonEncode(results)))));
}
