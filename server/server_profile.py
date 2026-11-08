"""Select an existing family profile without copying data or changing identity."""
import hashlib
import json
import os
from pathlib import Path
import sqlite3


def validate_existing(folder):
    path=Path(folder)
    if not path.is_absolute() or not path.is_dir() or path.is_symlink() or path.is_junction():
        raise ValueError('El perfil de servidor elegido debe ser una carpeta existente con ruta absoluta. No se ha creado ni sustituido ningún perfil.')
    for name in ('recetario.sqlite','desktop-connection.json'):
        item=path/name
        if not item.is_file() or item.is_symlink() or item.is_junction():
            raise ValueError('El perfil elegido está incompleto. Conserva su base y configuración originales; no se ha creado otra familia.')
    try:
        config=json.loads((path/'desktop-connection.json').read_text(encoding='utf-8-sig'))
        token=config.get('token')
        if not isinstance(token,str) or not token: raise ValueError()
        with sqlite3.connect((path/'recetario.sqlite').as_uri()+'?mode=ro',uri=True) as con:
            valid=con.execute('SELECT COUNT(*) FROM users WHERE token_hash=? AND revoked=0',
                              (hashlib.sha256(token.encode()).hexdigest(),)).fetchone()[0]
        if valid!=1:raise ValueError()
    except (OSError,ValueError,sqlite3.Error) as error:
        raise ValueError('La configuración elegida no corresponde a una credencial vigente de ese perfil. No se cambia la identidad ni se crea otra familia.') from error
    return path.resolve()


def select_server_data(profile, *, isolated=False, environ=None):
    """QA is always fenced; normal selection is explicit and persistent."""
    profile=Path(profile)
    if isolated:return profile/'server'
    environ=os.environ if environ is None else environ
    explicit=environ.get('MESA_SERVER_DATA','').strip()
    settings=profile/'server-profile.json'
    if not explicit and settings.exists():
        try:
            value=json.loads(settings.read_text(encoding='utf-8-sig'))
            if value.get('schema')!=1 or not isinstance(value.get('server_data_directory'),str):raise ValueError()
            explicit=value['server_data_directory']
        except (OSError,ValueError,AttributeError) as error:
            raise ValueError('La selección del servidor no es válida. Revisa server-profile.json; no se ha sustituido por un perfil vacío.') from error
    if not explicit:explicit=environ.get('RECETARIO_DATA','').strip()
    return validate_existing(explicit) if explicit else profile/'server'
