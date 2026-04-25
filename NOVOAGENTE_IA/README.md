# Agent Universal

Base **universal e multi-tenant** de agente de IA em n8n para vendas,
atendimento e agendamento. Pronto para ser especializado cliente-a-cliente
apenas via configuração (sem tocar no core).

## O que tem

- **Multi-tenant** desde o dia 1 (um n8n atende N clientes isolados)
- **AI Agent com tools plugáveis** (LangChain) — sem switches hardcoded
- **Canais**: WhatsApp (Baileys próprio, multi-instância) e Gmail
- **Integrações**: Google Calendar, Gmail, Mercado Pago Pix
- **Memória** conversacional por contato (12 msgs) + histórico persistido
- **Crons**: lembrete de agendamento (-24h/-2h) e follow-up de inativos
- **Auditoria**: cada chamada de tool logada em `tool_calls`
- **Exemplos reais** de tenant: clínica, barbearia, imobiliária, SaaS B2B

## Stack

```
WhatsApp (Baileys) ─┐
                    ├─→ n8n (workflows)
Gmail (OAuth)       ─┘      │
                            ├─→ OpenAI (gpt-4o-mini + tool-calling)
                            ├─→ PostgreSQL (estado + audit)
                            ├─→ Google Calendar (agendamentos)
                            └─→ Mercado Pago (cobranças)
```

## Estrutura

```
.
├── docker-compose.yml
├── .env.example
├── database/
│   ├── schema.sql       ← 8 tabelas multi-tenant
│   └── seeds.sql        ← tenant "demo" para dev
├── workflows/           ← 15 workflows n8n importáveis
│   ├── 01-channel-whatsapp-inbound.json
│   ├── 02-channel-gmail-inbound.json
│   ├── 10-agent-router.json          ← coração do sistema
│   ├── 20-23 tools calendar.*
│   ├── 30-31 tools gmail.*
│   ├── 40-42 tools payment.* + IPN
│   ├── 50-51 tools contact / deal
│   ├── 60    tool handoff.human
│   └── 70-71 crons reminder / followup
├── baileys-service/     ← microserviço Baileys multi-instância
├── prompts/
│   ├── system-prompt.md ← template universal
│   └── tools-spec.md    ← contratos I/O de cada tool
├── examples/            ← 4 configs de tenant reais
│   ├── tenant-clinica.json
│   ├── tenant-barbearia.json
│   ├── tenant-imobiliaria.json
│   └── tenant-vendas-b2b.json
└── docs/
    ├── architecture.md
    ├── tenants.md       ← como onboardar novo cliente
    ├── extending.md     ← como adicionar tools/canais
    ├── security.md
    └── roadmap.md
```

## Quick start

```bash
cp .env.example .env           # preencha com seus tokens
echo "N8N_ENCRYPTION_KEY=$(openssl rand -hex 32)" >> .env

docker compose up -d postgres  # cria tabelas + seed demo
docker compose up -d n8n
docker compose up -d baileys   # escaneie QR nos logs
```

No n8n (`http://localhost:5678`):
1. Crie credenciais: **Postgres Agent**, **OpenAI**, **Google Calendar OAuth2**, **Gmail OAuth2**
2. Copie `.env` → Settings → Variables (incl. conteúdo de `prompts/system-prompt.md` em `SYSTEM_PROMPT_TEMPLATE`)
3. Importe os 15 workflows em `workflows/`
4. No `10-agent-router.json`, re-linke os **Execute Workflow Tool** nas respectivas tools (20, 21, 22, 23, 30, 31, 40, 41, 50, 51, 60)
5. Ative todos

Passo-a-passo completo em `docs/tenants.md`.

## Onboardar um cliente novo

Em 3 passos:

```sql
-- 1. Inserir tenant (copiar de examples/)
INSERT INTO tenants (slug, nome, timezone, config) VALUES ('cliente-x', ...);

-- 2. Registrar canal WhatsApp
INSERT INTO channels (tenant_id, kind, external_id)
  SELECT id, 'whatsapp', 'cliente-x' FROM tenants WHERE slug='cliente-x';
```

```bash
# 3. Adicionar instância no Baileys
curl -X POST http://localhost:3001/instances \
  -H "Authorization: Bearer $BAILEYS_SERVICE_TOKEN" \
  -d '{"name":"cliente-x"}'
# → escaneie QR nos logs
```

Pronto. O mesmo código universal atende o novo cliente com a persona
e regras definidas em `config` (JSONB).

## Por que tools e não workflows por nicho?

Padrão antigo: "para clínica, crie o fluxo clínica.json; para barbearia,
crie barbearia.json". **Não escala.**

Aqui, o AI Agent tem acesso a tools genéricas (`calendar.book`,
`payment.create_pix`, `deal.upsert`). A diferença entre nichos é só o
**prompt** e quais tools estão habilitadas para cada tenant.

Mais detalhes em `docs/architecture.md` e `docs/extending.md`.

## Licença

MIT.
