-- ================================================================
-- SEED: Configuración de scoring Crack Tesos
-- Ejecutar después de 001_crack_tesos_schema.sql
-- ================================================================

-- Nota: Los valores de scoring están hardcodeados en los workflows de n8n
-- para máxima simplicidad. Este archivo es solo documentación de referencia.

-- SISTEMA DE GOLES:
-- Respuesta correcta base: 100 goles
-- Respuesta incorrecta: 0 goles
-- Fuera de 24h: 0 goles

-- TABLA DE BONO POR RAPIDEZ (solo si respuesta correcta):
-- Rango 1: 0-5 min    → +50 goles  → Total: 150
-- Rango 2: 5-15 min   → +35 goles  → Total: 135
-- Rango 3: 15-30 min  → +25 goles  → Total: 125
-- Rango 4: 30-360 min → +15 goles  → Total: 115
-- Rango 5: 360-1440   → +5 goles   → Total: 105
-- Fuera    > 1440 min → 0 goles

-- MULTIPLICADORES DISPONIBLES: x2, x3, x4
-- Aplican sobre el total (base + bono) de ESA TRIVIA ESPECÍFICA
-- Ejemplo: 135 goles × 2 = 270 → goles_adicionales = 135

-- TIMEZONE: America/Bogota (UTC-5) para TODOS los cálculos
