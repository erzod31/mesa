import 'package:flutter_test/flutter_test.dart';
import 'package:mesa/measurements.dart';
import 'package:mesa/recipe_presentation.dart';
import 'package:mesa/translation.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('Android changed quantity retries the full sentence with amount and unit protected',() async {
    const original='An den Seiten jeweils 3 cm freilassen.';
    var calls=0;
    final result=await translateCulinaryTexts([original],'de',(texts,source)async {
      if(++calls==1)return ['Dejar 5 cm a cada lado.'];
      expect(source,'de');expect(texts.single,contains('An den Seiten jeweils'));
      expect(texts.single,contains('freilassen.'));expect(texts.single.contains('3'),false);
      final marker=RegExp(r'ZXQ[A-Z]{4}QXZ').firstMatch(texts.single)![0];
      return ['Dejar $marker a cada lado.'];
    });
    expect(calls,2);expect(result,['Dejar 3 cm a cada lado.']);
  });
  test('The German model duplicate is removed only when every original amount then matches',() async {
    var calls=0;
    final value=await translateCulinaryTexts(['An den Seiten jeweils 3 cm freilassen.'],'de',(texts,_)async {
      calls++;return ['Dejar 3 cm 3 cm a cada lado.'];
    });
    expect(value,['Dejar 3 cm a cada lado.']);expect(calls,1);
  });
  test('A missing or duplicated protected amount never reaches the recipe',() async {
    var calls=0;
    await expectLater(translateCulinaryTexts(['Leave 3 cm.'],'en',(texts,_)async {
      if(++calls==1)return ['Dejar 5 cm.'];
      final marker=RegExp(r'ZXQ[A-Z]{4}QXZ').firstMatch(texts.single)![0];
      return ['$marker $marker'];
    }),throwsException);
  });
  test('Practical culinary equivalents preserve metric values and ambiguous measures', () {
    expect(practicalMetric('1 lb butter'), '450 g butter (aprox.)');
    expect(practicalMetric('Bake at 350 F for 20 minutes'), 'Bake at 180 °C for 20 minutes (aprox.)');
    expect(practicalMetric('400 °F'), '200 °C (aprox.)');
    expect(practicalMetric('1 cup flour',language:'en'), '120 g flour (aprox.)');
    expect(practicalMetric('1/2 cup milk',language:'en'), '120 ml milk (aprox.)');
    expect(practicalMetric('1 cucharadita de sal'), '5 ml de sal (aprox.)');
    expect(practicalMetric('1–2 tbsp oil'), '15–30 ml oil (aprox.)');
    expect(practicalMetric('9 x 13 inches'), '23 × 33 cm (aprox.)');
    expect(practicalMetric('1 cup almond flour',language:'en'), '240 ml almond flour (aprox.)');
    expect(practicalMetric('250 g harina'), '250 g harina');
    expect(practicalMetric('Una pizca de sal'), 'Una pizca de sal');
    expect(practicalMetric('1 cucharada colmada de harina'), '1 cucharada colmada de harina');
    expect(culinaryNumber(''), isNull);
  });
  test('Scale original amounts before applying practical rounding; leave stored data untouched', () {
    final data=<String,dynamic>{'ingredients':['1 lb beef'],'language':'en'};
    expect(presentedIngredients(data,2), ['910 g beef (aprox.)']);
    expect(presentedIngredients(data,2,originalMeasures:true), ['2 lb beef']);
    expect(data['ingredients'], ['1 lb beef']);
  });
  test('Translation protects numbers, fractions, provenance and original text', () async {
    final data=<String,dynamic>{'title':'Cake','ingredients':['1/2 cup flour','2 eggs'],
      'steps':['Bake at 350 F for 20 minutes.'],'notes':'','language':'en','photos':[{'url':'https://based.cooking/pix/cake.webp'}]};
    final value=await translateRecipeLocally(data,(texts,source) async {
      expect(source,'en');
      expect(texts.any((t)=>t.contains('350')), true);
      return texts.map((t)=>t.replaceAll('Cake','Pastel').replaceAll('flour','harina').replaceAll('eggs','huevos').replaceAll('Bake at','Hornear a').replaceAll('for','durante').replaceAll('minutes','minutos')).toList();
    });
    expect(value['ingredients'],['1/2 taza de harina','2 huevos']);
    expect(value['original']['ingredients'],data['ingredients']);
    expect(value['photos'],data['photos']);
    expect(data.containsKey('original'),false);
    expect(await translateRecipeLocally(value,(_,_) async=>throw StateError('must not translate twice')),same(value));
  });
  test('Reject incomplete translation and invented numbers', () async {
    final data=<String,dynamic>{'title':'Cake','ingredients':['2 eggs'],'steps':['Mix.'],'notes':'','language':'en'};
    await expectLater(translateRecipeLocally(data,(_,_) async=>[]),throwsException);
    await expectLater(translateRecipeLocally(data,(texts,_) async=>texts.map((t)=>'$t 10').toList()),throwsException);
    expect(data['ingredients'],['2 eggs']);
  });
  test('Decimal and fraction formats are restored but changed quantities fail', () {
    expect(restoreRecipeNumbers('1.5 cups','1,5 tazas'),'1.5 tazas');
    expect(restoreRecipeNumbers('1/2 cup','½ taza'),'1/2 taza');
    expect(()=>restoreRecipeNumbers('350 F','180 C'),throwsException);
  });
  test('Culinary glossary protects techniques, teaspoon sizes and recipe titles', () async {
    final value=await translateCulinaryTexts(['Pain','1/2 cuillère à café de sel','Faites revenir les oignons puis laissez mijoter pendant 20 minutes.'],'fr',(texts,_)async=>texts.map((t)=>t.replaceAll('sel','sal').replaceAll('puis','y luego').replaceAll('pendant','durante').replaceAll('minutes','minutos')).toList());
    expect(value,['Pan','1/2 cucharadita de sal','Rehoga las cebollas y luego deja cocer a fuego lento durante 20 minutos.']);
  });
  test('Long instructions and paragraph spacing survive native chunking', () async {
    final text='${List.filled(120,'Mix the ingredients for 20 minutes. ').join()}\n\nServe.';
    final value=await translateCulinaryTexts([text,''],'en',(texts,_)async {
      expect(texts.every((t)=>t.length<=1800),true);return texts;
    });
    expect(value,[text,'']);
  });
  test('Retranslate from originals including original foreign notes', () async {
    final value=<String,dynamic>{'title':'Dolor','ingredients':['2 huevos'],'steps':['Mezclar.'],'notes':'Nota antigua','notes_language':'es','language':'es',
      'original':{'title':'Bread','ingredients':['2 eggs'],'steps':['Mix.'],'notes':'Family recipe.','language':'en'},'translation':{'target_language':'es'}};
    final translated=await translateRecipeLocally(value,(texts,source)async {
      expect(source,'en');expect(texts.first,'Bread');expect(texts.last,'Family recipe.');
      return texts.map((t)=>t.replaceAll('Bread','Pan').replaceAll('eggs','huevos').replaceAll('Mix','Mezcla')).toList();
    },force:true);
    expect(translated['title'],'Pan');expect(translated['original'],value['original']);
    expect(value['title'],'Dolor');expect(canTranslateRecipe(value),true);
  });
  test('Generated Spanish adapter notes are never translated as foreign text', () async {
    const note='Rendimiento no declarado: se conserva la receta como base 1.';
    final data=<String,dynamic>{'title':'Bread','ingredients':['2 eggs'],'steps':['Mix.'],'notes':note,'language':'en','origin':{'provider':'wiki-en'}};
    final result=await translateRecipeLocally(data,(texts,_)async {expect(texts.contains(note),false);return texts;});
    expect(result['notes'],note);expect(result['original']['notes_language'],'es');
  });
}
