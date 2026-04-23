# Google Calendar

Workflow: `workflows/07-google-agenda.json`

## Por quê

- Dona da loja enxerga produção do dia na agenda que já usa
- Sincroniza automaticamente em celular/desktop
- Cores diferentes: retirada (laranja) vs entrega (verde)
- Status no título: `[EM_PREPARO]`, `[PRONTO]`, `[ENTREGUE]`

## Fluxo

### Criação (sub-workflow)
Chamado pelo workflow 01 após criar pedido:
- Calcula `horario_previsto` = agora + 25 min (retirada) ou + 45 min (entrega)
- Cria evento no Google Calendar via node oficial do n8n
- Salva `gcal_event_id` em `pedidos`

### Atualização (webhook)
Chamado quando status muda (pode ser plugado no workflow 02):
- POST para `.../webhook/salgaderia/gcal-update` com `{ codigo, status }`
- Atualiza título + cor do evento

## Setup

1. Criar projeto em https://console.cloud.google.com
2. **Habilitar Google Calendar API**
3. Criar credenciais OAuth 2.0 (Web app)
4. No n8n: `Credentials > Google Calendar OAuth2 API` → colar Client ID/Secret
5. Autenticar com conta Google da loja → aceitar escopo `calendar.events`
6. ID do calendário: use `primary` ou um calendário específico "Produção Salgados" (recomendado, não polui agenda pessoal)
7. Definir `GCAL_CALENDAR_ID` no n8n Variables

## Estrutura do evento

- **Summary**: `Pedido #42 - Marina (entrega)`
- **Description**: itens, valor, pagamento, observação
- **Location**: endereço (entrega) ou "Salgaderia (retirada)"
- **Start/End**: horário previsto + 15 min de buffer
- **Color**:
  - `10` verde = retirada
  - `11` vermelho = entrega
  - `2` verde-claro = entregue
  - `8` cinza = cancelado

## Integração com workflow 02

Para atualizar cor/título quando status mudar, plugue no workflow 02 após `Update Pedido`:

```
Update Pedido → HTTP POST /webhook/salgaderia/gcal-update
                body: { codigo, status }
```

## Cuidado com quotas

Google Calendar API tem limite de 1.000.000 req/dia/projeto — mais que suficiente.
Porém, **rate limit por usuário é 500 req / 100s**. Para loja com >300 pedidos/hora, usar Service Account.
