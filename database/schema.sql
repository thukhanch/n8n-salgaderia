-- =====================================================================
-- SALGADERIA - SCHEMA POSTGRESQL
-- Banco operacional do agente n8n
-- v2: Mercado Pago + Motoboy + Google Calendar + Impressora + Fidelidade
-- =====================================================================

CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ---------------------------------------------------------------------
-- 1. PRODUTOS (catálogo)
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS produtos (
    id            SERIAL PRIMARY KEY,
    nome          TEXT        NOT NULL,
    categoria     TEXT        NOT NULL CHECK (categoria IN ('frito','assado','bebida','combo')),
    preco         NUMERIC(8,2) NOT NULL DEFAULT 1.00,
    ativo         BOOLEAN     NOT NULL DEFAULT TRUE,
    criado_em     TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

INSERT INTO produtos (nome, categoria, preco) VALUES
    ('Coxinha',         'frito',  1.00),
    ('Risole de carne', 'frito',  1.00),
    ('Bolinha de queijo','frito', 1.00),
    ('Kibe',            'frito',  1.00),
    ('Esfiha de carne', 'assado', 1.00),
    ('Esfiha de frango','assado', 1.00),
    ('Empada de frango','assado', 1.00),
    ('Refrigerante lata','bebida',6.00),
    ('Suco 300ml',      'bebida', 5.00)
ON CONFLICT DO NOTHING;

-- ---------------------------------------------------------------------
-- 2. CLIENTES (cadastro + estado da conversa)
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS clientes (
    telefone        TEXT        PRIMARY KEY,        -- E.164 sem '+'
    nome            TEXT,
    endereco        TEXT,
    lat             NUMERIC(10,7),                  -- geocoding (motoboy)
    lng             NUMERIC(10,7),
    estado_atual    TEXT        NOT NULL DEFAULT 'INICIO',
    contexto        JSONB       NOT NULL DEFAULT '{}'::JSONB,
    pontos_fidelidade INT       NOT NULL DEFAULT 0, -- feature futura
    ultima_msg_em   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    criado_em       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CHECK (estado_atual IN (
        'INICIO',
        'COLETANDO_PEDIDO',
        'CONFIRMANDO_PEDIDO',
        'AGUARDANDO_ENDERECO',
        'AGUARDANDO_PAGAMENTO',
        'PEDIDO_CONFIRMADO',
        'EM_PREPARO',
        'PRONTO',
        'SAIU_ENTREGA',
        'FINALIZADO',
        'HUMANO'
    ))
);

CREATE INDEX IF NOT EXISTS idx_clientes_estado ON clientes (estado_atual);
CREATE INDEX IF NOT EXISTS idx_clientes_ultima ON clientes (ultima_msg_em);

-- ---------------------------------------------------------------------
-- 3. PEDIDOS
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS pedidos (
    id               UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    codigo           SERIAL       UNIQUE,
    telefone         TEXT         NOT NULL REFERENCES clientes(telefone),
    nome_cliente     TEXT         NOT NULL,
    itens            JSONB        NOT NULL,
    quantidade_total INT          NOT NULL,
    valor_total      NUMERIC(10,2) NOT NULL,
    taxa_entrega     NUMERIC(8,2) NOT NULL DEFAULT 0,
    tipo_entrega     TEXT         NOT NULL CHECK (tipo_entrega IN ('retirada','entrega')),
    endereco         TEXT,
    endereco_lat     NUMERIC(10,7),
    endereco_lng     NUMERIC(10,7),
    forma_pagamento  TEXT         NOT NULL CHECK (forma_pagamento IN ('pix','dinheiro','cartao_entrega')),
    status           TEXT         NOT NULL DEFAULT 'NOVO' CHECK (status IN
                       ('NOVO','AGUARDANDO_PAGAMENTO','PAGO','EM_PREPARO','PRONTO',
                        'SAIU_ENTREGA','ENTREGUE','CANCELADO')),
    observacao       TEXT,
    horario_previsto TIMESTAMPTZ,

    -- Mercado Pago
    mp_payment_id    TEXT,
    mp_qr_code       TEXT,                -- copia-e-cola
    mp_qr_base64     TEXT,                -- imagem QR
    mp_status        TEXT,                -- pending / approved / rejected / refunded
    mp_paid_at       TIMESTAMPTZ,

    -- Motoboy
    motoboy_provider     TEXT,            -- lalamove | uber_direct | loggi | manual
    motoboy_order_id     TEXT,
    motoboy_status       TEXT,            -- REQUESTED | ACCEPTED | PICKING_UP | DELIVERING | DELIVERED | CANCELED
    motoboy_driver_name  TEXT,
    motoboy_driver_phone TEXT,
    motoboy_tracking_url TEXT,
    motoboy_fee          NUMERIC(8,2),

    -- Google Calendar
    gcal_event_id    TEXT,

    -- Impressora
    printed_at       TIMESTAMPTZ,
    print_attempts   INT          NOT NULL DEFAULT 0,

    criado_em        TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    atualizado_em    TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_pedidos_status   ON pedidos (status);
CREATE INDEX IF NOT EXISTS idx_pedidos_telefone ON pedidos (telefone);
CREATE INDEX IF NOT EXISTS idx_pedidos_criado   ON pedidos (criado_em DESC);
CREATE INDEX IF NOT EXISTS idx_pedidos_mp_id    ON pedidos (mp_payment_id);
CREATE INDEX IF NOT EXISTS idx_pedidos_motoboy  ON pedidos (motoboy_order_id);

-- ---------------------------------------------------------------------
-- 4. CONVERSAS (memória curta por cliente)
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS conversas (
    id          BIGSERIAL    PRIMARY KEY,
    telefone    TEXT         NOT NULL,
    sender      TEXT         NOT NULL CHECK (sender IN ('cliente','bot','humano')),
    mensagem    TEXT         NOT NULL,
    intencao    TEXT,
    criado_em   TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_conversas_tel_data ON conversas (telefone, criado_em DESC);

-- ---------------------------------------------------------------------
-- 5. EVENTOS (auditoria)
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS eventos (
    id          BIGSERIAL    PRIMARY KEY,
    telefone    TEXT,
    pedido_id   UUID,
    tipo        TEXT         NOT NULL,
    payload     JSONB        NOT NULL DEFAULT '{}'::JSONB,
    criado_em   TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_eventos_pedido ON eventos (pedido_id);
CREATE INDEX IF NOT EXISTS idx_eventos_tipo   ON eventos (tipo);

-- ---------------------------------------------------------------------
-- 6. PAGAMENTOS (histórico de tentativas - Mercado Pago)
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS pagamentos (
    id              UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    pedido_id       UUID         NOT NULL REFERENCES pedidos(id) ON DELETE CASCADE,
    provider        TEXT         NOT NULL DEFAULT 'mercadopago',
    provider_id     TEXT,                           -- mp payment id
    metodo          TEXT         NOT NULL,          -- pix | card
    valor           NUMERIC(10,2) NOT NULL,
    status          TEXT         NOT NULL,          -- pending|approved|rejected|refunded|cancelled
    raw             JSONB,                          -- payload completo da PSP
    criado_em       TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    atualizado_em   TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_pagamentos_pedido   ON pagamentos (pedido_id);
CREATE INDEX IF NOT EXISTS idx_pagamentos_provider ON pagamentos (provider_id);

-- ---------------------------------------------------------------------
-- 7. ENTREGAS (tracking motoboy)
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS entregas (
    id              UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    pedido_id       UUID         NOT NULL REFERENCES pedidos(id) ON DELETE CASCADE,
    provider        TEXT         NOT NULL,          -- lalamove | uber_direct | loggi | manual
    provider_order_id TEXT,
    status          TEXT         NOT NULL,
    driver_name     TEXT,
    driver_phone    TEXT,
    tracking_url    TEXT,
    pickup_at       TIMESTAMPTZ,
    delivered_at    TIMESTAMPTZ,
    fee             NUMERIC(8,2),
    raw             JSONB,
    criado_em       TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    atualizado_em   TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_entregas_pedido   ON entregas (pedido_id);
CREATE INDEX IF NOT EXISTS idx_entregas_provider ON entregas (provider_order_id);

-- ---------------------------------------------------------------------
-- 8. FIDELIDADE (skeleton - feature futura)
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS fidelidade_transacoes (
    id          BIGSERIAL    PRIMARY KEY,
    telefone    TEXT         NOT NULL REFERENCES clientes(telefone),
    pedido_id   UUID         REFERENCES pedidos(id),
    tipo        TEXT         NOT NULL CHECK (tipo IN ('ACUMULO','RESGATE','EXPIRACAO')),
    pontos      INT          NOT NULL,
    descricao   TEXT,
    criado_em   TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_fidelidade_tel ON fidelidade_transacoes (telefone);

-- ---------------------------------------------------------------------
-- 9. NPS / FEEDBACK (skeleton - feature futura)
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS feedback (
    id          UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    pedido_id   UUID         REFERENCES pedidos(id),
    telefone    TEXT         NOT NULL,
    nota        INT          CHECK (nota BETWEEN 0 AND 10),
    comentario  TEXT,
    criado_em   TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

-- ---------------------------------------------------------------------
-- 10. TRIGGERS
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION trg_set_updated_at() RETURNS trigger AS $$
BEGIN NEW.atualizado_em = NOW(); RETURN NEW; END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS pedidos_set_updated_at ON pedidos;
CREATE TRIGGER pedidos_set_updated_at BEFORE UPDATE ON pedidos
    FOR EACH ROW EXECUTE FUNCTION trg_set_updated_at();

DROP TRIGGER IF EXISTS pagamentos_set_updated_at ON pagamentos;
CREATE TRIGGER pagamentos_set_updated_at BEFORE UPDATE ON pagamentos
    FOR EACH ROW EXECUTE FUNCTION trg_set_updated_at();

DROP TRIGGER IF EXISTS entregas_set_updated_at ON entregas;
CREATE TRIGGER entregas_set_updated_at BEFORE UPDATE ON entregas
    FOR EACH ROW EXECUTE FUNCTION trg_set_updated_at();

-- ---------------------------------------------------------------------
-- 11. VIEWS
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW vw_pedidos_cozinha AS
SELECT codigo, nome_cliente, telefone, itens, quantidade_total,
       tipo_entrega, observacao, status, criado_em
FROM pedidos
WHERE status IN ('PAGO','EM_PREPARO','PRONTO')
ORDER BY criado_em ASC;

CREATE OR REPLACE VIEW vw_clientes_inativos_24h AS
SELECT telefone, nome, estado_atual, ultima_msg_em
FROM clientes
WHERE estado_atual NOT IN ('FINALIZADO','INICIO')
  AND ultima_msg_em < NOW() - INTERVAL '24 hours';

CREATE OR REPLACE VIEW vw_pedidos_entrega_pendente AS
SELECT p.*, c.lat AS cliente_lat, c.lng AS cliente_lng
FROM pedidos p
JOIN clientes c ON c.telefone = p.telefone
WHERE p.tipo_entrega = 'entrega'
  AND p.status = 'PRONTO'
  AND p.motoboy_order_id IS NULL;

CREATE OR REPLACE VIEW vw_pedidos_nao_impressos AS
SELECT * FROM pedidos
WHERE status IN ('PAGO','EM_PREPARO')
  AND printed_at IS NULL
  AND print_attempts < 5
ORDER BY criado_em ASC;
