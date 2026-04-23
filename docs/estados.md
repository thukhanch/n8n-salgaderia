# Máquina de Estados da Conversa

Cada cliente tem UM estado atual em `clientes.estado_atual`.
O estado é o que o AI Agent usa para decidir o que perguntar/fazer.

## Diagrama

```
                          ┌────────┐
          (1ª mensagem) → │ INICIO │
                          └───┬────┘
                              │ cliente cumprimenta
                              ▼
                   ┌──────────────────────┐
                   │  COLETANDO_PEDIDO    │◀──────────────┐
                   └──────────┬───────────┘               │
                              │ itens + qtd válidos       │ faltam dados
                              ▼                           │
                   ┌──────────────────────┐               │
                   │  CONFIRMANDO_PEDIDO  │───────────────┘
                   └──────────┬───────────┘
                   confirma   │           não
                   ┌──────────┴──────────┐
                   ▼                     ▼
      ┌────────────────────┐   ┌────────────────────┐
      │ AGUARDANDO_ENDERECO│   │  COLETANDO_PEDIDO  │
      │ (se entrega)       │   └────────────────────┘
      └──────────┬─────────┘
                 ▼
      ┌──────────────────────┐
      │ AGUARDANDO_PAGAMENTO │
      └──────────┬───────────┘
                 │ pagou / dinheiro / cartão na retirada
                 ▼
      ┌──────────────────────┐    cozinha aceita
      │  PEDIDO_CONFIRMADO   │────────────────────▶  EM_PREPARO
      └──────────────────────┘                       │
                                                     │ cozinha finaliza
                                                     ▼
                                                  ┌────────┐
                                                  │ PRONTO │
                                                  └───┬────┘
                              retirado/entregue      │
                                                     ▼
                                              ┌─────────────┐
                                              │ FINALIZADO  │
                                              └─────────────┘

      [HUMANO]  ← qualquer estado, quando IA não resolve
```

## Tabela de responsabilidades

| Estado                | Quem altera?           | O que o bot faz nesse estado?                      |
|-----------------------|------------------------|----------------------------------------------------|
| INICIO                | Workflow 01 (AI)       | Cumprimenta, pergunta nome, mostra cardápio        |
| COLETANDO_PEDIDO      | Workflow 01 (AI)       | Interpreta itens/qtd, valida mínimo 10             |
| CONFIRMANDO_PEDIDO    | Workflow 01 (AI)       | Repete pedido + total, pede "confirma?"            |
| AGUARDANDO_ENDERECO   | Workflow 01 (AI)       | Pede rua/número/referência                         |
| AGUARDANDO_PAGAMENTO  | Workflow 01 (AI)       | Pergunta forma; se Pix, envia chave e aguarda      |
| PEDIDO_CONFIRMADO     | Workflow 01 (ao CRIAR) | Informa tempo; dispara cozinha                     |
| EM_PREPARO            | Workflow 02            | Notifica cliente "saindo da fritura"               |
| PRONTO                | Workflow 02            | Notifica pronto; se entrega, dispara Workflow 05   |
| SAIU_ENTREGA          | Workflow 05            | Motoboy a caminho; envia link de rastreio          |
| FINALIZADO            | Workflow 02/05         | Fecha ciclo; reinicia no próximo "oi"              |
| HUMANO                | Workflow 01 (fallback) | Bot pausa respostas; operação humana assume        |

## Regras invariantes

1. `estado_atual` é fonte única de verdade — nada decide por "chute" do que falta.
2. Qualquer transição é **persistida antes** do envio da resposta ao WhatsApp.
   Se a gravação falhar, a resposta NÃO vai (evita estado dessincronizado).
3. Cliente em `HUMANO` **não recebe resposta automática** até operação resetar.
4. `INICIO` é estado efêmero — só existe antes da primeira resposta.
5. Ao criar pedido, `contexto` vira `{}` (carrinho some), mas histórico fica.

## Timeouts (no Workflow 03)

| Estado                | Timeout      | Ação                                    |
|-----------------------|--------------|-----------------------------------------|
| COLETANDO_PEDIDO      | > 24h        | Reengajamento ("ainda quer finalizar?") |
| AGUARDANDO_PAGAMENTO  | > 2h         | Cancela pedido pendente; avisa cliente  |
| PRONTO (retirada)     | > 20 min     | Lembrete "tá te esperando"              |
| PRONTO (retirada)     | > 2h         | Alerta operação (Slack)                 |
