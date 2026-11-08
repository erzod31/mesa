import socket
import pytest
from server.fetcher import public_target, fetch_page, fetch_image, LIMIT

@pytest.mark.parametrize('url',['http://127.0.0.1','http://169.254.169.254','http://100.80.1.1','http://10.0.0.1','http://[::1]','file:///etc/passwd','https://user:pass@example.com','https://example.com:8765'])
def test_private_and_nonweb_urls_are_rejected(url):
    with pytest.raises((ValueError, OSError)):
        public_target(url)

def test_all_dns_answers_must_be_public(monkeypatch):
    monkeypatch.setattr(socket,'getaddrinfo',lambda *a,**kw:[(socket.AF_INET,socket.SOCK_STREAM,6,'',('93.184.216.34',443)),(socket.AF_INET,socket.SOCK_STREAM,6,'',('127.0.0.1',443))])
    with pytest.raises(ValueError):public_target('https://example.com')

def test_resolved_public_address_is_pinned(monkeypatch):
    monkeypatch.setattr(socket,'getaddrinfo',lambda *a,**kw:[(socket.AF_INET,socket.SOCK_STREAM,6,'',('93.184.216.34',80))])
    calls=[]
    class Response:
        status=200
        def getheader(self,name,default=None):return 'text/html' if name=='Content-Type' else default
        def read(self,n):return b'<html>recipe</html>'
    class Connection:
        def __init__(self,*a,**kw):pass
        def request(self,*a,**kw):pass
        def getresponse(self):return Response()
        def close(self):pass
    monkeypatch.setattr(socket,'create_connection',lambda target,**kw:calls.append(target))
    monkeypatch.setattr('server.fetcher.http.client.HTTPConnection',Connection)
    assert fetch_page('http://example.com/recipe')[0]=='<html>recipe</html>'
    assert calls==[('93.184.216.34',80)]

def test_redirect_into_private_network_is_rejected(monkeypatch):
    monkeypatch.setattr(socket,'getaddrinfo',lambda host,*a,**kw:[(socket.AF_INET,socket.SOCK_STREAM,6,'',('127.0.0.1' if host=='localhost' else '93.184.216.34',80))])
    class Response:
        status=302
        def getheader(self,*a):return 'http://localhost/secret'
    class Connection:
        def __init__(self,*a,**kw):pass
        def request(self,*a,**kw):pass
        def getresponse(self):return Response()
        def close(self):pass
    monkeypatch.setattr(socket,'create_connection',lambda *a,**kw:None)
    monkeypatch.setattr('server.fetcher.http.client.HTTPConnection',Connection)
    with pytest.raises(ValueError):fetch_page('http://example.com')


def test_binary_image_fetch_pins_dns_and_rejects_wrong_mime(monkeypatch):
    monkeypatch.setattr(socket, 'getaddrinfo', lambda *a, **kw: [(socket.AF_INET, socket.SOCK_STREAM, 6, '', ('93.184.216.34', 80))])
    calls = []
    media = ['image/jpeg']
    class Response:
        status = 200
        delivered = False
        def getheader(self, name, default=None): return media[0] if name == 'Content-Type' else default
        def read1(self, n):
            if self.delivered: return b''
            self.delivered = True
            return b'\xff\xd8\xffimage'
    class Socket:
        def settimeout(self, value): assert 0 < value <= 8
    class Connection:
        def __init__(self, *a, **kw): pass
        def request(self, method, path, headers):
            assert 'Authorization' not in headers
            assert headers['Accept'] == 'image/*'
        def getresponse(self): return Response()
        def close(self): pass
    def connect(target, **kw):
        calls.append(target)
        return Socket()
    monkeypatch.setattr(socket, 'create_connection', connect)
    monkeypatch.setattr('server.fetcher.http.client.HTTPConnection', Connection)
    assert fetch_image('http://example.com/photo.jpg')[0] == b'\xff\xd8\xffimage'
    assert calls == [('93.184.216.34', 80)]
    media[0] = 'text/html'
    with pytest.raises(ValueError): fetch_image('http://example.com/photo.jpg')
