import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:mesa/recipe_opening.dart';
import 'package:mesa/translation.dart';

Map<String,dynamic> sourceRecipe()=>{'title':'Bread','language':'en','ingredients':['2 eggs'],'steps':['Mix.'],'notes':'',
  'servings':2,'tags':<String>[],'origin':{'provider':'wiki-en','url':'https://en.wikibooks.org/wiki/Cookbook:Bread'},
  'photos':[{'url':'https://upload.wikimedia.org/wikipedia/commons/Bread.jpg','license':'CC BY-SA 4.0'}]};
Map<String,dynamic> translated(Map<String,dynamic> raw)=>{...raw,'language':'es','title':'Pan','ingredients':['2 huevos'],'steps':['Mezclar.'],
  'original':{for(final k in ['title','ingredients','steps','notes','language'])k:raw[k]},'translation':{'target_language':'es','revision':translationRevision}};

void main() {
  test('A previously cached foreign import labelled Spanish is translated without a source wait',() async {
    final raw={...sourceRecipe(),'language':'es','origin':{'provider':'open-based','url':'https://based.cooking/bread/'}};
    final opening=RecipeOpening(cached:raw,loadDetail:(_)=>throw StateError('must use cache'),
      translate:(value,{bool force=false})async {expect(value['language'],'en');return translated(value);},remember:(_)async{});
    await opening.start();await Future<void>.delayed(Duration.zero);
    expect(opening.data!['title'],'Pan');expect(opening.data!['ingredients'],['2 huevos']);opening.dispose();
  });
  test('Spanish generated notes metadata does not discard the finished translation when photos arrive',() async {
    final full=Completer<Map<String,dynamic>>();
    final raw={...sourceRecipe(),'notes':'Comprueba el rendimiento y el tiempo en la fuente.'};
    final saves=<Map<String,dynamic>>[];
    final opening=RecipeOpening(loadDetail:(onText){onText({...raw,'photos':[]});return full.future;},
      translate:(value,{bool force=false})async {
        final result=translated(value);result['original']['notes_language']='es';return result;
      },remember:(value)async{saves.add(value);});
    final ready=opening.start();await Future<void>.delayed(Duration.zero);
    expect(opening.data!['title'],'Pan');
    full.complete(raw);await ready;
    expect(opening.data!['title'],'Pan');expect(opening.data!['ingredients'],['2 huevos']);
    expect(opening.data!['photos'],raw['photos']);expect(saves.last['title'],'Pan');opening.dispose();
  });
  test('A failed translation can be retried without downloading the source again',() async {
    var attempts=0,downloads=0;
    final opening=RecipeOpening(loadDetail:(_)async{downloads++;return sourceRecipe();},
      translate:(value,{bool force=false})async {if(++attempts==1)throw Exception('Sin conexión');return translated(value);},remember:(_)async{});
    await opening.start();await Future<void>.delayed(Duration.zero);expect(opening.translationFailure,isNotNull);
    opening.retryTranslation();await Future<void>.delayed(Duration.zero);
    expect(opening.data!['title'],'Pan');expect(opening.translationFailure,isNull);expect(downloads,1);expect(attempts,2);opening.dispose();
  });
  test('An unchanged foreign response is a visible failure, not a completed translation',() async {
    final opening=RecipeOpening(loadDetail:(_)async=>sourceRecipe(),translate:(value,{bool force=false})async=>value,remember:(_)async{});
    await opening.start();await Future<void>.delayed(Duration.zero);
    expect(opening.data!['title'],'Bread');expect(opening.translationFailure,contains('No se recibió'));expect(opening.translating,false);opening.dispose();
  });
  test('Text appears before photo metadata and translation starts in parallel; photos never get overwritten',() async {
    final full=Completer<Map<String,dynamic>>(),spanish=Completer<Map<String,dynamic>>();
    final saves=<Map<String,dynamic>>[];var calls=0;
    final raw=sourceRecipe(),early={...sourceRecipe(),'photos':<Map<String,dynamic>>[]};
    final opening=RecipeOpening(loadDetail:(onText){onText(early);return full.future;},translate:(value,{bool force=false}) {calls++;return spanish.future;},remember:(value)async {saves.add(value);});
    final ready=opening.start();
    expect(opening.data!['ingredients'],['2 eggs']);expect(opening.complete,false);expect(opening.translating,true);expect(calls,1);expect(saves,isEmpty);
    full.complete(raw);await ready;
    expect(opening.complete,true);expect(opening.translating,true);expect(opening.data!['photos'],raw['photos']);
    spanish.complete(translated(early));await Future<void>.delayed(Duration.zero);
    expect(opening.data!['title'],'Pan');expect(opening.data!['photos'],raw['photos']);expect(calls,1);
    expect(saves.last['photos'],raw['photos']);opening.dispose();
  });
  test('Translation can finish before photo metadata without losing the gallery',() async {
    final full=Completer<Map<String,dynamic>>();final raw=sourceRecipe(),early={...sourceRecipe(),'photos':<Map<String,dynamic>>[]};
    final opening=RecipeOpening(loadDetail:(onText){onText(early);return full.future;},translate:(value,{bool force=false})async=>translated(value),remember:(_)async{});
    final ready=opening.start();await Future<void>.delayed(Duration.zero);expect(opening.data!['title'],'Pan');expect(opening.complete,false);
    full.complete(raw);await ready;expect(opening.data!['title'],'Pan');expect(opening.data!['photos'],raw['photos']);opening.dispose();
  });
  test('A cached current translation opens without network or model waiting',() async {
    final opening=RecipeOpening(cached:translated(sourceRecipe()),loadDetail:(_)=>throw StateError('must not request source'),translate:(_,{bool force=false})=>throw StateError('must not translate'),remember:(_)async{});
    expect(opening.data!['title'],'Pan');await opening.start();expect(opening.complete,true);expect(opening.fromCache,true);expect(opening.translating,false);opening.dispose();
  });
  test('Closing a preview prevents later notifications and database writes',() async {
    final full=Completer<Map<String,dynamic>>();var saves=0;
    final opening=RecipeOpening(loadDetail:(_)=>full.future,translate:(_,{bool force=false})async=>{},remember:(_)async{saves++;});
    final ready=opening.start();opening.dispose();full.complete(sourceRecipe());await ready;expect(saves,0);
  });
  test('Failed metadata leaves readable original text but cannot save an incomplete gallery',() async {
    final opening=RecipeOpening(loadDetail:(onText)async{onText({...sourceRecipe(),'photos':[]});throw Exception('Fotos no disponibles');},translate:(v,{bool force=false})async=>translated(v),remember:(_)=>throw StateError('must not save'));
    await opening.start();await Future<void>.delayed(Duration.zero);expect(opening.data,isNotNull);expect(opening.complete,false);expect(opening.failure,contains('Fotos no disponibles'));opening.dispose();
  });
  test('Translation failure keeps complete quantities, gallery and manual retry available',() async {
    final raw=sourceRecipe();final opening=RecipeOpening(loadDetail:(_)async=>raw,translate:(_,{bool force=false})async=>throw Exception('Traductor desconectado'),remember:(_)async{});
    await opening.start();await Future<void>.delayed(Duration.zero);expect(opening.data!['ingredients'],raw['ingredients']);expect(opening.data!['photos'],raw['photos']);expect(opening.translationFailure,isNotNull);expect(opening.complete,true);opening.dispose();
  });
}
