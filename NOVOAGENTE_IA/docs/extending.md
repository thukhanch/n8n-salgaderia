# Estendendo o agente

Três níveis de customização, do menos invasivo ao mais.

## Nível 1 — Só prompt (95% dos casos)

Cada novo cliente normalmente é um **novo tenant** com `prompt_extra`
diferente. O core não muda.

Exemplos: clínica, barbearia, imobiliária, SaaS B2B (ver `examples/`).

## Nível 2 — Tool nova (quando falta uma ação)

Se o cliente precisar de algo que as tools atuais não fazem — ex: consultar
estoque em ERP, gerar nota fiscal, buscar produtos em catálogo externo —
crie uma tool nova.

Passo-a-passo:

1. **Novo arquivo** `workflows/9X-tool-nome.json` com node
   `Execute Workflow Trigger` que aceita input padrão.
2. **Implementar** a lógica (HTTP, SQL, etc).
3. **Retornar** `{ok: true, data: {...}}` no node final `Set`.
4. **Logar** em `tool_calls`.
5. **Registrar no Agent Router** (workflow 10):
   - Adicionar mais um node `Execute Workflow Tool` com nome da tool,
     descrição (o modelo lê!) e `workflowId` apontando para a nova.
   - Conectar ao AI Agent via porta `ai_tool`.
6. **Habilitar** no tenant:
   ```sql
   UPDATE tenants SET config = jsonb_set(config, '{tools_enabled}',
     config->'tools_enabled' || to_jsonb('nome.da.tool'::text))
   WHERE slug='cliente-x';
   ```

## Nível 3 — Canal novo

Se o cliente quer Instagram DM, Telegram ou webchat:

1. Criar `workflows/0X-channel-xxx-inbound.json` no mesmo padrão do 01/02:
   - Webhook de entrada
   - Resolve tenant via `channels`
   - Upsert contact
   - Call `10 Agent Router` com `channel: 'xxx'`
   - Envia resposta no canal
2. Em `channels`, registrar `kind='xxx', external_id=...`
3. Adicionar lógica de envio na tool `payment.create_pix` (se houver canal
   para mandar QR) — idem para outras que mandam mensagens ativas.

## Credenciais por tenant (pattern avançado)

Hoje as tools usam credenciais fixas do n8n. Para escalar:

- **Google**: armazenar refresh_token por tenant em
  `tenants.config.gcal_refresh_token` e fazer HTTP Request direto à API do
  Google, trocando o token on-the-fly. As tools `20/21/22/23` viram HTTP
  Requests em vez do node `Google Calendar`.
- **Mercado Pago**: já suportado — `tenants.config.mp_access_token` tem
  precedência sobre `$vars.MP_ACCESS_TOKEN`.
- **Gmail**: mesmo padrão do Google (OAuth refresh token por tenant).

Vale a pena fazer isso quando passar de ~5 tenants.

## Boas práticas ao criar tool

- **Descrição clara**: o modelo lê o `description` do node
  `Execute Workflow Tool` para decidir usar ou não. Escreva como um
  bom JSDoc: "O que faz. Quando usar. Quando NÃO usar. Formato do input."
- **Idempotência**: se a ação é escrita externa, trate double-invoke.
- **Timeout curto**: 10–15s. O modelo trava se a tool demora.
- **Erro explícito**: em vez de throw, retorne `{ok: false, error: '...'}`.
  O modelo entende e pode retry ou pedir ajuda ao usuário.
- **Não side-effect escondido**: tudo que a tool faz deve estar no nome.
  Se a tool `calendar.book` também manda e-mail, rename para
  `calendar.book_and_email` ou separe.
