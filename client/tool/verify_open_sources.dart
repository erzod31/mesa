import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:mesa/catalogs.dart';
import 'package:mesa/models.dart';

Future<void> main(List<String> args) async {
  final client=http.Client();final api=CatalogApi(client);final rows=<Map<String,dynamic>>[];
  try {
    for(final entry in {
      'open-based':'https://based.cooking/casio-in-pastelletto/',
      'wiki-en':'Cookbook:1-2-3-4 Cake',
      'wiki-fr':'Livre de cuisine/Aligot',
      'wiki-it':"Libro di cucina/Ricette/Bigoli con l'anatra",
      'wiki-pt':'Livro de receitas/Ambotic',
      'wiki-de':'Kochbuch/ Apfelstrudel',
    }.entries) {
      if(args.isNotEmpty && !args.contains(entry.key))continue;
      final row=<String,dynamic>{'id':entry.key};
      try {
        final recipe=await api.detail(CatalogItem(id:entry.value,title:'Receta',provider:entry.key));
        validateEntryData('recipe',recipe);
        row.addAll({'ok':true,'title':recipe['title'],'ingredients':(recipe['ingredients'] as List).length,
          'steps':(recipe['steps'] as List).length,'photos':(recipe['photos'] as List).where((p)=>'${p['url']??''}'.isNotEmpty).length,
          'license':recipe['origin']['license'],'language':recipe['language'],'url':recipe['source']});
      } catch(error) {row.addAll({'ok':false,'error':'$error'});}
      rows.add(row);stdout.writeln(jsonEncode(row));
      await Future<void>.delayed(const Duration(seconds:2));
    }
    final destination=File('../output/open-sources-client-live.json');
    final previous=args.isNotEmpty && destination.existsSync() ? (jsonDecode(destination.readAsStringSync()) as List).where((r)=>!args.contains(r['id'])).toList() : <dynamic>[];
    destination.writeAsStringSync(const JsonEncoder.withIndent('  ').convert([...previous,...rows]));
    if(rows.any((r)=>r['ok']!=true))exitCode=1;
  } finally {client.close();}
}
