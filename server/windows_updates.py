"""Mesa per-user binary updates: signed metadata, bounded downloads, OS handoff.

OS effects live behind WindowsPlatform, allowing the entire apply/reopen path
to be exercised with fakes without executing any updater/installer on the host.
"""
from __future__ import annotations
import base64
import configparser
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import threading
import time
import urllib.error
import urllib.parse
import urllib.request

from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PublicKey

DEFAULT_FEED = 'https://starfly.tailc69897.ts.net:9443/descargar/windows-update.json'
PUBLIC_KEY = Path(__file__).with_name('windows_update_key.pub')
PRODUCT = 'com.mesa.mesa.windows'
MAX_PACKAGE = 2_000_000_000


class UpdateError(Exception):
    pass


def canonical(data):
    return json.dumps(data,sort_keys=True,separators=(',',':'),ensure_ascii=False).encode('utf-8')


def file_hash(path):
    with Path(path).open('rb') as stream:
        return hashlib.file_digest(stream,'sha256').hexdigest()


def same_origin(url,feed):
    uri,origin=urllib.parse.urlsplit(url),urllib.parse.urlsplit(feed)
    return (uri.scheme=='https' and origin.scheme=='https' and bool(uri.hostname)
            and not uri.username and not uri.password and not uri.fragment
            and not origin.username and not origin.password and not origin.fragment
            and uri.hostname==origin.hostname and (uri.port or 443)==(origin.port or 443))


def parse_release(envelope,feed,public_key=None):
    if not same_origin(feed,feed): raise UpdateError('El canal debe usar HTTPS sin credenciales.')
    if not isinstance(envelope,dict) or set(envelope)!= {'release','signature'}:
        raise UpdateError('Manifiesto de actualización incorrecto.')
    data=envelope['release']
    try:
        raw=bytes.fromhex((public_key or PUBLIC_KEY.read_text(encoding='ascii')).strip())
        Ed25519PublicKey.from_public_bytes(raw).verify(base64.b64decode(envelope['signature'],validate=True),canonical(data))
    except Exception as error:
        raise UpdateError('La firma del canal no corresponde a Mesa.') from error
    if not isinstance(data,dict): raise UpdateError('Versión incorrecta.')
    version,code,size=data.get('version'),data.get('version_code'),data.get('size')
    if (data.get('product')!=PRODUCT or data.get('platform')!='windows' or data.get('architecture')!='x64'
        or not isinstance(version,str) or not re.fullmatch(r'\d+\.\d+\.\d+',version)
        or type(code) is not int or not 0<code<2147483647 or type(size) is not int or not 0<size<=MAX_PACKAGE
        or not isinstance(data.get('sha256'),str) or not re.fullmatch('[a-f0-9]{64}',data['sha256'])
        or data.get('installer_path')!=f'/descargar/Mesa-Setup-{version}-{code}-x64.exe'
        or not isinstance(data.get('notes'),list) or len(data['notes'])>20
        or any(not isinstance(n,str) or len(n)>1000 for n in data['notes'])
        or type(data.get('authenticode_required')) is not bool):
        raise UpdateError('El paquete no corresponde a Mesa Windows x64.')
    thumb=data.get('authenticode_thumbprint')
    if (data['authenticode_required'] and (not isinstance(thumb,str) or not re.fullmatch('[A-F0-9]{40}',thumb))) or (not data['authenticode_required'] and thumb is not None):
        raise UpdateError('Política de firma de Windows incorrecta.')
    url=urllib.parse.urljoin(feed,data['installer_path'])
    if not same_origin(url,feed): raise UpdateError('Origen de descarga incorrecto.')
    return {**data,'url':url}


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self,*args,**kwargs): return None


def open_https(url,feed):
    opener=urllib.request.build_opener(urllib.request.ProxyHandler({}),NoRedirect())
    for _ in range(4):
        if not same_origin(url,feed): raise UpdateError('Redirección de actualización no permitida.')
        try:
            return opener.open(urllib.request.Request(url,headers={'Accept-Encoding':'identity'}),timeout=15)
        except urllib.error.HTTPError as error:
            if error.code not in (301,302,303,307,308): raise UpdateError(f'El canal no está disponible (HTTP {error.code}).') from error
            location=error.headers.get('Location')
            if not location: raise UpdateError('Redirección sin destino.')
            url=urllib.parse.urljoin(url,location)
            error.close()
    raise UpdateError('Demasiadas redirecciones del canal.')


class WindowsPlatform:
    def registered_installation(self,installation):
        import winreg
        try:
            with winreg.OpenKey(winreg.HKEY_CURRENT_USER,r'Software\Microsoft\Windows\CurrentVersion\Uninstall\Mesa',0,winreg.KEY_READ|winreg.KEY_WOW64_64KEY) as key:
                location=winreg.QueryValueEx(key,'InstallLocation')[0]
            return Path(location).resolve()==Path(installation).resolve()
        except (OSError,ValueError): return False

    def installed_code(self,installation):
        info=self.inspect(Path(installation)/'app/mesa.exe')
        if info.get('product')!='mesa' or type(info.get('code')) is not int:
            raise UpdateError('No se reconoce el cliente Windows instalado.')
        return info['code']

    def inspect(self,path):
        from .windows_file_info import inspect
        return inspect(path)

    def spawn_helper(self,helper,request):
        subprocess.Popen([str(helper),'--request',str(request)],cwd=helper.parent,
                         creationflags=getattr(subprocess,'CREATE_NO_WINDOW',0))

    def wait_parent(self,pid,expected):
        import ctypes
        from ctypes import wintypes
        kernel=ctypes.WinDLL('kernel32',use_last_error=True)
        kernel.OpenProcess.argtypes=[wintypes.DWORD,wintypes.BOOL,wintypes.DWORD]
        kernel.OpenProcess.restype=wintypes.HANDLE
        kernel.CloseHandle.argtypes=[wintypes.HANDLE]
        kernel.QueryFullProcessImageNameW.argtypes=[wintypes.HANDLE,wintypes.DWORD,wintypes.LPWSTR,ctypes.POINTER(wintypes.DWORD)]
        kernel.WaitForSingleObject.argtypes=[wintypes.HANDLE,wintypes.DWORD]
        handle=kernel.OpenProcess(0x00100000|0x1000,False,pid)
        if not handle:
            if ctypes.get_last_error()==87: return
            raise UpdateError('No se pudo comprobar el proceso de Mesa. No se ha instalado nada.')
        try:
            size=wintypes.DWORD(32768);buffer=ctypes.create_unicode_buffer(size.value)
            if not kernel.QueryFullProcessImageNameW(handle,0,buffer,ctypes.byref(size)) or Path(buffer.value).resolve()!=Path(expected).resolve():
                raise UpdateError('El proceso de origen no corresponde a Mesa.')
            if kernel.WaitForSingleObject(handle,60_000)!=0:
                raise UpdateError('Mesa sigue abierta. Cierra la app y vuelve a actualizar; no se ha forzado su cierre.')
        finally: kernel.CloseHandle(handle)

    def run_installer(self,path):
        # Interactive NSIS: normal confirmation and licence pages stay enabled.
        return subprocess.run([str(path)],cwd=path.parent,check=False).returncode

    def reopen(self,path):
        subprocess.Popen([str(path)],cwd=path.parent)


def verify_artifact(path,release,current_code,platform,current_version=None):
    path=Path(path)
    if release['version_code']<=current_code: raise UpdateError('Se rechaza una versión igual o anterior.')
    if current_version and tuple(map(int,release['version'].split('.')))<tuple(map(int,current_version.split('.'))):
        raise UpdateError('Se rechaza el retroceso de versión de Mesa.')
    if not path.is_file() or path.stat().st_size!=release['size'] or file_hash(path)!=release['sha256']:
        raise UpdateError('Tamaño o SHA-256 de la descarga incorrectos.')
    meta=platform.inspect(path)
    if (meta.get('product')!='Mesa' or meta.get('description')!='Instalador de Mesa para Windows x64'
        or meta.get('version')!=release['version'] or meta.get('code')!=release['version_code']):
        raise UpdateError('El ejecutable no coincide con el producto o la versión firmados.')
    if release['authenticode_required']:
        if meta.get('signature')!='Valid' or meta.get('thumbprint')!=release['authenticode_thumbprint']:
            raise UpdateError('La firma Authenticode no coincide con la versión anunciada.')
    elif meta.get('signature')!='NotSigned':
        raise UpdateError('La firma del ejecutable no coincide con la política firmada del canal.')


def installed_marker(installation):
    marker=Path(installation)/'mesa-install.ini'
    parser=configparser.ConfigParser()
    try:
        # NSIS Unicode writes UTF-16 LE INI; accept older UTF-8 markers as well.
        raw=marker.read_bytes()
        parser.read_string(raw.decode('utf-16' if raw.startswith((b'\xff\xfe',b'\xfe\xff')) else 'utf-8-sig'))
        return parser.get('Mesa','Version')
    except (OSError,ValueError,configparser.Error): return None


class WindowsUpdateService:
    def __init__(self,installation,cache,version,*,feed=None,platform=None,transport=None,public_key=None,allow_apply=True):
        self.installation=Path(installation).resolve();self.cache=Path(cache).resolve()
        self.version,self.code=version.split('+');self.code=int(self.code)
        self.feed=feed or os.environ.get('MESA_WINDOWS_UPDATE_FEED',DEFAULT_FEED)
        self.platform=platform or WindowsPlatform();self.transport=transport or open_https
        self.public_key=public_key;self.allow_apply=allow_apply
        self.envelope=None;self.release=None
        self._cancel=threading.Event();self._lock=threading.Lock()
        self.state={'status':'idle','received':0}

    def info(self):
        managed=installed_marker(self.installation) is not None and self.allow_apply and self.platform.registered_installation(self.installation)
        return {'version':self.version,'version_code':self.code,'platform':'windows','sdk':999,'abis':['x64'],
                'can_install':managed,'managed_install':managed,'feed':self.feed}

    def check(self):
        if self.state['status']=='downloading': raise UpdateError('Espera o cancela la descarga actual.')
        with self.transport(self.feed,self.feed) as response:
            payload=response.read(16001)
        if len(payload)>16000: raise UpdateError('El manifiesto supera el límite permitido.')
        try: envelope=json.loads(payload)
        except (ValueError,UnicodeError) as error: raise UpdateError('Canal de actualización incorrecto.') from error
        release=parse_release(envelope,self.feed,self.public_key)
        self.envelope,self.release=envelope,release
        self.state={'status':'idle','received':0}
        return release

    def _selected(self,args):
        if not self.release or any(args.get(k)!=self.release[k] for k in ('version_code','size','sha256','url')):
            raise UpdateError('Busca actualizaciones de nuevo: la selección no coincide con el canal verificado.')
        if self.release['version_code']<=self.code: raise UpdateError('No es una versión más reciente.')
        return self.release

    def package(self):
        return self.cache/f"Mesa-Setup-{self.release['version']}-{self.release['version_code']}-x64.exe"

    def download(self,args,*,background=True):
        release=self._selected(args)
        if not self._lock.acquire(blocking=False): raise UpdateError('Ya hay una descarga en curso.')
        self._cancel.clear();self.state={'status':'downloading','received':0}
        def run():
            path=self.package();part=path.with_suffix('.exe.part')
            try:
                self.cache.mkdir(parents=True,exist_ok=True)
                with self.transport(release['url'],self.feed) as response:
                    if response.status!=200 or response.headers.get('Content-Length')!=str(release['size']):
                        raise UpdateError('El servidor no ofrece el tamaño anunciado.')
                    started=time.monotonic()
                    with part.open('wb') as output:
                        while True:
                            if self._cancel.is_set(): raise UpdateError('Descarga cancelada.')
                            if time.monotonic()-started>1800: raise UpdateError('La descarga tardó demasiado.')
                            chunk=response.read(65536)
                            if not chunk: break
                            self.state['received']+=len(chunk)
                            if self.state['received']>release['size']: raise UpdateError('La descarga supera el tamaño anunciado.')
                            output.write(chunk)
                verify_artifact(part,release,self.code,self.platform,self.version)
                if self._cancel.is_set(): raise UpdateError('Descarga cancelada.')
                part.replace(path)
                self.state={'status':'ready','received':release['size']}
            except Exception as error:
                self.state={'status':'cancelled' if self._cancel.is_set() else 'error','received':self.state['received'],'error':str(error)}
            finally:
                part.unlink(missing_ok=True);self._lock.release()
        if background: threading.Thread(target=run,daemon=True).start()
        else: run()
        return dict(self.state)

    def cancel(self):
        self._cancel.set()

    def apply(self,args):
        release=self._selected(args)
        if not self.info()['can_install']: raise UpdateError('Esta copia necesita una primera instalación manual de Mesa Windows. Abre la app desde su acceso instalado.')
        if self.state['status']!='ready': raise UpdateError('Descarga y verifica la actualización primero.')
        path=self.package()
        verify_artifact(path,release,self.code,self.platform,self.version)
        helper=self.installation/'MesaUpdateHelper.exe'
        if not helper.is_file(): raise UpdateError('Falta el asistente de actualización. Repara la instalación de Mesa.')
        # The independent one-file helper is copied OUTSIDE the installation so
        # its own executable and Python DLL do not lock files being replaced.
        run=self.cache/('handoff-'+os.urandom(8).hex());run.mkdir()
        copied=run/'MesaUpdateHelper.exe';shutil.copy2(helper,copied)
        request=run/'request.json'
        request.write_text(json.dumps({'envelope':self.envelope,'feed':self.feed,'installer':str(path),
            'installation':str(self.installation),'current_code':self.code,'parent_pid':os.getpid()},ensure_ascii=False),encoding='utf-8')
        self.platform.spawn_helper(copied,request)
        self.state={'status':'handoff','received':release['size']}
        return {'close_app':True,'restart':'helper_after_native_installer'}


def apply_request(request,*,platform=None,public_key=None):
    platform=platform or WindowsPlatform()
    data=json.loads(Path(request).read_text(encoding='utf-8'))
    release=parse_release(data['envelope'],data['feed'],public_key)
    installation=Path(data['installation']).resolve();installer=Path(data['installer']).resolve()
    if installed_marker(installation) is None or not (installation/'Mesa.exe').is_file() or not platform.registered_installation(installation):
        raise UpdateError('No se reconoce la instalación original de Mesa.')
    actual_code=platform.installed_code(installation)
    if actual_code!=data['current_code']: raise UpdateError('La instalación ha cambiado. Busca actualizaciones de nuevo.')
    verify_artifact(installer,release,actual_code,platform,installed_marker(installation))
    platform.wait_parent(int(data['parent_pid']),installation/'Mesa.exe')
    # Recheck after waiting, immediately before handing off to Windows.
    verify_artifact(installer,release,platform.installed_code(installation),platform,installed_marker(installation))
    code=platform.run_installer(installer)
    if code==0:
        actual=installed_marker(installation)
        if actual!=release['version'] or platform.installed_code(installation)!=release['version_code']:
            raise UpdateError('El instalador terminó sin actualizar esta copia. Abre Mesa desde su acceso y comprueba la versión.')
    # A cancelled native installer reopens the previous app, preserving data.
    platform.reopen(installation/'Mesa.exe')
    return {'installer_exit':code,'reopen_requested':True,'updated':code==0}
