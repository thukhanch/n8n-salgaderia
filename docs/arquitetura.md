# Arquitetura - Sistema de Atendimento Salgaderia

## 1. Visão geral

```
┌──────────┐   Webhook    ┌──────────────┐   SQL   ┌──────────────┐
│ WhatsApp │ ───────────▶ │   n8n 01     │ ──────▶ │  Postgres /  │
│ (cliente)│ ◀─────────── │ Atendimento  │ ◀────── │   Supabase   │
└──────────┘   Evolution  │  Principal   │         └──────────────┘
                          │   + LLM      │                 ▲
                          └──────┬───────┘                 │
                                 │ HTTP POST               │
                                 ▼                         │
                          ┌──────────────┐                 │
                          │   Cozinha    │                 │
                          │ (TV/impr/ERP)│ ──────┐         │
                          └──────┬───────┘       │callback │
                                 │               │POST     │
                                 ▼               ▼         │
                          ┌──────────────────────────┐     │
                          │  n8n 02 Status Cozinha   │─────┘
                          └──────────────────────────┘

                          ┌──────────────────────────┐
                          │ n8n 03 Lembretes (cron)  │────▶ WhatsApp
                          └──────────────────────────┘
```

## 2. Componentes

| Camada          | Tecnologia sugerida                   | Motivo                                  |
|-----------------|---------------------------------------|-----------------------------------------|
| Canal           | Evolution API (WhatsApp não oficial)  | Baixo custo, roda no VPS, sem Meta BSP  |
| Orquestração    | n8n (self-hosted em Docker)           | Workflows visuais, controle total       |
| LLM             | OpenAI gpt-4o-mini                    | Barato (~R$0,01/conversa), JSON mode    |
| Memória/Estado  | Postgres 15 (Supabase free)           | Views, JSONB, triggers                  |
| Cozinha         | Webhook → display web ou ESC/POS      | Desacoplado do n8n                      |
| Observabilidade | Slack webhook + tabela `eventos`      | Alertas + auditoria                     |

## 3. Fluxo de dados

1. Cliente envia mensagem → Evolution API chama webhook do n8n.
2. Workflow 01 normaliza, busca/cria cliente, registra mensagem.
3. AI Agent recebe contexto (estado + carrinho + histórico) e retorna JSON estruturado.
4. Workflow atualiza estado do cliente e, se `acao=CRIAR_PEDIDO`, grava pedido + notifica cozinha.
5. Resposta volta ao cliente via Evolution API.
6. Cozinha atualiza status via Workflow 02 → cliente é notificado automaticamente.
7. Workflow 03 (cron) envia lembretes e reengaja clientes parados.

## 4. Por que essa separação?

- **Workflow 01** é síncrono e rápido (< 3s). Não pode ter polling.
- **Workflow 02** é desacoplado: a cozinha pode demorar horas para atualizar e isso não trava nada.
- **Workflow 03** é idempotente via tabela `eventos` — nunca envia lembrete duplicado.

## 5. Deployment mínimo

- 1 VPS 2 vCPU / 4 GB (Hetzner/Contabo ~R$ 35/mês)
- Docker: `n8n`, `evolution-api`, `postgres` (ou Supabase cloud)
- Traefik/Caddy para TLS
- Backup diário do Postgres para S3/B2
