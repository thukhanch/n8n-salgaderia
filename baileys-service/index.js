// =====================================================================
// Baileys Service - Salgaderia
// Ponte WhatsApp ↔ n8n.
//   - IN:  escuta mensagens e faz POST para WEBHOOK_N8N_URL
//   - OUT: HTTP API local para n8n enviar mensagens (/send-text, /send-image)
// =====================================================================

import 'dotenv/config';
import express from 'express';
import pino from 'pino';
import qrcode from 'qrcode-terminal';
import { fetch } from 'undici';
import {
  default as makeWASocket,
  DisconnectReason,
  useMultiFileAuthState,
  fetchLatestBaileysVersion,
} from '@whiskeysockets/baileys';

const log = pino({ level: process.env.LOG_LEVEL || 'info' });

const {
  PORT = 3001,
  AUTH_DIR = './auth',
  WEBHOOK_N8N_URL,                       // p/ onde mandamos msgs recebidas
  SERVICE_TOKEN,                         // usado nos headers (outgoing e incoming)
} = process.env;

if (!WEBHOOK_N8N_URL) throw new Error('WEBHOOK_N8N_URL é obrigatória');

let sock;

async function start() {
  const { state, saveCreds } = await useMultiFileAuthState(AUTH_DIR);
  const { version } = await fetchLatestBaileysVersion();

  sock = makeWASocket({
    version,
    auth: state,
    printQRInTerminal: false,
    logger: pino({ level: 'warn' }),
    markOnlineOnConnect: false,
    syncFullHistory: false,
  });

  sock.ev.on('creds.update', saveCreds);

  sock.ev.on('connection.update', ({ connection, lastDisconnect, qr }) => {
    if (qr) {
      log.info('Escaneie o QR code abaixo com o WhatsApp do negócio:');
      qrcode.generate(qr, { small: true });
    }
    if (connection === 'open') log.info('WhatsApp conectado ✅');
    if (connection === 'close') {
      const code = lastDisconnect?.error?.output?.statusCode;
      const shouldReconnect = code !== DisconnectReason.loggedOut;
      log.warn({ code }, `Conexão fechada. Reconnect=${shouldReconnect}`);
      if (shouldReconnect) setTimeout(start, 2000);
    }
  });

  sock.ev.on('messages.upsert', async ({ messages, type }) => {
    if (type !== 'notify') return;
    for (const m of messages) {
      if (!m.message) continue;
      if (m.key.fromMe) continue;                     // ignora própria mensagem

      const payload = {
        id:          m.key.id,
        remoteJid:   m.key.remoteJid,
        telefone:    (m.key.remoteJid || '').replace(/@s\.whatsapp\.net|@c\.us|@g\.us/g, ''),
        fromMe:      m.key.fromMe,
        pushName:    m.pushName || '',
        messageType: Object.keys(m.message || {})[0],
        text:
          m.message.conversation ||
          m.message.extendedTextMessage?.text ||
          m.message.imageMessage?.caption ||
          '',
        hasMedia: !!(m.message.imageMessage || m.message.audioMessage || m.message.documentMessage),
        timestamp: m.messageTimestamp,
      };

      try {
        const res = await fetch(WEBHOOK_N8N_URL, {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            ...(SERVICE_TOKEN ? { Authorization: `Bearer ${SERVICE_TOKEN}` } : {}),
          },
          body: JSON.stringify(payload),
        });
        if (!res.ok) log.error({ status: res.status }, 'n8n webhook respondeu !ok');
      } catch (err) {
        log.error({ err: err.message }, 'Falha POST n8n');
      }
    }
  });
}

// --------- HTTP API (n8n → Baileys) ---------
const app = express();
app.use(express.json({ limit: '5mb' }));

app.use((req, res, next) => {
  if (!SERVICE_TOKEN) return next();
  const got = (req.headers.authorization || '').replace('Bearer ', '');
  if (got !== SERVICE_TOKEN) return res.status(401).json({ error: 'unauthorized' });
  next();
});

const jidFromNumber = (n) => (n.includes('@') ? n : `${n.replace(/\D/g, '')}@s.whatsapp.net`);

app.get('/health', (_req, res) => res.json({ ok: true, connected: !!sock?.user }));

app.post('/send-text', async (req, res) => {
  try {
    const { number, text } = req.body;
    const r = await sock.sendMessage(jidFromNumber(number), { text });
    res.json({ ok: true, id: r?.key?.id });
  } catch (err) {
    log.error({ err: err.message }, 'send-text falhou');
    res.status(500).json({ ok: false, error: err.message });
  }
});

app.post('/send-image', async (req, res) => {
  try {
    const { number, imageUrl, imageBase64, caption } = req.body;
    const image = imageBase64 ? Buffer.from(imageBase64, 'base64') : { url: imageUrl };
    const r = await sock.sendMessage(jidFromNumber(number), { image, caption });
    res.json({ ok: true, id: r?.key?.id });
  } catch (err) {
    res.status(500).json({ ok: false, error: err.message });
  }
});

app.post('/send-location', async (req, res) => {
  try {
    const { number, lat, lng, name, address } = req.body;
    const r = await sock.sendMessage(jidFromNumber(number), {
      location: { degreesLatitude: lat, degreesLongitude: lng, name, address },
    });
    res.json({ ok: true, id: r?.key?.id });
  } catch (err) {
    res.status(500).json({ ok: false, error: err.message });
  }
});

app.listen(PORT, () => log.info(`Baileys HTTP em :${PORT}`));
start().catch((e) => log.error(e));
