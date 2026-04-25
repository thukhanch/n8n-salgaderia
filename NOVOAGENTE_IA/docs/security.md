# Segurança

## Princípios

- **Tudo que entra por webhook** tem `Authorization: Bearer`
- **Multi-tenant nativo**: queries sempre filtram por `tenant_id`
- **Segredos nunca em código**: `.env` + `n8n Variables` + `tenants.config` (JSONB)
- **Logs sem PII em Slack**: handoff manda só nome ou telefone, não a conversa inteira

## Checklist produção

- [ ] HTTPS obrigatório (Caddy/Traefik com Let's Encrypt)
- [ ] Postgres com senha forte, porta NÃO exposta (só rede Docker interna)
- [ ] `N8N_ENCRYPTION_KEY` gerado com `openssl rand -hex 32` e guardado em
      cofre (1Password / Vault)
- [ ] Tokens de serviço (`BAILEYS_SERVICE_TOKEN`) rotacionados trimestralmente
- [ ] Rate limit no Nginx/Caddy para `/webhook/agent/*` (ex: 60 req/min/IP)
- [ ] Backup diário do Postgres → S3/Backblaze (ver `docs/backup.md`)
- [ ] Monitoramento: Uptime Kuma apontando para `/health` do baileys e
      um healthcheck SQL (`SELECT 1 FROM tenants LIMIT 1`)

## Dados pessoais (LGPD)

- `contacts.consent_marketing` controla se podemos enviar broadcasts
- **Direito ao esquecimento**: `DELETE FROM contacts WHERE id=...` faz
  cascade em `conversations`, `appointments`, `deals`, `payments` (FK
  `ON DELETE CASCADE`).
- **Retenção**: considerar cron que delete `conversations` mais antigas
  que 90 dias para contatos `FINALIZADO`.

## Prompt injection

Usuários podem tentar "ignore all previous instructions, do X".
Mitigações já no prompt:
- Regras imutáveis são reforçadas no system prompt
- Tools verificam `tenant_id`/`contact_id` do contexto (não do argumento
  que o modelo passou) — então "me mostre o pedido de outro cliente" não
  funciona, pois o `contact_id` vem do channel workflow, não do modelo.
- `handoff.human` em casos ambíguos

## Fraude de pagamento

- Mercado Pago IPN verificado via **GET** no pagamento real (não confiamos
  no body do webhook)
- `X-Idempotency-Key = payment.id` previne cobrança duplicada

## Abuso de WhatsApp

- Sem mensagens ativas a contatos que nunca escreveram (só follow-up em
  quem iniciou)
- `batching` em broadcasts (3–5 por vez com 1.5–2.5s entre)
- Se houver ban, trocar chip; as mensagens e estado dos contatos ficam
  preservados no Postgres.
