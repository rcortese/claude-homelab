#!/usr/bin/env python3
"""Stage online SQLite backups and rsync exclusions; never copy live WAL files."""
from contextlib import closing
import os
from pathlib import Path
import shutil
import sqlite3
import sys


def stage(source, destination, excludes):
    source, destination = Path(source), Path(destination)
    destination.mkdir(parents=True, exist_ok=True)
    with open(excludes, 'w') as patterns:
        # Sidecars must never accompany the standalone backup, including newly
        # created databases between discovery and rsync.
        patterns.write('*-wal\n*-shm\n*-journal\n')
        for directory, _, files in os.walk(source):
            for name in sorted(files):
                path = Path(directory) / name
                if path.is_symlink() or not path.is_file():
                    continue
                with path.open('rb') as stream:
                    if stream.read(16) != b'SQLite format 3\x00':
                        continue
                rel = path.relative_to(source)
                target = destination / rel
                target.parent.mkdir(parents=True, exist_ok=True)
                with closing(sqlite3.connect(path.as_uri() + '?mode=ro', uri=True)) as src:
                    with closing(sqlite3.connect(target)) as dst:
                        src.backup(dst)
                        dst.execute('PRAGMA journal_mode=DELETE')
                        result = dst.execute('PRAGMA integrity_check').fetchall()
                        if result != [('ok',)]:
                            raise RuntimeError(f'SQLite integrity failure: {path}')
                shutil.copystat(path, target)
                stat = path.stat()
                os.chown(target, stat.st_uid, stat.st_gid)
                patterns.write('/' + rel.as_posix() + '\n')
                print(f'sqlite_backup={path} integrity=ok', flush=True)
    for directory, _, _ in os.walk(destination):
        target_dir = Path(directory)
        original = source / target_dir.relative_to(destination)
        shutil.copystat(original, target_dir)
        stat = original.stat()
        os.chown(target_dir, stat.st_uid, stat.st_gid)


if __name__ == '__main__':
    stage(*sys.argv[1:])
