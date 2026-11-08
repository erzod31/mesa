"""Installed Mesa entry point. Owns only the services it starts; never kills others."""
from __future__ import annotations

import argparse
import asyncio
import ctypes
import hashlib
import json
import os
from pathlib import Path
import socket
import subprocess
import sys
import threading
import time
import secrets
import base64

VERSION = '1.18.2+37'


def free_port():
    with socket.socket() as listener:
        listener.bind(('127.0.0.1', 0))
        return listener.getsockname()[1]


def read_json(path):
    return json.loads(path.read_text(encoding='utf-8-sig'))


def main(argv=None):
    parser = argparse.ArgumentParser()
    parser.add_argument('--isolated-profile', type=Path)
    parser.add_argument('--self-test', action='store_true')
    parser.add_argument('--report', type=Path)
    parser.add_argument('--isolated-api-port', type=int, help='Stable loopback port for isolated restart verification only.')
    args = parser.parse_args(argv)
    if args.isolated_profile and not args.isolated_profile.is_absolute():
        parser.error('El perfil aislado necesita una ruta absoluta.')
    if args.self_test and not args.isolated_profile:
        parser.error('--self-test necesita --isolated-profile.')
    if args.isolated_api_port is not None and (not args.isolated_profile or not 1024 <= args.isolated_api_port <= 65535):
        parser.error('--isolated-api-port necesita perfil aislado y puerto 1024–65535.')
    installation = Path(sys.executable).resolve().parent if getattr(sys, 'frozen', False) else Path(__file__).resolve().parents[1]
    profile = args.isolated_profile or Path(os.environ['LOCALAPPDATA']) / 'Mesa'
    from server.server_profile import select_server_data
    data = select_server_data(profile, isolated=bool(args.isolated_profile))
    os.environ['RECETARIO_DATA'] = str(data)
    # Frozen resource paths are resolved by the original server modules, while
    # every mutable database/credential stays outside the installation directory.
    from server.app import app
    import httpx
    import uvicorn

    profile.mkdir(parents=True, exist_ok=True)
    config_path = data / 'desktop-connection.json'
    config = read_json(config_path)
    if args.self_test:
        async def check():
            async with httpx.AsyncClient(transport=httpx.ASGITransport(app=app), base_url='http://mesa.test') as client:
                client.headers['Authorization'] = 'Bearer ' + config['token']
                health = await client.get('/health')
                health.raise_for_status()
                snapshot = (await client.get('/v1/snapshot')).json()
                recipe = {'title': 'Comprobación aislada', 'ingredients': ['2 huevos'], 'steps': ['Batir.'], 'servings': 2, 'tags': []}
                response = await client.post('/v1/push', json={'generation': snapshot['generation'], 'operations': [{'id': 'installer-smoke', 'entity_id': 'installer-smoke', 'kind': 'recipe', 'base': 0, 'data': recipe}]})
                response.raise_for_status()
                saved = (await client.get('/v1/snapshot')).json()['entities']
                assert any(e['data']['title'] == recipe['title'] for e in saved)
            from server.translation import translate_texts
            translated = {language: translate_texts([text], language)[0] for language,text in
                          {'en':'Mix 2 eggs.', 'de':'2 Eier mischen.'}.items()}
            assert '2' in translated['en'] and translated['en'] != 'Mix 2 eggs.'
            assert translated['de'] == 'Mezclar 2 huevos.'
            # Exercise the packaged OCR models and native DLLs, offline, without
            # saving a photograph or touching the user's recetario.
            import io
            from PIL import Image, ImageDraw, ImageFont
            from server.ocr import recognize_image
            picture = Image.new('RGB', (1100, 330), 'white')
            draw = ImageDraw.Draw(picture)
            font = ImageFont.load_default(size=38)
            for index, line in enumerate(('Tortilla de patatas', '2 huevos y 250 g de patatas', '1. Batir los huevos.', '2. Cocinar durante 10 minutos.')):
                draw.text((30, 20+index*70), line, fill='black', font=font)
            buffer = io.BytesIO()
            picture.save(buffer, format='PNG')
            first = recognize_image(buffer.getvalue())
            second = recognize_image(buffer.getvalue())
            assert all(fragment in second['text'] for fragment in ('2 huevos', '250', 'Batir', '10 minutos'))
            return {'version': VERSION, 'health': health.json(), 'saveRead': True, 'translation': translated,
                    'ocr':{'engine':second['engine'], 'text':second['text'], 'cold_ms':first['elapsed_ms'],
                           'warm_ms':second['elapsed_ms'], 'license_url':second['license_url']},
                    'isolatedProfile': str(profile)}
        report = asyncio.run(check())
        if args.report:
            args.report.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf-8')
        return 0

    api_port = (args.isolated_api_port or free_port()) if args.isolated_profile else 8765
    download_port = free_port() if args.isolated_profile else 8768
    url = f'http://127.0.0.1:{api_port}'
    owned_server = None
    owned_downloads = None
    with httpx.Client(trust_env=False, timeout=2) as client:
        existing = False
        try:
            # A fresh QA port cannot already host Mesa. Closed loopback ports
            # may time out on Windows rather than refuse immediately.
            health = None if args.isolated_profile else client.get(url + '/health')
            existing = health is not None and health.status_code == 200 and health.json().get('product') == 'mesa'
            if existing:
                client.get(url + '/v1/snapshot?limit=1', headers={'Authorization': 'Bearer ' + config['token']}).raise_for_status()
        except (httpx.ConnectError, httpx.ConnectTimeout):
            pass
        except Exception as error:
            raise RuntimeError('El puerto de Mesa pertenece a otro servicio o perfil. No se ha cerrado ningún proceso.') from error
        if not existing:
            # Bind here so a collision is reported without touching another app.
            listener = socket.socket()
            listener.bind(('127.0.0.1', api_port))
            owned_server = uvicorn.Server(uvicorn.Config(app, host='127.0.0.1', port=api_port, log_config=None, loop='asyncio', http='h11', ws='none'))
            thread = threading.Thread(target=lambda: owned_server.run(sockets=[listener]), daemon=True)
            thread.start()
            for _ in range(80):
                try:
                    if client.get(url + '/health').status_code == 200:
                        break
                except httpx.HTTPError:
                    pass
                time.sleep(.1)
            else:
                owned_server.should_exit = True
                raise RuntimeError('El servidor local no pudo iniciar.')
        config['url'] = url
        # Only the laboratory connection is rewritten. Existing family URLs and
        # tokens in normal data remain unchanged across upgrades.
        connection = profile / 'isolated-connection.json' if args.isolated_profile else config_path
        if args.isolated_profile or read_json(config_path).get('url') != url:
            connection.write_text(json.dumps(config, ensure_ascii=False, indent=2), encoding='utf-8')
        updates = installation / 'updates'
        if (updates / 'android-update.json').is_file():
            from http.server import ThreadingHTTPServer
            from scripts import serve_apk
            serve_apk.DIST = updates
            try:
                owned_downloads = ThreadingHTTPServer(('127.0.0.1', download_port), serve_apk.Download)
                threading.Thread(target=owned_downloads.serve_forever, daemon=True).start()
            except OSError:
                # The download helper is optional for local recipe editing.
                pass
        launch = [str(installation / 'app/mesa.exe'), '--connect-json=' + str(connection)]
        # Keep binary updates local to this Windows launcher. Reusing an older
        # server must not silently attach an updater that it does not implement.
        if owned_server:
            from server.windows_updates import WindowsUpdateService
            session=secrets.token_urlsafe(32)
            app.state.windows_update_session=session
            app.state.windows_updater=WindowsUpdateService(installation,profile/'updates',VERSION,
                allow_apply=not bool(args.isolated_profile))
            session_info=base64.urlsafe_b64encode(json.dumps({'url':url,'session':session}).encode()).decode()
            launch.append('--windows-update-session='+session_info)
        if args.isolated_profile:
            launch.append('--isolated-profile=' + str(profile / 'client'))
        process = None
        try:
            process = subprocess.Popen(launch, cwd=installation / 'app')
            if args.report:
                args.report.write_text(json.dumps({'launcherPid': os.getpid(), 'clientPid': process.pid, 'apiPort': api_port, 'downloadPort': download_port, 'profile': str(profile), 'version': VERSION}, indent=2), encoding='utf-8')
            return process.wait()
        finally:
            if owned_server:
                owned_server.should_exit = True
                thread.join(timeout=8)
            if owned_downloads:
                owned_downloads.shutdown()
                owned_downloads.server_close()


if __name__ == '__main__':
    try:
        raise SystemExit(main())
    except Exception as error:
        # Diagnostic files belong only to an explicitly supplied report path.
        if '--report' in sys.argv:
            target = Path(sys.argv[sys.argv.index('--report') + 1])
            target.write_text(json.dumps({'error': str(error)}, ensure_ascii=False), encoding='utf-8')
        else:
            ctypes.windll.user32.MessageBoxW(None, str(error), 'Mesa · no se pudo iniciar', 0x10)
        raise SystemExit(1)
