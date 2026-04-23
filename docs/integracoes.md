# Guia de Integrações & Setup

## 0. Pré-requisitos

- VPS Linux com Docker e Docker Compose
- Domínio com DNS apontando (para TLS em Evolution e n8n)
- Conta OpenAI com saldo (~R$ 20 cobre centenas de pedidos)

## 1. Postgres / Supabase

**Opção A — Supabase (recomendado para começar):**
1. Criar projeto em https://supabase.com
2. `SQL editor` → colar conteúdo de `database/schema.sql` → Run
3. Copiar Host / Password para `.env`
4. Habilitar **Connection Pooler** (porta 6543) para evitar limite de conexões do n8n

**Opção B — Postgres no mesmo VPS:**
```yaml
# docker-compose.yml (trecho)
postgres:
  image: postgres:15
  environment:
    POSTGRES_DB: salgaderia
    POSTGRES_USER: salgaderia
    POSTGRES_PASSWORD: ${PG_PASSWORD}
  volumes: ["./pg-data:/var/lib/postgresql/data"]
```

Rodar o schema:
```bash
docker compose exec postgres psql -U salgaderia -d salgaderia < database/schema.sql
```

## 2. Evolution API (WhatsApp)

Instalar ao lado do n8n:
```yaml
evolution-api:
  image: atendai/evolution-api:v2
  environment:
    - AUTHENTICATION_API_KEY=${EVOLUTION_API_KEY}
    - DATABASE_PROVIDER=postgresql
    - DATABASE_CONNECTION_URI=postgresql://evolution:senha@postgres:5432/evolution
  ports: ["8080:8080"]
```

Passo a passo:
1. `curl -X POST https://evolution.seudominio.com/instance/create -H "apikey: $EVOLUTION_API_KEY" -d '{"instanceName":"salgaderia","qrcode":true}'`
2. Abrir `/manager` no browser → escanear QR Code com o WhatsApp do negócio
3. Configurar webhook para o n8n:
   ```bash
   curl -X POST https://evolution.seudominio.com/webhook/set/salgaderia \
     -H "apikey: $EVOLUTION_API_KEY" \
     -H "Content-Type: application/json" \
     -d '{
       "url": "https://n8n.seudominio.com/webhook/salgaderia/whatsapp",
       "webhook_by_events": false,
       "events": ["MESSAGES_UPSERT"]
     }'
   ```

## 3. n8n

```yaml
n8n:
  image: n8nio/n8n:latest
  environment:
    - N8N_HOST=n8n.seudominio.com
    - N8N_PROTOCOL=https
    - WEBHOOK_URL=https://n8n.seudominio.com
    - N8N_ENCRYPTION_KEY=${N8N_ENCRYPTION_KEY}
    - DB_TYPE=postgresdb
    - DB_POSTGRESDB_HOST=postgres
    - DB_POSTGRESDB_DATABASE=n8n
  volumes: ["./n8n-data:/home/node/.n8n"]
```

### 3.1 Credenciais a criar no n8n (Settings → Credentials)

| Nome              | Tipo       | Campos                                   |
|-------------------|------------|------------------------------------------|
| Postgres Salgaderia | Postgres | host/port/db/user/pwd (SSL=on em Supabase) |
| OpenAI            | OpenAI API | API Key                                  |

### 3.2 Variáveis globais (Settings → Variables)

Copie do `.env.example`. Importante: `PROMPT_DONA_SALGADA` contém o conteúdo completo de `prompts/ai-system-prompt.md`.

### 3.3 Import dos workflows

1. `Import from File` → `workflows/01-atendimento-principal.json`
2. Idem para 02 e 03
3. Em cada workflow, re-vincule a credencial Postgres (os IDs são placeholders)
4. Ative os três workflows (toggle no topo)

## 4. Webhook da cozinha

Você tem 3 opções:

**A. Display web simples (mais rápido de ter em produção):**
- Página web que faz long-poll na view `vw_pedidos_cozinha`
- n8n `node-cozinha` só serve para invalidar cache (opcional)
- Atualização de status: botão na tela → `POST /salgaderia/cozinha-status` (Workflow 02)

**B. Integração com ERP (Omie/Bling):**
- `WEBHOOK_COZINHA_URL` = endpoint do ERP que aceita pedido
- Callback de status vem do ERP

**C. Impressora térmica (bobina 80mm):**
- Microserviço Python com `python-escpos` escutando em `WEBHOOK_COZINHA_URL`
- Imprime comanda direto na cozinha

Em todos os casos: o callback de atualização de status deve bater no **Workflow 02** com body:
```json
{ "codigo": 42, "status": "EM_PREPARO" }
```
e header `Authorization: Bearer ${COZINHA_TOKEN}`.

## 5. Pagamento (Pix)

MVP: Pix estático (chave copia-e-cola). Cliente envia comprovante como imagem →
operação confirma manualmente via painel.

V2 (opcional): Pix dinâmico via Efí/Mercado Pago:
- Workflow extra cria cobrança no ato da confirmação
- Webhook da PSP atualiza `pedidos.status='PAGO'` e dispara cozinha

## 6. Teste end-to-end

1. Mande "oi" para o número → deve receber saudação + cardápio em < 5s
2. "quero 15 coxinhas, pra retirar" → deve confirmar valor
3. "confirmo, pix, Marina" → recebe chave Pix
4. Na cozinha, mudar status para `EM_PREPARO` → cliente recebe notificação
5. Mudar para `PRONTO` → cliente recebe aviso
6. `SELECT * FROM pedidos ORDER BY criado_em DESC LIMIT 1` → pedido gravado

## 7. Custos estimados (200 pedidos/mês)

| Item              | Custo/mês       |
|-------------------|-----------------|
| VPS 2c/4g         | R$ 35           |
| OpenAI gpt-4o-mini| R$ 5–15         |
| Supabase free     | R$ 0            |
| Domínio           | R$ 3            |
| **Total**         | **~R$ 45**      |
