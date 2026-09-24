#!/usr/bin/env python3
"""Isolated real-WAL and missing-required-source regression checks."""
import importlib.util
import os
from pathlib import Path
import sqlite3
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('sqlite_backup', ROOT / 'sqlite-backup.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
with tempfile.TemporaryDirectory(prefix='zbox-backup-test-') as temp:
    temp = Path(temp)
    src, dst = temp / 'source', temp / 'copy'
    src.mkdir(mode=0o750)
    db = src / 'wal.db'
    with sqlite3.connect(db) as live:
        live.execute('PRAGMA journal_mode=WAL')
        live.execute('PRAGMA wal_autocheckpoint=0')
        live.execute('CREATE TABLE proof (value TEXT)')
        live.execute("INSERT INTO proof VALUES ('committed WAL row')")
        live.commit()
        assert Path(str(db) + '-wal').stat().st_size > 0
        (src / 'portainer.db').write_bytes(b'not a SQLite database')
        module.stage(src, dst, temp / 'excludes')
        with sqlite3.connect(dst / 'wal.db') as restored:
            assert restored.execute('PRAGMA integrity_check').fetchall() == [('ok',)]
            assert restored.execute('SELECT value FROM proof').fetchall() == [('committed WAL row',)]
        assert not (dst / 'wal.db-wal').exists()
        assert not (dst / 'portainer.db').exists()
        assert '/wal.db\n' in (temp / 'excludes').read_text()
        assert dst.stat().st_mode == src.stat().st_mode
    print('PASS: real WAL data, integrity, sidecar exclusion, non-SQLite preservation, directory mode')
    manifest = temp / 'paths'
    config = temp / 'config'
    config.write_text(f'REMOTE_HOST=unused\nREMOTE_USER=unused\nREMOTE_BASE=/unused\nSSH_KEY_FILE=/unused\nSMART_HOME_ENV_FILE={config}\nMARIADB_CONTAINER=unused\nBACKUP_PATHS_FILE={manifest}\n')
    for kind in ('file', 'dir'):
        manifest.write_text(f'{kind}|{temp}/missing|required\n')
        result = subprocess.run(['bash', str(ROOT / 'zbox-backup.sh'), '--check-sources'], env={**os.environ, 'CONFIG_FILE': str(config)}, capture_output=True, text=True)
        assert result.returncode != 0 and f'missing required {kind}:' in result.stderr, result
        print(f'PASS: missing required {kind} fails closed')
    manifest.write_text(f'dir|{src}|source\n')
    result = subprocess.run(['bash', str(ROOT / 'zbox-backup.sh'), '--check-sources'], env={**os.environ, 'CONFIG_FILE': str(config)}, capture_output=True, text=True)
    assert result.returncode == 0 and 'required sources ok' in result.stdout, result
    print('PASS: existing required source succeeds')
