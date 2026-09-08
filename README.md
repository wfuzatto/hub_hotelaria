# HUB Hotelaria — Plataforma Docker

Repositório pai de **infraestrutura e orquestração** do ecossistema hoteleiro.

Produção não depende de XAMPP. O padrão oficial é **Ubuntu + Docker Engine + Docker Compose**. Cada módulo continua em seu próprio repositório e é incorporado ao stack como um serviço isolado e versionado.

## Serviços atuais

- `gateway` — Caddy, único ponto público do stack (`80/443`) e TLS automático.
- `hub-core` — núcleo PHP/Apache do HUB em container, preparado para MySQL.
- `mysql` — banco central do HUB e base para novos módulos; somente rede privada Docker.
- `totem-api` — backend do `totem_autoatendimento`, Node.js 22 LTS, com dados persistidos em volume.
- `face-scanner` — FastAPI/Python, OCR e processamento de documentos; porta `8091` somente interna.
- `backup-helper` — utilitário sob demanda para backup do volume do Totem.

## Arquitetura

```text
Internet
   |
   | 80/443
   v
Caddy gateway
   |
   +---- hub-core:80
   +---- totem-api:3080
   +---- face-scanner:8091
              |
              +---- GPU NVIDIA opcional

mysql:3306  <---- somente rede Docker privada
```

Nenhuma aplicação publica `3080`, `8091` ou `3306` no host. Somente o gateway publica `80/443`.

## Primeiro deploy

Requisitos no host:

- Ubuntu Server;
- Docker Engine + Docker Compose v2;
- Git;
- DNS dos domínios apontando para o servidor;
- para GPU: driver NVIDIA + NVIDIA Container Toolkit.

```bash
git clone git@github.com:wfuzatto/hub_hotelaria.git
cd hub_hotelaria
cp .env.example .env
# edite senhas, domínios e e-mail ACME
./scripts/bootstrap.sh
./scripts/preflight.sh
docker compose up -d --build
```

Com GPU liberada ao `face-scanner`:

```bash
docker compose -f compose.yml -f compose.gpu.yml up -d --build
```

## Atualização de produção

O HUB é o **único ponto de atualização**. O script atualiza o próprio `hub_hotelaria`, posiciona Totem e Face Scanner nos commits homologados de `modules/modules.list`, executa preflight, cria backup pré-update quando o MySQL está saudável, reconstrói os containers e aguarda os healthchecks.

Atualização normal:

```bash
./scripts/update.sh
```

Atualização com override NVIDIA:

```bash
./scripts/update.sh --gpu
```

Se o checkout do HUB estiver muito antigo, use a forma universal:

```bash
git pull --ff-only origin main && chmod +x scripts/*.sh && ./scripts/update.sh
```

## Comandos úteis

```bash
make bootstrap
make up
make up-gpu
make ps
make logs
make health
make backup
make update
make down
```

## Novos módulos

1. O módulo continua em repositório próprio.
2. Adicione o repositório em `modules/modules.list`.
3. Adicione o serviço ao `compose.yml` ou a um override específico.
4. Não publique porta diretamente; use `expose` e o `gateway`.
5. Adicione healthcheck, política de restart e persistência explícita.

Veja `docs/ADDING_MODULE.md`.

## Regras de produção

- nada de XAMPP no servidor;
- nada de `latest` nos componentes de aplicação; versões/digests devem ser controlados;
- banco nunca exposto na Internet;
- segredos ficam em `.env`/secret store, nunca no Git;
- `restart: unless-stopped` em serviços críticos;
- healthcheck em todos os módulos;
- backups fora do servidor são obrigatórios;
- atualização automática de containers é proibida em produção;
- atualização de módulos usa commits explicitamente aprovados;
- rollback é feito por versão/commit, não por edição manual no servidor.

## Desenvolvimento

XAMPP pode continuar temporariamente em alguma estação antiga apenas para compatibilidade, mas **não faz parte da arquitetura oficial**. A direção do projeto é usar Docker também no desenvolvimento para manter o ambiente o mais próximo possível da produção.
