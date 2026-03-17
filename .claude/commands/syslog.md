---
description: Conectar ao syslog-ng e ler logs da infraestrutura
allowed-tools: Bash, Read, Grep
---

# Syslog Viewer

**Argumento:** `$ARGUMENTS` pode ser um filtro opcional (host, programa, nível) — ex: `media`, `sshd`, `err`.

Se nenhum argumento, mostra os últimos logs de todos os hosts.

## Container

O syslog-ng roda no `infra-stack`. Nome do container: detectar via:
```
docker ps --filter name=syslog-ng --format '{{.Names}}' | head -1
```

## Comandos por modo

### Últimas 100 linhas (padrão)
```
docker exec <container> tail -100 /var/log/messages
```

### Filtrar por host ou programa
```
docker exec <container> grep -i "<ARGUMENTS>" /var/log/messages | tail -50
```

### Follow ao vivo (máx 30s para não bloquear)
```
timeout 30 docker exec <container> tail -f /var/log/messages
```

### Resumo por host (de onde estão chegando logs)
```
docker exec <container> awk '{print $4}' /var/log/messages | sort | uniq -c | sort -rn | head -20
```

### Resumo por programa
```
docker exec <container> grep -oP '\S+(?=\[\d+\])' /var/log/messages | sort | uniq -c | sort -rn | head -20
```

## Portas de entrada

| Protocolo | Porta | Uso |
|-----------|-------|-----|
| TCP (syslog RFC5424) | 6601 | Encaminhamento confiável |
| UDP (syslog RFC5424) | 5514 | Dispositivos legados |

## Outputs

| Arquivo (dentro do container) | Conteúdo |
|-------------------------------|---------|
| `/var/log/messages` | Todos os logs (formato legível) |
| `/var/log/messages-kv.log` | Todos os logs (formato WELF key=value) |

## Passo a passo

1. Detectar o nome do container syslog-ng
2. Se `$ARGUMENTS` fornecido, usar grep com o filtro
3. Se não, mostrar tail das últimas 100 linhas
4. Apresentar: tabela de hosts ativos + logs relevantes
5. Oferecer follow ao vivo se o usuário quiser

## Relatório final

Formato: tabela `| Host | Programa | Último evento | Volume |` + logs brutos relevantes.
