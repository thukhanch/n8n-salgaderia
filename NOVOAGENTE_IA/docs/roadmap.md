# Roadmap

## Próximas tools (prioridade alta)

- `calendar.reschedule` — alterar horário de um appointment existente
- `payment.create_boleto` / `payment.create_card_link` — outros meios MP
- `payment.refund` — estorno
- `contact.search` — busca livre por nome/tel/email (caso o modelo precise
  descobrir que "João" tinha outro registro)
- `whatsapp.send_template` — para mensagens ativas aprovadas (futuro Meta
  Cloud API)
- `knowledge.search` — RAG sobre documentos do tenant (FAQ, políticas).
  Depende de vetor store (pgvector ou Qdrant)

## Canais

- Instagram DM (via Meta Graph API)
- Telegram
- Webchat (widget JS embedável)
- SMS (Zenvia / Infobip)

## Infra

- **pgvector** para RAG: tabela `documents` com embeddings por tenant
- **Redis** como cache de `tenants` e `channels` (hoje é SELECT direto)
- **Observabilidade**: OpenTelemetry → Grafana/Tempo para ver trace de
  cada invocação (channel → router → N tools)
- **Admin UI**: painel simples (Retool / Metabase) para:
  - CRUD de tenants e config JSONB com editor de JSON
  - Ver conversations e tool_calls filtrados
  - Aprovar handoff / retomar atendimento automático

## Robustez

- **Streaming de resposta**: hoje o channel espera a resposta completa;
  para mensagens longas faz sentido streamar partial chunks
- **Retry automático de tools com backoff** quando provedor externo devolve 5xx
- **Dead letter queue** no workflow 10 quando o AI Agent falha
- **Testes**: suite de golden conversations por tenant (arquivo YAML →
  roda contra o agent → compara com regex)

## Billing / comercial

- Tabela `usage` incrementada por `tool_call` e `conversations`:
  fácil cobrar dos tenants por uso real (msg/tool)
- `cost_cents` por tool_call calculado (OpenAI + provider externo)

## IA

- **Suporte a Claude, Gemini, Llama** via node `lmChat*` do n8n
- **Modelo por tenant** (tenant premium usa modelo maior; demo usa
  4o-mini)
- **Function-calling com tools tipadas** (hoje é `toolWorkflow` com
  descrição em texto; ideal seria JSON Schema explícito)
- **Speech-to-text** (áudio WhatsApp → Whisper antes do router)
