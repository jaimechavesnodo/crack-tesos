# Crack Tesos 2026 — Contexto del Proyecto

Actividad de engagement para distribuidores Terpel vía WhatsApp (trivias + acumulación de "Estrellas Tesos"). Producción: 11 jun 2026. Cierre: 31 jul 2026. ~1.200 participantes, 18 agentes comerciales, 54 ganadores (Top 3 × 18).

## Stack

- **Canal**: WATI (WhatsApp Business), número 3152625389
- **Orquestador**: n8n self-hosted en EasyPanel — `n8n-content-creation-nodo-n8n.5szgix.easypanel.host`
- **BD**: Supabase (PostgreSQL)
- **Dashboard**: `web/dashboard.html` — HTML/JS + Chart.js, estático
- **Módulo Multiplicadores**: `web/index.html` + `modulo-multiplicadores/src/` — login + carga de Excel
- **Emails diarios**: n8n + Claude API (modelo `claude-haiku-4-5-20251001`)
- **TimeZone operativo**: `America/Bogota` (UTC-5) en todo el sistema

### Credenciales n8n (no rotar sin avisar)
- Postgres credential: id `Sff6cVWV0sgHQvDE`, nombre "Postgres account"
- Gmail credential: id `MPFuKPfWjUdoz0Gt`, nombre "Gmail account"
- Token webhook WATI: ver constante en `wf-01` a `wf-05` y flujos de `wati-flows/` (header `x-wati-token`)
- Token admin: Base64 `email|timestamp|<secreto>`, ver constante en `wf-11-auth.json`, válido 8h
- Claude API (WF-14): credential `httpHeaderAuth` llamado "Claude API Key (x-api-key)" — la API key NUNCA va hardcodeada en el JSON del workflow ni en este repo. Si reimportas WF-14 y el nodo "Claude API — Análisis" pide credential, créalo en n8n (Header Name: `x-api-key`, Header Value: la key real) y asígnalo

## Deploy — cómo se publican los cambios

**`web/dashboard.html` y `web/index.html` son estáticos y se despliegan vía GitHub → EasyPanel.** Editar el archivo local en este repo no actualiza lo que ve el usuario en producción — falta el paso de publicar.

Flujo real:
1. Repo: `https://github.com/jaimechavesnodo/crack-tesos.git`, rama `main`
2. EasyPanel (Hostinger VPS) sirve la app estática vía nginx, leyendo del repo en GitHub
3. Para que un cambio a `web/*.html` se vea en producción hace falta `git push` a `main`, y luego, si el webhook de GitHub no está configurado en EasyPanel, un clic manual en "Implementar" dentro de EasyPanel
4. Los workflows de n8n (`n8n-workflows/*.json`) son independientes de este flujo — se importan manualmente en la UI de n8n, el push a GitHub no los actualiza

**Nota para Claude**: al terminar una edición a `web/dashboard.html` o `web/index.html`, recordar explícitamente que el cambio no estará visible hasta hacer push (y posiblemente redeploy manual en EasyPanel) — no asumir que "guardado en el repo" equivale a "desplegado".

## Esquema de Base de Datos (Supabase)

**`ct_users`** — participantes. Campos clave: `user_id` (PK), `phone` (UNIQUE, formato `57XXXXXXXXXX`), `document_id` (cédula), `name`, `agent_id`/`agent_name`, `registered` (bool, aceptó T&C), `status` ('active'|'inactive'), `total_goals` (caché recalculable), `source` ('preload'|'whatsapp_flow').

**`ct_trivias`** — preguntas. `trivia_id` (PK), `trivia_number` (UNIQUE), `option_a/b/c` shuffleadas, `correct_option`, `sent_at`, `closes_at` (sent_at + 24h), `status` ('draft'|'ready'|'sent'|'closed'|'settled').

**`ct_trivia_responses`** — respuestas. `response_id` (PK), `trivia_id`+`user_id` UNIQUE, `is_correct`/`is_duplicate`/`is_out_of_time`, `base_goals`+`speed_bonus`+`multiplier_bonus`=`total_goals`/`final_goals`.

**`ct_scoring_ledger`** — fuente de verdad de goles (no usar `ct_users.total_goals` para auditoría, es solo caché). `movement_type` ('trivia_base'|'speed_bonus'|'multiplier_bonus'|'adjustment').

**`ct_multiplier_batches`** — trazabilidad de cargas de multiplicadores.

**`ct_audit_logs`** — log de operaciones administrativas.

**`v_ct_rankings`** (vista) — agrega `ct_scoring_ledger` por usuario: `total_goals`, `rank_general`, `rank_agent`, `total_responses`, `correct_count`, `avg_speed_seconds`.

**`ct_recalculate_user_goals(user_id)`** — función PL/pgSQL para recalcular `ct_users.total_goals` desde el ledger.

## Workflows n8n (`n8n-workflows/`)

| WF | Función |
|----|---------|
| 01 | Obtener Datos de Usuario — consulta por `phone` |
| 02 | Registro de Usuario — UPSERT por `phone` desde flujo WATI |
| 03 | Obtener Trivia activa (shuffleada) |
| 04 | Respuesta Trivia + Scoring — calcula goles, registra en ledger |
| 05 | Consulta Ranking — rank general + por agente |
| 06 | Gestión Trivias — CRUD para operador |
| 07 | Cerrar Trivias — scheduler, cierra ventana 24h |
| 08 | Sync Sheets — exporta a Google Sheets |
| 09 | Multiplicadores Preview — valida Excel antes de aplicar |
| 10 | Multiplicadores Aplicar — aplica bono, UUID generado a mano (`crypto.randomUUID()` no existe en sandbox n8n) |
| 11 | Auth — login admin, token Base64 8h |
| 12 | Trivias con Multiplicador — marca `has_multiplier` |
| 13 | Dashboard Data — alimenta `dashboard.html`, queries envueltas en `json_agg` (evita timeout con +1K usuarios) |
| 14 | Email Diario — KPIs + análisis Claude + envío Gmail, cron `0 0 14 * * *` (7AM Bogotá) |
| 15 | Reporte Trazabilidad — endpoint on-demand (botón "📋 Informe de Trazabilidad" en dashboard), expone `ct_scoring_ledger` detallado por usuario+trivia+tipo de movimiento, exportado como Excel de 2 hojas (Detalle/Resumen). Separado de WF-13 a propósito: el detalle puede ser ~90K filas y solo se necesita on-demand, no en cada refresh del dashboard |

## Reglas de Negocio Críticas

**Scoring**: 100 goles base (respuesta correcta) + bono de velocidad: ≤5min +50, 5-15min +35, 15-30min +25, 30min-6h +15, 6h-24h +5. Total sin multiplicador: 100-150.

**Multiplicador**: `floor(número_de_códigos / 15) * 100` goles adicionales — aplica SOLO sobre los 100 goles base, NO sobre el bono de velocidad ni el total. (Antes se multiplicaba el total completo, fue un bug corregido.)

**Exclusión PRUEBAS**: Todo query de reportes/dashboard/email debe excluir `agent_name='PRUEBAS'` en `ct_users` y, para `ct_trivia_responses`, usar `user_id NOT IN (SELECT user_id FROM ct_users WHERE agent_name='PRUEBAS')`. Patrón obligatorio en WF-13 y WF-14.

**Usuarios inactivados**: `status='inactive'` se asigna por `document_id` (no por `phone`, que puede cambiar). El historial de respuestas/goles NUNCA se borra ni se descuenta — sigue contando en acumulados. Aparecen automáticamente en el tab "Desactivados" del dashboard (WF-13 filtra `WHERE status='inactive'`).

**Primera respuesta cuenta**: duplicados se marcan `is_duplicate=true` pero no se eliminan ni puntúan.

**Ventana 24h**: fuera de rango → `is_out_of_time=true`, 0 goles, pero se registra.

## Patrones técnicos de n8n (lecciones aprendidas)

- **`crypto.randomUUID()` no está disponible** en el sandbox de Code nodes de n8n 2.26.7. Usar generador manual: `'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, c => {...})`.
- **Múltiples statements SQL en un solo nodo Postgres `executeQuery` no funcionan de forma confiable.** Consolidar en un único CTE con `RETURNING` para garantizar que el nodo devuelva al menos 1 fila (si no, el nodo "Responder" del webhook nunca se dispara).
- **LEFT JOIN + SUM() infla resultados**: si se hace `SUM(u.total_goals)` con un `LEFT JOIN` a una tabla con relación 1-a-muchos (ej. respuestas), el total se multiplica por cada fila del join. Separar agregaciones en CTEs independientes (uno por `ct_users`, otro por `ct_trivia_responses`) y unir al final.
- **`json_agg` en WF-13**: cada query se envuelve en `SELECT json_agg(t) FROM (...) t` para que el nodo Postgres devuelva 1 fila con un array, evitando que n8n multiplique items entre nodos en cadena.
- **Email (WF-14) vs Dashboard (WF-13) mostrarán números levemente distintos** si se comparan en momentos diferentes del día — ambos usan el mismo algoritmo de regresión lineal, pero el email es un snapshot de las 7AM y el dashboard es en vivo. No es un bug.
- **Extraer datos embebidos en `description` con `regexp_match`**: en vez de agregar columnas nuevas al esquema para datos ya descriptivos en texto (ej. cantidad de códigos en `ct_scoring_ledger.description`, formato `'+200 goles por 15 códigos — Trivia #18'`), usar `(regexp_match(description, 'por (\d+) códigos'))[1]::int` directamente en el SELECT (ver WF-15).

## Operaciones manuales de datos

Altas/bajas masivas de participantes se hacen con SQL directo en el SQL Editor de Supabase (no hay UI de administración para esto). Bajas por `document_id`, altas por UPSERT en `phone`. Ver histórico de ejemplo en `supabase/ops/`.
