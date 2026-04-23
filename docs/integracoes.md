# Guia de Integrações & Setup (v2)

> Quick-start para subir todo o stack do zero em ~40 minutos.

## 0. Pré-requisitos

- VPS Linux (Hetzner/Contabo 2c/4g) com Docker + Docker Compose
- Domínio apontando para o VPS (para TLS)
- Conta OpenAI com ~R$ 20 de saldo
- Conta Mercado Pago (CNPJ ou CPF)
- Impressora térmica ESC/POS conectada à rede local da loja
- WhatsApp do negócio (celular ou número dedicado)

## 1. Clonar e configurar

```bash
git clone <repo> && cd n8n-salgaderia
cp .env.example .env
# edite .env com seus valores
```

Gerar chave de criptografia do n8n:
```bash
echo "N8N_ENCRYPTION_KEY=$(openssl rand -hex 32)" >> .env
```

## 2. Subir stack

```bash
docker compose up -d postgres
# aguarde DB inicializar + rodar schema.sql

docker compose up -d n8n
# acesse https://n8n.seudominio.com e crie usuário admin

docker compose up -d baileys
docker compose logs -f baileys
# escaneie o QR code com o WhatsApp do negócio
```

## 3. n8n: credenciais + variáveis

### 3.1 Credentials
| Nome                         | Tipo                       | Valores                             |
|------------------------------|----------------------------|-------------------------------------|
| Postgres Salgaderia          | Postgres                   | host=postgres, db=salgaderia        |
| OpenAI                       | OpenAI API                 | `OPENAI_API_KEY`                    |
| Google Calendar              | Google Calendar OAuth2 API | Client ID/Secret + autorizar       |

### 3.2 Variables (copiar do .env)
Veja `.env.example` — atenção especial:
- `PROMPT_DONA_SALGADA` → colar conteúdo completo de `prompts/ai-system-prompt.md`
- `BAILEYS_HOST=baileys:3001` (dentro do compose)

## 4. Import dos 8 workflows

Na ordem:
1. `01-atendimento-principal.json`
2. `02-status-cozinha.json`
3. `03-lembretes-followup.json`
4. `04-mercadopago-pix.json`
5. `05-motoboy.json`
6. `06-impressora-termica.json`
7. `07-google-agenda.json`
8. `08-future-features-skeleton.json` (deixe inativo até precisar)

Para cada um:
- Re-vincular **Postgres Salgaderia** nas credenciais (os IDs são placeholders)
- No Workflow 01, nos nodes **Execute Workflow**, selecionar os sub-workflows importados (04, 06, 07)
- No Workflow 02, no node **Execute Workflow**, selecionar o 05

## 5. Configurar webhooks externos

### Baileys → n8n
Já automático (o service posta em `BAILEYS_WEBHOOK_N8N_URL`).

### Mercado Pago (IPN)
Painel → Suas integrações → Notificações → Webhooks:
- URL: `https://n8n.seudominio.com/webhook/salgaderia/mp-webhook`
- Evento: `payment`

### Motoboy
No painel do provider escolhido (Lalamove/Uber/Loggi), configurar webhook:
- URL: `https://n8n.seudominio.com/webhook/salgaderia/motoboy-webhook`
- Header adicional: `x-provider: lalamove` (ou `uber_direct`, etc)

### Cozinha → n8n (status)
O display/ERP da cozinha deve fazer `POST .../salgaderia/cozinha-status`
com `{ codigo, status }` e header `Authorization: Bearer ${COZINHA_TOKEN}`.

## 6. Impressora térmica

Rodando **na loja** (não no VPS), pois precisa acesso à rede local:

```bash
# máquina da loja (Linux mini-PC, Raspberry Pi, etc)
git clone <repo> && cd n8n-salgaderia/printer-service
cp ../.env.example .env  # ou só as vars PRINTER_*
docker build -t salgaderia-printer .
docker run -d --restart unless-stopped \
  -p 3002:3002 \
  -e PRINTER_INTERFACE=tcp://192.168.1.50:9100 \
  -e SERVICE_TOKEN=$PRINTER_SERVICE_TOKEN \
  salgaderia-printer
```

No n8n, `PRINTER_HOST` precisa ser alcançável do VPS:
- Opção A: VPN entre loja e VPS (Tailscale — recomendado)
- Opção B: expor printer-service via DDNS + firewall (porta fechada exceto VPS)
- Opção C: rodar n8n TAMBÉM na loja (mais simples se não precisa acesso remoto)

## 7. Google Calendar

1. https://console.cloud.google.com → novo projeto
2. APIs & Services → Enable **Google Calendar API**
3. Credentials → OAuth 2.0 → Web application
4. Redirect URI: `https://n8n.seudominio.com/rest/oauth2-credential/callback`
5. No n8n, criar credential **Google Calendar OAuth2 API** → autorizar com conta da loja
6. Criar calendário "Produção Salgados" → copiar ID → `GCAL_CALENDAR_ID`

## 8. Mercado Pago

1. https://www.mercadopago.com.br/developers/panel
2. Criar aplicação → copiar **Access Token (produção)**
3. Configurar webhook de notificação (passo 5)
4. Para aceitar Pix em produção, a conta precisa estar aprovada (documento enviado)

## 9. Motoboy (exemplo Lalamove)

1. https://developers.lalamove.com → cadastro
2. Sandbox key grátis imediatamente
3. Para produção: conversar com comercial
4. Configurar webhook (passo 5)

## 10. Teste end-to-end

Mande no WhatsApp da loja, de outro número:

```
1. "oi"
   → deve receber saudação + cardápio em <5s
2. "quero 15 coxinhas, pra entregar na Rua X, 100"
   → deve confirmar valor + taxa
3. "confirmo, pix, Marina"
   → deve receber QR Code + copia-e-cola
4. Pagar no MP (teste) ou forçar via painel
   → Cliente recebe "pagamento confirmado"
   → Impressora imprime comanda
   → Evento aparece no Google Calendar
5. Na cozinha, POST para /salgaderia/cozinha-status {codigo, status:PRONTO}
   → Como é ENTREGA: motoboy é chamado automaticamente
   → Cliente recebe link de rastreio
6. Motoboy marca entregue → webhook → cliente recebe agradecimento
```

Conferência SQL:
```sql
SELECT codigo, status, mp_status, motoboy_status, printed_at, gcal_event_id
FROM pedidos ORDER BY criado_em DESC LIMIT 1;
```

## 11. Custos estimados (300 pedidos/mês)

| Item                   | Custo/mês     |
|------------------------|---------------|
| VPS 2c/4g              | R$ 35         |
| OpenAI gpt-4o-mini     | R$ 10–20      |
| Mercado Pago (0,99%)   | ~R$ 30 (1% do faturamento) |
| Motoboy                | pago pelo cliente |
| Google Calendar        | R$ 0          |
| Domínio                | R$ 3          |
| **Total fixo**         | **~R$ 70**    |
