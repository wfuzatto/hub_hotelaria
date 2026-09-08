# Deploy de produção

## Host

Instale somente o necessário no host:

- Ubuntu Server;
- Docker Engine / Compose;
- Git;
- SSH;
- driver NVIDIA e NVIDIA Container Toolkit quando houver GPU.

Não instalar XAMPP, PHP, MySQL, Python, Node ou Tesseract diretamente no host para atender os serviços do stack.

## Fluxo

```bash
git clone git@github.com:wfuzatto/hub_hotelaria.git
cd hub_hotelaria
cp .env.example .env
nano .env
./scripts/bootstrap.sh
./scripts/preflight.sh
make up
```

Para GPU:

```bash
make up-gpu
```

## Firewall

Externamente, libere somente o estritamente necessário:

- TCP 80 — ACME/redirecionamento;
- TCP 443 — HTTPS;
- UDP 443 — HTTP/3 opcional;
- SSH — preferencialmente restrito por IP/VPN.

Não liberar 3080, 3306 ou 8091.

## Atualização

Nunca editar arquivos dentro do container.

```bash
make backup
make update
make health
```

Se uma versão de aplicação causar regressão, volte o repositório do módulo ao commit/tag aprovado, reconstrua e suba novamente.

## Backup

`make backup` gera dump MySQL e arquivo do volume persistente do Totem em `backups/`. Produção deve copiar estes arquivos para armazenamento externo ao servidor.
