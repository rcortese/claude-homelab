# Generation protocol (TAC-551 candidate; not activated)

Base: operational commit `049d10bbda84652e521be310e8b249fd6b9dbcf3`, a descendant of origin/main `199b2127876557449246b81445c39ebfe0045613` when prepared. Runtime owns `/srv/homelab/ops/zbox-backup`; the service and validator units point there. This source candidate is not an installation receipt. Existing host edits to BACKUP-SCOPE.md and RESTORE.md must remain untouched.

## Scope and states

The existing selection and exclusions are unchanged. This fixes publication of that selection; it does not resolve the coverage gaps, retention decision, bootstrap custody or TSDB/MQTT consistency described in TAC-550. No new secrets, targets, timers, notification paths or services are introduced.

1. `attempts/<UTC-run>/` is exclusively allocated before capture. A failed attempt cannot overwrite an older attempt or snapshot. Local staging is allocated only after taking the existing exclusive host lock.
2. Files and online SQLite backups go inside the attempt. All SQLite databases discovered in copied regular files are checked again on the destination. The logical MariaDB dump belongs inside `.generation/homeassistant.sql.gz`, not a separately expiring dump family.
3. `.generation/` also contains the frozen source/exclusion manifests, capture identity, producer commit and script hashes, and reports. `status.txt` says `captured-pending-validation`, not published success.
4. The destination helper requires the selected destinations and nonempty critical files, including the current Shield operational Compose/env/egress/unit vector rather than the obsolete historical promotion. It validates the gzip stream and SQL header/schema/completion marker, standalone SQLite integrity, and inventories file SHA-256/size/mode/UID/GID, directory metadata and symlink targets. A structurally valid SQL dump is NOT a proven SQL import or application restore.
5. Successful seal creates `.generation/manifest.json` with `status=valid`, `restore_tested=false`. The publisher verifies the sealed inventory and checks again. An attempt with no valid seal never promotes.
6. `os.rename(attempt, snapshots/<run>)` must succeed atomically on the target filesystem; EXDEV fails closed. `current` becomes an atomic symlink alias of `latest` while latest still refers to the previous generation. One `os.replace` of `latest` is the commit point. Before it, both references resolve to the previous latest; after it, both resolve to the new coherent set. Previous generations are never mutated or deleted.
7. A kill after the directory rename but before latest leaves an unreferenced valid snapshot, not a published success. Inspect and reconcile before retry; the publisher refuses to overwrite it. A connection loss at the final commit is ambiguous: read latest and verify the exact run; do not rerun blindly.

Only `latest` is authoritative. The helper's immutable valid receipt is the validation result; publication is established by reference readback, not by the capture report. Restore testing is a separate receipt bound to the same generation and does not edit its sealed manifest.

## Consumer changes and retention boundary

The companion `zbox-backup-validate.sh` reads the captured latest identity, then invokes the helper to validate the self-contained generation. Freshness uses the UTC capture ID (26h maximum, future IDs rejected), never directory mtime. A concurrent publication may cause a conservative validation failure; it must not make a bad generation look healthy.

Global legacy `reports/zbox-backup-latest.txt`, timestamped reports and the old independent `dumps/` family are no longer updated by the new producer. They remain untouched historical evidence. Operators must use `latest/.generation/report.txt`, `latest/.generation/manifest.json` and the updated validator together. External readers of the old global report, if any, must be reconciled before activation; do not infer their absence from tests.

There is deliberately NO pruning in this candidate: neither historical snapshots/dumps nor new attempts are deleted automatically. SNAPSHOT_KEEP and DUMP_RETENTION_DAYS are not applied by this producer. The next retention delivery must operate on whole sealed sets, protect latest, require approved policy and preserve historical material unless its exact targets are authorized. Until that delivery, failed attempts and generations accumulate; storage remains an explicit operational limit, not an approved unlimited retention policy.

## Tests and assurance limits

Run `python3 test-generation.py` for isolated generation CLI tests. Run `python3 test-backup.py` and `python3 test-entrypoints.py` as root in an isolated test workspace with local rsync; fixtures replace SSH, Docker, systemctl and findmnt, and never contact production. The entrypoint suite runs real rsync/gzip/SQLite, synthetic SQL, both producer and consumer, and transport failures. The helper suite SIGKILLs actual child processes at validation and publication boundaries. All fixtures are synthetic; no service lifecycle is exercised.

Process interruption atomicity is not a claim of power-loss durability, cross-service transactionality or tamper-proof/immutable storage against a privileged adversary. SHA-256 here detects drift, not malicious replacement of both payload and manifest. Live Prometheus/MQTT/BoltDB capture semantics remain as before, explicitly not certified application-consistent. No new encryption is introduced: existing selection still contains sensitive plaintext in the existing private destination. Full restore, coverage, retention and operator alert delivery belong to their applicable acceptance gates.

## Activation and recovery (requires explicit human authorization)

Before changing the live source: verify base/allowed-path hashes and preservation of unrelated edits; inventory actual readers of the producer/validator/report layout; confirm Python3/SQLite and atomic rename on the destination; preserve exact preimages outside the lost-disk boundary; reconcile source remote and runtime paths. Install only reviewed allowlisted files, paired producer/helper/validator, without unit/timer edits or lifecycle changes. Do not copy fixtures into service paths unless their inclusion is explicitly part of source synchronization.

Run the authorized producer once and read back exact latest target, helper verification, manifest identity/checks/dump binding and consumer output. If the call loses its acknowledgement, reconcile before any retry. This proves a new valid generation only at the stated validation level, not restored recovery.

For recovery from a bad candidate before successful publication, restore exact source preimages and keep prior latest. If new latest already committed, preserve the new generation and reconcile the generation/layout consumer; never roll back by deleting backup data. Restoring an old producer also restores its unsafe automatic prune and obsolete requirement: do not execute it as a recovery shortcut. A deployment recovery instruction must explicitly fence scheduled execution without guessing authorization to stop/change timers. If that is required, obtain the specific lifecycle authorization first. No such action is performed by preparing this candidate.
