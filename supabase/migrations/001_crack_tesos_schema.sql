-- ================================================================
-- CRACK TESOS — Schema Supabase
-- Convive con el schema de Desafío Teso (tablas separadas)
-- Timezone operativo: America/Bogota (UTC-5)
-- ================================================================

-- Reutiliza la tabla commercial_agents existente (ya tiene los 18 agentes + AGT-19)

-- ================================================================
-- 1. USERS — Participantes
-- ================================================================
CREATE TABLE IF NOT EXISTS ct_users (
  user_id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  phone             TEXT UNIQUE NOT NULL,        -- 57XXXXXXXXXX (llave principal WhatsApp)
  document_id       TEXT,                        -- cédula (llave cruce multiplicadores)
  name              TEXT NOT NULL,
  email             TEXT,
  city              TEXT,
  zone              TEXT,
  agent_id          TEXT REFERENCES commercial_agents(agent_id),
  agent_name        TEXT,
  pos_id            TEXT,
  pos_name          TEXT,
  registered        BOOLEAN DEFAULT FALSE,       -- aceptó T&C
  registered_at     TIMESTAMPTZ,                 -- timestamp Bogotá
  terms_at          TIMESTAMPTZ,                 -- timestamp Bogotá
  status            TEXT DEFAULT 'active' CHECK (status IN ('active','inactive')),
  total_goals       INTEGER DEFAULT 0,           -- caché acumulado (recalculable desde ledger)
  source            TEXT DEFAULT 'preload',      -- 'preload' | 'whatsapp'
  created_at        TIMESTAMPTZ DEFAULT NOW(),
  updated_at        TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS ct_idx_users_phone    ON ct_users(phone);
CREATE INDEX IF NOT EXISTS ct_idx_users_document ON ct_users(document_id);
CREATE INDEX IF NOT EXISTS ct_idx_users_agent    ON ct_users(agent_id);
CREATE INDEX IF NOT EXISTS ct_idx_users_status   ON ct_users(status);

-- ================================================================
-- 2. TRIVIAS — Preguntas y configuración
-- ================================================================
CREATE TABLE IF NOT EXISTS ct_trivias (
  trivia_id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  trivia_number     INTEGER UNIQUE NOT NULL,     -- 1, 2, 3... 13+
  question          TEXT NOT NULL,

  -- Opciones (posición A/B/C shuffleada al guardar en formulario)
  option_a          TEXT NOT NULL,
  option_b          TEXT NOT NULL,
  option_c          TEXT NOT NULL,
  correct_option    TEXT NOT NULL CHECK (correct_option IN ('A','B','C')),

  -- Textos originales antes del shuffle (para edición y trazabilidad)
  correct_answer    TEXT NOT NULL,
  wrong_1           TEXT NOT NULL,
  wrong_2           TEXT NOT NULL,

  -- Programación — MANUAL (ingresado por operador en formulario n8n)
  -- sent_at = fecha y hora EXACTA de envío de la difusión en WATI
  -- Formato almacenado: TIMESTAMPTZ con timezone Bogotá
  -- Editable hasta que llegue la primera respuesta
  sent_at           TIMESTAMPTZ,                 -- hora Bogotá del envío manual
  closes_at         TIMESTAMPTZ,                 -- sent_at + 24 horas (calculado al guardar sent_at)

  -- Goles adicionales (multiplicador)
  has_multiplier    BOOLEAN DEFAULT FALSE,

  -- Estado
  status            TEXT DEFAULT 'draft'
                    CHECK (status IN ('draft','ready','sent','closed','settled')),
  -- draft   = recién creada, sin sent_at definido
  -- ready   = sent_at definido, lista para enviar
  -- sent    = difusión enviada manualmente, acepta respuestas
  -- closed  = ventana 24h cerrada
  -- settled = multiplicadores aplicados, cerrada definitivamente

  created_at        TIMESTAMPTZ DEFAULT NOW(),
  updated_at        TIMESTAMPTZ DEFAULT NOW(),
  created_by        TEXT
);

CREATE INDEX IF NOT EXISTS ct_idx_trivias_status  ON ct_trivias(status);
CREATE INDEX IF NOT EXISTS ct_idx_trivias_sent    ON ct_trivias(sent_at);

-- ================================================================
-- 3. TRIVIA_RESPONSES — Respuestas de participantes
-- ================================================================
CREATE TABLE IF NOT EXISTS ct_trivia_responses (
  response_id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  trivia_id           UUID NOT NULL REFERENCES ct_trivias(trivia_id),
  user_id             UUID NOT NULL REFERENCES ct_users(user_id),
  phone               TEXT NOT NULL,             -- redundante para trazabilidad

  selected_option     TEXT NOT NULL CHECK (selected_option IN ('A','B','C')),
  is_correct          BOOLEAN,
  is_duplicate        BOOLEAN DEFAULT FALSE,
  is_out_of_time      BOOLEAN DEFAULT FALSE,

  -- Timestamps en Bogotá
  responded_at        TIMESTAMPTZ DEFAULT NOW(), -- hora Bogotá de la respuesta
  response_seconds    INTEGER,                   -- segundos desde sent_at hasta responded_at
  speed_range         INTEGER,                   -- 1-5 (0 si fuera de tiempo o incorrecto)

  -- Goles
  base_goals          INTEGER DEFAULT 0,
  speed_bonus         INTEGER DEFAULT 0,
  multiplier_bonus    INTEGER DEFAULT 0,         -- se actualiza al aplicar multiplicador
  total_goals         INTEGER DEFAULT 0,         -- base + speed (sin multiplicador)
  final_goals         INTEGER DEFAULT 0,         -- total incluyendo multiplicador

  raw_payload         JSONB,

  UNIQUE(trivia_id, user_id)
);

CREATE INDEX IF NOT EXISTS ct_idx_responses_trivia   ON ct_trivia_responses(trivia_id);
CREATE INDEX IF NOT EXISTS ct_idx_responses_user     ON ct_trivia_responses(user_id);
CREATE INDEX IF NOT EXISTS ct_idx_responses_phone    ON ct_trivia_responses(phone);
CREATE INDEX IF NOT EXISTS ct_idx_responses_correct  ON ct_trivia_responses(is_correct);

-- ================================================================
-- 4. SCORING_LEDGER — Fuente de verdad de goles
-- ================================================================
CREATE TABLE IF NOT EXISTS ct_scoring_ledger (
  ledger_id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id           UUID NOT NULL REFERENCES ct_users(user_id),
  trivia_id         UUID REFERENCES ct_trivias(trivia_id),
  trivia_number     INTEGER,                     -- desnormalizado para consultas fáciles
  movement_type     TEXT NOT NULL
                    CHECK (movement_type IN ('trivia_base','speed_bonus','multiplier_bonus','adjustment')),
  amount            INTEGER NOT NULL,            -- negativo solo para adjustments
  description       TEXT,
  reference_id      UUID,                        -- response_id o batch_id
  created_at        TIMESTAMPTZ DEFAULT NOW(),   -- hora Bogotá
  created_by        TEXT DEFAULT 'system'        -- 'system' | 'admin:email'
);

CREATE INDEX IF NOT EXISTS ct_idx_ledger_user    ON ct_scoring_ledger(user_id);
CREATE INDEX IF NOT EXISTS ct_idx_ledger_trivia  ON ct_scoring_ledger(trivia_id);
CREATE INDEX IF NOT EXISTS ct_idx_ledger_type    ON ct_scoring_ledger(movement_type);
CREATE INDEX IF NOT EXISTS ct_idx_ledger_created ON ct_scoring_ledger(created_at DESC);

-- ================================================================
-- 5. MULTIPLIER_BATCHES — Trazabilidad de cargas de multiplicadores
-- ================================================================
CREATE TABLE IF NOT EXISTS ct_multiplier_batches (
  batch_id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  trivia_id           UUID REFERENCES ct_trivias(trivia_id),
  trivia_number       INTEGER NOT NULL,
  multiplier          NUMERIC NOT NULL CHECK (multiplier IN (2, 3, 4)),
  source_file         TEXT,                      -- nombre del archivo Excel subido
  total_records_file  INTEGER DEFAULT 0,         -- filas en el archivo
  matched_records     INTEGER DEFAULT 0,         -- encontrados en BD
  eligible_records    INTEGER DEFAULT 0,         -- respondieron correctamente la trivia
  applied_records     INTEGER DEFAULT 0,         -- a quienes se aplicó
  not_found_records   INTEGER DEFAULT 0,
  total_goals_added   INTEGER DEFAULT 0,
  status              TEXT DEFAULT 'preview'
                      CHECK (status IN ('preview','applied','error')),
  applied_at          TIMESTAMPTZ,               -- hora Bogotá
  applied_by          TEXT,                      -- email del operador
  ip_address          TEXT,
  notes               TEXT,
  created_at          TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS ct_idx_batches_trivia ON ct_multiplier_batches(trivia_id);

-- ================================================================
-- 6. AUDIT_LOGS — Log de operaciones del sistema
-- ================================================================
CREATE TABLE IF NOT EXISTS ct_audit_logs (
  log_id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  event_type        TEXT NOT NULL,
  -- 'multiplier_applied' | 'trivia_sent_marked' | 'webhook_error'
  -- 'user_registered' | 'manual_adjustment' | 'module_login'
  operator_email    TEXT,                        -- quién hizo la acción (null = sistema)
  trivia_number     INTEGER,
  user_affected     TEXT,                        -- phone o 'bulk:N'
  payload           JSONB,                       -- datos del evento
  result            TEXT CHECK (result IN ('success','error','warning')),
  error_msg         TEXT,
  ip_address        TEXT,
  created_at        TIMESTAMPTZ DEFAULT NOW()    -- hora Bogotá
);

CREATE INDEX IF NOT EXISTS ct_idx_audit_type    ON ct_audit_logs(event_type);
CREATE INDEX IF NOT EXISTS ct_idx_audit_created ON ct_audit_logs(created_at DESC);
CREATE INDEX IF NOT EXISTS ct_idx_audit_trivia  ON ct_audit_logs(trivia_number);

-- ================================================================
-- VISTA: v_ct_rankings
-- Rankings desde scoring_ledger (recalculable en cualquier momento)
-- ================================================================
CREATE OR REPLACE VIEW v_ct_rankings AS
SELECT
  u.user_id,
  u.phone,
  u.name,
  u.document_id,
  u.agent_id,
  u.agent_name,
  u.city,
  u.pos_name,
  u.status,

  -- Goles totales
  COALESCE(SUM(sl.amount), 0)::INTEGER AS total_goals,

  -- Rankings
  RANK() OVER (ORDER BY COALESCE(SUM(sl.amount), 0) DESC)::INTEGER
    AS rank_general,
  RANK() OVER (PARTITION BY u.agent_id ORDER BY COALESCE(SUM(sl.amount), 0) DESC)::INTEGER
    AS rank_agent,

  -- Estadísticas de respuestas
  COUNT(DISTINCT r.trivia_id)::INTEGER AS total_responses,
  COUNT(DISTINCT CASE WHEN r.is_correct = TRUE AND r.is_duplicate = FALSE
    THEN r.trivia_id END)::INTEGER AS correct_count,

  -- Velocidad promedio (solo respuestas correctas, en segundos)
  AVG(CASE WHEN r.is_correct = TRUE AND r.is_duplicate = FALSE AND r.response_seconds IS NOT NULL
    THEN r.response_seconds END)::INTEGER AS avg_speed_seconds,

  -- Para contar participantes por agente
  COUNT(u.user_id) OVER (PARTITION BY u.agent_id)::INTEGER AS total_in_agent,
  COUNT(u.user_id) OVER ()::INTEGER AS total_participants

FROM ct_users u
LEFT JOIN ct_scoring_ledger sl ON u.user_id = sl.user_id
LEFT JOIN ct_trivia_responses r ON u.user_id = r.user_id AND r.is_duplicate = FALSE
WHERE u.status = 'active'
GROUP BY u.user_id, u.phone, u.name, u.document_id,
         u.agent_id, u.agent_name, u.city, u.pos_name, u.status;

-- ================================================================
-- FUNCIÓN: Reconstruir total_goals desde ledger
-- ================================================================
CREATE OR REPLACE FUNCTION ct_recalculate_user_goals(p_user_id UUID)
RETURNS INTEGER AS $$
DECLARE v_total INTEGER;
BEGIN
  SELECT COALESCE(SUM(amount), 0) INTO v_total
  FROM ct_scoring_ledger WHERE user_id = p_user_id;
  UPDATE ct_users SET total_goals = v_total, updated_at = NOW()
  WHERE user_id = p_user_id;
  RETURN v_total;
END;
$$ LANGUAGE plpgsql;

-- ================================================================
-- TRIGGER: updated_at automático en ct_trivias y ct_users
-- ================================================================
CREATE OR REPLACE FUNCTION ct_update_updated_at()
RETURNS TRIGGER AS $$
BEGIN NEW.updated_at = NOW(); RETURN NEW; END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER ct_trivias_updated_at
  BEFORE UPDATE ON ct_trivias
  FOR EACH ROW EXECUTE FUNCTION ct_update_updated_at();

CREATE TRIGGER ct_users_updated_at
  BEFORE UPDATE ON ct_users
  FOR EACH ROW EXECUTE FUNCTION ct_update_updated_at();
