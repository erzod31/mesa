import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mesa/catalogs.dart';

void main() {
  test('Wikibooks emits complete text before photo licensing finishes and coalesces duplicate reads',() async {
    final images=Completer<http.Response>();var parses=0;final early=<Map<String,dynamic>>[];
    final api=CatalogApi(MockClient((request)async {
      if(request.url.queryParameters['action']=='parse') {
        parses++;return http.Response(jsonEncode({'parse':{'title':'Cookbook:Bread','revid':17,'images':['Bread.jpg'],
          'text':'<h2>Ingredients</h2><ul><li>2 eggs</li></ul><h2>Preparation</h2><p>Mix.</p>'}}),200);
      }
      return images.future;
    }));
    const item=CatalogItem(id:'Cookbook:Bread',title:'Bread',provider:'wiki-en');
    final a=api.detail(item,onTextReady:early.add);await Future<void>.delayed(Duration.zero);
    expect(early.single['ingredients'],['2 eggs']);expect(early.single['photos'],isEmpty);
    final b=api.detail(item,onTextReady:early.add);expect(early,hasLength(2));expect(parses,1);
    images.complete(http.Response(jsonEncode({'query':{'pages':[{'title':'File:Bread.jpg','imageinfo':[{
      'url':'https://upload.wikimedia.org/wikipedia/commons/Bread.jpg','extmetadata':{'LicenseShortName':{'value':'CC BY-SA 4.0'},'LicenseUrl':{'value':'https://creativecommons.org/licenses/by-sa/4.0/'}}}]}]}}),200));
    final results=await Future.wait([a,b]);expect(results.every((r)=>(r['photos'] as List).length==1),true);
    expect(early.first['photos'],isEmpty);
  });
}
