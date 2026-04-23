# Motoboy (Delivery)

Workflow: `workflows/05-motoboy.json`

## Quando é chamado

Pelo **Workflow 02 (Status Cozinha)** quando:
- `status = PRONTO` **E** `tipo_entrega = 'entrega'` **E** pedido ainda não tem motoboy.

## Provedores suportados (switch por `MOTOBOY_PROVIDER`)

| Provider    | API pública? | Cobertura        | Taxa média        |
|-------------|--------------|------------------|-------------------|
| lalamove    | ✅ sim       | SP, RJ, BH, POA  | R$ 8–25           |
| uber_direct | 🔐 parceria  | grandes capitais | R$ 10–30          |
| loggi       | ✅ sim       | nacional         | R$ 7–20 (Fast)    |
| manual      | Slack/WhatsApp → motoboy próprio | — | fixa |

Cada branch faz o POST correto na API do provedor. A saída é **normalizada** por um node Code para `{ provider, order_id, tracking_url, fee, status }`.

## Dados persistidos

- Tabela `entregas`: tracking completo, raw de cada webhook
- Tabela `pedidos`: colunas `motoboy_*` com o último estado
- View `vw_pedidos_entrega_pendente` para dashboard

## Webhook de tracking

Cada provider precisa ser configurado para postar em:
`https://n8n.seudominio.com/webhook/salgaderia/motoboy-webhook`

O workflow normaliza o payload por provider (`x-provider` header ou `body.provider`) e atualiza status.

Status unificado interno:
- `REQUESTED` → pedido criado na API
- `ACCEPTED` → motoboy aceitou
- `PICKING_UP` → indo buscar na loja
- `DELIVERING` → saiu com o pedido
- `DELIVERED` / `COMPLETED` → entregue → dispara status `ENTREGUE`
- `CANCELED` / `FAILED` → cancelado → dispara `CANCELADO`

## Setup Lalamove

1. Cadastro em https://developers.lalamove.com
2. Sandbox grátis para testes; produção via comercial
3. Variáveis: `LALAMOVE_API_KEY`, `LALAMOVE_HMAC`
4. Webhook: configurar no painel → `.../salgaderia/motoboy-webhook` com `x-provider: lalamove`

## Setup Uber Direct

1. Requer **conta Uber Business + aprovação** (B2B)
2. Variáveis: `UBER_DIRECT_TOKEN`, `UBER_CUSTOMER_ID`

## Setup Loggi Fast

1. https://www.loggi.com/parceiros/
2. Variáveis: `LOGGI_API_KEY`, `LOGGI_SHOP_ID`

## Geocoding (futuro)

Hoje o workflow usa `cliente.lat/lng` se existir, senão manda só endereço string.
Para precisão: adicionar node **HTTP Request** para Google Geocoding API antes do
`Switch Provider`, preenchendo `dropoff_lat/lng`.

## Fallback manual

Se nenhum provider estiver configurado, o workflow dispara um **alerta no Slack**
para que a operação chame motoboy próprio — e já cria registro em `entregas`
com `provider=manual`.
