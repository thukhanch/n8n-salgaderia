-- =====================================================================
-- AGENT UNIVERSAL - SCHEMA POSTGRESQL (multi-tenant)
-- Base universal para qualquer nicho (vendas, atendimento, agendamento)
-- =====================================================================

CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ---------------------------------------------------------------------
-- TENANTS (cada cliente final = 1 tenant)
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS tenants (
    id              UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    slug            TEXT         UNIQUE NOT NULL,            -- 'studio-x'
    nome            TEXT         NOT NULL,
    timezone        TEXT         NOT NULL DEFAULT 'America/Sao_Paulo',
    config          JSONB        NOT NULL DEFAULT '{}'::JSONB,
        -- {
        --   "prompt_extra": "...",
        --   "business_hours": {"mon": ["09:00-18:00"], ...},
        --   "appointment_default_min": 60,
        --   "products": [{"sku":"...","name":"...","price":...}],
        --   "calendar_id": "primary",
        --   "gmail_from": "atendimento@cliente.com",
        --   "tools_enabled": ["calendar.*","payment.*","gmail.send"],
        --   "handoff_channel": "slack-webhook-url",
        --   "language": "pt-BR"
        -- }
    ativo           BOOLEAN      NOT NULL DEFAULT TRUE,
    criado_em       TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    atualizado_em   TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_tenants_slug ON tenants (slug);

-- ---------------------------------------------------------------------
-- CHANNELS (ligações tenant ↔ canal externo)
--   Ex: WhatsApp instance "studio-x", Gmail account "...@cliente.com"
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS channels (
    id              UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id       UUID         NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    kind            TEXT         NOT NULL CHECK (kind IN ('whatsapp','gmail','webchat','telegram','sms')),
    external_id     TEXT         NOT NULL,                   -- baileys instance, gmail address, etc
    config          JSONB        NOT NULL DEFAULT '{}'::JSONB,
    ativo           BOOLEAN      NOT NULL DEFAULT TRUE,
    criado_em       TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    UNIQUE (kind, external_id)
);

CREATE INDEX IF NOT EXISTS idx_channels_tenant ON channels (tenant_id);

-- ---------------------------------------------------------------------
-- CONTACTS (uma pessoa por tenant; identificada por canal+identifier)
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS contacts (
    id              UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id       UUID         NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    nome            TEXT,
    email           TEXT,
    telefone        TEXT,
    attributes      JSONB        NOT NULL DEFAULT '{}'::JSONB,  -- livre por tenant
    estado          TEXT         NOT NULL DEFAULT 'NOVO',
    contexto        JSONB        NOT NULL DEFAULT '{}'::JSONB,  -- working memory do agente
    tags            TEXT[]       NOT NULL DEFAULT '{}',
    consent_marketing BOOLEAN    NOT NULL DEFAULT FALSE,
    ultima_msg_em   TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    criado_em       TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    atualizado_em   TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_contacts_tenant_tel   ON contacts (tenant_id, telefone);
CREATE INDEX IF NOT EXISTS idx_contacts_tenant_email ON contacts (tenant_id, email);
CREATE INDEX IF NOT EXISTS idx_contacts_estado       ON contacts (tenant_id, estado);
CREATE UNIQUE INDEX IF NOT EXISTS uq_contacts_tenant_tel
    ON contacts (tenant_id, telefone) WHERE telefone IS NOT NULL;

-- ---------------------------------------------------------------------
-- CONVERSATIONS (todas as mensagens, qualquer canal)
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS conversations (
    id              BIGSERIAL    PRIMARY KEY,
    tenant_id       UUID         NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    contact_id      UUID         NOT NULL REFERENCES contacts(id) ON DELETE CASCADE,
    channel         TEXT         NOT NULL,
    sender          TEXT         NOT NULL CHECK (sender IN ('contact','agent','human')),
    content         TEXT         NOT NULL,
    intent          TEXT,
    metadata        JSONB        NOT NULL DEFAULT '{}'::JSONB,
    criado_em       TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_conv_tenant_contact ON conversations (tenant_id, contact_id, criado_em DESC);

-- ---------------------------------------------------------------------
-- APPOINTMENTS (agendamentos sincronizados com Google Calendar)
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS appointments (
    id              UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id       UUID         NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    contact_id      UUID         NOT NULL REFERENCES contacts(id),
    titulo          TEXT         NOT NULL,
    descricao       TEXT,
    inicio          TIMESTAMPTZ  NOT NULL,
    fim             TIMESTAMPTZ  NOT NULL,
    status          TEXT         NOT NULL DEFAULT 'AGENDADO'
                       CHECK (status IN ('AGENDADO','CONFIRMADO','REAGENDADO','CANCELADO','REALIZADO','NO_SHOW')),
    gcal_event_id   TEXT,
    metadata        JSONB        NOT NULL DEFAULT '{}'::JSONB,
    reminder_sent   TIMESTAMPTZ,
    criado_em       TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    atualizado_em   TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_appt_tenant_inicio ON appointments (tenant_id, inicio);
CREATE INDEX IF NOT EXISTS idx_appt_status        ON appointments (tenant_id, status);

-- ---------------------------------------------------------------------
-- DEALS (oportunidades / pedidos / contratos — pipeline de vendas)
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS deals (
    id              UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id       UUID         NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    contact_id      UUID         NOT NULL REFERENCES contacts(id),
    titulo          TEXT         NOT NULL,
    stage           TEXT         NOT NULL DEFAULT 'LEAD',
                       -- 'LEAD','QUALIFICADO','PROPOSTA','NEGOCIACAO','GANHO','PERDIDO'
    valor           NUMERIC(12,2) NOT NULL DEFAULT 0,
    itens           JSONB        NOT NULL DEFAULT '[]'::JSONB,
    metadata        JSONB        NOT NULL DEFAULT '{}'::JSONB,
    fechado_em      TIMESTAMPTZ,
    criado_em       TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    atualizado_em   TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_deals_tenant_stage ON deals (tenant_id, stage);

-- ---------------------------------------------------------------------
-- PAYMENTS (pagamentos genéricos; provider abstraído)
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS payments (
    id              UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id       UUID         NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    deal_id         UUID         REFERENCES deals(id) ON DELETE SET NULL,
    contact_id      UUID         REFERENCES contacts(id),
    provider        TEXT         NOT NULL DEFAULT 'mercadopago',
    provider_id     TEXT,
    method          TEXT         NOT NULL,                   -- pix | boleto | card
    amount          NUMERIC(12,2) NOT NULL,
    status          TEXT         NOT NULL,                   -- pending|approved|rejected|refunded
    qr_code         TEXT,
    qr_base64       TEXT,
    paid_at         TIMESTAMPTZ,
    raw             JSONB,
    criado_em       TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    atualizado_em   TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_payments_tenant   ON payments (tenant_id);
CREATE INDEX IF NOT EXISTS idx_payments_provider ON payments (provider, provider_id);

-- ---------------------------------------------------------------------
-- TOOL_CALLS (auditoria de cada chamada de ferramenta pelo agente)
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS tool_calls (
    id              BIGSERIAL    PRIMARY KEY,
    tenant_id       UUID         NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    contact_id      UUID         REFERENCES contacts(id),
    tool            TEXT         NOT NULL,                   -- 'calendar.book'
    input           JSONB        NOT NULL DEFAULT '{}'::JSONB,
    output          JSONB,
    success         BOOLEAN,
    duration_ms     INT,
    criado_em       TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_toolcalls_tenant ON tool_calls (tenant_id, criado_em DESC);
CREATE INDEX IF NOT EXISTS idx_toolcalls_tool   ON tool_calls (tool);

-- ---------------------------------------------------------------------
-- EVENTS (auditoria geral)
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS events (
    id              BIGSERIAL    PRIMARY KEY,
    tenant_id       UUID         REFERENCES tenants(id) ON DELETE CASCADE,
    contact_id      UUID         REFERENCES contacts(id),
    tipo            TEXT         NOT NULL,
    payload         JSONB        NOT NULL DEFAULT '{}'::JSONB,
    criado_em       TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_events_tenant ON events (tenant_id, criado_em DESC);

-- ---------------------------------------------------------------------
-- TRIGGERS
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION trg_set_updated_at() RETURNS trigger AS $$
BEGIN NEW.atualizado_em = NOW(); RETURN NEW; END;
$$ LANGUAGE plpgsql;

DO $$ BEGIN
    PERFORM 1 FROM pg_trigger WHERE tgname = 't_tenants_upd';
    IF NOT FOUND THEN
        CREATE TRIGGER t_tenants_upd      BEFORE UPDATE ON tenants      FOR EACH ROW EXECUTE FUNCTION trg_set_updated_at();
        CREATE TRIGGER t_contacts_upd     BEFORE UPDATE ON contacts     FOR EACH ROW EXECUTE FUNCTION trg_set_updated_at();
        CREATE TRIGGER t_appointments_upd BEFORE UPDATE ON appointments FOR EACH ROW EXECUTE FUNCTION trg_set_updated_at();
        CREATE TRIGGER t_deals_upd        BEFORE UPDATE ON deals        FOR EACH ROW EXECUTE FUNCTION trg_set_updated_at();
        CREATE TRIGGER t_payments_upd     BEFORE UPDATE ON payments     FOR EACH ROW EXECUTE FUNCTION trg_set_updated_at();
    END IF;
END $$;

-- ---------------------------------------------------------------------
-- VIEWS úteis
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW vw_appointments_proximas_24h AS
SELECT a.*, c.nome AS contato_nome, c.telefone, c.email
FROM appointments a
JOIN contacts c ON c.id = a.contact_id
WHERE a.status IN ('AGENDADO','CONFIRMADO')
  AND a.inicio BETWEEN NOW() AND NOW() + INTERVAL '24 hours'
  AND a.reminder_sent IS NULL;

CREATE OR REPLACE VIEW vw_contacts_inativos_7d AS
SELECT *
FROM contacts
WHERE estado <> 'FINALIZADO'
  AND ultima_msg_em < NOW() - INTERVAL '7 days';

CREATE OR REPLACE VIEW vw_deals_pipeline AS
SELECT tenant_id, stage, COUNT(*) AS qtd, SUM(valor) AS total
FROM deals
WHERE stage NOT IN ('GANHO','PERDIDO')
GROUP BY tenant_id, stage;
