"""Read PE version resources and Authenticode using Windows APIs, without execution."""
import ctypes
from ctypes import wintypes as w
from pathlib import Path
import uuid


class GUID(ctypes.Structure):
    _fields_=[('a',w.DWORD),('b',w.WORD),('c',w.WORD),('d',ctypes.c_ubyte*8)]


class TrustFile(ctypes.Structure):
    _fields_=[('size',w.DWORD),('path',w.LPCWSTR),('file',w.HANDLE),('subject',ctypes.c_void_p)]


class TrustData(ctypes.Structure):
    _fields_=[('size',w.DWORD),('policy',ctypes.c_void_p),('sip',ctypes.c_void_p),
              ('ui',w.DWORD),('revocation',w.DWORD),('choice',w.DWORD),('file',ctypes.c_void_p),
              ('action',w.DWORD),('state',w.HANDLE),('url',w.LPCWSTR),('flags',w.DWORD),
              ('context',w.DWORD),('settings',ctypes.c_void_p)]


class ProviderCert(ctypes.Structure):
    _fields_=[('size',w.DWORD),('cert',ctypes.c_void_p)]


class ProviderSigner(ctypes.Structure):
    _fields_=[('size',w.DWORD),('time',w.FILETIME),('count',w.DWORD),('certs',ctypes.POINTER(ProviderCert))]


def authenticode(path):
    trust=ctypes.WinDLL('wintrust',use_last_error=True)
    verify=trust.WinVerifyTrust
    verify.argtypes=[w.HWND,ctypes.POINTER(GUID),ctypes.POINTER(TrustData)]
    verify.restype=w.LONG
    action=GUID.from_buffer_copy(uuid.UUID('00AAC56B-CD44-11d0-8CC2-00C04FC295EE').bytes_le)
    file=TrustFile(ctypes.sizeof(TrustFile),str(path),None,None)
    data=TrustData();data.size=ctypes.sizeof(data);data.ui=2;data.revocation=1
    data.choice=1;data.file=ctypes.cast(ctypes.pointer(file),ctypes.c_void_p)
    data.action=1;data.flags=0x80  # Revocation check for the chain, excluding the root.
    thumb=None
    try:
        status=verify(None,ctypes.byref(action),ctypes.byref(data)) & 0xffffffff
        if status==0:
            provider=trust.WTHelperProvDataFromStateData
            provider.argtypes=[w.HANDLE];provider.restype=ctypes.c_void_p
            signer=trust.WTHelperGetProvSignerFromChain
            signer.argtypes=[ctypes.c_void_p,w.DWORD,w.BOOL,w.DWORD]
            signer.restype=ctypes.POINTER(ProviderSigner)
            details=signer(provider(data.state),0,False,0)
            if not details or not details.contents.count: raise ValueError('Firma sin certificado verificable.')
            cert=details.contents.certs.contents.cert
            crypt=ctypes.WinDLL('crypt32',use_last_error=True)
            get=crypt.CertGetCertificateContextProperty
            get.argtypes=[ctypes.c_void_p,w.DWORD,ctypes.c_void_p,ctypes.POINTER(w.DWORD)]
            size=w.DWORD(20);buffer=(ctypes.c_ubyte*20)()
            if not get(cert,3,buffer,ctypes.byref(size)) or size.value!=20: raise ValueError('No se pudo leer la identidad de firma.')
            thumb=bytes(buffer).hex().upper()
        return {'signature':'Valid' if status==0 else 'NotSigned' if status==0x800B0100 else f'Invalid:{status:08X}', 'thumbprint':thumb}
    finally:
        data.action=2;verify(None,ctypes.byref(action),ctypes.byref(data))


def inspect(path):
    path=Path(path).resolve()
    api=ctypes.WinDLL('version',use_last_error=True)
    api.GetFileVersionInfoSizeW.argtypes=[w.LPCWSTR,ctypes.POINTER(w.DWORD)]
    api.GetFileVersionInfoSizeW.restype=w.DWORD
    api.GetFileVersionInfoW.argtypes=[w.LPCWSTR,w.DWORD,w.DWORD,ctypes.c_void_p]
    api.VerQueryValueW.argtypes=[ctypes.c_void_p,w.LPCWSTR,ctypes.POINTER(ctypes.c_void_p),ctypes.POINTER(w.UINT)]
    size=api.GetFileVersionInfoSizeW(str(path),None)
    if not size: raise ValueError('El ejecutable no contiene una versión válida.')
    block=ctypes.create_string_buffer(size)
    if not api.GetFileVersionInfoW(str(path),0,size,block): raise ValueError('No se pudo leer la versión del ejecutable.')
    def query(key):
        pointer=ctypes.c_void_p();length=w.UINT()
        if not api.VerQueryValueW(block,key,ctypes.byref(pointer),ctypes.byref(length)): raise ValueError('Metadatos de producto incompletos.')
        return pointer,length.value
    pointer,length=query('\\')
    fixed=ctypes.cast(pointer,ctypes.POINTER(w.DWORD*13)).contents
    if length<52 or fixed[0]!=0xFEEF04BD: raise ValueError('Versión PE incorrecta.')
    pointer,length=query('\\VarFileInfo\\Translation')
    if length<4: raise ValueError('Falta el idioma de los metadatos.')
    language,codepage=ctypes.cast(pointer,ctypes.POINTER(w.WORD*2)).contents
    def string(name):
        pointer,length=query(f'\\StringFileInfo\\{language:04x}{codepage:04x}\\{name}')
        return ctypes.wstring_at(pointer,max(0,length-1))
    return {'product':string('ProductName'),'description':string('FileDescription'),
            'version':string('FileVersion'),'code':fixed[3]&0xffff,**authenticode(path)}
