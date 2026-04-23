// =====================================================================
// Printer Service - Salgaderia
// Recebe pedido em JSON via POST /print e imprime na térmica (ESC/POS).
// Suporta rede (TCP, Epson/Bematech) e USB.
// =====================================================================

import 'dotenv/config';
import express from 'express';
import pino from 'pino';
import { printer as ThermalPrinter, types as PrinterTypes } from 'node-thermal-printer';

const log = pino({ level: process.env.LOG_LEVEL || 'info' });

const {
  PORT = 3002,
  PRINTER_TYPE = 'EPSON',          // EPSON | STAR
  PRINTER_INTERFACE = 'tcp://192.168.1.50:9100',  // ou 'printer:usb:...'
  PRINTER_WIDTH = 48,              // colunas
  SERVICE_TOKEN,
  SHOP_NAME = 'SALGADERIA DO BAIRRO',
} = process.env;

const printer = new ThermalPrinter({
  type: PRINTER_TYPE === 'STAR' ? PrinterTypes.STAR : PrinterTypes.EPSON,
  interface: PRINTER_INTERFACE,
  width: Number(PRINTER_WIDTH),
  characterSet: 'PC860_PORTUGUESE',
  removeSpecialCharacters: false,
  options: { timeout: 5000 },
});

async function imprimir(pedido) {
  printer.clear();
  printer.alignCenter();
  printer.setTextDoubleHeight();
  printer.bold(true);
  printer.println(SHOP_NAME);
  printer.bold(false);
  printer.setTextNormal();
  printer.drawLine();

  printer.alignLeft();
  printer.println(`Pedido #${pedido.codigo}`);
  printer.println(`Cliente: ${pedido.nome_cliente}`);
  printer.println(`Tel: ${pedido.telefone}`);
  printer.println(`Tipo: ${pedido.tipo_entrega === 'entrega' ? 'ENTREGA' : 'RETIRADA'}`);
  if (pedido.tipo_entrega === 'entrega' && pedido.endereco) {
    printer.println(`End: ${pedido.endereco}`);
  }
  printer.println(`Pag: ${pedido.forma_pagamento}`);
  printer.println(`Hora: ${new Date(pedido.criado_em).toLocaleString('pt-BR')}`);
  printer.drawLine();

  printer.bold(true);
  printer.println('ITENS:');
  printer.bold(false);
  for (const it of pedido.itens || []) {
    const linha = `${String(it.qtd).padStart(3, ' ')}x ${it.produto}`;
    const total = `R$ ${(it.qtd * it.preco_unit).toFixed(2)}`;
    printer.leftRight(linha, total);
  }
  printer.drawLine();

  if (pedido.taxa_entrega && Number(pedido.taxa_entrega) > 0) {
    printer.leftRight('Taxa de entrega', `R$ ${Number(pedido.taxa_entrega).toFixed(2)}`);
  }
  printer.setTextDoubleHeight();
  printer.bold(true);
  printer.leftRight('TOTAL', `R$ ${Number(pedido.valor_total).toFixed(2)}`);
  printer.bold(false);
  printer.setTextNormal();

  if (pedido.observacao) {
    printer.drawLine();
    printer.println('Observação:');
    printer.println(pedido.observacao);
  }

  printer.drawLine();
  printer.alignCenter();
  printer.println('*** BOM TRABALHO ***');
  printer.newLine();
  printer.cut();

  const ok = await printer.execute();
  if (!ok) throw new Error('printer.execute() retornou falso');
}

const app = express();
app.use(express.json({ limit: '1mb' }));

app.use((req, res, next) => {
  if (!SERVICE_TOKEN) return next();
  const got = (req.headers.authorization || '').replace('Bearer ', '');
  if (got !== SERVICE_TOKEN) return res.status(401).json({ error: 'unauthorized' });
  next();
});

app.get('/health', async (_req, res) => {
  const connected = await printer.isPrinterConnected();
  res.json({ ok: true, printer_connected: connected });
});

app.post('/print', async (req, res) => {
  try {
    await imprimir(req.body);
    res.json({ ok: true, printed_at: new Date().toISOString() });
  } catch (err) {
    log.error({ err: err.message }, 'print falhou');
    res.status(500).json({ ok: false, error: err.message });
  }
});

app.listen(PORT, () => log.info(`Printer HTTP em :${PORT} (iface=${PRINTER_INTERFACE})`));
