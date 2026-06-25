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

**KPI "Goles acumulados" incluye activos E inactivos**: a propósito, `goles_totales` en WF-13 y WF-14 NO filtra por `status` — solo excluye `agent_name='PRUEBAS'`. Es el total histórico real de goles entregados durante el evento, consistente con el informe de trazabilidad (WF-15). Los demás KPIs de conteo (`total_usuarios`, `registrados`, `activos`) sí siguen filtrando `status='active'`, porque describen la base de participantes vigente, no el histórico de goles. No reintroducir `AND status='active'` en `goles_totales`/`pruebas_goles` sin confirmar con Jaime — ya se corrigió una vez por inconsistencia entre el dashboard y el informe de trazabilidad.

**Primera respuesta cuenta**: duplicados se marcan `is_duplicate=true` pero no se eliminan ni puntúan.

**Ventana 24h**: fuera de rango → `is_out_of_time=true`, 0 goles, pero se registra.

## Patrones técnicos de n8n (lecciones aprendidas)

- **`crypto.randomUUID()` no está disponible** en el sandbox de Code nodes de n8n 2.26.7. Usar generador manual: `'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, c => {...})`.
- **Múltiples statements SQL en un solo nodo Postgres `executeQuery` no funcionan de forma confiable.** Consolidar en un único CTE con `RETURNING` para garantizar que el nodo devuelva al menos 1 fila (si no, el nodo "Responder" del webhook nunca se dispara).
- **LEFT JOIN + SUM() infla resultados**: si se hace `SUM(u.total_goals)` con un `LEFT JOIN` a una tabla con relación 1-a-muchos (ej. respuestas), el total se multiplica por cada fila del join. Separar agregaciones en CTEs independientes (uno por `ct_users`, otro por `ct_trivia_responses`) y unir al final.
- **`json_agg` en WF-13**: cada query se envuelve en `SELECT json_agg(t) FROM (...) t` para que el nodo Postgres devuelva 1 fila con un array, evitando que n8n multiplique items entre nodos en cadena.
- **Email (WF-14) vs Dashboard (WF-13) mostrarán números levemente distintos** si se comparan en momentos diferentes del día — ambos usan el mismo algoritmo de regresión lineal, pero el email es un snapshot de las 7AM y el dashboard es en vivo. No es un bug.
- **Extraer datos embebidos en `description` con `regexp_match`**: en vez de agregar columnas nuevas al esquema para datos ya descriptivos en texto (ej. cantidad de códigos en `ct_scoring_ledger.description`, formato `'+200 goles por 15 códigos — Trivia #18'`), usar `(regexp_match(description, 'por (\d+) códigos'))[1]::int` directamente en el SELECT (ver WF-15).
- **Nodo HTTP Request con credential genérico (Header Auth)**: en el campo "Authentication" del nodo, hay que elegir **"Generic Credential Type"**, NO "Predefined Credential Type" (ese es solo para integraciones predefinidas como OpenAI/Slack y no sirve para un header custom). Tras elegir "Generic Credential Type" aparece "Generic Auth Type" → elegir "Header Auth" → ahí sí aparece el dropdown para seleccionar/crear el credential real. Si al reimportar un workflow el campo "Credential Type" sale vacío en rojo, es porque quedó en modo "Predefined" — cambiarlo manualmente (ver caso WF-14 / Claude API).
- **Reimportar un workflow en n8n puede dejarlo INACTIVO** aunque antes estuviera activo. Siempre revisar el toggle de activación después de reimportar, antes de asumir que el webhook ya responde.
- **`MAX()` tras una subquery agregada, no `SUM()` directo**: si necesitas traer un valor ya agregado por una tabla 1-a-muchos (ej. códigos registrados desde `ct_scoring_ledger`, varias filas por trivia) hacia una query que ya tiene OTRO `LEFT JOIN` 1-a-muchos (ej. `ct_trivia_responses`), primero agrega esa tabla en una subquery `GROUP BY` aparte (1 fila por trivia), y al traerla al SELECT final usa `MAX()` (no `SUM()`) — el valor se repite idéntico en cada fila del join externo, así que `SUM` lo multiplicaría por la cantidad de respuestas. Ver "Query Trivias" en WF-13.
- **Tool `web_search` con modelos que no soportan "programmatic tool calling" (ej. Haiku)**: si se usa el server-side tool `web_search_20260209` con un modelo sin soporte de PTC, la API rechaza la request (400) a menos que se declare explícitamente `allowed_callers: ['direct']` en la definición del tool. Se probó en WF-14 y se descartó (ver más abajo) — dejar la lección por si se reintenta con otro modelo.

## Dashboard — `state.data.trivias` (campos extendidos, WF-13 "Query Trivias")

Además de `trivia_number/respuestas/correctas/fuera_tiempo/avg_segundos`, cada item incluye: `has_multiplier` (bool), `question`, `option_a/b/c`, `correct_option` ('A'|'B'|'C'), `goles_sin_multiplicador` (SUM base_goals+speed_bonus), `goles_multiplicador` (SUM multiplier_bonus), `codigos_registrados` (extraído de `ct_scoring_ledger.description` vía regexp, 0 si la trivia no tuvo multiplicador). Usado por: banner Top3 (no depende de esto, usa `ranking`), KPIs de códigos/goles-por-código, gráfico "Impacto de Multiplicadores", tarjetas de pregunta en tab Participación.

## KPIs de códigos/multiplicadores (WF-13 y WF-14)

Ambos workflows exponen `kpis.participantes_codigos` (COUNT DISTINCT user_id en `ct_scoring_ledger` con `movement_type='multiplier_bonus'`, excluyendo PRUEBAS) — cuántos participantes distintos han registrado al menos 1 código. WF-14 además expone `kpis.codigos_totales` (suma de códigos extraída por regexp del ledger). Dashboard: tarjeta "Participantes que han enviado códigos" al final de "Engagement de Crack Tesos". Email: sección "📦 Códigos y Multiplicadores" con 3 tiles (códigos totales, participantes registrados, participantes con código).

## Checklist operativo — antes de enviar una trivia

1. Confirmar que el workflow relevante (WF-03/04/06/07, y si se tocó algo, WF-13/14/15) esté **activo** en n8n tras cualquier reimportación
2. Si se modificó WF-14, probar el nodo "Claude API — Análisis" con "Execute step" manualmente antes de depender del cron de las 7AM
3. Refrescar `dashboard.html` y confirmar que los KPIs (especialmente "Goles acumulados") muestran el número esperado
4. Crear/confirmar la trivia del día: `trivia_number` consecutivo, pregunta + 3 opciones + `correct_option`, shuffle de A/B/C aplicado
5. Definir `has_multiplier` si esta trivia llevará carga de códigos después
6. Definir `sent_at` (hora de envío); `closes_at` se calcula como `sent_at + 24h`
7. Confirmar que WF-07 (cierre automático 24h) está activo para que la trivia anterior cierre sola si corresponde
8. Probar la trivia end-to-end con un número de cuenta `agent_name='PRUEBAS'` antes del envío masivo (valida WF-03 + WF-04 con la pregunta real del día)
9. Enviar el broadcast desde WATI a la audiencia (excluir PRUEBAS e inactivos) — **mecanismo exacto de envío del broadcast aún no documentado, confirmar con Jaime y agregar aquí cuando se confirme**
10. Tras el envío, monitorear el tab "Participación" del dashboard para confirmar que llegan respuestas

## Operaciones manuales de datos

Altas/bajas masivas de participantes se hacen con SQL directo en el SQL Editor de Supabase (no hay UI de administración para esto). Bajas por `document_id`, altas por UPSERT en `phone`. Ver histórico de ejemplo en `supabase/ops/`.
