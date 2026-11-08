"""Private family cookbook API. Bind only to loopback; expose with Tailscale Serve."""
from __future__ import annotations

from contextlib import contextmanager, asynccontextmanager, suppress
from datetime import datetime, timezone
from hashlib import sha256
from pathlib import Path
from typing import Literal
import base64
import http.client
import asyncio
import io
import json
import math
import os
import secrets
import sqlite3
import time
import uuid

from fastapi import Depends, FastAPI, HTTPException, Request, Query, BackgroundTasks
from fastapi.responses import Response
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from starlette.middleware.gzip import GZipMiddleware
from starlette.concurrency import run_in_threadpool
from PIL import Image, UnidentifiedImageError
from pydantic import BaseModel, Field, field_validator
from .online_photos import online_recipe_data, online_photo_tree, online_photo_url

MAX_BODY = 12_000_000
DATA = Path(os.environ.get('RECETARIO_DATA', Path(__file__).resolve().parents[1] / 'data'))
bearer = HTTPBearer(auto_error=False)


def stamp():
    return datetime.now(timezone.utc).isoformat()


class Invite(BaseModel):
    name: str = Field(min_length=1, max_length=80)
    role: Literal['editor', 'reader'] = 'editor'

class TranslateRecipe(BaseModel):
    recipe: dict
    source: str = Field(min_length=2,max_length=20)
    force: bool = False

    @field_validator('source')
    @classmethod
    def translation_language(cls,value):
        language=value.lower().replace('_','-').split('-')[0]
        if language not in {'en','fr','it','de','pt'}:
            raise ValueError('Idioma no compatible. Mesa traduce inglés, francés, italiano, alemán y portugués al español; se conserva el original.')
        return language


class Pair(BaseModel):
    code: str = Field(min_length=6, max_length=100)
    name: str = Field(min_length=1, max_length=80)


class Operation(BaseModel):
    id: str = Field(min_length=1, max_length=80)
    entity_id: str = Field(min_length=1, max_length=80)
    kind: Literal['recipe', 'shopping', 'meal', 'collection']
    base: int = Field(ge=0)
    data: dict
    deleted: bool = False
    action: Literal['save', 'check'] = 'save'

    @field_validator('data')
    @classmethod
    def size_limit(cls, value, info):
        if len(json.dumps(value, ensure_ascii=False).encode('utf-8')) > (8_000_000 if info.data.get('kind') == 'recipe' else 900_000):
            raise ValueError('El elemento es demasiado grande.')
        return value


class Push(BaseModel):
    generation: str
    operations: list[Operation] = Field(max_length=25)


class ImportText(BaseModel):
    text: str = Field(min_length=1, max_length=500_000)


class ImportUrl(BaseModel):
    url: str = Field(min_length=1, max_length=4000)
    provider: str = Field(default='', max_length=80)
    skip_photos: list[str] = Field(default_factory=list, max_length=500)

    @field_validator('skip_photos')
    @classmethod
    def skip_photo_lengths(cls, values):
        if any(len(x)>10000 for x in values):
            raise ValueError('Referencia de foto demasiado larga.')
        return values


def validate_data(kind, data):
    if kind == 'recipe':
        if not isinstance(data.get('title'), str) or not data['title'].strip() or len(data['title']) > 250:
            raise HTTPException(422, 'La receta necesita un título de hasta 250 caracteres.')
        for field in ('ingredients', 'steps', 'tags', 'category_ids', 'catalog_ids'):
            value = data.get(field, [])
            if not isinstance(value, list) or len(value) > 500 or any(not isinstance(x, str) or len(x) > 10000 for x in value):
                raise HTTPException(422, 'Formato de receta incorrecto: ' + field)
        origin = data.get('origin')
        if origin is not None and (not isinstance(origin, dict) or
                any(not isinstance(origin.get(k), str) or len(origin[k]) > 4000 for k in
                    ('provider', 'id', 'attribution', 'license', 'license_url', 'url', 'language'))):
            raise HTTPException(422, 'Atribución incorrecta.')
        original = data.get('original')
        if original is not None:
            if (not isinstance(original,dict) or not isinstance(original.get('language'),str) or
                not isinstance(original.get('title'),str) or len(original['title'])>250 or
                not isinstance(original.get('notes'),str) or len(original['notes'])>120000 or
                any(not isinstance(original.get(k),list) or len(original[k])>500 or any(not isinstance(v,str) or len(v)>10000 for v in original[k]) for k in ('ingredients','steps'))):
                raise HTTPException(422,'El texto original de la traducción no es válido.')
        translation = data.get('translation')
        if translation is not None and (not isinstance(translation,dict) or any(not isinstance(translation.get(k),str) or len(translation[k])>100 for k in ('source_language','target_language','engine'))):
            raise HTTPException(422,'Los datos de traducción no son válidos.')
        servings = data.get('servings', 4)
        if isinstance(servings, bool) or not isinstance(servings, (int, float)) or not 0 < servings <= 10000:
            raise HTTPException(422, 'Raciones incorrectas.')
        minutes = data.get('minutes', 0)
        if isinstance(minutes, bool) or not isinstance(minutes, int) or not 0 <= minutes <= 100000:
            raise HTTPException(422, 'Tiempo de receta incorrecto.')
        rating = data.get('rating', 0)
        if isinstance(rating, bool) or not isinstance(rating, int) or not 0 <= rating <= 5:
            raise HTTPException(422, 'Valoración incorrecta.')
        for field, maximum in [('notes', 120000), ('source', 4000)]:
            value = data.get(field, '')
            if not isinstance(value, str) or len(value) > maximum:
                raise HTTPException(422, 'Texto de receta incorrecto: ' + field)
        image = data.get('image', '')
        if not isinstance(image, str):
            raise HTTPException(422, 'Datos de foto incorrectos.')
        if data.get('image_url') is not None and not online_photo_url(data['image_url']):
            raise HTTPException(422, 'Enlace de portada incorrecto.')
        if image:
            try:
                raw = base64.b64decode(image, validate=True)
                if len(raw) > 600_000:
                    raise ValueError()
                with Image.open(io.BytesIO(raw)) as photo:
                    if photo.width * photo.height > 4_000_000:
                        raise ValueError()
                    photo.verify()
            except (ValueError, UnidentifiedImageError, OSError, Image.DecompressionBombError):
                raise HTTPException(422, 'La foto no es válida o es demasiado grande.')
        photos = data.get('photos', [])
        if not isinstance(photos, list) or len(photos) > 500:
            raise HTTPException(422, 'Galería incorrecta.')
        for item in photos:
            if not isinstance(item, dict) or any(not isinstance(v, str) or len(v) > (800_000 if k == 'image' else 10_000) for k, v in item.items()):
                raise HTTPException(422, 'Datos de foto incorrectos.')
            if item.get('url') and not online_photo_url(item['url']):
                raise HTTPException(422, 'La foto necesita un enlace HTTPS público.')
            if item.get('image'):
                try:
                    raw = base64.b64decode(item['image'], validate=True)
                    if len(raw) > 600_000:
                        raise ValueError()
                    with Image.open(io.BytesIO(raw)) as photo:
                        if photo.width * photo.height > 4_000_000:
                            raise ValueError()
                        photo.verify()
                except (ValueError, UnidentifiedImageError, OSError, Image.DecompressionBombError):
                    raise HTTPException(422, 'Una foto de la galería no es válida.')
    elif kind == 'collection':
        if data.get('type') not in ('category', 'catalog') or not isinstance(data.get('title'), str) or not data['title'].strip() or len(data['title']) > 80:
            raise HTTPException(422, 'La categoría o catálogo necesita un nombre de hasta 80 caracteres.')
    elif kind == 'shopping':
        for field, maximum in [('recipe_title', 250), ('source', 4000)]:
            if data.get(field) is not None and (not isinstance(data[field], str) or len(data[field]) > maximum):
                raise HTTPException(422, 'Referencia de compra incorrecta: ' + field)
        if not isinstance(data.get('name'), str) or not data['name'].strip() or len(data['name']) > 1000:
            raise HTTPException(422, 'El producto necesita un nombre.')
        if not isinstance(data.get('checked', False), bool):
            raise HTTPException(422, 'Estado de compra incorrecto.')
    elif kind == 'meal':
        try:
            parsed = datetime.strptime(data['date'], '%Y-%m-%d')
            if parsed.strftime('%Y-%m-%d') != data['date']:
                raise ValueError()
        except (KeyError, TypeError, ValueError):
            raise HTTPException(422, 'Fecha de menú incorrecta.')
        if data.get('slot') not in ('Comida', 'Cena'):
            raise HTTPException(422, 'Franja de menú incorrecta.')
        if (not isinstance(data.get('title'), str) or not data['title'].strip() or len(data['title']) > 250 or
                (data.get('recipe_id') is not None and (not isinstance(data['recipe_id'], str) or len(data['recipe_id']) > 80))):
            raise HTTPException(422, 'Plato del menú incorrecto.')
        servings = data.get('servings', 4)
        if isinstance(servings, bool) or not isinstance(servings, (int, float)) or not math.isfinite(servings) or not 0 < servings <= 10000:
            raise HTTPException(422, 'Raciones del menú incorrectas.')


def create_app(data_dir: Path | None = None):
    root = data_dir or DATA
    root.mkdir(parents=True, exist_ok=True)
    db_path = root / 'recetario.sqlite'

    @contextmanager
    def db():
        connection = sqlite3.connect(db_path, timeout=20)
        connection.row_factory = sqlite3.Row
        connection.execute('PRAGMA foreign_keys=ON')
        try:
            yield connection
            connection.commit()
        except Exception:
            connection.rollback()
            raise
        finally:
            connection.close()

    with db() as con:
        con.execute('PRAGMA journal_mode=WAL')
        con.executescript('''
          CREATE TABLE IF NOT EXISTS meta (key TEXT PRIMARY KEY, value TEXT NOT NULL);
          CREATE TABLE IF NOT EXISTS users (id TEXT PRIMARY KEY, name TEXT, role TEXT, token_hash TEXT UNIQUE, revoked INTEGER DEFAULT 0);
          CREATE TABLE IF NOT EXISTS invites (hash TEXT PRIMARY KEY, name TEXT, role TEXT, expires REAL, used INTEGER DEFAULT 0);
          CREATE TABLE IF NOT EXISTS entities (id TEXT PRIMARY KEY, kind TEXT NOT NULL, revision INTEGER NOT NULL, data TEXT NOT NULL, deleted INTEGER NOT NULL, updated TEXT, author TEXT);
          CREATE TABLE IF NOT EXISTS changes (seq INTEGER PRIMARY KEY AUTOINCREMENT, entity TEXT NOT NULL);
          CREATE TABLE IF NOT EXISTS operations (id TEXT, user_id TEXT, fingerprint TEXT, result TEXT, PRIMARY KEY(id,user_id));
          CREATE TABLE IF NOT EXISTS history (seq INTEGER PRIMARY KEY AUTOINCREMENT, entity_id TEXT, snapshot TEXT, at TEXT, author TEXT);
        ''')
        if not con.execute("SELECT 1 FROM meta WHERE key='generation'").fetchone():
            con.execute('INSERT INTO meta VALUES (?,?)', ('generation', str(uuid.uuid4())))
        if not con.execute('SELECT 1 FROM users').fetchone():
            token = secrets.token_urlsafe(36)
            con.execute('INSERT INTO users VALUES (?,?,?,?,0)', (str(uuid.uuid4()), 'Administrador', 'admin', sha256(token.encode()).hexdigest()))
            (root / 'desktop-connection.json').write_text(json.dumps({'url': 'http://127.0.0.1:8765', 'token': token}, indent=2), encoding='utf-8')

        # Keep receipt fingerprints immutable so older clients can retry.
        if not con.execute("SELECT 1 FROM meta WHERE key='online-photos-v1'").fetchone():
            changed = []
            for row in con.execute("SELECT * FROM entities WHERE kind='recipe'").fetchall():
                old = json.loads(row['data'])
                clean = online_recipe_data(old)
                if clean != old:
                    con.execute('UPDATE entities SET data=? WHERE id=?',
                                (json.dumps(clean, ensure_ascii=False), row['id']))
                    changed.append(dict(row) | {'data': json.dumps(clean, ensure_ascii=False)})
            for table, column in [('changes', 'entity'), ('history', 'snapshot'),
                                  ('operations', 'result')]:
                for row in con.execute(f'SELECT rowid AS migration_rowid,{column} FROM {table}').fetchall():
                    old = json.loads(row[column])
                    clean = online_photo_tree(old)
                    if clean != old:
                        con.execute(f'UPDATE {table} SET {column}=? WHERE rowid=?',
                                    (json.dumps(clean, ensure_ascii=False), row['migration_rowid']))
            for row in changed:
                value = {k: row[k] for k in ('id', 'kind', 'revision', 'updated', 'author')}
                value.update(data=json.loads(row['data']), deleted=bool(row['deleted']))
                con.execute('INSERT INTO changes(entity) VALUES (?)',
                            (json.dumps(value, ensure_ascii=False),))
            con.execute('INSERT INTO meta VALUES (?,?)', ('online-photos-v1', 'true'))

    def make_backup():
        target = root / 'backups'
        target.mkdir(exist_ok=True)
        name = datetime.now().strftime('%Y%m%d-%H%M%S') + '-' + secrets.token_hex(3) + '.sqlite'
        with db() as con, sqlite3.connect(target / name) as dest:
            con.backup(dest)
        return name

    @asynccontextmanager
    async def lifespan(_):
        async def daily_backup():
            while True:
                try:
                    today = datetime.now().strftime('%Y%m%d')
                    if not any((root / 'backups').glob(today + '-*.sqlite')):
                        await asyncio.to_thread(make_backup)
                except (OSError, sqlite3.Error):
                    import logging
                    logging.getLogger('mesa').exception('No se pudo crear la copia automática. Revisa espacio y permisos.')
                await asyncio.sleep(3600)
        task = asyncio.create_task(daily_backup())
        try:
            yield
        finally:
            task.cancel()
            with suppress(asyncio.CancelledError):
                await task

    api = FastAPI(title='Mesa · Recetario familiar', version='0.7.0', docs_url=None, redoc_url=None, openapi_url=None, lifespan=lifespan)
    api.add_middleware(GZipMiddleware, minimum_size=1200, compresslevel=4)
    api.state.db = db
    api.state.root = root

    @api.middleware('http')
    async def limit_body(request: Request, call_next):
        # Enforce actual bytes as well as Content-Length, including chunked requests.
        from starlette.responses import JSONResponse
        if request.method in ('POST', 'PUT', 'PATCH'):
            total = 0
            chunks = []
            async for chunk in request.stream():
                total += len(chunk)
                limit = 10_000_000 if request.url.path == '/v1/ocr' else MAX_BODY
                if total > limit:
                    return JSONResponse({'detail': 'Petición demasiado grande.'}, status_code=413)
                chunks.append(chunk)
            request._body = b''.join(chunks)
        response = await call_next(request)
        response.headers['X-Content-Type-Options'] = 'nosniff'
        response.headers['Cache-Control'] = 'no-store'
        return response

    def user(credentials: HTTPAuthorizationCredentials | None = Depends(bearer)):
        if not credentials:
            raise HTTPException(401, 'Conecta este dispositivo con el recetario.')
        with db() as con:
            record = con.execute('SELECT * FROM users WHERE token_hash=? AND revoked=0', (sha256(credentials.credentials.encode()).hexdigest(),)).fetchone()
        if not record:
            raise HTTPException(401, 'Este dispositivo no está autorizado.')
        return dict(record)

    def admin(actor=Depends(user)):
        if actor['role'] != 'admin':
            raise HTTPException(403, 'Solo el administrador puede realizar esta acción.')
        return actor

    def entity(row):
        return {'id': row['id'], 'kind': row['kind'], 'revision': row['revision'], 'data': json.loads(row['data']), 'deleted': bool(row['deleted']), 'updated': row['updated'], 'author': row['author']}

    def generation(con):
        return con.execute("SELECT value FROM meta WHERE key='generation'").fetchone()[0]

    @api.get('/health')
    def health():
        return {'status': 'ok', 'product': 'mesa', 'version': '0.7.0', 'protocol': 1, 'capabilities': ['collections', 'recipe-attribution', 'photo-gallery', 'publisher-catalogs', 'remote-photos', 'local-translation', 'paginated-snapshot', 'retranslate-original', 'translation-warmup', 'persistent-translation-cache', 'indra-ocr']}

    @api.post('/v1/ocr')
    async def ocr_photo(request: Request, actor=Depends(user)):
        from .ocr import recognize_image, OcrError
        payload = await request.body()
        try:
            return await run_in_threadpool(recognize_image, payload)
        except OcrError as error:
            raise HTTPException(error.status, str(error)) from error

    @api.get('/v1/me')
    def me(actor=Depends(user)):
        return {key: actor[key] for key in ('id', 'name', 'role')}

    @api.post('/v1/app-updates/{action}')
    async def desktop_update(action: str, request: Request):
        # This capability is issued only to the Windows child of the local
        # launcher. Family API credentials cannot authorize a binary update.
        session=getattr(api.state,'windows_update_session',None)
        supplied=request.headers.get('X-Mesa-Update-Session','')
        if not session or not secrets.compare_digest(supplied,session):
            raise HTTPException(403,'Abre Actualizar Mesa desde la copia Windows instalada.')
        updater=api.state.windows_updater
        from .windows_updates import UpdateError
        try:
            if action=='info': return updater.info()
            if action=='check': return await run_in_threadpool(updater.check)
            if action=='state': return dict(updater.state)
            if action=='cancel': updater.cancel(); return {'cancelled':True}
            body=await request.json()
            if not isinstance(body,dict): raise UpdateError('Selección de actualización incorrecta.')
            if action=='download': return updater.download(body)
            if action=='install': return await run_in_threadpool(updater.apply,body)
            raise HTTPException(404,'Acción de actualización desconocida.')
        except UpdateError as error:
            raise HTTPException(400,str(error)) from error
        except (OSError,ValueError) as error:
            raise HTTPException(503,'El canal no está disponible. Revisa Tailscale y el ordenador o reintenta.') from error

    @api.post('/v1/invites')
    def invite(body: Invite, actor=Depends(admin)):
        code = secrets.token_hex(8).upper()
        with db() as con:
            con.execute('INSERT INTO invites VALUES (?,?,?,?,0)', (sha256(code.encode()).hexdigest(), body.name, body.role, time.time() + 600))
        return {'code': code, 'expires_in': 600, 'role': body.role}

    @api.post('/v1/pair')
    def pair(body: Pair):
        with db() as con:
            con.execute('BEGIN IMMEDIATE')
            code_hash = sha256(body.code.strip().upper().encode()).hexdigest()
            inv = con.execute('SELECT * FROM invites WHERE hash=? AND used=0 AND expires>?', (code_hash, time.time())).fetchone()
            if not inv:
                raise HTTPException(401, 'Invitación no válida, usada o caducada.')
            token = secrets.token_urlsafe(36)
            uid = str(uuid.uuid4())
            con.execute('INSERT INTO users VALUES (?,?,?,?,0)', (uid, body.name, inv['role'], sha256(token.encode()).hexdigest()))
            con.execute('UPDATE invites SET used=1 WHERE hash=?', (code_hash,))
        return {'token': token, 'id': uid, 'name': body.name, 'role': inv['role']}

    @api.get('/v1/members')
    def members(actor=Depends(admin)):
        with db() as con:
            return [dict(x) for x in con.execute('SELECT id,name,role,revoked FROM users')]

    @api.delete('/v1/members/{uid}')
    def revoke(uid: str, actor=Depends(admin)):
        if uid == actor['id']:
            raise HTTPException(400, 'No puedes revocar tu propio acceso de administrador.')
        with db() as con:
            con.execute('UPDATE users SET revoked=1 WHERE id=?', (uid,))
        return {'ok': True}

    @api.get('/v1/snapshot')
    def snapshot(after: str = Query(default='', max_length=80), limit: int | None = Query(default=None, ge=1, le=100),
                 epoch: str = Query(default='', max_length=80), start_cursor: int | None = Query(default=None,ge=0), actor=Depends(user)):
        with db() as con:
            con.execute('BEGIN')
            current_generation=generation(con)
            if epoch and epoch!=current_generation: raise HTTPException(409,'El servidor cambió durante la descarga; vuelve a intentarlo.')
            cursor=con.execute('SELECT COALESCE(MAX(seq),0) FROM changes').fetchone()[0]
            if start_cursor is not None and start_cursor>cursor: raise HTTPException(409,'El recetario cambió; vuelve a descargarlo.')
            if limit is None:
                return {'generation':current_generation,'cursor':cursor,'entities':[entity(x) for x in con.execute('SELECT * FROM entities')]}
            rows=con.execute('SELECT * FROM entities WHERE id>? ORDER BY id LIMIT ?', (after,limit+1)).fetchall()
            values=[];size=0
            for row in rows[:limit]:
                value=entity(row); amount=len(json.dumps(value,ensure_ascii=False).encode())
                if values and size+amount>8_500_000: break
                values.append(value);size+=amount
            more=len(rows)>len(values)
            return {'generation':current_generation,'cursor':start_cursor if start_cursor is not None else cursor,
                    'entities':values,'next':values[-1]['id'] if more and values else None}

    @api.get('/v1/changes')
    def changes(cursor: int = 0, epoch: str = '', actor=Depends(user)):
        if cursor < 0:
            raise HTTPException(422, 'Cursor incorrecto.')
        with db() as con:
            con.execute('BEGIN')
            if epoch != generation(con):
                raise HTTPException(409, 'Es necesario volver a descargar el recetario.')
            rows = con.execute('SELECT seq,entity FROM changes WHERE seq>? ORDER BY seq LIMIT 100', (cursor,)).fetchall()
            selected=[]; size=0
            for row in rows:
                amount=len(row['entity'].encode('utf-8'))
                if selected and size+amount>8_500_000: break
                selected.append(row);size+=amount
            return {'generation': generation(con), 'cursor': selected[-1]['seq'] if selected else cursor,
                    'more': len(selected)<len(rows) or len(rows)==100, 'entities': [json.loads(x['entity']) for x in selected]}

    @api.post('/v1/push')
    def push(body: Push, actor=Depends(user)):
        if actor['role'] == 'reader':
            raise HTTPException(403, 'Este perfil tiene acceso de lectura.')
        results = []
        with db() as con:
            con.execute('BEGIN IMMEDIATE')
            if body.generation != generation(con):
                raise HTTPException(409, 'Es necesario volver a descargar el recetario.')
            for op in body.operations:
                fingerprint = sha256(op.model_dump_json().encode()).hexdigest()
                prior = con.execute('SELECT * FROM operations WHERE id=? AND user_id=?', (op.id, actor['id'])).fetchone()
                if prior:
                    if prior['fingerprint'] != fingerprint:
                        raise HTTPException(409, 'Un identificador de operación ya se utilizó con otros datos.')
                    results.append(json.loads(prior['result']))
                    continue
                current = con.execute('SELECT * FROM entities WHERE id=?', (op.entity_id,)).fetchone()
                if current and current['kind'] != op.kind:
                    raise HTTPException(422, 'Tipo de elemento incorrecto.')
                check = op.action == 'check'
                if check and (op.kind != 'shopping' or set(op.data) != {'checked'} or not isinstance(op.data['checked'], bool)):
                    raise HTTPException(422, 'Operación de compra incorrecta.')
                revision = current['revision'] if current else 0
                if (check and (not current or current['deleted'])) or (not check and op.base != revision):
                    result = {'id': op.id, 'status': 'conflict', 'server': entity(current) if current else None}
                else:
                    payload = json.loads(current['data']) | op.data if check else op.data
                    validate_data(op.kind, payload)
                    if op.kind == 'recipe':
                        payload = online_recipe_data(payload)
                    value = {'id': op.entity_id, 'kind': op.kind, 'revision': revision + 1, 'data': payload, 'deleted': op.deleted if not check else False, 'updated': stamp(), 'author': actor['name']}
                    encoded = json.dumps(value, ensure_ascii=False)
                    if current:
                        con.execute('INSERT INTO history(entity_id,snapshot,at,author) VALUES (?,?,?,?)', (op.entity_id, json.dumps(entity(current), ensure_ascii=False), stamp(), actor['name']))
                    con.execute('INSERT OR REPLACE INTO entities VALUES (?,?,?,?,?,?,?)', (value['id'], value['kind'], value['revision'], json.dumps(payload, ensure_ascii=False), int(value['deleted']), value['updated'], value['author']))
                    con.execute('INSERT INTO changes(entity) VALUES (?)', (encoded,))
                    result = {'id': op.id, 'status': 'applied', 'entity': value}
                con.execute('INSERT INTO operations VALUES (?,?,?,?)', (op.id, actor['id'], fingerprint, json.dumps(result, ensure_ascii=False)))
                results.append(result)
        return {'results': results}

    @api.get('/v1/history/{eid}')
    def history(eid: str, actor=Depends(user)):
        with db() as con:
            return [{'entity': json.loads(x['snapshot']), 'at': x['at'], 'author': x['author']} for x in con.execute('SELECT * FROM history WHERE entity_id=? ORDER BY seq DESC LIMIT 25', (eid,))]

    @api.post('/v1/import')
    def import_recipe(body: ImportText, actor=Depends(user)):
        # Parse supplied structured data only. Never fetch arbitrary URLs on the private server.
        from .importer import extract_recipe
        try:
            return extract_recipe(body.text)
        except ValueError as exc:
            raise HTTPException(422, str(exc))

    @api.post('/v1/translate-recipe')
    def translate(body: TranslateRecipe, actor=Depends(user)):
        validate_data('recipe',body.recipe)
        from .translation import translate_recipe
        try:
            return translate_recipe(body.recipe,body.source,force=body.force)
        except (ValueError,ImportError,RuntimeError) as exc:
            raise HTTPException(422,str(exc) or 'No se pudo traducir la receta; se conserva el original.') from exc

    @api.post('/v1/translation/warm',status_code=202)
    def translation_warm(background:BackgroundTasks,actor=Depends(user)):
        from .quality_translation import available,warm_model
        ready=available()
        if ready:background.add_task(warm_model)
        return {'queued':ready}

    @api.post('/v1/import-url')
    def import_url(body: ImportUrl, actor=Depends(user)):
        from .fetcher import fetch_page
        from .importer import extract_recipe
        try:
            from .catalogs import SOURCES
            from urllib.parse import urlsplit
            matched = next((s for s in SOURCES.values() if urlsplit(body.url).hostname in {urlsplit(s['url']).hostname,*s.get('aliases',[])}), None)
            if matched and matched['mode']=='book':
                raise ValueError('La importación de esta fuente está pendiente de autorización del editor.')
            if matched and matched['id']=='es-encantar':
                if body.provider and body.provider!='es-encantar': raise ValueError('El enlace pertenece a otra fuente.')
                from .encantar import import_recipe
                return import_recipe(body.url)
            if matched and matched['mode']=='asset':
                if body.provider and body.provider != matched['id']: raise ValueError('El enlace pertenece a otra fuente.')
                from .licensed_collections import recipe
                return recipe(matched['id'],body.url)
            if urlsplit(body.url).hostname in {'creativegan.net','www.creativegan.net'}:
                if body.provider and body.provider!='es-creativegan': raise ValueError('El enlace pertenece a otra fuente.')
                from .creativegan import parse_recipe
                page, final = fetch_page(body.url)
                return parse_recipe(page, final)
            if urlsplit(body.url).hostname=='delokos.wordpress.com':
                if body.provider and body.provider!='delokos-es': raise ValueError('El enlace pertenece a otra fuente.')
                from .wordpress_catalog import import_recipe
                return import_recipe(body.url)
            wiki_source = next((s for s in SOURCES.values() if s['id'].startswith('wiki-') and urlsplit(s['url']).hostname == urlsplit(body.url).hostname), None)
            if wiki_source:
                if body.provider and body.provider != wiki_source['id']:
                    raise ValueError('El enlace pertenece a otra fuente.')
                from .open_catalogs import wiki_recipe
                return wiki_recipe(wiki_source,body.url)
            page, source = fetch_page(body.url)
            from .catalogs import SOURCES
            from urllib.parse import urlsplit
            target = urlsplit(source)
            provider = body.provider or next((s['id'] for s in SOURCES.values() if s['mode']=='web'
                        and target.hostname in {urlsplit(s['url']).hostname,*s.get('aliases',[])}
                        and target.path.startswith(urlsplit(s['url']).path.rstrip('/'))), '')
            if provider == 'mx-kiwilimon':
                from .publisher_adapters import kiwilimon_recipe
                result = kiwilimon_recipe(source, page)
            else:
                result = extract_recipe(page, source, language=SOURCES[provider].get('language_code','es') if provider in SOURCES else 'es')
            result['source'] = source
            if provider:
                from .catalogs import publisher_origin
                publisher_origin(result, provider)
            from .photos import hydrate_photos
            hydrate_photos(result, skip_urls=set(body.skip_photos))
            return result
        except (ValueError, OSError, TimeoutError, http.client.HTTPException) as exc:
            raise HTTPException(422, str(exc) or 'No se pudo extraer el enlace. Abre la fuente original y conserva la receta como borrador.') from exc

    @api.get('/v1/catalog/{provider}')
    def catalog(provider: str, q: str = Query(default='', max_length=4000), cursor: str | None = Query(default=None, max_length=80), actor=Depends(user)):
        from .catalogs import publisher_catalog
        try:
            return publisher_catalog(provider, q, cursor)
        except (ValueError, OSError, TimeoutError, http.client.HTTPException) as exc:
            raise HTTPException(422, str(exc) or 'La fuente no permite la consulta automática. Abre el sitio original.') from exc

    @api.get('/v1/source-photo/{provider}/{page}')
    def source_photo(provider: str, page: int, actor=Depends(user)):
        from .licensed_collections import photo
        try:
            return Response(photo(provider,page), media_type='image/jpeg', headers={'Cache-Control':'no-store','X-Content-Type-Options':'nosniff'})
        except (ValueError, OSError, TimeoutError, http.client.HTTPException) as exc:
            raise HTTPException(422, str(exc) or 'No se pudo leer la foto del documento.') from exc

    @api.get('/v1/export')
    def export(actor=Depends(user)):
        result = snapshot(after='', limit=None, epoch='', start_cursor=None, actor=actor)
        return {'format': 'mesa-recetario', 'version': 1, 'exported': stamp(), 'entities': result['entities']}

    @api.post('/v1/backup')
    def backup(actor=Depends(admin)):
        name = make_backup()
        return {'name': name, 'message': 'Copia creada en el ordenador servidor.'}

    return api


app = create_app()


if __name__ == '__main__':
    import uvicorn
    uvicorn.run(app, host='127.0.0.1', port=8765, log_level='info')
