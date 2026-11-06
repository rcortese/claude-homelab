#!/usr/bin/env python3
"""Fail-closed generation sealing, verification and single-pointer publication.

Executed on the destination through SSH stdin; no service or database lifecycle.
Only latest is authoritative. No retention or historical migration is performed.
"""
import datetime as dt
import gzip
import hashlib
import json
import os
from pathlib import Path
import re
import sqlite3
import stat
import sys

SCHEMA = 1
CRITICAL_SQLITE = (
    'sentinel/state/sentinel.db',
    'sentinel/runtime/gatus/gatus.db',
    'sentinel/runtime/grafana/grafana.db',
)
CRITICAL = (
    'network-stack/.env',
    'smart-home/config/.env',
    *CRITICAL_SQLITE,
    'smart-home/config/docker-compose.yml',
    'sentinel/shield-v2/operational/source/compose.yaml',
    'sentinel/shield-v2/operational/source/compose.shield-v2.yaml',
    'sentinel/shield-v2/operational/deployment.env',
    'sentinel/shield-v2/operational/egress.compose.yaml',
    'sentinel/shield-v2/operational/shield_v2_egress.py',
    'sentinel/shield-v2/units/shield-v2-egress.service',
    'sentinel/shield-v2/units/shield-v2-start.service',
    'sentinel/shield-v2/units/shield-v2-reconciler.conf',
)


def require(condition, message):
    if not condition:
        raise ValueError(message)


def digest(path):
    h = hashlib.sha256()
    with path.open('rb') as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            h.update(chunk)
    return h.hexdigest()


def relative(value):
    p = Path(value)
    require(value and not p.is_absolute() and '..' not in p.parts and value != '.', 'unsafe manifest path')
    require(p.parts[0] != '.generation', 'reserved manifest destination')
    return p


def inventory(root):
    result = {}
    for directory, dirs, files in os.walk(root, followlinks=False):
        for name in sorted(dirs + files):
            path = Path(directory) / name
            rel = path.relative_to(root).as_posix()
            if rel == '.generation/manifest.json':
                continue
            s = path.lstat()
            item = {'mode': stat.S_IMODE(s.st_mode), 'uid': s.st_uid, 'gid': s.st_gid}
            if stat.S_ISLNK(s.st_mode):
                item.update(type='symlink', target=os.readlink(path))
            elif stat.S_ISREG(s.st_mode):
                item.update(type='file', size=s.st_size, sha256=digest(path))
            elif stat.S_ISDIR(s.st_mode):
                item.update(type='dir')
            else:
                raise ValueError('unsupported special file in generation')
            result[rel] = item
    return result


def validate_dump(path):
    # Streaming structural validation, explicitly NOT a successful SQL import.
    start = b''
    tail = b''
    has_schema = False
    size = 0
    with gzip.GzipFile(filename=path, mode='rb') as stream:
        for line in stream:
            if len(start) < 4096:
                start += line[:4096 - len(start)]
            has_schema |= line.startswith(b'CREATE TABLE ')
            tail = (tail + line)[-4096:]
            size += len(line)
    require((b'-- MariaDB dump' in start or b'-- MySQL dump' in start)
            and has_schema and b'-- Dump completed on ' in tail,
            'dump structural validation failed')
    return {'compressed_sha256': digest(path), 'sql_bytes': size, 'validation': 'gzip-and-sql-structure', 'restore_tested': False}


def validate_sqlite(path):
    require(path.is_file() and not path.is_symlink(), 'missing regular SQLite database')
    # Expected databases must never become generic files by losing their magic.
    with path.open('rb') as stream:
        require(stream.read(16) == b'SQLite format 3\x00', 'invalid SQLite database header')
    db = sqlite3.connect(path.resolve().as_uri() + '?mode=ro&immutable=1', uri=True)
    try:
        require(db.execute('PRAGMA integrity_check').fetchall() == [('ok',)], 'SQLite integrity failure')
    finally:
        db.close()


def checks(root):
    metadata = root / '.generation'
    for line in (metadata / 'backup-paths.txt').read_text().splitlines():
        if not line or line.startswith('#'):
            continue
        kind, source, dest = line.split('|')
        p = root / relative(dest)
        require(kind in ('file', 'dir'), 'invalid manifest kind')
        require(p.is_file() if kind == 'file' else p.is_dir(), 'missing manifest destination')
    for rel in CRITICAL:
        p = root / rel
        require(p.is_file() and p.stat().st_size > 0, 'missing critical artifact')
    # Validate the copied standalone DBs, not live sources or user rows.
    for rel in CRITICAL_SQLITE:
        validate_sqlite(root / rel)
    db_count = len(CRITICAL_SQLITE)
    for directory, _, files in os.walk(root, followlinks=False):
        for name in files:
            p = Path(directory) / name
            if p.is_symlink() or not p.is_file():
                continue
            if p.relative_to(root).as_posix() in CRITICAL_SQLITE:
                continue
            with p.open('rb') as stream:
                header = stream.read(16)
            if header == b'SQLite format 3\x00':
                validate_sqlite(p)
                db_count += 1
    return {'sqlite_databases': db_count, 'dump': validate_dump(metadata / 'homeassistant.sql.gz')}


def seal(root, run):
    require(root.name == run, 'generation identity mismatch')
    meta = root / '.generation'
    require(not (meta / 'manifest.json').exists(), 'generation already sealed')
    provenance = json.loads((meta / 'capture.json').read_text())
    require(provenance['run_ts'] == run, 'capture identity mismatch')
    receipt = {'schema': SCHEMA, 'run_ts': run, 'status': 'valid',
               'restore_tested': False, 'capture': provenance, 'checks': checks(root),
               'sealed_at': dt.datetime.now(dt.timezone.utc).isoformat(), 'files': inventory(root)}
    with (meta / 'manifest.json').open('x') as stream:
        json.dump(receipt, stream, sort_keys=True)
        stream.flush()
        os.fsync(stream.fileno())
    return receipt


def verify(root):
    receipt = json.loads((root / '.generation/manifest.json').read_text())
    require(receipt['schema'] == SCHEMA and receipt['status'] == 'valid'
            and receipt['run_ts'] == root.name, 'invalid generation identity')
    require(receipt['files'] == inventory(root), 'generation inventory mismatch')
    require(receipt['checks'] == checks(root), 'generation validation mismatch')
    return receipt


def atomic_link(root, name, target, run):
    p = root / ('.' + name + '.' + run + '.partial')
    os.symlink(target, p)
    os.replace(p, root / name)


def publish(base, run):
    attempt = base / 'attempts' / run
    final = base / 'snapshots' / run
    require(not final.exists(), 'generation already exists; reconcile before retry')
    verify(attempt)
    (base / 'snapshots').mkdir(exist_ok=True)
    # Same-filesystem atomic rename is mandatory. EXDEV fails closed.
    os.rename(attempt, final)
    # Legacy current becomes an alias of latest before the single commit point.
    # Until latest changes it still resolves to the previous known good snapshot.
    atomic_link(base, 'current', 'latest', run)
    atomic_link(base, 'latest', 'snapshots/' + run, run)
    # No fallible side effect after the commit point. Orphaned valid snapshots
    # from interrupted publication can be inspected; never auto-delete them.


def main(argv):
    action, base_arg, run = argv
    require(re.fullmatch(r'[0-9]{8}T[0-9]{6}Z', run) is not None, 'invalid run id')
    base = Path(base_arg)
    require(base.is_absolute(), 'backup base must be absolute')
    if action == 'seal':
        seal(base / 'attempts' / run, run)
    elif action == 'publish':
        publish(base, run)
    elif action == 'verify':
        verify(base / 'snapshots' / run)
    elif action == 'latest':
        require(os.readlink(base / 'latest') == 'snapshots/' + run, 'latest identity mismatch')
        receipt = verify(base / 'snapshots' / run)
        captured = dt.datetime.strptime(receipt['run_ts'], '%Y%m%dT%H%M%SZ').replace(tzinfo=dt.timezone.utc)
        age = (dt.datetime.now(dt.timezone.utc) - captured).total_seconds()
        require(0 <= age <= 26 * 3600, 'valid generation is stale or future-dated')
    else:
        raise ValueError('invalid action')
    print('generation_' + action + '=ok restore_tested=false')


if __name__ == '__main__':
    try:
        main(sys.argv[1:])
    except Exception as exc:
        # Do not expose secrets, SQL content or raw sensitive paths on failure.
        detail = ': ' + str(exc) if type(exc) is ValueError else ''
        print('generation_failed=' + type(exc).__name__ + detail, file=sys.stderr)
        sys.exit(1)
