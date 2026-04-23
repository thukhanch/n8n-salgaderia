# Mercado Pago - Pix Dinâmico

Workflow: `workflows/04-mercadopago-pix.json`

## O que faz

1. Quando o pedido é criado com `forma_pagamento='pix'`, o workflow 01
   chama este como **sub-workflow** passando `{ pedido }`.
2. Cria charge Pix via `POST /v1/payments` com `payment_method_id: pix`.
3. Persiste `mp_payment_id`, `mp_qr_code` (copia-e-cola) e `mp_qr_base64` (imagem).
4. Envia **QR code em imagem** e o **copia-e-cola em texto** ao cliente via Baileys.
5. Quando o pagamento cair, MP dispara IPN em `/webhook/salgaderia/mp-webhook`:
   - Busca status atual do pagamento (confirma via GET, não confia no body)
   - Atualiza `pedidos.mp_status`, `pagamentos.status`
   - Se `approved` → muda status do pedido para `PAGO`, notifica cliente e cozinha

## Setup

1. Criar aplicação em https://www.mercadopago.com.br/developers/panel
2. Copiar **Access Token (produção)** para `MP_ACCESS_TOKEN`
3. Configurar **Notificações (IPN)**:
   - URL: `https://n8n.seudominio.com/webhook/salgaderia/mp-webhook`
   - Eventos: `payment`
4. Em produção o app precisa estar `Em produção` no painel (liberação de credenciais)

## Segurança

- **X-Idempotency-Key**: enviamos `pedido.id` (UUID) para evitar cobrança duplicada caso o workflow rode 2x
- **Confirmação dupla**: nunca marcamos PAGO só pelo IPN; sempre fazemos GET no MP para confirmar status real
- **Webhook signature (opcional)**: MP envia `x-signature` — podemos validar em produção. Hoje está simples por confiança na URL pública + HTTPS

## Taxas

- Pix no MP: ~0,99% (no recebimento imediato)
- Cai em conta MP; transferência para banco é gratuita (D+0)

## Alternativas

- Efí (antiga Gerencianet): API Pix simples, sem taxa nas primeiras 80 transações/mês
- Asaas: API pix + boleto + cartão no mesmo SDK

Para trocar, basta criar um `04b-efi-pix.json` com o mesmo contrato de sub-workflow (`{ pedido }` de entrada) e alterar o `WF_MERCADOPAGO` no workflow 01.
