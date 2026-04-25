# Onboarding de um novo tenant

Passo-a-passo para subir um cliente novo no agente universal.

## 1. Inserir tenant no banco

```sql
INSERT INTO tenants (slug, nome, timezone, config)
VALUES ('cliente-x', 'Cliente X Ltda', 'America/Sao_Paulo',
  jsonb_build_object(
    'prompt_extra', '...persona específica...',
    'business_hours', jsonb_build_object('mon', jsonb_build_array('09:00-18:00')),
    'appointment_default_min', 60,
    'products', jsonb_build_array(
      jsonb_build_object('sku','X','name','Produto X','price',100)
    ),
    'calendar_id', 'primary',
    'gmail_from', 'atendimento@clientex.com',
    'tools_enabled', jsonb_build_array(
      'calendar.check_availability','calendar.book','contact.update','deal.upsert'
    ),
    'mp_access_token', 'APP_USR-token-especifico',
    'handoff_channel', 'https://hooks.slack.com/services/...',
    'language', 'pt-BR'
  ));
```

Modelos completos em `examples/tenant-*.json`.

## 2. Registrar canal WhatsApp

```sql
INSERT INTO channels (tenant_id, kind, external_id)
SELECT id, 'whatsapp', 'cliente-x' FROM tenants WHERE slug='cliente-x';
```

`external_id` é o **nome da instância Baileys** (veremos em 4).

## 3. (Opcional) Registrar canal Gmail

```sql
INSERT INTO channels (tenant_id, kind, external_id)
SELECT id, 'gmail', 'atendimento@clientex.com' FROM tenants WHERE slug='cliente-x';
```

## 4. Subir instância Baileys

Adicione o slug ao `.env`:
```
BAILEYS_INSTANCES=demo,cliente-x
```

Ou em runtime:
```bash
curl -X POST http://localhost:3001/instances \
  -H "Authorization: Bearer $BAILEYS_SERVICE_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"name":"cliente-x"}'
```

Escaneie o QR code nos logs (`docker compose logs -f baileys`) com o WhatsApp
do cliente.

## 5. Autorizar Google (Calendar + Gmail)

No n8n, em **Credentials**, crie credenciais OAuth2 específicas por tenant
**OU** compartilhe uma credencial e setar `calendar_id` + `gmail_from` diferente
por tenant. A segunda forma só funciona se o agente operar com UMA conta
Google que tem múltiplos calendários/aliases.

Recomendado: uma credencial OAuth por tenant. Nome da credencial =
`gcal-cliente-x`, `gmail-cliente-x`. Dentro de cada tool, trocar a credencial
conforme o tenant — **isso exige customização** (hoje as tools usam um
credential fixo). Caminhos possíveis:
- A) Duplicar as tools por tenant (simples, escala pequena)
- B) Usar o node `HTTP Request` direto na Google API com token do tenant no
     `config` (mais escalável — ver `docs/extending.md`)

## 6. Configurar webhooks externos

- **Mercado Pago**: painel do MP → Notificações → URL
  `https://SEU_N8N/webhook/agent/mp-webhook`
- **Baileys**: já sai configurado via `BAILEYS_WEBHOOK_N8N_URL`

## 7. Testar

Mande "oi" para o WhatsApp da instância.
Conferência SQL:
```sql
SELECT * FROM conversations ORDER BY criado_em DESC LIMIT 5;
SELECT tool, success, input, output FROM tool_calls ORDER BY criado_em DESC LIMIT 5;
```

## 8. Ativar/desativar tenants

```sql
UPDATE tenants SET ativo=FALSE WHERE slug='cliente-x';
```
O Channel Workflow filtra por `ativo=TRUE`; mensagens para tenant inativo são descartadas.
