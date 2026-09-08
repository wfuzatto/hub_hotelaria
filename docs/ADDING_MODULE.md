# Adicionando um módulo

Todo complemento novo do Totem/HUB deve nascer desacoplado e pronto para Docker.

## Contrato mínimo

Cada repositório de módulo deve conter:

- `Dockerfile`;
- `.dockerignore`;
- `.env.example` sem segredos;
- endpoint de healthcheck;
- README com API/integração;
- persistência documentada;
- processo único em foreground (PID 1);
- logs em stdout/stderr;
- encerramento gracioso quando aplicável.

## Incorporação

1. Adicione em `modules/modules.list`:

```text
meu_modulo|git@github.com:wfuzatto/meu_modulo.git
```

2. Adicione serviço no `compose.yml`:

```yaml
  meu-modulo:
    build:
      context: ./modules/meu_modulo
    restart: unless-stopped
    expose:
      - "8080"
    networks:
      - backend
    healthcheck:
      test: ["CMD", "...health..."]
```

3. Se precisar ser acessado externamente, crie hostname no `Caddyfile`. **Não use `ports:` no módulo.**

4. Dados persistentes devem usar volume próprio.

5. Se usar banco, crie usuário e permissões exclusivos para o módulo quando ele entrar em produção.

6. Se usar GPU, mantenha um override separado e fallback CPU sempre que tecnicamente possível.
