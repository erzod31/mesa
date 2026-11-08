import 'dart:convert';
import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mesa/catalogs.dart';
import 'package:mesa/store.dart';
import 'store_test.dart' show recipe;

http.Response jsonResult(dynamic value)=>http.Response(jsonEncode(value),200,headers:{'content-type':'application/json'});
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('Portuguese cooking headings and French galleries preserve recipe structure', () {
    final en = parseWiki('wiki-en', jsonDecode(File('test/fixtures/wiki-en-cake.json').readAsStringSync()));
    expect(en['steps'].length,greaterThanOrEqualTo(15));
    final pt = parseWiki('wiki-pt', jsonDecode(File('test/fixtures/wiki-pt-ambotic.json').readAsStringSync()));
    expect(pt['ingredients'],hasLength(13));expect(pt['steps'],hasLength(1));
    final fr = parseWiki('wiki-fr', jsonDecode(File('test/fixtures/wiki-fr-aligot.json').readAsStringSync()));
    expect(fr['ingredients'],hasLength(6));expect(fr['steps'],hasLength(5));expect(fr['servings'],6);
    expect(fr['ingredients'].any((s)=>'$s'.contains('Fromages utilisables')),false);
  });
  test('Based Cooking uses text and tree metadata without requesting images',() async {
    final calls=<Uri>[];
    final api=CatalogApi(MockClient((request) async {
      calls.add(request.url);
      expect(request.headers.containsKey('authorization'),false);
      if(request.url.host=='api.github.com')return jsonResult({'truncated':false,'tree':[{'path':'static/pix/bread.webp'}]});
      expect(request.url.toString(),'https://based.cooking/');
      return http.Response('<a href="https://based.cooking/bread/">Bread</a><a href="https://based.cooking/soup/">Soup</a>',200);
    }));
    final result=await api.search('open-based');
    expect(result.items.single.title,'Bread');
    expect(result.items.single.image,'https://based.cooking/pix/bread.webp');
    expect(calls.length,2);
  });
  test('An interrupted snapshot preserves local data until the entire download is complete',() async {
    bool interrupted=true;
    final store=Cookbook(LocalDb(NativeDatabase.memory()),client:MockClient((request) async {
      if(request.url.path=='/v1/snapshot') {
        if(request.url.queryParameters['after']==null)return jsonResult({'generation':'new','cursor':2,'entities':[{'id':'a','kind':'recipe','revision':1,'deleted':false,'data':recipe('Servidor A')}],'next':'a'});
        if(interrupted)throw http.ClientException('Second page disconnected');
        expect(request.url.queryParameters['start_cursor'],'2');
        return jsonResult({'generation':'new','cursor':2,'entities':[{'id':'b','kind':'recipe','revision':1,'deleted':false,'data':recipe('Servidor B')}],'next':null});
      }
      if(request.url.path=='/v1/changes')return jsonResult({'generation':'new','cursor':2,'entities':[],'more':false});
      throw StateError('Unexpected request');
    }));
    await store.load(readSecrets:false);
    await store.db.customStatement('INSERT INTO entities VALUES (?,?,?,?,?)',['old','recipe',1,jsonEncode(recipe('Local guardada')),0]);
    await store.load(readSecrets:false);
    await store.preference('url','http://127.0.0.1:8765');store.token='fixture';
    await store.sync();
    expect(store.get('old')?.title,'Local guardada');
    expect(store.get('a'),isNull);
    expect(store.generation,isEmpty);
    interrupted=false;await store.sync();
    expect(store.of('recipe').map((e)=>e.title).toSet(),{'Servidor A','Servidor B'});
    expect(store.generation,'new');
    store.dispose();await store.db.close();
  });
}
