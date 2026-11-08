import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mesa/recipe_presentation.dart';

void main() {
  testWidgets('A bad existing translation can be reviewed; discard preserves it and apply is explicit',(tester)async {
    final old=<String,dynamic>{'title':'Dolor','language':'es','ingredients':['2 huevos'],'steps':['Mezclar.'],
      'original':{'title':'Pain','language':'fr','ingredients':['2 œufs'],'steps':['Mélanger.']}};
    final fixed=<String,dynamic>{...old,'title':'Pan'};
    var applied=0;
    var pending=Completer<Map<String,dynamic>>();
    await tester.pumpWidget(MaterialApp(home:Scaffold(body:RecipeTranslationAction(data:old,translate:()=>pending.future,apply:(value)async{applied++;expect(value['title'],'Pan');}))));
    expect(find.text('Volver a traducir'),findsOneWidget);
    await tester.tap(find.text('Volver a traducir'));await tester.pump();
    expect(find.text('Traduciendo…'),findsOneWidget);
    pending.complete(fixed);await tester.pumpAndSettle();
    expect(find.text('Revisar traducción'),findsOneWidget);
    await tester.tap(find.text('Descartar'));await tester.pumpAndSettle();
    expect(applied,0);expect(old['title'],'Dolor');
    pending=Completer<Map<String,dynamic>>();
    await tester.tap(find.text('Volver a traducir'));await tester.pump();
    pending.complete(fixed);await tester.pumpAndSettle();
    await tester.tap(find.text('Aplicar traducción'));await tester.pumpAndSettle();
    expect(applied,1);expect(old['title'],'Dolor');
  });
}
