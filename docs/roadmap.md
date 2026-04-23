# Roadmap — Features Futuras

Skeleton pronto em `workflows/08-future-features-skeleton.json` e tabelas em `database/schema.sql`.

## Já com esqueleto (só ativar e plugar)

### 1. NPS / Feedback automático
- **Cron 1h**: query de pedidos `ENTREGUE` há 1–2h sem `feedback`
- Pergunta nota 0–10 ao cliente
- **Falta**: criar workflow que recebe a resposta e insere em `feedback`
  (reusar o workflow 01, adicionando um estado `AGUARDANDO_NPS`)

### 2. Fidelidade / Cashback
- Tabela `fidelidade_transacoes` + coluna `clientes.pontos_fidelidade` prontas
- Regra atual (skeleton): 1 ponto a cada R$ 10
- **Falta**:
  - Comando "meus pontos" no AI Agent → query + resposta
  - Resgate: "quero usar 50 pontos" → desconto proporcional no próximo pedido
  - Expiração via cron mensal

### 3. Transcrição de áudio (Whisper)
- Hook de sub-workflow pronto para receber um áudio e retornar texto
- **Falta**: no workflow 01, antes do `AI Agent`, se `has_media && messageType=audioMessage`:
  1. Baixar áudio do Baileys (`GET /media/:id`) — endpoint a adicionar no baileys-service
  2. Chamar sub-workflow 08 com o buffer
  3. Usar o texto retornado como `mensagem_atual`

### 4. Broadcast marketing
- Cron diário 10h busca `clientes` inativos > 30 dias
- Envia cupom `VOLTA10` com `batching`
- **Falta**: tabela `cupons` + validação no fechamento do pedido

## Esqueleto no schema, sem workflow ainda

### 5. Upsell / Cross-sell
- Detectar no AI Agent: pedido só com salgado → sugerir bebida
- Basta adicionar regra no `prompts/ai-system-prompt.md`

### 6. Dashboard operacional
- Metabase/Grafana apontando no mesmo Postgres
- Métricas: pedidos/dia, ticket médio, tempo médio de preparo, top clientes, taxa de cancelamento
- Zero código — só instalar e criar dashboards

### 7. Multi-loja
- Adicionar coluna `loja_id` em `clientes`, `pedidos`, `produtos`
- Webhook Baileys passa a receber `instance` → mapear para `loja_id`
- AI Agent recebe contexto da loja certa (cardápio, endereço, horário)

### 8. Reserva / Encomenda agendada
- Cliente: "quero 100 coxinhas pra sábado às 14h"
- AI Agent detecta data/hora → `pedidos.horario_previsto` no futuro
- Cron diário checa encomendas do dia e avisa cozinha pela manhã

### 9. Pagamento com cartão presencial via maquininha
- Integração com Stone/Cielo/PagBank via API
- Comando "cobrar cartão" do atendente → gera pagamento na maquininha pareada

### 10. WhatsApp Business Cloud API (migração Meta)
- Trocar `baileys-service` por implementação Meta (mesmo contrato HTTP)
- Necessário quando volume ou risco de ban for crítico

### 11. Relatórios fiscais
- Exportar XMLs/CSVs por mês para contabilidade
- Integração com sistema fiscal (NFC-e via SEBRAE/Focus NFe)

### 12. App mobile interno para cozinha
- Em vez de impressora: PWA com lista de pedidos, toque pra avançar status
- Zero extra no backend — só consumir `vw_pedidos_cozinha` e postar em `/salgaderia/cozinha-status`
