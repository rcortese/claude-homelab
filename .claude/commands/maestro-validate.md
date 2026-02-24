---
description: Run the homelab-maestro validation pipeline (structure, env sync, compose, quality)
allowed-tools: Bash, Read
---

# Maestro Validation Pipeline

Run the full validation suite for homelab-maestro.

## Quick mode (default)
```
cd /srv/homelab/homelab-maestro
./scripts/check_all.sh 2>&1 | tail -30
```

This runs in order:
1. `check_structure.sh` — repo directory/file layout
2. `check_env_sync.sh` — env file chain consistency
3. `validate_env_output.sh` — env variable output validation
4. `validate_compose.sh` — `docker compose config` for all instances

## With quality checks
If the user asks for full/thorough validation:
```
cd /srv/homelab/homelab-maestro
./scripts/check_all.sh --with-quality-checks 2>&1 | tail -50
```

This additionally runs:
- `pytest` smoke tests
- `shfmt` format check
- `shellcheck` lint
- `checkbashisms` compliance

## Individual checks (if isolating a failure)

| Check | Command |
|-------|---------|
| Structure | `./scripts/check_structure.sh 2>&1 \| tail -15` |
| Env sync | `./scripts/check_env_sync.sh 2>&1 \| tail -15` |
| Compose | `./scripts/validate_compose.sh 2>&1 \| tail -15` |
| Health | `./scripts/check_health.sh core 2>&1 \| tail -20` |
| Quality | `./scripts/run_quality_checks.sh 2>&1 \| tail -20` |

## Report
Table format: `| Check | Status | Details |`

If any check fails, show the relevant error output and suggest a fix.
