-- Patch de compatibilidade não-destrutivo para usar o banco whatsapp_flow
-- com os workflows do projeto n8n-salgaderia.
-- Objetivo: adicionar/ajustar estrutura faltante sem remover colunas/tabelas legadas.

CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ------------------------------------------------------------------
-- CLIENTES: manter colunas legadas e adicionar colunas esperadas
-- ------------------------------------------------------------------
ALTER TABLE IF EXISTS clientes ADD COLUMN IF NOT EXISTS telefone TEXT;
ALTER TABLE IF EXISTS clientes ADD COLUMN IF NOT EXISTS nome TEXT;
ALTER TABLE IF EXISTS clientes ADD COLUMN IF NOT EXISTS endereco TEXT;
ALTER TABLE IF EXISTS clientes ADD COLUMN IF NOT EXISTS estado_atual TEXT NOT NULL DEFAULT 'INICIO';
ALTER TABLE IF EXISTS clientes ADD COLUMN IF NOT EXISTS contexto JSONB NOT NULL DEFAULT '{}'::JSONB;
ALTER TABLE IF EXISTS clientes ADD COLUMN IF NOT EXISTS ultima_msg_em TIMESTAMPTZ NOT NULL DEFAULT NOW();
ALTER TABLE IF EXISTS clientes ADD COLUMN IF NOT EXISTS criado_em TIMESTAMPTZ NOT NULL DEFAULT NOW();

UPDATE clientes
SET telefone = COALESCE(telefone, phone),
    nome = COALESCE(nome, name),
    criado_em = COALESCE(criado_em, created_at),
    ultima_msg_em = COALESCE(ultima_msg_em, updated_at, created_at, NOW())
WHERE telefone IS NULL OR nome IS NULL OR criado_em IS NULL OR ultima_msg_em IS NULL;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'clientes_telefone_unique_compat'
  ) THEN
    ALTER TABLE clientes ADD CONSTRAINT clientes_telefone_unique_compat UNIQUE (telefone);
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_clientes_estado ON clientes (estado_atual);
CREATE INDEX IF NOT EXISTS idx_clientes_ultima ON clientes (ultima_msg_em);

-- ------------------------------------------------------------------
-- PEDIDOS: adicionar colunas esperadas preservando estrutura legado
-- ------------------------------------------------------------------
ALTER TABLE IF EXISTS pedidos ADD COLUMN IF NOT EXISTS pedido_uuid UUID DEFAULT gen_random_uuid();
ALTER TABLE IF EXISTS pedidos ADD COLUMN IF NOT EXISTS codigo INTEGER;
ALTER TABLE IF EXISTS pedidos ADD COLUMN IF NOT EXISTS telefone TEXT;
ALTER TABLE IF EXISTS pedidos ADD COLUMN IF NOT EXISTS nome_cliente TEXT;
ALTER TABLE IF EXISTS pedidos ADD COLUMN IF NOT EXISTS itens JSONB NOT NULL DEFAULT '[]'::JSONB;
ALTER TABLE IF EXISTS pedidos ADD COLUMN IF NOT EXISTS quantidade_total INTEGER NOT NULL DEFAULT 0;
ALTER TABLE IF EXISTS pedidos ADD COLUMN IF NOT EXISTS valor_total NUMERIC(10,2) NOT NULL DEFAULT 0;
ALTER TABLE IF EXISTS pedidos ADD COLUMN IF NOT EXISTS forma_pagamento TEXT;
ALTER TABLE IF EXISTS pedidos ADD COLUMN IF NOT EXISTS observacao TEXT;
ALTER TABLE IF EXISTS pedidos ADD COLUMN IF NOT EXISTS horario_previsto TIMESTAMPTZ;
ALTER TABLE IF EXISTS pedidos ADD COLUMN IF NOT EXISTS criado_em TIMESTAMPTZ NOT NULL DEFAULT NOW();
ALTER TABLE IF EXISTS pedidos ADD COLUMN IF NOT EXISTS atualizado_em TIMESTAMPTZ NOT NULL DEFAULT NOW();

UPDATE pedidos
SET telefone = COALESCE(telefone, phone),
    valor_total = COALESCE(valor_total, valor_final),
    quantidade_total = COALESCE(quantidade_total, quantidade, 0),
    criado_em = COALESCE(criado_em, created_at, NOW()),
    atualizado_em = COALESCE(atualizado_em, updated_at, created_at, NOW()),
    codigo = COALESCE(codigo, id)
WHERE telefone IS NULL
   OR valor_total IS NULL
   OR quantidade_total IS NULL
   OR criado_em IS NULL
   OR atualizado_em IS NULL
   OR codigo IS NULL;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'pedidos_pedido_uuid_unique_compat'
  ) THEN
    ALTER TABLE pedidos ADD CONSTRAINT pedidos_pedido_uuid_unique_compat UNIQUE (pedido_uuid);
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'pedidos_codigo_unique_compat'
  ) THEN
    ALTER TABLE pedidos ADD CONSTRAINT pedidos_codigo_unique_compat UNIQUE (codigo);
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_pedidos_status ON pedidos (status);
CREATE INDEX IF NOT EXISTS idx_pedidos_telefone ON pedidos (telefone);
CREATE INDEX IF NOT EXISTS idx_pedidos_criado ON pedidos (criado_em DESC);

-- ------------------------------------------------------------------
-- CONVERSAS / EVENTOS / VIEW
-- ------------------------------------------------------------------
ALTER TABLE IF EXISTS conversas ADD COLUMN IF NOT EXISTS telefone TEXT;
ALTER TABLE IF EXISTS conversas ADD COLUMN IF NOT EXISTS sender TEXT;
ALTER TABLE IF EXISTS conversas ADD COLUMN IF NOT EXISTS mensagem TEXT;
ALTER TABLE IF EXISTS conversas ADD COLUMN IF NOT EXISTS intencao TEXT;
ALTER TABLE IF EXISTS conversas ADD COLUMN IF NOT EXISTS criado_em TIMESTAMPTZ NOT NULL DEFAULT NOW();

UPDATE conversas
SET telefone = COALESCE(telefone, phone),
    criado_em = COALESCE(criado_em, ultima_interacao, created_at, updated_at, NOW())
WHERE telefone IS NULL OR criado_em IS NULL;

CREATE INDEX IF NOT EXISTS idx_conversas_tel_data ON conversas (telefone, criado_em DESC);

CREATE TABLE IF NOT EXISTS eventos (
    id BIGSERIAL PRIMARY KEY,
    telefone TEXT,
    pedido_id UUID,
    tipo TEXT NOT NULL,
    payload JSONB NOT NULL DEFAULT '{}'::JSONB,
    criado_em TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE OR REPLACE FUNCTION trg_set_updated_at_compat() RETURNS trigger AS $$
BEGIN
  NEW.atualizado_em = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS pedidos_set_updated_at_compat ON pedidos;
CREATE TRIGGER pedidos_set_updated_at_compat
BEFORE UPDATE ON pedidos
FOR EACH ROW EXECUTE FUNCTION trg_set_updated_at_compat();

CREATE OR REPLACE VIEW vw_clientes_inativos_24h AS
SELECT telefone, nome, estado_atual, ultima_msg_em
FROM clientes
WHERE estado_atual NOT IN ('FINALIZADO','INICIO')
  AND ultima_msg_em < NOW() - INTERVAL '24 hours';
