# Impressora Térmica

Workflow: `workflows/06-impressora-termica.json`
Microserviço: `printer-service/` (Node.js + `node-thermal-printer`)

## Fluxo

1. Workflow 01, após `Criar Pedido (DB)`, chama Workflow 06 via `Execute Workflow` passando `{ pedido }`.
2. Workflow 06 faz `POST http://printer:3002/print` com o pedido em JSON.
3. O printer service formata ESC/POS (cabeçalho, itens, total, cut) e envia para a térmica.
4. Se retornar `ok: true`, `pedidos.printed_at = NOW()`. Senão, incrementa `print_attempts` e alerta Slack.
5. **Retry automático**: cron de 5min busca `vw_pedidos_nao_impressos` (até 5 tentativas).

## Impressoras suportadas

- **Epson** (TM-T20, T88, etc)
- **Bematech** (MP-4200 — compatível Epson ESC/POS)
- **Star Micronics** (TSP100, TSP143)
- Genéricas ESC/POS

## Interfaces

### 1. Rede (recomendado)
```
PRINTER_INTERFACE=tcp://192.168.1.50:9100
```
Mais estável. Use IP fixo da impressora no roteador.

### 2. USB no host
```
PRINTER_INTERFACE=printer:/dev/usb/lp0
```
No docker-compose.yml, descomente:
```yaml
devices: ["/dev/usb/lp0:/dev/usb/lp0"]
privileged: true
```

### 3. Bluetooth
Não suportado diretamente; use um router Raspberry Pi fazendo bridge BT→TCP.

## Layout da comanda

Configurável em `printer-service/index.js` (`async function imprimir`):
- Largura: 48 col (80mm) ou 32 col (58mm) via `PRINTER_WIDTH`
- Cabeçalho com nome da loja
- Código do pedido em destaque
- Itens com `leftRight(nome, preço)`
- Observação no fim
- `cut()` corta o papel

## Customização

```js
printer.alignCenter().setTextDoubleHeight().bold(true).println('SALGADERIA');
printer.drawLine();
printer.alignLeft().println(`Pedido #${p.codigo}`);
...
```

## Troubleshooting

| Sintoma                          | Causa provável                    | Solução                           |
|----------------------------------|-----------------------------------|-----------------------------------|
| `isPrinterConnected()` = false   | IP errado / impressora dormindo   | ping + desabilitar auto-sleep     |
| Imprime lixo / caracteres tortos | charset errado                    | trocar `PC860_PORTUGUESE`         |
| Não corta papel                  | modelo não suporta auto-cut       | remover `printer.cut()`           |
| Demora > 10s                     | timeout baixo ou rede ruim        | aumentar `timeout` no node HTTP   |

## Fila e concorrência

O service é single-threaded; se dois pedidos chegam juntos, o segundo espera na fila TCP.
Para volumes altos (>30/h), considere fila Redis entre n8n e printer.
