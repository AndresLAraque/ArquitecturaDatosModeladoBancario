# CHANGELOG

Todas las entradas siguen el formato: `YYYY-MM-DD — autor — descripción`.

## [Unreleased]

- 2026-08-24 — andresypm@gmail.com — Inicialización del repositorio: estructura de carpetas,
  README con sector (Escenario A — Banca) y plataforma (GCP) declarados, decisiones de
  arquitectura documentadas (BigQuery+dbt para Silver/Gold, Cloud Workflows+Scheduler+Run
  para orquestación, Terraform para IaC). Plan de fases en `PLAN.md`.
- 2026-08-24 — andresypm@gmail.com — Fase 0 completada: Python 3.12, Terraform 1.15.8 y
  Google Cloud SDK instalados; proyecto GCP `finbank-data-platform-dev` creado con billing
  del free trial vinculado (`us-central1`); se eliminó un proyecto duplicado creado por error
  (`fibank-data-platform`, typo, sin billing) tras validar que había dos organizaciones y dos
  billing accounts distintas en la cuenta.
- 2026-08-24 — andresypm@gmail.com — Fase 1 completada: generador sintético reproducible
  (semilla 42) de las 6 tablas fuente de FinBank en `/data-generation`, con distribuciones
  realistas, ~5% de nulos controlados, 4 anomalías intencionales documentadas en
  `ANOMALIES.md`, salida en CSV+JSON+Parquet. Cargado exitosamente en Postgres local
  (Docker, puerto 5434) vía `load_to_postgres.py` — evidencia en
  `data-generation/output/load_evidence.txt`. Diagrama ER agregado en `/docs/er-diagram.md`.
- 2026-08-24 — andresypm@gmail.com — Fase 2 completada: módulo Terraform en `/infra` (44
  recursos aplicados en `finbank-data-platform-dev`/`dev`) — buckets bronze/silver/gold,
  datasets BigQuery Silver/Gold, Cloud SQL Postgres 16, 3 service accounts con IAM granular,
  Secret Manager, Pub/Sub, Artifact Registry, Cloud Workflows + Cloud Scheduler (placeholder,
  se completa en Fase 4). Backend remoto de estado en GCS. Corregido sobre la marcha un error
  de edición de Cloud SQL (`ENTERPRISE_PLUS` no soporta `db-f1-micro`). Evidencia y lista de
  recursos en `docs/evidencia/` e `infra/RESOURCES.md`.
- 2026-08-24 — andresypm@gmail.com — Datos de Fase 1 cargados también en Cloud SQL
  (`finbank-sqlpg-dev`), no solo en el Postgres local: `load_to_postgres.py` ahora soporta
  el Cloud SQL Python Connector (mismo código, sin IP pública autorizada). En el camino se
  corrigieron 5 bugs reales de compatibilidad con el driver `pg8000` (password desde
  Secret Manager pisada por `.env`, `pd.read_json` reconvirtiendo `num_doc` a entero,
  `INSERT` multi-fila de pandas incompatible con pg8000, enteros nullable serializados como
  `"44.0"`/`"<NA>"`, y una caída de socket SSL en `executemany` con 10k+ filas). Carga final
  vía `COPY ... FROM STDIN`, mucho más rápida y estable. Evidencia en
  `data-generation/output/load_evidence_cloudsql.txt`.
- 2026-08-24 — andresypm@gmail.com — Capa Bronze (`/pipelines/bronze`): extracción Cloud SQL
  → GCS en Parquet, columnas de auditoría, particionado por fecha de ingesta, log de
  ejecución en GCS, modo incremental por watermark para `TB_MOV_FINANCIEROS`/
  `TB_COMISIONES_LOG`. Corrido 2 veces contra datos reales: la segunda corrida confirma la
  incrementalidad (0 filas nuevas en las tablas incrementales). Evidencia en
  `docs/evidencia/fase3-bronze/`.
