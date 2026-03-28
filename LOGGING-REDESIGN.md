# Docker Logging Redesign

## Decision

Host-wide Docker logging policy:

- `log-driver: local`
- `log-opts.max-size: "10m"`

Compose files no longer declare `logging:` for the active stacks unless a service needs an exception later.

## Why

- A single-host homelab benefits more from one daemon policy than from repeating the same logging block in every stack.
- `local` is a better operational default than `json-file` here:
  - rotation enabled by default
  - compressed rotated logs
  - lower disk overhead
- `docker logs` still works normally
- The previous host default was `json-file` with `10m/3`, so leaving logging undefined in Compose would not preserve the current container behavior.

## Panel Summary

The panel argued both sides before the rollout:

- host-wide won on long-term simplicity, drift reduction, and alignment with Docker guidance
- per-stack won on immediate safety and lower rollout cost

This pass chose host-wide because the rollout was explicitly approved, including Docker restart and container recreation. That resolves the policy split instead of documenting it indefinitely.

## Current Target State

### Host

`/etc/docker/daemon.json`:

```json
{
  "log-driver": "local",
  "log-opts": {
    "max-size": "10m"
  }
}
```

### Active stacks

- `network-stack`
- `infra-stack`
- `smart-home-stack`
- `homelab-maestro`

All inherit the host default unless they declare a service-specific exception in the future.

## Safe Compose Cleanup

The cleanup applied in this pass removes only settings that became redundant after the host policy moved to the daemon:

- `logging.driver: local`
- `logging.options.max-size: "10m"`
- `logging.options.max-file: "5"`

Additional no-op cleanup also applied where it matched Docker defaults exactly:

- `healthcheck.interval: 30s`
- `healthcheck.retries: 3`

Not removed:

- restart policies
- ports
- hostnames
- container names
- network settings
- healthcheck fields that still change runtime

## Operational Notes

- Docker daemon defaults apply only to newly created containers.
- After changing `daemon.json`, containers must be recreated to inherit the new logging driver.
- Existing `docker logs` workflows remain valid.
- Direct tooling that reads Docker log files from disk must not assume `json-file` layout anymore.

## Centralized Logging

This redesign does not put `syslog-ng` back into the container startup path.

Preferred long-term shape:

1. Keep application containers on daemon-default `local`.
2. Run an asynchronous collector that tails Docker logs from the host.
3. Enrich and route logs without blocking container startup.

Candidate collectors:

- `vector`
- `fluent-bit`

## Sources

- https://docs.docker.com/engine/logging/configure/
- https://docs.docker.com/engine/logging/drivers/local/
- https://docs.docker.com/engine/logging/drivers/json-file/
- https://docs.docker.com/reference/dockerfile/#healthcheck
