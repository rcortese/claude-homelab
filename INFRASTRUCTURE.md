# Homelab Infrastructure Reference

> Cross-stack topology, port inventory, integration points, security, and DR. Stack-specific details live in each stack's `CLAUDE.md`.

---

## Network Topology

```
ISP Router
  │
  └─ 10.18.19.1 (gateway)
       │
       ├─ 10.18.19.2  unraid (media server)
       ├─ 10.18.19.3  zbox   (primary compute)
       │
       ├─ 10.18.19.11 wireguard  (macvlan, zbox/ens1)
       ├─ 10.18.19.12 pihole     (macvlan, zbox/ens1)
       ├─ 10.18.19.13 pihole     (macvlan, unraid/eth0)
       │
       └─ 10.18.19.99 host-macvlan bridge (zbox route to containers)
```

| Subnet | CIDR | Purpose |
|--------|------|---------|
| Home LAN | `10.18.19.0/24` | Physical hosts + macvlan containers |
| WireGuard VPN | `10.13.13.0/24` | VPN tunnel clients |
| Docker bridge | `172.17.0.0/16` | Standard container networking |

---

## Service Dependency Graph

```
                    ┌─────────────────────────────────────────────┐
                    │              network-stack                   │
                    │  pihole ◄── cloudflared (upstream DoH)      │
                    │  wireguard (host mode, independent)         │
                    │  caddy ──► zbox.lan:5678 (reverse proxy)    │
                    │  cloudflare-ddns (independent)              │
                    └──────────────────┬──────────────────────────┘
                                       │ DNS for all containers
                    ┌──────────────────▼──────────────────────────┐
                    │            homelab-maestro                   │
                    │  postgres ◄── n8n, adminer                  │
                    │  redis ◄── n8n                              │
                    │  n8n ──► webhook: diun notifications        │
                    │       ──► SSH: unraid management            │
                    │       ──► git: workflow backup              │
                    └──────────────────┬──────────────────────────┘
                                       │ monitors all stacks
                    ┌──────────────────▼──────────────────────────┐
                    │            smart-home-stack                  │
                    │  mariadb ◄── homeassistant (recorder)       │
                    │  mosquitto ◄── homeassistant (MQTT)         │
                    │  deconz ◄── homeassistant (Zigbee)          │
                    │  homeassistant ──► file-mover (export)      │
                    │                ──► unraid (SSH commands)    │
                    └─────────────────────────────────────────────┘

                    ┌─────────────────────────────────────────────┐
                    │              infra-stack                     │
                    │  portainer (independent, manages Docker)    │
                    │  librespeed (independent, speed tests)      │
                    │  syslog-ng (independent, log collection)    │
                    │  diun ──► n8n webhook (image update alerts) │
                    └─────────────────────────────────────────────┘
```

---

## Cross-Stack Integration Points

| Source | Target | Mechanism | Purpose |
|--------|--------|-----------|---------|
| Diun (infra) | n8n (maestro) | Webhook `POST /webhook/diun-updates` | Image update notifications |
| Caddy (network) | n8n (maestro) | Reverse proxy to `zbox.lan:5678` | External HTTPS access |
| VPN clients | Pi-hole (network) | DNS queries to `10.18.19.12/13` | Ad-blocked DNS over VPN |
| n8n (maestro) | All stacks | SSH + HTTP probes | Health monitoring (Moss) |
| n8n (maestro) | homelab-n8n-workflows | Bind mount + git | Workflow version control |
| HA (smart-home) | Unraid | SSH shell commands | VM/Docker management |
| Pi-hole (network) | *.rodolflix.com | Local CNAME | Service discovery on LAN |
| Cloudflare DDNS | ISP | HTTP API | Dynamic DNS updates (every 5m) |

---

## Shared Environment Variables

| Variable | infra | network | smart-home | maestro | Purpose |
|----------|-------|---------|------------|---------|---------|
| `TZ` | America/Sao_Paulo | America/Sao_Paulo | America/Sao_Paulo | America/Sao_Paulo | Timezone |
| `PUID` | 1000 | 1000 (zbox) / 99 (unraid) | -- | 1000 | Container UID |
| `PGID` | 1002 | 1002 (zbox) / 100 (unraid) | -- | 1000 | Container GID |

Stack-specific variables: see each stack's `CLAUDE.md`.

---

## Security Posture

### Privileged Access

| Service | Stack | Mode | Risk |
|---------|-------|------|------|
| Portainer | infra-stack | r/w Docker socket | **High** |
| Diun | infra-stack | r/w Docker socket | Medium |
| Home Assistant | smart-home-stack | `privileged: true` | High |
| WireGuard | network-stack | `NET_ADMIN`, `SYS_MODULE` | Medium |
| Pi-hole | network-stack | `NET_ADMIN` | Low |

### Credential Locations

| Secret | Location |
|--------|----------|
| Cloudflare API/tunnel tokens | `network-stack/.env` |
| Pi-hole web password | `network-stack/.env` |
| MariaDB passwords | `smart-home-stack/.env` |
| n8n encryption key | `homelab-maestro/env/local/core.env` |
| PostgreSQL/Redis passwords | `homelab-maestro/env/local/common.env` |
| WireGuard private keys | `network-stack/wireguard/` |
| Camera RTSP credentials | `smart-home-stack/.env` |

### Open Concerns

1. Mosquitto MQTT: anonymous, no TLS
2. Adminer (8080): no access controls beyond DB creds
3. Syslog-ng: no auth, log injection risk
4. All services bind `0.0.0.0`: no host firewall documented

---

Startup order and backup data: use `/update-stacks` and `/backup` skills.
