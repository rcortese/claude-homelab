#!/usr/bin/env python3
import datetime as dt
import importlib.util
import os
from pathlib import Path
import unittest
import retention as r

spec = importlib.util.spec_from_file_location('fixtures', Path(__file__).with_name('test-generation.py'))
assert spec and spec.loader
f = importlib.util.module_from_spec(spec)
spec.loader.exec_module(f)

class Retention(unittest.TestCase):
    def test_daily_anchor_and_last_good_after_long_failure(self):
        now = dt.datetime(2026, 11, 6, tzinfo=r.UTC)
        names = [(now - dt.timedelta(days=i)).strftime('%Y%m%dT%H%M%SZ') for i in range(70)]
        result = r.select(names, now, names[0])
        self.assertEqual(sum(x['action'] != 'remove-candidate' for x in result), 31)
        self.assertEqual(result[-1]['action'], 'protect')
        later = r.select(names, now + dt.timedelta(days=100), names[0])
        self.assertEqual(sum(x['action'] != 'remove-candidate' for x in later), 31)
        self.assertTrue(all(not x['deletion_authorized'] for x in later))

    def test_sparse_anchor_and_duplicate_day(self):
        names = ['20261106T010000Z', '20261106T020000Z', '20260901T000000Z']
        result = {x['name']: x for x in r.select(names, dt.datetime(2026, 11, 6, 3, tzinfo=r.UTC), names[1])}
        self.assertEqual(result[names[0]]['action'], 'remove-candidate')
        self.assertEqual(result[names[2]]['action'], 'keep')

    def test_real_seal_legacy_attempts_links_and_corruption(self):
        fixture = f.Generation()
        fixture.setUp()
        try:
            f.g.seal(fixture.root, fixture.run_id)
            f.g.publish(fixture.base, fixture.run_id)
            snapshot = fixture.base / 'snapshots' / fixture.run_id
            os.symlink('/outside', fixture.base / 'snapshots' / 'unexpected-link')
            (fixture.base / 'attempts' / 'incomplete').mkdir()
            before = f.g.inventory(fixture.base)
            result = r.plan(fixture.base, dt.datetime.now(r.UTC))
            self.assertEqual(before, f.g.inventory(fixture.base))
            self.assertEqual(result['verified_generations'], 1)
            self.assertFalse(result['history_reaches_30_days'])
            self.assertTrue(all(x['action'] == 'protect' for x in result['selection']))
            self.assertEqual(result, r.plan(fixture.base, dt.datetime.now(r.UTC)))
            (snapshot / '.generation/homeassistant.sql.gz').write_bytes(b'corrupt')
            with self.assertRaises(ValueError):
                r.plan(fixture.base, dt.datetime.now(r.UTC))
        finally:
            fixture.doCleanups()

    def test_bad_names_future_and_unsafe_latest(self):
        with self.assertRaises(ValueError):
            r.select(['../../escape'], dt.datetime.now(r.UTC), '../../escape')
        with self.assertRaises(ValueError):
            r.select(['20990101T000000Z'], dt.datetime.now(r.UTC), '20990101T000000Z')

if __name__ == '__main__':
    unittest.main()
