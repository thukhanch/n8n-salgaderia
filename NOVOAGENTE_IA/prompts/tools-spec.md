# Catálogo de Tools (contrato I/O)

> Cada tool é um sub-workflow n8n acessado via `Execute Workflow Tool`
> dentro do AI Agent. Todas seguem o **mesmo padrão**:
>
> - Entrada: JSON com `{tenant_id, contact_id, ...args}`
> - Saída: JSON com `{ok: bool, data?, error?}`
> - Toda execução é logada em `tool_calls`

---

## calendar.check_availability
Lista horários livres em uma janela.

**Input**
```json
{ "tenant_id": "uuid", "contact_id": "uuid",
  "from": "2026-04-25T09:00:00-03:00",
  "to":   "2026-04-25T18:00:00-03:00",
  "duration_min": 60 }
```
**Output**
```json
{ "ok": true, "data": { "slots": [
  {"start":"2026-04-25T09:00:00-03:00","end":"2026-04-25T10:00:00-03:00"},
  {"start":"2026-04-25T14:00:00-03:00","end":"2026-04-25T15:00:00-03:00"}
]}}
```

---

## calendar.book
Cria um agendamento (Google Calendar + tabela `appointments`).

**Input**
```json
{ "tenant_id": "uuid", "contact_id": "uuid",
  "titulo": "Consultoria 1h - João",
  "descricao": "Diagnóstico inicial",
  "inicio": "2026-04-25T14:00:00-03:00",
  "duration_min": 60 }
```
**Output** `{ "ok": true, "data": { "appointment_id": "...", "gcal_event_id": "..." } }`

---

## calendar.cancel
Cancela um agendamento existente.

**Input** `{ "tenant_id":"...", "appointment_id":"..." }`
**Output** `{ "ok": true }`

---

## calendar.list_mine
Lista próximos agendamentos do contato (para "quando é minha consulta?").

**Input** `{ "tenant_id":"...", "contact_id":"..." }`
**Output** `{ "ok": true, "data": { "appointments": [...] } }`

---

## gmail.send
Envia e-mail via Gmail OAuth do tenant.

**Input**
```json
{ "tenant_id": "uuid",
  "to": "fulano@email.com",
  "subject": "...",
  "body_html": "<p>...</p>",
  "body_text": "..." }
```
**Output** `{ "ok": true, "data": { "message_id": "..." } }`

---

## gmail.search
Busca mensagens recentes (para "já mandei o orçamento?").

**Input** `{ "tenant_id":"...", "query":"from:fulano@email.com newer_than:7d" }`
**Output** `{ "ok": true, "data": { "messages": [...] } }`

---

## payment.create_pix
Cria cobrança Pix via Mercado Pago.

**Input**
```json
{ "tenant_id":"...", "contact_id":"...",
  "deal_id": "uuid?",
  "amount": 300.00,
  "description": "Consultoria 1h" }
```
**Output**
```json
{ "ok": true, "data": {
  "payment_id": "...", "qr_code": "00020126...",
  "qr_base64": "...", "expires_at": "..."
}}
```
> O channel inbound é responsável por enviar a imagem QR ao contato.
> A tool já posta no canal correto via `contact.last_channel`.

---

## payment.status
Consulta status de um pagamento.

**Input** `{ "tenant_id":"...", "payment_id":"..." }`
**Output** `{ "ok": true, "data": { "status": "pending|approved|...", "paid_at": "..." } }`

---

## contact.update
Atualiza atributos do contato.

**Input** `{ "tenant_id":"...", "contact_id":"...", "patch": { "nome":"...", "email":"...", "attributes":{...} } }`
**Output** `{ "ok": true, "data": { "contact": {...} } }`

---

## deal.upsert
Cria ou atualiza um deal (pipeline de vendas).

**Input**
```json
{ "tenant_id":"...", "contact_id":"...",
  "titulo": "Pacote 4h - Empresa X",
  "stage": "PROPOSTA",
  "valor": 1000.00,
  "itens": [{"sku":"CONS-4H","qtd":1,"preco":1000}] }
```
**Output** `{ "ok": true, "data": { "deal_id": "..." } }`

---

## handoff.human
Marca contato para atendimento humano e dispara alerta no canal interno do tenant.

**Input** `{ "tenant_id":"...", "contact_id":"...", "motivo":"...", "resumo":"..." }`
**Output** `{ "ok": true }`

---

## Como adicionar uma nova tool

1. Criar workflow `9X-tool-mynew.json` com node `Execute Workflow Trigger` que aceita o input padrão
2. Implementar a lógica
3. Retornar `{ok, data?, error?}` no node final (Set)
4. Logar a chamada em `tool_calls`
5. Em `10-agent-router.json`, adicionar mais um `Execute Workflow Tool` apontando para ele
6. Adicionar o nome em `tools_enabled` do tenant (no `config` JSONB)
