"""Limited public-page fetcher: pin validated DNS answers, recheck every redirect."""
import http.client
import ipaddress
import socket
import ssl
import time
import zlib
from urllib.parse import urlsplit, urljoin

LIMIT = 4_000_000


def public_target(url):
    target = urlsplit(url)
    if target.scheme not in ('http', 'https') or not target.hostname or target.username or target.password:
        raise ValueError('Usa un enlace público HTTP o HTTPS sin credenciales.')
    port = target.port or (443 if target.scheme == 'https' else 80)
    if port != (443 if target.scheme == 'https' else 80):
        raise ValueError('Solo se admiten puertos web estándar.')
    hostname = target.hostname.encode('idna').decode('ascii')
    addresses = socket.getaddrinfo(hostname, port, type=socket.SOCK_STREAM)
    if not addresses or any(not ipaddress.ip_address(item[4][0]).is_global for item in addresses):
        raise ValueError('No se pueden importar direcciones privadas, locales o de Tailscale.')
    return target, hostname, port, addresses[0][4][0]


def _fetch_public(url, *, image=False, document=False, post_data=None):
    deadline = time.monotonic() + (45 if document else 12 if image else 25)
    for _ in range(4):
        if deadline is not None and time.monotonic() >= deadline:
            raise TimeoutError('Tiempo de descarga de la foto agotado.')
        target, hostname, port, address = public_target(url)
        timeout = min(8, max(.1, deadline - time.monotonic())) if deadline is not None else 8
        connection = http.client.HTTPConnection(hostname, port, timeout=timeout)
        # Connect to the address that was checked; TLS still verifies the original host.
        connection.sock = socket.create_connection((address, port), timeout=timeout)
        try:
            if target.scheme == 'https':
                context = ssl.create_default_context()
                context.set_alpn_protocols(['http/1.1'])
                # Match Python's standard HTTPSConnection negotiation while keeping DNS pinned.
                context.post_handshake_auth = True
                connection.sock = context.wrap_socket(connection.sock, server_hostname=hostname)
            path = target.path or '/'
            if target.query:
                path += '?' + target.query
            headers = {'Host': hostname, 'User-Agent': 'Mesa-Source-Research/1.0 (public read-only sample audit)', 'Accept': 'application/pdf' if document else 'image/*' if image else 'text/html,application/json', 'Accept-Encoding': 'identity'}
            if post_data is not None:
                headers['Content-Type'] = 'application/x-www-form-urlencoded'
            connection.request('POST' if post_data is not None else 'GET', path, body=post_data, headers=headers) if post_data is not None else connection.request('GET', path, headers=headers)
            response = connection.getresponse()
            if response.status in (301, 302, 303, 307, 308):
                location = response.getheader('Location')
                if not location:
                    raise ValueError('El enlace redirige sin indicar un destino.')
                url = urljoin(url, location)
                continue
            if response.status != 200:
                raise ValueError(f'La fuente no permitió la consulta automática (HTTP {response.status}). Abre el sitio original.')
            media = response.getheader('Content-Type', '').lower()
            compatible = media.startswith('application/pdf') if document else media.startswith('image/') if image else (media.startswith('text/') or any(kind in media for kind in ('application/json', 'application/ld+json')))
            if not compatible:
                raise ValueError('El enlace no contiene una página o receta compatible.')
            encoding = response.getheader('Content-Encoding', 'identity').lower()
            if encoding not in ('identity','gzip','deflate'):
                raise ValueError('La página usa una compresión no admitida. Abre el original.')
            limit = 30_000_000 if document else 10_000_000 if image else LIMIT
            if image or hasattr(response, 'read1'):
                body = bytearray()
                while len(body) <= limit:
                    remaining = deadline - time.monotonic()
                    if remaining <= 0:
                        raise TimeoutError('Tiempo de descarga agotado.')
                    if connection.sock is not None:
                        connection.sock.settimeout(min(8, remaining))
                    part = response.read1(min(65536, limit + 1 - len(body)))
                    if not part:
                        break
                    body.extend(part)
            else:
                body = response.read(limit + 1)
            if len(body) > limit:
                raise ValueError('La página es demasiado grande para importarla automáticamente.')
            if encoding != 'identity':
                decoder = zlib.decompressobj(16+zlib.MAX_WBITS if encoding == 'gzip' else zlib.MAX_WBITS)
                try:
                    body = decoder.decompress(bytes(body), limit+1)
                except zlib.error as exc:
                    raise ValueError('La respuesta comprimida no es válida.') from exc
                if len(body) > limit or decoder.unconsumed_tail or not decoder.eof:
                    raise ValueError('La página descomprimida supera el límite de importación.')
            return bytes(body), url
        finally:
            connection.close()
    raise ValueError('El enlace redirige demasiadas veces.')


def fetch_page(url):
    body, final = _fetch_public(url)
    return body.decode('utf-8', errors='replace'), final


def fetch_image(url):
    return _fetch_public(url, image=True)


def fetch_document(url):
    body, final = _fetch_public(url, document=True)
    if not body.startswith(b'%PDF'):
        raise ValueError('El documento no contiene un PDF válido.')
    return body, final
