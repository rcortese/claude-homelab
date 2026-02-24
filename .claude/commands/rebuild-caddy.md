---
description: Rebuild Caddy with Cloudflare DNS module from updated base images
allowed-tools: Bash, Read
---

Rebuild the custom Caddy image (with cloudflare-dns module) in network-stack.

## Context
Caddy uses a custom Dockerfile (`caddy-cloudflare.Dockerfile`) that compiles the `caddy-dns/cloudflare` module via xcaddy. It must be **built**, not pulled.

## Step 1: Pull fresh base images
```
cd /srv/homelab/network-stack
docker pull caddy:2-builder 2>&1 | tail -3
docker pull caddy:2 2>&1 | tail -3
```

## Step 2: Build with no cache
```
docker compose -f docker-compose.zbox.yml build --no-cache caddy 2>&1 | tail -10
```

## Step 3: Validate config before deploying
```
docker compose -f docker-compose.zbox.yml run --rm caddy caddy validate --config /etc/caddy/Caddyfile 2>&1 | tail -5
```
If validation fails, **stop** and show the error. Do not recreate.

## Step 4: Recreate container
```
docker compose -f docker-compose.zbox.yml up -d caddy 2>&1 | tail -5
```

## Step 5: Verify
```
docker compose -f docker-compose.zbox.yml ps caddy --format table
docker compose -f docker-compose.zbox.yml logs caddy --tail 10
```

Report success/failure with Caddy version from logs.
