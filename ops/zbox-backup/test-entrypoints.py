#!/usr/bin/env python3
"""Exercise the real shell entrypoints with isolated SSH/Docker transports.

Requires root as the production entrypoint does. Real local rsync/gzip/SQLite;
no real SSH, Docker daemon, systemctl, remote share, secrets or application data.
"""
import importlib.util
import json
import os
from pathlib import Path
import shutil
import sqlite3
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('generation', ROOT / 'generation.py')
assert spec and spec.loader
g = importlib.util.module_from_spec(spec)
spec.loader.exec_module(g)
TRANSPORT = r'''#!/usr/bin/env python3
import os, pathlib, subprocess, sys
name = pathlib.Path(sys.argv[0]).name
fault = os.environ.get('FIXTURE_FAULT', '')
if name == 'ssh':
    cmd = sys.argv[-1]
    if fault in ('seal', 'publish') and ("- '" + fault + "'") in cmd:
        sys.exit(73)
    sys.exit(subprocess.run(['bash', '-c', cmd]).returncode)
elif name == 'rsync':
    args = sys.argv[1:]
    args[-1] = args[-1].split(':', 1)[1]
    if fault == 'capture':
        pathlib.Path(args[-1]).write_bytes(b'incomplete transport')
        sys.exit(74)
    sys.exit(subprocess.run(['/usr/bin/rsync', *args]).returncode)
elif name == 'docker':
    if len(sys.argv) > 2 and sys.argv[1] == 'exec':
        if fault == 'dump-command':
            sys.exit(75)
        if fault == 'dump-invalid':
            print('not SQL, but gzip will succeed')
        else:
            print('-- MariaDB dump 10.19\nCREATE TABLE `proof` (`id` int);\n-- Dump completed on 2026-11-04 00:00:00')
    else:
        print('fixture inventory')
elif name == 'findmnt':
    print('/mnt/user fuse.shfs')
elif name == 'systemctl':
    print('fixture inventory')
else:
    sys.exit(99)
'''


@unittest.skipUnless(os.geteuid() == 0 and shutil.which('rsync'), 'root and local rsync required')
class Entrypoints(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='zbox-entrypoints-')
        self.addCleanup(self.tmp.cleanup)
        self.base = Path(self.tmp.name)
        self.bin = self.base / 'bin'
        self.bin.mkdir()
        for name in ('ssh', 'rsync', 'docker', 'findmnt', 'systemctl'):
            p = self.bin / name
            p.write_text(TRANSPORT)
            p.chmod(0o755)
        self.source = self.base / 'source'
        self.source.mkdir()
        entries = []
        for i, rel in enumerate(g.CRITICAL):
            p = self.source / str(i)
            if rel.endswith('.db'):
                db = sqlite3.connect(p)
                db.execute('CREATE TABLE proof (id INTEGER)')
                db.close()
            else:
                p.write_text('fixture configuration\n')
            entries.append(f'file|{p}|{rel}\n')
        # A real directory exercises the SQLite staging overlay too.
        dbdir = self.source / 'directory'
        dbdir.mkdir()
        db = sqlite3.connect(dbdir / 'more.db')
        db.execute('CREATE TABLE proof (id INTEGER)')
        db.close()
        (dbdir / 'keep.txt').write_text('keep')
        entries.append(f'dir|{dbdir}|directory\n')
        self.paths = self.base / 'paths'
        self.paths.write_text(''.join(entries))
        self.database_env = self.base / 'database.env'
        self.database_env.write_text('MARIADB_DATABASE=fixture\nMARIADB_USER=fixture\nMARIADB_PASSWORD=fixture-not-a-secret\n')
        self.remote = self.base / 'remote'
        old = self.remote / 'snapshots/20000101T000000Z'
        old.mkdir(parents=True)
        (old / 'keep').write_text('known-good')
        (self.remote / 'dumps').mkdir()
        (self.remote / 'dumps/historical.sql.gz').write_bytes(b'historical-do-not-touch')
        os.symlink('snapshots/20000101T000000Z', self.remote / 'latest')
        os.symlink('snapshots/20000101T000000Z', self.remote / 'current')
        self.config = self.base / 'config'
        self.config.write_text(f'''REMOTE_HOST=fixture
REMOTE_USER=fixture
REMOTE_BASE={self.remote}
SSH_KEY_FILE=/nonexistent-fixture-key
SMART_HOME_ENV_FILE={self.database_env}
MARIADB_CONTAINER=fixture
BACKUP_PATHS_FILE={self.paths}
BACKUP_EXCLUDES_FILE={self.base}/excludes
LOCAL_STAGING_ROOT={self.base}/staging
LOCK_FILE={self.base}/lock
''')
        (self.base / 'excludes').write_text('# fixture\n')
        self.env = {**os.environ, 'PATH': str(self.bin) + ':' + os.environ['PATH'], 'CONFIG_FILE': str(self.config), 'PYTHONDONTWRITEBYTECODE': '1'}

    def run_backup(self, fault='', ok=False, args=()):
        result = subprocess.run(['bash', str(ROOT / 'zbox-backup.sh'), *args], env={**self.env, 'FIXTURE_FAULT': fault}, capture_output=True, text=True)
        self.assertEqual(result.returncode == 0, ok, result.stdout + result.stderr)
        self.assertEqual((self.remote / 'dumps/historical.sql.gz').read_bytes(), b'historical-do-not-touch')
        if not ok:
            self.assertEqual(os.readlink(self.remote / 'latest'), 'snapshots/20000101T000000Z')
            self.assertEqual((self.remote / 'current/keep').read_text(), 'known-good')
        return result

    def test_success_and_real_consumer(self):
        self.run_backup(ok=True)
        result = subprocess.run(['bash', str(ROOT / 'zbox-backup-validate.sh')], env=self.env, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        receipt = json.loads((self.remote / 'latest/.generation/manifest.json').read_text())
        self.assertEqual(receipt['checks']['sqlite_databases'], 4)
        self.assertFalse(receipt['restore_tested'])
        self.assertEqual((self.remote / 'latest/directory/keep.txt').read_text(), 'keep')
        # Hash binding is enforced by the actual consumer, not only seal tests.
        (self.remote / 'latest/directory/keep.txt').write_text('tampered')
        result = subprocess.run(['bash', str(ROOT / 'zbox-backup-validate.sh')], env=self.env, capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)

    def test_missing_source(self):
        (self.source / '0').unlink()
        self.run_backup()
        self.assertFalse((self.remote / 'attempts').exists())

    def test_unsafe_manifest_destination(self):
        self.paths.write_text(f'file|{self.source}/0|../escape\n')
        self.run_backup()
        self.assertFalse((self.remote / 'attempts').exists())

    def test_capture_transport_interrupted(self):
        self.run_backup('capture')

    def test_dump_command_fails(self):
        self.run_backup('dump-command')

    def test_dump_valid_gzip_invalid_sql(self):
        self.run_backup('dump-invalid')

    def test_validation_transport_interrupted(self):
        self.run_backup('seal')

    def test_publication_transport_interrupted(self):
        self.run_backup('publish')


if __name__ == '__main__':
    unittest.main(verbosity=2)
