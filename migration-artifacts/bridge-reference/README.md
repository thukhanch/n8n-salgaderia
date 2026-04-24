# Bridge Baileys internalizada (referência)

Copiado de `~/whatsapp-flow/apps/api/src/modules/whatsapp` em 2026-04-23.

## Objetivo
Trazer para dentro do projeto `n8n-salgaderia` a camada mínima hoje usada como transporte WhatsApp via Baileys.

## Conteúdo copiado
- `whatsapp/` módulo NestJS com controller, gateway, service e entity
- `main.ts` e `app.module.ts` do runtime atual usados apenas como referência técnica

## Status
- Cópia de referência iniciada.
- Runtime principal ainda não foi migrado para execução nativa dentro deste repositório.
- Enquanto isso, o `whatsapp-flow` continua sendo a fonte operacional temporária até a bridge local ser religada e validada.

## Próxima migração real
1. Criar um runtime mínimo próprio dentro deste repositório
2. Isolar dependências realmente necessárias
3. Persistir sessões em caminho local do projeto novo
4. Subir a API da bridge em porta local estável
5. Validar `GET /api/whatsapp/sessions` e `POST /api/whatsapp/sessions/:id/send`
6. Só então deixar o `whatsapp-flow` apenas como consulta
