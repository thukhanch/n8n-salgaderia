# Salgaderia — Sistema completo de automação (n8n + IA + WhatsApp)

Sistema de produção para salgaderia com atendimento automatizado via WhatsApp,
pagamento Pix, entrega com motoboy, impressão em cozinha e agenda integrada.

## Stack

- **n8n** (orquestração) — 8 workflows importáveis
- **Baileys** (WhatsApp) — microserviço Node.js próprio
- **PostgreSQL** — estado, pedidos, conversas, pagamentos, entregas, auditoria
- **OpenAI gpt-4o-mini** — AI Agent com saída JSON estruturada
- **Mercado Pago** — Pix dinâmico + confirmação via IPN
- **Lalamove / Uber Direct / Loggi** — motoboy automático
- **Impressora térmica ESC/POS** — microserviço Node.js
- **Google Calendar** — agenda de produção/entrega

## Estrutura

```
.
├── docker-compose.yml                     ← sobe tudo
├── .env.example
├── workflows/                             ← importar no n8n
│   ├── 01-atendimento-principal.json      ← WhatsApp + IA + pedido (Baileys)
│   ├── 02-status-cozinha.json             ← callback da cozinha
│   ├── 03-lembretes-followup.json         ← cron de reengajamento
│   ├── 04-mercadopago-pix.json            ← Pix dinâmico + IPN
│   ├── 05-motoboy.json                    ← Lalamove/Uber/Loggi + webhook
│   ├── 06-impressora-termica.json         ← POST /print + retry
│   ├── 07-google-agenda.json              ← evento no Calendar
│   └── 08-future-features-skeleton.json   ← NPS, fidelidade, Whisper, broadcast
├── baileys-service/                       ← microserviço WhatsApp
│   ├── index.js
│   ├── package.json
│   └── Dockerfile
├── printer-service/                       ← microserviço ESC/POS
│   ├── index.js
│   ├── package.json
│   └── Dockerfile
├── database/
│   └── schema.sql                         ← Postgres completo (10 tabelas + views)
├── prompts/
│   └── ai-system-prompt.md                ← "Dona Salgada"
└── docs/
    ├── arquitetura.md
    ├── estados.md
    ├── integracoes.md                     ← setup completo
    ├── baileys.md
    ├── mercadopago.md
    ├── motoboy.md
    ├── impressora.md
    ├── google-calendar.md
    └── roadmap.md                         ← features futuras
```

## Quick start

```bash
cp .env.example .env           # edite com seus tokens
docker compose up -d postgres  # roda schema.sql automático
docker compose up -d n8n
docker compose up -d baileys   # escaneie QR nos logs
```

Depois no n8n:
1. Criar credenciais Postgres, OpenAI e Google Calendar
2. Copiar variables do `.env` para Settings → Variables (incl. prompt)
3. Importar os 8 workflows
4. Nos `Execute Workflow` nodes, re-linkar os sub-workflows (04, 05, 06, 07)
5. Ativar todos

Setup completo em `docs/integracoes.md`.

## Fluxo de um pedido

1. Cliente manda "oi" → Baileys → Workflow 01
2. AI Agent conduz a conversa (saudação → itens → confirmação → endereço → pagamento)
3. Pedido é criado no Postgres; em paralelo:
   - **Workflow 04** gera QR Pix e manda pro cliente
   - **Workflow 06** imprime comanda na cozinha
   - **Workflow 07** cria evento no Google Calendar
4. Mercado Pago confirma pagamento → `status=PAGO` → cozinha é avisada
5. Cozinha marca `PRONTO` → Workflow 02:
   - Retirada: só avisa o cliente
   - Entrega: **Workflow 05** chama motoboy e manda link de rastreio
6. Motoboy entrega → webhook → `status=ENTREGUE` → cliente recebe agradecimento
7. 1h depois, **Workflow 08** pergunta NPS (opcional)

## Features entregues

- [x] Atendimento WhatsApp via **Baileys** próprio (sem Evolution)
- [x] Máquina de estados persistida (11 estados)
- [x] AI Agent com saída JSON estruturada + memória de 12 msgs
- [x] Pedido transacional com criação de evento no calendar + print + Pix em paralelo
- [x] **Mercado Pago Pix dinâmico** com QR + copia-e-cola + IPN
- [x] **Motoboy automático**: Lalamove, Uber Direct, Loggi ou manual (Slack)
- [x] **Impressora térmica** com retry automático
- [x] **Google Calendar** — evento por pedido, cor por tipo, atualização por status
- [x] Lembretes e reengajamento (cron)
- [x] Escalonamento para humano + alerta Slack
- [x] Auditoria completa em `eventos`, `pagamentos`, `entregas`

## Features futuras (skeleton pronto)

No workflow `08-future-features-skeleton.json` e no schema:
- NPS / Feedback automático
- Fidelidade / cashback (tabela + coluna prontas)
- Transcrição de áudio (Whisper)
- Broadcast de marketing para inativos 30d
- Upsell (adicionar regra no prompt)
- Multi-loja (adicionar `loja_id`)
- Encomenda agendada
- Pagamento cartão presencial (maquininha)
- Relatórios fiscais
- App mobile para cozinha (substituir impressora)

Detalhes em `docs/roadmap.md`.

## Custos (300 pedidos/mês)

~R$ 70/mês fixo (VPS + OpenAI + Pix) — Mercado Pago: 0,99% por transação.
