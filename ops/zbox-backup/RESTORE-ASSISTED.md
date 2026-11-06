# Reconstrução assistida do zbox e ensaio isolado

Escopo: perda do disco do zbox, MEDIA disponível. Este roteiro não autoriza lifecycle de produção, substituição de dados, novos acessos, exclusões ou mudanças de custódia. Recuperação real exige a autorização aplicável. Nunca executar Compose restaurado em produção como teste.

## Disponibilidade independente e seleção

Este arquivo vive no repositório privado `rcortese/claude-homelab`, em `ops/zbox-backup/RESTORE-ASSISTED.md`; o relatório também está no documento `restore-evidence` da TAC-553 no Paperclip. Ambos podem ser obtidos sem o disco do zbox, por principal já autorizado. O acesso Moss ao MEDIA foi exercitado pelo endpoint direto 10.18.19.2, não por DNS fornecido pelo zbox. Isso não demonstra acesso humano independente nem sobrevivência das credenciais de todos os operadores.

O payload fica no MEDIA em `/mnt/user/backups/zbox`. `latest` é apenas seleção inicial: fixar o nome de geração, conferir `.generation/manifest.json`, status, inventário e associação do dump. Usar o dump interno `.generation/homeassistant.sql.gz` da mesma geração; não selecionar o dump externo mais recente separadamente. Não misturar vetores Shield de gerações diferentes.

Exemplo efetivamente utilizado, pela conexão SSH Moss já provisionada:

```sh
ssh -F /opt/data/.ssh/config media readlink -f /mnt/user/backups/zbox/latest
```

Resultado observado: `/mnt/user/backups/zbox/snapshots/20261106T063111Z`.

O helper `generation.py` verifica inventário, hashes e bancos conforme seu contrato. Recuperá-lo da versão identificada, não executar produtor antigo ou prune. A seleção de retenção é passiva; não contém executor destrutivo. O histórico ainda não alcança 30 dias coerentes.

## Sequência para perda real — procedimento, não execução certificada

1. Disponibilizar disco/OS compatível, console e conectividade LAN. Reinstalar SSH e Docker/Compose. Não depender de Pi-hole, WireGuard ou túneis no disco perdido para acessar MEDIA. Confirmar identidade do host por canal já autorizado; não desativar verificação de host SSH.
2. Obter este roteiro, fonte de tooling e fontes dos stacks por acesso privado independente. Conferir commits e alterações efetivas necessárias; Git não contém automaticamente dirty/untracked, secrets, builds locais ou imagens. Não restaurar cegamente containers a partir de inventário de nomes.
3. Selecionar geração coerente no MEDIA e verificar seus insumos. Preparar destino privado novo, preservando UID/GID/modos. Manter origem somente leitura. Corrigir caminhos de restauração conforme `backup-paths.txt`, não copiar o layout inteiro do snapshot sobre `/srv/homelab`.
4. Recuperar bootstrap do host, rede, mounts, units e credenciais necessárias por custódia autorizada. Confirmar CIFS real de `//media.lan/home-assistant` antes de habilitar export/file-mover; ausência de mount não pode virar escrita silenciosa em disco local. Não inventar credenciais ou regenerar identidades.
5. Preparar rede/ingress e dependências sem habilitar túnel, DDNS, ACME, automações ou notificações incidentalmente. Configurações network ficam em `network-stack/`; config infra em `infra-stack/config/`, Portainer em `infra-stack/portainer/`.
6. Restaurar MariaDB por import lógico em banco vazio compatível. Restaurar HA de `smart-home/homeassistant/` e configuração de `smart-home/config/`; só habilitar HA depois de reconciliar banco/config e efeitos externos. MQTT exige estado/config correspondentes. O ensaio abaixo não valida HA end-to-end nem MQTT.
7. Restaurar Sentinel: `sentinel/config/` para config canônica; `sentinel/state/` para state; `sentinel/runtime/{grafana,gatus,alertmanager}/` para data correspondentes; `sentinel/metrics/prometheus/` para TSDB. Shield requer vetor operacional, private/state/units da MESMA geração, além de guard e referências resolvidas. Não iniciar reconciler ou coletores antes de conferir efeitos e autorização.
8. Testar DNS/ingress, banco/histórico, aplicações e mounts; habilitar automações e observabilidade por último. Restaurar timers só a partir das units corretas, depois de conferir fonte, destino, ausência de poda implícita e autorização. Registrar idade da geração, tempo real de recuperação e lacunas antes de declarar retomada.

## Ensaio real em 2026-11-06

Geração: `20261106T063111Z`, status valid, selada `2026-11-06T06:36:17.708992+00:00`. Produtor registrado `9ce5dd49c5faa2a65d725df8023fb5529bb182ba`; retenção/runtime posteriormente em `e5f0d9c16b436c57e6b9270949452c2e223e5781`. O código de geração não mudou entre esses estados. O ensaio não criou outra geração.

Identidades verificadas no MEDIA:

| Insumo | SHA-256 | Bytes |
|---|---|---:|
| `.generation/manifest.json` | `7a0056bf9bdeb3664b82ec3f54674628db099579441aeea170604b7ecba74421` | não usado como medida de cobertura |
| `.generation/homeassistant.sql.gz` | `dcfcb1db011a3374a75f8f1794db25141522c4d34c0fecaba0ddae8f2a44ceb2` | 12429478 |
| `sentinel/runtime/grafana/grafana.db` | `0c2837bb6a9af43f6221a7126cbb98664134290841222d9fbad3bd1dbae5baad` | 3215360 |

Amostra escolhida pela matriz de cobertura: dump lógico HA/MariaDB, SQLite/Grafana e outras bases selecionadas, DNS Pi-hole e persistência não-SQLite Prometheus. Cópias adicionais de WireGuard e vetor Shield foram verificadas por presença/hash, sem ativação. Dados foram transportados por tar via SSH diretamente MEDIA → cópia privada no zbox; nenhum payload sensível foi enviado ao board ou ao Git. O ensaio de runtime usou o zbox como executor, não como origem dos dados recuperados.

Isolamento: containers descartáveis `tac553-*`, `--pull=never`, `--network none`, sem publicação de portas, memória/CPU/PIDs limitados, apenas bind de cópias isoladas. Nenhum socket Docker, diretório live ou configuração de integração de produção foi montado nos containers. Não foi carregado Compose de produção. Grafana iniciou com banco recuperado e sem provisioning/datasources externos montados; Prometheus com `scrape_configs: []`. Consultas de saúde/DNS ocorreram por `docker exec` dentro do namespace isolado. Inspeção confirmou NetworkMode=none e ausência de PortBindings.

| Componente | Uso funcional e resultado real | Limite |
|---|---|---|
| MariaDB | Import em diretório de dados novo; `mariadb-check` exit 0; 13 tabelas, 65538 states, 7514 events, 585148 statistics; consulta MAX(last_updated_ts)=1793946875.350372 | Sem HA UI, integrações ou transação coordenada cross-service |
| Grafana | SQLite integrity=ok; 1 usuário, 6 datasources e 0 dashboards no banco recuperado; `/api/health` database=ok, versão 13.2.3 | Sem login humano ou consulta real a datasources; não alegar dashboards recuperados quando contagem é zero |
| SQLite complementar | 17 bancos na amostra estendida passaram integrity_check e consulta de schema | Não equivale a abertura funcional de Gatus/Sentinel/LibreSpeed |
| Pi-hole | Processo recuperado respondeu consulta `dig @127.0.0.1 pi.hole +short` | Não testou upstream, resolução pública, DHCP ou rede real |
| Prometheus | TSDB recuperada pronta; 16 blocos; query histórica agregada retornou 10709 séries | Uma cópia live abriu nesta geração; não prova captura app-consistente nem toda série/horizonte |
| WireGuard / Shield | 7 configs WireGuard e arquivos operacionais Shield presentes; amostra hash-bound | Não ativados; não testados túnel, render completo, private/state, reconciler ou peers |

Comandos centrais realmente exercitados (omitidos argumentos de construção do sandbox e saída sensível):

```sh
# Dentro do container MariaDB isolado, nunca no container mariadb de produção:
mariadb -uroot -e 'CREATE DATABASE IF NOT EXISTS homeassistant'
# gzip descomprimido pelo executor foi enviado por stdin a:
mariadb -uroot homeassistant
mariadb-check -uroot homeassistant
# Dentro dos containers respectivos:
wget -qO- http://127.0.0.1:3000/api/health
dig @127.0.0.1 pi.hole +short
wget -qO- http://127.0.0.1:9090/-/ready
```

Imagem MariaDB `sha256:10731763b027649b7cbcbcf76e8c35a0f4f4240475473839e122ea5f19de29a1`; Grafana `sha256:fe28f8795cacedcab7a315750dc2ad6bb6f7b63ac720525cb76b15b6647a28c4`; Pi-hole `sha256:c3c5f5b1ba1fdadb0095bc3985ff3de599fd51317b8d5efe6001f9d704723e80`; Prometheus `sha256:66416213a3b43651d3521acc3987277b4f97ad0ae29acc581f910ef9bd3959bd`. São IDs de imagens locais usadas, não garantia de disponibilidade futura no registry nem arquivos de imagem independentes.

A primeira tentativa do harness falhou na etapa de import (exit 1, sem erro SQL preservado); sua causa exata não ficou demonstrada. A inspeção do harness revelou readiness insuficiente: ping do MariaDB podia aceitar o servidor temporário de inicialização. O teste foi corrigido para aguardar mariadbd/mysqld como PID 1 e ping antes do import; repetido com diretório mysql novo. Resultado final: import 162,826 s; campanha MariaDB/Grafana 198,875 s; campanha estendida 122,374 s. Soma de execução bem-sucedida 321,249 s, excluindo transferência, preparação, diagnóstico e reinstalação. 155 arquivos copiados foram comparados ao manifesto antes da campanha estendida; Grafana já aberto na primeira campanha foi excluído dessa comparação e teve origem verificada separadamente. Containers preexistentes permaneceram em execução com mesmos IDs na comparação feita na campanha MariaDB/Grafana; isso não é uma auditoria global de não interferência.

## RPO, RTO e insumos pendentes

Às 12:35:45 UTC a geração tinha 6,076 horas; maior timestamp de states recuperado corresponde a 06:34:35 UTC. O timestamp nominal marca início de captura, não transação única: o dado pode ser alguns minutos posterior. Isso é uma observação pontual, não cumprimento contínuo de RPO 72h. Ainda não há 30 dias de gerações coerentes demonstrados.

Retomada assistida no mesmo dia é tecnicamente plausível para os componentes amostrados, condicionada a disco/OS, acesso independente, bootstrap, imagens/receitas e dados cobertos. NÃO é um RTO integral demonstrado. O ensaio não reinstalou OS, não simulou perda física do host nem utilizou executor substituto.

Lacunas para integração da frente: `RESTORE-QUICKSTART.md` citado no guia antigo estava ausente no MEDIA; este roteiro e o documento do board substituem a dependência documental, sem instalação no destino. O snapshot não fornece por si só bootstrap integral de `/etc`, rede/SSH, credencial CIFS, tooling/units completos, builds locais ou fontes efetivas dirty/untracked. A custódia mínima e decisões de novos segredos pertencem à frente mãe; não copiar novos segredos nem presumir aprovação de criptografia/destino. Não é necessário ampliar acesso ou mudar tecnologia para registrar esta limitação.

Não testados funcionalmente: HA UI/automações, MQTT, Portainer/BoltDB, Alertmanager, Gatus/Sentinel/LibreSpeed como aplicações, ingress/Caddy/ACME, WireGuard/túneis/DDNS, vetor Shield completo, logging, builds, recuperação das identidades e bootstrap. Não há certificação de reconstrução integral ou de dados omitidos. Nenhum lifecycle de produção, timer, limpeza do acervo ou notificação foi executado neste ensaio.
