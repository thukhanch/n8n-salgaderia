# Migration Artifacts

Este diretório contém o material histórico e operacional da migração e desenvolvimento do projeto.

## O que é

Registros da transição do `whatsapp-flow` legado para o `n8n-salgaderia` autossuficiente.
Não é parte do produto final, mas está preservado para consulta e auditoria.

## Estrutura

```
migration-artifacts/
├── bridge-reference/           ← cópia parcial do whatsapp-flow antigo (fase 1)
├── bridge-runtime/             ← runtime experimental da bridge internalizada
├── database/
│   └── compat_patch_*.sql       ← patch de compatibilidade com banco legado
└── workflows/
    ├── _api_*                  ← variante com chamada direta (não usada)
    ├── _create_*               ← tentativa de criar via API (não usada)
    └── _import_*               ← exportação de importação (não usada)
```

## O que importa lembrar

- O produto final roda com `workflows/01..08` e `baileys-service/`
- A bridge Baileys do produto está em `baileys-service/`, não em `bridge-runtime/`
- Os artefatos `_api_*`, `_create_*`, `_import_*` eram tentativas de workaround de import
- `bridge-runtime/` contém a tentativa de runtime próprio da bridge, mas foi suspensa em favor do `baileys-service/` que já funciona