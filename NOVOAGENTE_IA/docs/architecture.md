# Arquitetura

## Visão geral

```
                     ┌───────────────────┐
                     │  Canais externos  │
                     │  WhatsApp · Gmail │
                     └─────────┬─────────┘
                               │ inbound
                    ┌──────────▼──────────┐
                    │  Channel Workflows  │  (01, 02)
                    │  - resolve tenant   │
                    │  - upsert contact   │
                    │  - call router      │
                    └──────────┬──────────┘
                               │
                    ┌──────────▼──────────┐
                    │  10 Agent Router    │
                    │  ┌────────────────┐ │
                    │  │    AI Agent    │ │
                    │  │  (LangChain)   │ │
                    │  └───┬─────────┬──┘ │
                    │      │ tools   │    │
                    │  ┌───▼──┐   ┌──▼─┐  │
                    │  │ 20-60│   │ ...│  │
                    │  └──────┘   └────┘  │
                    └──────────┬──────────┘
                               │
                    ┌──────────▼──────────┐
                    │    PostgreSQL       │
                    │  tenants, contacts, │
                    │  appointments, ...  │
                    └─────────────────────┘

        Crons (70, 71)  ──→ agem sobre os mesmos dados
        Webhooks (42)   ──→ recebem callbacks de APIs externas
```

## Princípios

1. **Multi-tenant nativo**. Toda linha tem `tenant_id`. Um n8n atende N clientes.
2. **Tools-first**. O agente é um AI Agent com ferramentas plugáveis; não há
   `switch/case` de intenção. O modelo decide qual tool chamar. Adicionar feature
   nova = criar uma tool nova, não reescrever o fluxo.
3. **Tenant config em JSONB**. Cada cliente especializa o universal via
   `tenants.config` (prompt_extra, horários, produtos, tools habilitadas,
   tokens próprios de integração).
4. **Contrato padrão de tools**. Toda tool aceita `{tenant_id, contact_id, ...}`
   e devolve `{ok, data?, error?}`. Log em `tool_calls`.
5. **Canal-agnóstico**. O Agent Router não sabe se veio de WhatsApp ou Gmail —
   só `message`. A resposta é entregue pelo mesmo canal que trouxe.
6. **Idempotência nas ações externas**. `X-Idempotency-Key` no MP. `UNIQUE`
   onde fizer sentido. Retry seguro.

## Fluxo de uma mensagem

1. **Cliente → WhatsApp/Gmail** → Baileys/Gmail Trigger
2. **Channel workflow** (01/02):
   - Resolve `tenant_id` via tabela `channels`
   - Upsert `contact` no tenant
   - Chama `10 Agent Router` com `{tenant_id, contact_id, channel, message}`
3. **Agent Router**:
   - Carrega tenant (prompt + tools habilitadas)
   - Carrega contato e últimas 12 msgs
   - Interpola o system prompt
   - Roda AI Agent com tools registradas
   - Modelo pode chamar 0, 1 ou N tools antes de responder
   - Loga mensagem do agente em `conversations`
   - Retorna `{reply}` para o channel workflow
4. **Channel workflow** entrega a reply no mesmo canal

## Por que tools em vez de switch hardcoded?

Comparado ao padrão "receba msg → if intent=X → faz Y", o padrão
**tool-calling** tem:

- **Flexibilidade**: o modelo escolhe a sequência ("preciso chamar
  check_availability antes de book"). Você não precisa hardcodar isso.
- **Composição**: "agendar consulta E mandar e-mail de confirmação E criar
  deal" em um único turno — três tools chamadas em sequência.
- **Observabilidade**: `tool_calls` vira um log linha-a-linha do que o
  agente fez, útil para debug e billing.
- **Reuso cross-tenant**: a mesma tool `calendar.book` serve clínica,
  barbearia, imobiliária — muda só o prompt e o calendar_id.

## Onde customizar por cliente

| Mudança                              | Onde                                          |
|--------------------------------------|-----------------------------------------------|
| Persona / tom de voz                 | `tenants.config.prompt_extra`                 |
| Horários                             | `tenants.config.business_hours`               |
| Catálogo / preços                    | `tenants.config.products`                     |
| Quais tools o agente pode usar       | `tenants.config.tools_enabled`                |
| Credenciais próprias (MP, calendar)  | `tenants.config.mp_access_token`, `calendar_id` |
| Canal de handoff humano              | `tenants.config.handoff_channel` (URL Slack)  |
| Integração nova específica           | Criar tool `9X-tool-xxx.json` e habilitar     |

Nada disso mexe no core. Um novo cliente = 1 linha em `tenants` + 1 linha
em `channels` + OAuth do Google + QR do WhatsApp.
