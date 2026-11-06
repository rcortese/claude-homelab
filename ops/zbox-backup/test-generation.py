#!/usr/bin/env python3
"""Isolated producer/consumer contract tests. No production endpoints or data.

Seams: capture entrypoint, generation seal/publish CLI, freshness consumer.
Failure injection uses transport fixtures or OS-call interception in child tests,
never a production fault-injection switch. SQL fixtures are synthetic, not imports.
"""
import datetime as dt
import gzip
import importlib.util
import json
import os
from pathlib import Path
import signal
import sqlite3
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('generation', ROOT / 'generation.py')
assert spec and spec.loader
g = importlib.util.module_from_spec(spec)
spec.loader.exec_module(g)
SQL = b'-- MariaDB dump 10.19\nCREATE TABLE `proof` (`id` int);\n-- Dump completed on 2026-11-04 00:00:00\n'


class Generation(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='zbox-generation-')
        self.addCleanup(self.tmp.cleanup)
        self.base = Path(self.tmp.name)
        self.run_id = dt.datetime.now(dt.timezone.utc).strftime('%Y%m%dT%H%M%SZ')
        self.root = self.base / 'attempts' / self.run_id
        self.meta = self.root / '.generation'
        self.meta.mkdir(parents=True)
        for rel in g.CRITICAL:
            p = self.root / rel
            p.parent.mkdir(parents=True, exist_ok=True)
            if rel.endswith('.db'):
                db = sqlite3.connect(p)
                db.execute('CREATE TABLE proof (id INTEGER)')
                db.close()
            else:
                p.write_text('synthetic fixture\n')
        (self.meta / 'backup-paths.txt').write_text('file|/synthetic/source|smart-home/config/docker-compose.yml\n')
        (self.meta / 'backup-excludes.txt').write_text('# synthetic\n')
        (self.meta / 'capture.json').write_text(json.dumps({'run_ts': self.run_id, 'producer_commit': 'fixture'}))
        (self.meta / 'report.txt').write_text('synthetic receipt\n')
        (self.meta / 'status.txt').write_text('status=captured-pending-validation\n')
        self.dump(SQL)
        old = self.base / 'snapshots' / '20000101T000000Z'
        old.mkdir(parents=True)
        (old / 'known-good').write_bytes(b'keep this exact reference and bytes')
        os.symlink('snapshots/20000101T000000Z', self.base / 'latest')
        os.symlink('snapshots/20000101T000000Z', self.base / 'current')

    def dump(self, data):
        with gzip.open(self.meta / 'homeassistant.sql.gz', 'wb') as stream:
            stream.write(data)

    def cli(self, action, ok=True):
        result = subprocess.run([sys.executable, str(ROOT / 'generation.py'), action, str(self.base), self.run_id], capture_output=True, text=True)
        self.assertEqual(result.returncode == 0, ok, result.stderr)
        return result

    def old_good(self):
        self.assertEqual(os.readlink(self.base / 'latest'), 'snapshots/20000101T000000Z')
        self.assertEqual((self.base / 'latest/known-good').read_bytes(), b'keep this exact reference and bytes')
        self.assertEqual((self.base / 'current/known-good').read_bytes(), b'keep this exact reference and bytes')

    def test_coherent_publication_and_consumer(self):
        self.cli('seal')
        self.cli('publish')
        self.cli('latest')
        self.assertEqual(os.readlink(self.base / 'current'), 'latest')
        receipt = json.loads((self.base / 'latest/.generation/manifest.json').read_text())
        self.assertEqual(receipt['status'], 'valid')
        self.assertFalse(receipt['restore_tested'])
        self.assertFalse(receipt['checks']['dump']['restore_tested'])
        self.assertTrue((self.base / 'snapshots/20000101T000000Z/known-good').exists())
        self.assertFalse(self.root.exists())

    def test_missing_required_destination(self):
        (self.root / 'smart-home/config/docker-compose.yml').unlink()
        self.cli('seal', False)
        self.cli('publish', False)
        self.old_good()

    def test_operational_vector_not_obsolete_promotion(self):
        self.assertFalse((self.root / 'sentinel/promotions').exists())
        self.cli('seal')
        (self.root / 'sentinel/shield-v2/operational/source/compose.shield-v2.yaml').unlink()
        self.cli('publish', False)
        self.old_good()

    def test_valid_gzip_not_sql(self):
        self.dump(b'valid gzip but not a SQL dump\n')
        self.cli('seal', False)
        self.old_good()

    def test_truncated_sql(self):
        self.dump(SQL.split(b'-- Dump completed on')[0])
        self.cli('seal', False)
        self.old_good()

    def test_corrupt_gzip(self):
        p = self.meta / 'homeassistant.sql.gz'
        p.write_bytes(p.read_bytes()[:-8])
        self.cli('seal', False)
        self.old_good()

    def test_corrupt_sqlite(self):
        p = self.root / 'sentinel/state/sentinel.db'
        p.write_bytes(b'SQLite format 3\x00' + b'corrupt' * 40)
        self.cli('seal', False)
        self.old_good()

    def reject_invalid_required_sqlite(self, payload):
        # Literal expected paths form an oracle independent of magic discovery.
        for rel in ('sentinel/state/sentinel.db',
                    'sentinel/runtime/gatus/gatus.db',
                    'sentinel/runtime/grafana/grafana.db'):
            with self.subTest(database=rel):
                case = Generation(methodName='runTest')
                case.setUp()
                try:
                    (case.root / rel).write_bytes(payload)
                    case.cli('seal', False)
                    case.cli('publish', False)
                    case.old_good()
                    self.assertFalse((case.meta / 'manifest.json').exists())
                finally:
                    case.doCleanups()

    def test_required_sqlite_invalid_header(self):
        self.reject_invalid_required_sqlite(b'not a SQLite database; corrupted header\n')

    def test_required_sqlite_truncated_header(self):
        self.reject_invalid_required_sqlite(b'SQLite')

    def corrupt_sealed_required_sqlite(self, root):
        # Model a structurally hash-consistent receipt from the old faulty
        # producer. The semantic oracle must reject the expected DB type too.
        (root / 'sentinel/state/sentinel.db').write_bytes(b'corrupted header\n')
        manifest = root / '.generation/manifest.json'
        receipt = json.loads(manifest.read_text())
        receipt['files'] = g.inventory(root)
        receipt['checks']['sqlite_databases'] = 2
        manifest.write_text(json.dumps(receipt))

    def test_publish_rechecks_required_sqlite_type(self):
        self.cli('seal')
        self.corrupt_sealed_required_sqlite(self.root)
        self.cli('publish', False)
        self.old_good()

    def test_consumer_rechecks_required_sqlite_type(self):
        self.cli('seal')
        self.cli('publish')
        self.corrupt_sealed_required_sqlite(self.base / 'snapshots' / self.run_id)
        self.cli('latest', False)

    def test_tamper_after_validation(self):
        self.cli('seal')
        (self.meta / 'report.txt').write_text('tampered')
        self.cli('publish', False)
        self.old_good()

    def test_capture_interrupted_no_seal(self):
        self.cli('publish', False)
        self.old_good()

    def interrupted_child(self, phase):
        # SIGKILL the actual helper subprocess at a named OS boundary. The
        # production module has no test hooks and must preserve old references.
        code = '''
import importlib.util, os, signal, sys
from pathlib import Path
spec = importlib.util.spec_from_file_location('g', sys.argv[1])
g = importlib.util.module_from_spec(spec); spec.loader.exec_module(g)
phase = sys.argv[4]
if phase == 'validation':
    original = g.digest
    def stop(path):
        os.kill(os.getpid(), signal.SIGKILL)
    g.digest = stop
    g.seal(Path(sys.argv[2]) / 'attempts' / sys.argv[3], sys.argv[3])
else:
    original = g.os.replace
    def stop(src, dest):
        if Path(dest).name == phase:
            os.kill(os.getpid(), signal.SIGKILL)
        return original(src, dest)
    g.os.replace = stop
    g.publish(Path(sys.argv[2]), sys.argv[3])
'''
        result = subprocess.run([sys.executable, '-c', code, str(ROOT / 'generation.py'), str(self.base), self.run_id, phase])
        self.assertEqual(result.returncode, -signal.SIGKILL)
        self.old_good()

    def test_kill_during_validation(self):
        self.interrupted_child('validation')

    def test_kill_after_rename_before_current(self):
        self.cli('seal')
        self.interrupted_child('current')
        self.cli('verify')

    def test_kill_before_latest_commit(self):
        self.cli('seal')
        self.interrupted_child('latest')
        self.cli('verify')

    def test_stale_not_refreshed_by_directory_mtime(self):
        old_run = '20010101T000000Z'
        (self.meta / 'capture.json').write_text(json.dumps({'run_ts': old_run}))
        old_root = self.root.with_name(old_run)
        self.root.rename(old_root)
        self.run_id, self.root = old_run, old_root
        self.cli('seal')
        self.cli('publish')
        os.utime(self.base / 'latest', None)
        self.cli('latest', False)

    def test_cli_rejects_invalid_identity(self):
        self.run_id = '../escape'
        self.cli('publish', False)
        self.old_good()


if __name__ == '__main__':
    unittest.main(verbosity=2)
