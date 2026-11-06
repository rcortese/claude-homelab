#!/usr/bin/env python3
"""Read-only policy-A selection. No delete API, even with extra CLI flags."""
import datetime as dt
import json
import os
from pathlib import Path
import re
import sys
import generation

UTC = dt.timezone.utc
PATTERN = r'[0-9]{8}T[0-9]{6}Z'

def timestamp(name):
    if not re.fullmatch(PATTERN, name):
        raise ValueError('unexpected generation name')
    return dt.datetime.strptime(name, '%Y%m%dT%H%M%SZ').replace(tzinfo=UTC)

def select(valid, now, latest):
    """One latest point per UTC day, 31 days plus boundary anchor and latest."""
    cutoff = now - dt.timedelta(days=30)
    daily = {}
    for name in sorted(valid, reverse=True):
        instant = timestamp(name)
        if instant > now:
            raise ValueError('future generation')
        daily.setdefault(instant.date(), name)
    keep = set(sorted(daily.values(), reverse=True)[:31])
    anchors = [n for n in valid if timestamp(n) <= cutoff]
    if anchors:
        keep.add(max(anchors))
    keep.add(latest)
    return [{'name': n, 'action': 'protect' if n == latest else 'keep' if n in keep else 'remove-candidate',
             'reason': 'last-published-good' if n == latest else 'daily-or-boundary-anchor' if n in keep else 'outside-policy',
             'deletion_authorized': False} for n in sorted(valid)]

def plan(base, now):
    base = Path(base)
    if not base.is_absolute() or base.is_symlink() or not base.is_dir():
        raise ValueError('unsafe base')
    for part in base.parents:
        if part.is_symlink():
            raise ValueError('symlink ancestor')
    snapshots = base / 'snapshots'
    if snapshots.is_symlink() or not snapshots.is_dir():
        raise ValueError('unsafe snapshots root')
    target = os.readlink(base / 'latest')
    if not re.fullmatch('snapshots/' + PATTERN, target):
        raise ValueError('unsafe latest target')
    latest = target.split('/')[1]
    valid, protected = [], []
    for entry in sorted(snapshots.iterdir()):
        name = entry.name
        try:
            timestamp(name)
            if entry.is_symlink() or not entry.is_dir():
                raise ValueError('unsafe entry')
            # Generation metadata itself must not redirect verification outside.
            meta = entry / '.generation'
            if meta.is_symlink() or not meta.is_dir():
                raise ValueError('legacy or unsafe metadata')
            if any(p.is_symlink() for p in meta.rglob('*')):
                raise ValueError('metadata link')
            generation.verify(entry)
            valid.append(name)
        except (ValueError, OSError, KeyError, TypeError):
            protected.append({'name': name, 'action': 'protect', 'reason': 'legacy-invalid-or-unexpected', 'deletion_authorized': False})
    if latest not in valid:
        raise ValueError('latest is not a verified coherent generation')
    decisions = select(valid, now, latest) + protected
    attempts = base / 'attempts'
    if attempts.is_symlink():
        raise ValueError('unsafe attempts root')
    for entry in sorted(attempts.iterdir()) if attempts.exists() else []:
        decisions.append({'name': 'attempts/' + entry.name, 'action': 'protect', 'reason': 'incomplete-attempt-no-automatic-cleanup', 'deletion_authorized': False})
    return {'schema': 1, 'mode': 'dry-run-only', 'policy': 'A', 'daily_points': 31,
            'horizon_days': 30, 'new_capacity_envelope_gib': 140,
            'last_good': latest, 'verified_generations': len(valid),
            'history_reaches_30_days': any(timestamp(n) <= now - dt.timedelta(days=30) for n in valid),
            'selection': decisions, 'execution_supported': False,
            'limits': 'Whole generation includes snapshot, dump and metadata. Legacy always protected. No cleanup authorization. Coverage and restore not certified.'}

def main():
    if len(sys.argv) != 2:
        raise ValueError('usage: retention.py ABSOLUTE_BACKUP_BASE (dry-run only)')
    print(json.dumps(plan(sys.argv[1], dt.datetime.now(UTC)), sort_keys=True, indent=2))

if __name__ == '__main__':
    main()
