// =====================================================================
// Baileys Service - Agent Universal (multi-instance / multi-tenant)
//   - Uma instância WhatsApp por tenant (identificada pelo slug)
//   - IN:  cada msg recebida → POST WEBHOOK_N8N_URL com {instance, telefone, text,...}
//   - OUT: HTTP API /send-text /send-image /send-location recebe {instance, ...}
// =====================================================================

import 'dotenv/config';
import express from 'express';
import pino from 'pino';
import qrcode from 'qrcode-terminal';
import { fetch } from 'undici';
import fs from 'node:fs';
import path from 'node:path';
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
  WEBHOOK_N8N_URL,
  SERVICE_TOKEN,
  INSTANCES = '',      // lista separada por vírgula: "demo,cliente-x,cliente-y"
} = process.env;

if (!WEBHOOK_N8N_URL) throw new Error('WEBHOOK_N8N_URL obrigatória');

const sockets = new Map();   // instance → sock

async function startInstance(name) {
  const dir = path.join(AUTH_DIR, name);
  fs.mkdirSync(dir, { recursive: true });
  const { state, saveCreds } = await useMultiFileAuthState(dir);
  const { version } = await fetchLatestBaileysVersion();

  const sock = makeWASocket({
    version, auth: state,
    printQRInTerminal: false,
    logger: pino({ level: 'warn' }),
    markOnlineOnConnect: false,
    syncFullHistory: false,
  });

  sock.ev.on('creds.update', saveCreds);

  sock.ev.on('connection.update', ({ connection, lastDisconnect, qr }) => {
    if (qr) {
      log.info(`[${name}] escaneie o QR:`);
      qrcode.generate(qr, { small: true });
    }
    if (connection === 'open') log.info(`[${name}] conectado ✅`);
    if (connection === 'close') {
      const code = lastDisconnect?.error?.output?.statusCode;
      const reconnect = code !== DisconnectReason.loggedOut;
      log.warn({ code }, `[${name}] fechou. reconnect=${reconnect}`);
      if (reconnect) setTimeout(() => startInstance(name), 3000);
    }
  });

  sock.ev.on('messages.upsert', async ({ messages, type }) => {
    if (type !== 'notify') return;
    for (const m of messages) {
      if (!m.message || m.key.fromMe) continue;

      const payload = {
        instance: name,
        id: m.key.id,
        telefone: (m.key.remoteJid || '').replace(/@s\.whatsapp\.net|@c\.us|@g\.us/g, ''),
        fromMe: m.key.fromMe,
        pushName: m.pushName || '',
        messageType: Object.keys(m.message || {})[0],
        text: m.message.conversation ||
              m.message.extendedTextMessage?.text ||
              m.message.imageMessage?.caption || '',
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
        if (!res.ok) log.error({ status: res.status, instance: name }, 'n8n !ok');
      } catch (err) {
        log.error({ err: err.message, instance: name }, 'POST n8n falhou');
      }
    }
  });

  sockets.set(name, sock);
  return sock;
}

// ----- Boot instances -----
const instances = INSTANCES.split(',').map(s => s.trim()).filter(Boolean);
if (!instances.length) instances.push('demo');
for (const name of instances) startInstance(name).catch(e => log.error(e));

// ----- HTTP API -----
const app = express();
app.use(express.json({ limit: '5mb' }));
app.use((req, res, next) => {
  if (!SERVICE_TOKEN) return next();
  const got = (req.headers.authorization || '').replace('Bearer ', '');
  if (got !== SERVICE_TOKEN) return res.status(401).json({ error: 'unauthorized' });
  next();
});

const jid = n => n.includes('@') ? n : `${n.replace(/\D/g,'')}@s.whatsapp.net`;
const sockOf = instance => {
  const s = sockets.get(instance);
  if (!s) throw new Error(`instance "${instance}" not found`);
  return s;
};

app.get('/health', (_req, res) => {
  const info = {};
  for (const [k, s] of sockets) info[k] = { connected: !!s?.user };
  res.json({ ok: true, instances: info });
});

app.post('/instances', async (req, res) => {
  try { await startInstance(req.body.name); res.json({ ok: true }); }
  catch (e) { res.status(500).json({ ok: false, error: e.message }); }
});

app.post('/send-text', async (req, res) => {
  try {
    const { instance, number, text } = req.body;
    const r = await sockOf(instance).sendMessage(jid(number), { text });
    res.json({ ok: true, id: r?.key?.id });
  } catch (e) { res.status(500).json({ ok: false, error: e.message }); }
});

app.post('/send-image', async (req, res) => {
  try {
    const { instance, number, imageUrl, imageBase64, caption } = req.body;
    const image = imageBase64 ? Buffer.from(imageBase64, 'base64') : { url: imageUrl };
    const r = await sockOf(instance).sendMessage(jid(number), { image, caption });
    res.json({ ok: true, id: r?.key?.id });
  } catch (e) { res.status(500).json({ ok: false, error: e.message }); }
});

app.post('/send-location', async (req, res) => {
  try {
    const { instance, number, lat, lng, name, address } = req.body;
    const r = await sockOf(instance).sendMessage(jid(number), {
      location: { degreesLatitude: lat, degreesLongitude: lng, name, address },
    });
    res.json({ ok: true, id: r?.key?.id });
  } catch (e) { res.status(500).json({ ok: false, error: e.message }); }
});

app.listen(PORT, () => log.info(`Baileys multi-instance em :${PORT}`));
