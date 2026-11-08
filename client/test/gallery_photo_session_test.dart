import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mesa/photos.dart';
import 'photos_test.dart' show photoBytes;

void main() {
  test('Visible cover and thumbnail share one download; last release removes it',() async {
    var calls=0;
    final session=GalleryPhotoSession(clientFactory:()=>MockClient((request)async {
      calls++;expect(request.headers.containsKey('authorization'),false);expect(request.headers['cache-control'],'no-cache, no-store');
      return http.Response.bytes(photoBytes(),200);
    }));
    final main=session.acquire('https://example.org/pan.jpg'),thumb=session.acquire('https://example.org/pan.jpg',priority:false);
    expect(identical(main.bytes,thumb.bytes),true);await Future.wait([main.bytes,thumb.bytes]);expect(calls,1);
    main.release();final stillVisible=session.acquire('https://example.org/pan.jpg');await stillVisible.bytes;expect(calls,1);
    thumb.release();stillVisible.release();
    final reopened=session.acquire('https://example.org/pan.jpg');await reopened.bytes;expect(calls,2);
    reopened.release();session.dispose();
  });
  test('A failed photo can retry without an old thumbnail releasing the new request',() async {
    var calls=0;
    final session=GalleryPhotoSession(clientFactory:()=>MockClient((request)async {calls++;return calls==1?http.Response('',503):http.Response.bytes(photoBytes(),200);}));
    final main=session.acquire('https://example.org/pan.jpg'),oldThumb=session.acquire('https://example.org/pan.jpg',priority:false);
    await Future.wait([main.bytes.catchError((_)=>Uint8List(0)),oldThumb.bytes.catchError((_)=>Uint8List(0))]);
    main.release();final retry=session.acquire('https://example.org/pan.jpg');oldThumb.release();
    expect(await retry.bytes,isNotEmpty);expect(calls,2);retry.release();session.dispose();
  });
  test('At most three downloads run; a queued main photo takes priority over thumbnails',() async {
    final gates=<String,Completer<http.Response>>{};final order=<String>[];
    final session=GalleryPhotoSession(clientFactory:()=>MockClient((request)async {
      final id=request.url.path;order.add(id);final gate=Completer<http.Response>();gates[id]=gate;return gate.future;
    }));
    final leases=[for(var i=0;i<4;i++)session.acquire('https://example.org/$i.jpg',priority:false)];
    leases.add(session.acquire('https://example.org/main.jpg'));
    final all=Future.wait(leases.map((p)=>p.bytes));await Future<void>.delayed(Duration.zero);
    expect(order,['/0.jpg','/1.jpg','/2.jpg']);
    gates['/0.jpg']!.complete(http.Response.bytes(photoBytes(),200));await leases[0].bytes;await Future<void>.delayed(Duration.zero);
    expect(order.last,'/main.jpg');
    gates['/1.jpg']!.complete(http.Response.bytes(photoBytes(),200));await leases[1].bytes;await Future<void>.delayed(Duration.zero);
    for(final id in ['/2.jpg','/main.jpg','/3.jpg']){gates[id]!.complete(http.Response.bytes(photoBytes(),200));}
    await all;for(final lease in leases){lease.release();}session.dispose();
  });
}
