# Arquitetura

## Princípios

1. Um serviço por responsabilidade.
2. Apenas o gateway publica portas no host.
3. Persistência sempre em volume explícito.
4. Healthcheck obrigatório.
5. Reinício automático obrigatório.
6. Nenhum segredo no Git.
7. O Totem deve continuar operando em contingência quando um módulo opcional estiver degradado.
8. GPU é aceleração, não dependência: o stack base sobe sem NVIDIA.

## Redes

- `edge`: gateway.
- `backend`: comunicação entre serviços.

O MySQL não possui `ports`, somente `expose`, portanto não é acessível diretamente da Internet.

## Dados

- `mysql_data`: banco HUB.
- `totem_data`: SQLite, uploads, branding e print jobs atuais do Totem.
- `caddy_data`/`caddy_config`: certificados e estado do gateway.

A migração do SQLite do Totem para MySQL será uma mudança separada, depois de testes específicos. Containerização e troca de banco não devem ser feitas no mesmo passo de produção.

## GPU

`compose.yml` é CPU-safe. `compose.gpu.yml` libera NVIDIA ao `face-scanner`. A aplicação deve implementar fallback para CPU antes de GPU se tornar requisito de produção.
