"""Bounded, content-addressed translation text cache in Mesa's private data folder."""
import hashlib
import json
import os
from pathlib import Path
import sqlite3
import time
from contextlib import closing

ROOT=Path(__file__).resolve().parents[1]
PATH=Path(os.environ.get('RECETARIO_DATA',ROOT/'data'))/'translation-cache.sqlite'
MAX_ENTRIES=256
MAX_RESULT_BYTES=250_000
TTL=30*86400

def key(texts,source,model):
    # A changed implementation or model manifest invalidates previous translations.
    engine=hashlib.sha256((ROOT/'server/quality_translation.py').read_bytes()+(ROOT/'server/translation.py').read_bytes()+(ROOT/'client/assets/translation/culinary-glossary.json').read_bytes()).hexdigest()
    try:manifest=json.loads((ROOT/'.tools/translation/translategemma.json').read_text(encoding='utf-8-sig')).get('manifest_sha256','')
    except (OSError,ValueError):manifest=''
    return hashlib.sha256(json.dumps([2,engine,manifest,source,model,texts],ensure_ascii=False).encode()).hexdigest()

def connect():
    PATH.parent.mkdir(parents=True,exist_ok=True)
    con=sqlite3.connect(PATH,timeout=2)
    con.execute('CREATE TABLE IF NOT EXISTS translations (key TEXT PRIMARY KEY,payload TEXT NOT NULL,touched REAL NOT NULL)')
    return con

def read(cache_key,texts):
    try:
        with closing(connect()) as con,con:
            row=con.execute('SELECT payload,touched FROM translations WHERE key=?',(cache_key,)).fetchone()
            if not row:return None
            if time.time()-row[1]>TTL:
                con.execute('DELETE FROM translations WHERE key=?',(cache_key,));return None
            result=json.loads(row[0])
            if not isinstance(result,list) or len(result)!=len(texts) or any(not isinstance(t,str) or (not t.strip() and original.strip()) or (not original.strip() and t!=original) for original,t in zip(texts,result)):return None
            from .translation import restore_numbers
            for original,translated in zip(texts,result):restore_numbers(original,translated)
            con.execute('UPDATE translations SET touched=? WHERE key=?',(time.time(),cache_key))
            return tuple(result)
    except (OSError,sqlite3.Error,ValueError):return None

def write(cache_key,texts,result):
    try:
        from .translation import restore_numbers
        if len(texts)!=len(result):return
        for original,translated in zip(texts,result):restore_numbers(original,translated)
        payload=json.dumps(result,ensure_ascii=False)
        if len(payload.encode())>MAX_RESULT_BYTES:return
        with closing(connect()) as con,con:
            con.execute('INSERT OR REPLACE INTO translations VALUES (?,?,?)',(cache_key,payload,time.time()))
            con.execute('DELETE FROM translations WHERE key IN (SELECT key FROM translations ORDER BY touched DESC LIMIT -1 OFFSET ?)',(MAX_ENTRIES,))
    except (OSError,sqlite3.Error,ValueError):pass
