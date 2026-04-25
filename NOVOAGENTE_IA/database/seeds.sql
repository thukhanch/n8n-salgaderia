-- Seed: 1 tenant demo para desenvolvimento
INSERT INTO tenants (slug, nome, timezone, config) VALUES (
  'demo',
  'Tenant Demo',
  'America/Sao_Paulo',
  jsonb_build_object(
    'prompt_extra', E'Você atende uma empresa de demonstração que vende serviços de consultoria.\nProdutos: Consultoria 1h (R$ 300), Consultoria pacote 4h (R$ 1.000).\nVocê pode agendar reuniões e gerar cobranças via Pix.',
    'business_hours', jsonb_build_object(
      'mon', jsonb_build_array('09:00-18:00'),
      'tue', jsonb_build_array('09:00-18:00'),
      'wed', jsonb_build_array('09:00-18:00'),
      'thu', jsonb_build_array('09:00-18:00'),
      'fri', jsonb_build_array('09:00-17:00')
    ),
    'appointment_default_min', 60,
    'products', jsonb_build_array(
      jsonb_build_object('sku','CONS-1H','name','Consultoria 1h','price',300),
      jsonb_build_object('sku','CONS-4H','name','Pacote 4h','price',1000)
    ),
    'calendar_id', 'primary',
    'gmail_from', 'atendimento@demo.local',
    'tools_enabled', jsonb_build_array(
      'calendar.check_availability','calendar.book','calendar.cancel',
      'gmail.send','payment.create_pix','contact.update','deal.upsert','handoff.human'
    ),
    'language', 'pt-BR'
  )
) ON CONFLICT (slug) DO NOTHING;

-- Channel demo: WhatsApp instance "demo"
INSERT INTO channels (tenant_id, kind, external_id, config)
SELECT id, 'whatsapp', 'demo', '{}'::jsonb FROM tenants WHERE slug='demo'
ON CONFLICT DO NOTHING;
