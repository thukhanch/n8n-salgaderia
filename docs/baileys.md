# Baileys Service

Microserviço Node.js que é a ponte WhatsApp ↔ n8n.
Substitui Evolution API — usa `@whiskeysockets/baileys` direto.

## Por quê Baileys?

- Grátis, sem taxa por instância
- Código nosso, sem dependência de terceiro
- Controle total do parser de mensagens

## Contrato HTTP

### IN (Baileys → n8n)
Quando o WhatsApp recebe mensagem, fazemos `POST WEBHOOK_N8N_URL`:

```json
{
  "id": "3EB0...",
  "remoteJid": "5511999999999@s.whatsapp.net",
  "telefone": "5511999999999",
  "fromMe": false,
  "pushName": "Marina",
  "messageType": "conversation",
  "text": "oi",
  "hasMedia": false,
  "timestamp": 1735000000
}
```
Header: `Authorization: Bearer ${SERVICE_TOKEN}`.

### OUT (n8n → Baileys)

- `POST /send-text` — `{ number, text }`
- `POST /send-image` — `{ number, imageUrl | imageBase64, caption? }`
- `POST /send-location` — `{ number, lat, lng, name?, address? }`
- `GET  /health` — `{ ok, connected }`

Padrão recomendado para os workflows do produto:
- usar `BAILEYS_HOST` + `BAILEYS_SERVICE_TOKEN`
- nunca hardcodar `127.0.0.1`, id de sessão ou token no JSON dos workflows
- tratar o service como contrato HTTP estável, independente do ambiente

Todos exigem `Authorization: Bearer ${SERVICE_TOKEN}`.

## Primeira execução

```bash
cd baileys-service
npm install
WEBHOOK_N8N_URL=http://localhost:5678/webhook/salgaderia/whatsapp \
SERVICE_TOKEN=seu-token node index.js
```

No terminal aparece o QR code — escaneie com o WhatsApp do negócio.
Credenciais ficam salvas em `./auth/` (volume Docker). Após isso, reconecta sozinho.

## Produção (Docker Compose)

Já incluído em `docker-compose.yml`. Para reescanear: `rm -rf ./baileys-auth && docker compose restart baileys && docker compose logs -f baileys`.

## Limitações

- WhatsApp pode banir se houver spam. Respeite:
  - `batchSize: 5` e `batchInterval: 1500ms` nos broadcasts
  - Não mandar primeira msg (cliente sempre inicia)
- Em caso de ban, trocar chip / instância.
- Para escala grande, considere **WhatsApp Business Cloud API (Meta)**. O contrato HTTP do nosso service pode ser mantido — só troca o driver.
