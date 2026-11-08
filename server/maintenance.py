"""Offline-only backup restore. Close clients and stop the server before invoking."""
from pathlib import Path
from contextlib import closing
import argparse
import os
import socket
import sqlite3
import uuid
from datetime import datetime

def restore(backup: Path, root: Path):
    backup = backup.resolve(strict=True)
    root = root.resolve(strict=True)
    target = root / 'recetario.sqlite'
    if backup == target:
        raise ValueError('Elige una copia, no la base de datos activa.')
    # Refuse a running default server. This command restores only this installation.
    with socket.socket() as probe:
        if probe.connect_ex(('127.0.0.1',8765)) == 0:
            raise ValueError('Detén el servidor de Mesa antes de restaurar.')
    with closing(sqlite3.connect(backup.as_uri()+'?mode=ro',uri=True)) as source:
        if source.execute('PRAGMA integrity_check').fetchone()[0] != 'ok':
            raise ValueError('La copia no pasa la comprobación de integridad.')
        tables = {row[0] for row in source.execute("SELECT name FROM sqlite_master WHERE type='table'")}
        if not {'entities','users','changes','operations','history','meta','invites'} <= tables:
            raise ValueError('La copia no pertenece al servidor de Mesa.')
        safety = root / 'backups' / ('antes-restaurar-' + datetime.now().strftime('%Y%m%d-%H%M%S') + '.sqlite')
        safety.parent.mkdir(exist_ok=True)
        if target.exists():
            with closing(sqlite3.connect(target)) as current, closing(sqlite3.connect(safety)) as dest:
                current.backup(dest)
                current.execute('PRAGMA wal_checkpoint(TRUNCATE)')
        staged = root / 'restore-staged.sqlite'
        with closing(sqlite3.connect(staged)) as dest:
            source.backup(dest)
            dest.execute("UPDATE meta SET value=? WHERE key='generation'",(str(uuid.uuid4()),))
            # Old operation receipts must not acknowledge data removed by the restore.
            dest.execute('DELETE FROM operations')
            dest.commit()
        for suffix in ('-wal','-shm'):
            (root / ('recetario.sqlite'+suffix)).unlink(missing_ok=True)
        os.replace(staged,target)
    return safety

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description='Restaurar una copia de Mesa con el servidor detenido.')
    parser.add_argument('backup',type=Path)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1] / 'data'
    print('Copia previa conservada en:',restore(args.backup,root))
