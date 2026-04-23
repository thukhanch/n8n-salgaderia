-- =====================================================================
-- SALGADERIA - SCHEMA POSTGRESQL / SUPABASE
-- Banco operacional do agente n8n
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
    estado_atual    TEXT        NOT NULL DEFAULT 'INICIO',
    contexto        JSONB       NOT NULL DEFAULT '{}'::JSONB,  -- carrinho, dados parciais
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
        'FINALIZADO',
        'HUMANO'
    ))
);

CREATE INDEX IF NOT EXISTS idx_clientes_estado ON clientes (estado_atual);
CREATE INDEX IF NOT EXISTS idx_clientes_ultima  ON clientes (ultima_msg_em);

-- ---------------------------------------------------------------------
-- 3. PEDIDOS
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS pedidos (
    id               UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    codigo           SERIAL       UNIQUE,            -- número curto p/ cozinha
    telefone         TEXT         NOT NULL REFERENCES clientes(telefone),
    nome_cliente     TEXT         NOT NULL,
    itens            JSONB        NOT NULL,          -- [{produto_id, nome, qtd, preco_unit}]
    quantidade_total INT          NOT NULL,
    valor_total      NUMERIC(10,2) NOT NULL,
    tipo_entrega     TEXT         NOT NULL CHECK (tipo_entrega IN ('retirada','entrega')),
    endereco         TEXT,
    forma_pagamento  TEXT         NOT NULL CHECK (forma_pagamento IN ('pix','dinheiro','cartao_entrega')),
    status           TEXT         NOT NULL DEFAULT 'NOVO' CHECK (status IN
                       ('NOVO','PAGO','EM_PREPARO','PRONTO','SAIU_ENTREGA','ENTREGUE','CANCELADO')),
    observacao       TEXT,
    horario_previsto TIMESTAMPTZ,
    criado_em        TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    atualizado_em    TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_pedidos_status   ON pedidos (status);
CREATE INDEX IF NOT EXISTS idx_pedidos_telefone ON pedidos (telefone);
CREATE INDEX IF NOT EXISTS idx_pedidos_criado   ON pedidos (criado_em DESC);

-- ---------------------------------------------------------------------
-- 4. CONVERSAS (memória curta por cliente)
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS conversas (
    id          BIGSERIAL    PRIMARY KEY,
    telefone    TEXT         NOT NULL,
    sender      TEXT         NOT NULL CHECK (sender IN ('cliente','bot','humano')),
    mensagem    TEXT         NOT NULL,
    intencao    TEXT,                                -- saudacao, pedido, duvida, cancelar, etc
    criado_em   TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_conversas_tel_data ON conversas (telefone, criado_em DESC);

-- ---------------------------------------------------------------------
-- 5. EVENTOS (auditoria do estado machine)
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS eventos (
    id          BIGSERIAL    PRIMARY KEY,
    telefone    TEXT,
    pedido_id   UUID,
    tipo        TEXT         NOT NULL,               -- ESTADO_MUDOU, ERRO_API, FALLBACK_HUMANO
    payload     JSONB        NOT NULL DEFAULT '{}'::JSONB,
    criado_em   TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

-- ---------------------------------------------------------------------
-- 6. TRIGGER: atualizar atualizado_em
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION trg_set_updated_at() RETURNS trigger AS $$
BEGIN NEW.atualizado_em = NOW(); RETURN NEW; END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS pedidos_set_updated_at ON pedidos;
CREATE TRIGGER pedidos_set_updated_at BEFORE UPDATE ON pedidos
    FOR EACH ROW EXECUTE FUNCTION trg_set_updated_at();

-- ---------------------------------------------------------------------
-- 7. VIEWS úteis
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
