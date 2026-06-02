-- ================================================================
-- SEED: Agente y usuarios de prueba — Crack Tesos
-- ================================================================

-- AGT-19 ya existe en commercial_agents (creado en Desafío Teso)
-- Solo insertar si no existe
INSERT INTO commercial_agents (agent_id, agent_name)
VALUES ('AGT-19', 'PRUEBAS')
ON CONFLICT (agent_id) DO NOTHING;

-- Usuarios de prueba en ct_users
INSERT INTO ct_users (phone, document_id, name, agent_id, agent_name, city, status, source)
VALUES
  ('573158893577', '1000000001', 'ANA DIAZ',                    'AGT-19', 'PRUEBAS', 'BOGOTÁ', 'active', 'preload'),
  ('573208439238', '1000000002', 'JAIME CHAVES',                'AGT-19', 'PRUEBAS', 'BOGOTÁ', 'active', 'preload'),
  ('573118642756', '1000000003', 'DANIELA CORREDOR',            'AGT-19', 'PRUEBAS', 'BOGOTÁ', 'active', 'preload'),
  ('573105594321', '1000000004', 'INGRITH CUELLAR',             'AGT-19', 'PRUEBAS', 'BOGOTÁ', 'active', 'preload'),
  ('573014306888', '1000000005', 'MARIA DE LOS ANGELES ACOSTA', 'AGT-19', 'PRUEBAS', 'BOGOTÁ', 'active', 'preload'),
  ('573229278662', '1000000006', 'CAMILA PULIDO',               'AGT-19', 'PRUEBAS', 'BOGOTÁ', 'active', 'preload'),
  ('573052574676', '1000000007', 'LAURA URIBE',                 'AGT-19', 'PRUEBAS', 'BOGOTÁ', 'active', 'preload'),
  ('573022105683', '1000000008', 'VALENTINA MORALES',           'AGT-19', 'PRUEBAS', 'BOGOTÁ', 'active', 'preload'),
  ('573208362797', '1000000009', 'FRANCISCO RODRIGUEZ',         'AGT-19', 'PRUEBAS', 'BOGOTÁ', 'active', 'preload')
ON CONFLICT (phone) DO UPDATE SET
  name       = EXCLUDED.name,
  agent_id   = EXCLUDED.agent_id,
  agent_name = EXCLUDED.agent_name,
  updated_at = NOW();
