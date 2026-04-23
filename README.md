# Sistema de Atendimento - Salgaderia

Workflow n8n pronto para produção: WhatsApp → IA → Pedido → Cozinha → Cliente.

## Estrutura

```
.
├── workflows/
│   ├── 01-atendimento-principal.json   ← WhatsApp in/out + IA + pedido
│   ├── 02-status-cozinha.json          ← callback da cozinha
│   └── 03-lembretes-followup.json      ← cron de reengajamento
├── database/
│   └── schema.sql                      ← Postgres/Supabase
├── prompts/
│   └── ai-system-prompt.md             ← "Dona Salgada"
├── docs/
│   ├── arquitetura.md
│   ├── estados.md
│   └── integracoes.md
└── .env.example
```

## Quick start (resumo)

1. Rodar `database/schema.sql` no Postgres/Supabase
2. Subir n8n + Evolution API via Docker Compose
3. Criar credenciais **Postgres Salgaderia** e **OpenAI** no n8n
4. Copiar variáveis do `.env.example` para `Settings > Variables` no n8n
   (inclusive colar o prompt completo em `PROMPT_DONA_SALGADA`)
5. Importar os 3 workflows
6. Ativar os 3 workflows
7. Apontar webhook do Evolution para `…/webhook/salgaderia/whatsapp`

Detalhes completos em `docs/integracoes.md`.

## Diagramas

Ver `docs/arquitetura.md` (arquitetura geral) e `docs/estados.md` (FSM da conversa).

## O que está incluído

- [x] Recepção WhatsApp via Evolution API (webhook)
- [x] Normalização de mensagem + deduplicação (`fromMe`)
- [x] Máquina de estados persistida em Postgres (10 estados)
- [x] AI Agent (OpenAI gpt-4o-mini) com saída JSON estruturada
- [x] Memória conversacional (últimas 12 mensagens por cliente)
- [x] Carrinho e dados parciais em `clientes.contexto` (JSONB)
- [x] Criação de pedido transacional (pedido + reset contexto)
- [x] Envio p/ cozinha via webhook autenticado
- [x] Callback da cozinha atualiza status e notifica cliente
- [x] Lembrete de retirada (10 min após PRONTO, idempotente via `eventos`)
- [x] Reengajamento de clientes parados (> 24h)
- [x] Escalonamento para humano + alerta Slack
- [x] Error Trigger + logs em tabela `eventos`
- [x] Views de apoio (`vw_pedidos_cozinha`, `vw_clientes_inativos_24h`)

## O que NÃO está incluído (melhorias futuras)

- Pagamento Pix dinâmico (PSP) — hoje é estático
- Dashboard operacional (Metabase/Retool apontando no mesmo Postgres)
- Transcrição de áudio (Whisper node antes do AI Agent)
- Multi-atendente (o fluxo HUMANO só flagga; a UI do operador é externa)
- Fidelidade / cashback
