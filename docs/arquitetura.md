# Arquitetura v2 - Sistema de Atendimento Salgaderia

## 1. Visão geral

```
                                     ┌──────────────────────────┐
                                     │   Google Calendar        │
                                     └───────────▲──────────────┘
                                                 │ evento
┌──────────┐  POST   ┌──────────┐   webhook     │              ┌──────────────┐
│ Cliente  │◀──────▶│ Baileys  │──────────────▶│  n8n 01      │◀────▶ OpenAI │
│ WhatsApp │         │ service  │               │ Atendimento  │      └────────┘
└──────────┘         └─────▲────┘               │ + AI Agent   │
                           │ /send-text         └──────┬───────┘
                           │                           │ SQL
                           │                           ▼
                           │                    ┌──────────────┐
                           │                    │  PostgreSQL  │
                           │                    └──────▲───────┘
                           │                           │
                           │     ┌─────────────────────┼──────────────────┐
                           │     │                     │                  │
                     ┌─────┴─────┴────┐  ┌─────────────┴──┐     ┌────────┴───────┐
                     │   n8n 04       │  │   n8n 06       │     │   n8n 02       │
                     │  MercadoPago   │  │  Impressora    │     │  Status Cozinha│
                     │  Pix (IPN)     │  │  Térmica       │     │  (callback)    │
                     └─────▲──────────┘  └─────┬──────────┘     └────┬───────────┘
                           │ webhook            │ POST /print         │
                     ┌─────┴──────┐       ┌─────┴────────┐      ┌─────┴──────────┐
                     │MercadoPago │       │ Printer svc  │      │   n8n 05       │
                     │            │       │ ESC/POS      │      │   Motoboy      │
                     └────────────┘       └──────────────┘      │(Lalamove/Uber) │
                                                                └─────▲──────────┘
                                                                      │ webhook
                                                                ┌─────┴──────────┐
                                                                │ Lalamove/Uber  │
                                                                └────────────────┘

                     ┌────────────────┐   ┌────────────────┐
                     │   n8n 03       │   │   n8n 07       │
                     │  Lembretes     │   │  Google Cal    │
                     │  (cron)        │   │  (agenda)      │
                     └────────────────┘   └────────────────┘

                     ┌────────────────┐
                     │   n8n 08       │
                     │  Features      │
                     │  futuras       │
                     └────────────────┘
```

## 2. Componentes

| Camada          | Tecnologia                            | Motivo                                    |
|-----------------|---------------------------------------|-------------------------------------------|
| WhatsApp        | **Baileys** (Node.js) self-hosted     | Grátis, sem taxa, controle total          |
| Orquestração    | n8n self-hosted                       | Workflows visuais                         |
| LLM             | OpenAI-compatible API (JSON mode)     | Flexível: OpenAI ou gateway local         |
| Estado/Dados    | **PostgreSQL 15**                     | JSONB, triggers, views                    |
| Pagamento       | **Mercado Pago** (Pix dinâmico)       | API madura, taxa baixa, IPN confiável     |
| Entrega         | **Lalamove / Uber Direct / Loggi**    | APIs públicas, tracking automático        |
| Cozinha física  | **Impressora térmica** (ESC/POS)      | Workflow padrão food service              |
| Agenda          | **Google Calendar** API               | Dona já usa no celular                    |
| Observabilidade | Webhook operacional + tabelas `eventos`/`pagamentos` | Alertas + auditoria |

## 3. Serviços Docker

Ver `docker-compose.yml`:
- `postgres` — banco
- `n8n` — orquestrador
- `baileys` — bridge WhatsApp
- `printer` — bridge ESC/POS

Recursos sugeridos:
- VPS 2 vCPU / 4 GB RAM (Hetzner/Contabo ~R$ 35/mês) para os 3 primeiros
- `printer` RODA NA LOJA (conectado à rede local da impressora)

## 4. Fluxo de pedido completo

1. Cliente manda "oi" → Baileys → **Workflow 01**
2. AI Agent coleta itens, endereço, pagamento
3. Cria pedido no Postgres → dispara **em paralelo**:
   - **04 Mercado Pago** cria QR Pix (se pix) e manda pro cliente
   - **06 Impressora** imprime comanda na cozinha
   - **07 Calendar** cria evento na agenda da dona
4. MP confirma pagamento → status `PAGO` → notifica cliente e cozinha
5. Cozinha toca "pronto" → **Workflow 02**:
   - Se `retirada` → só avisa cliente
   - Se `entrega` → **Workflow 05** chama motoboy + envia link de rastreio
6. Motoboy entrega → webhook → status `ENTREGUE` → cliente recebe agradecimento

## 5. Princípios de design

- **Sub-workflows isolados** (`Execute Workflow`): cada integração em seu arquivo, testável e descartável
- **Idempotência**: `X-Idempotency-Key` em MP, `UNIQUE` em `motoboy_order_id`, retry seguro na impressora
- **Auditoria**: toda mudança importante gera linha em `eventos`
- **Graceful degradation**: se MP cair, pedido continua (só não tem Pix); se impressora cair, cozinha vê pelo display; se motoboy falhar, Slack alerta humano
- **Zero segredo em código**: tudo em `.env` e n8n Variables
