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
- 2026-08-25 — andresypm@gmail.com — Capa Silver (`/pipelines/silver` + `/pipelines/dbt_finbank`):
  puente Bronze->BigQuery (`load_bronze_to_bq.py`) + proyecto dbt con 6 modelos staging (dedup,
  tipado, integridad referencial, estrategia de nulos documentada por columna, hash SHA256 de
  PII, `ind_sospechoso` con ventana móvil 30 días), tabla `err_calidad_datos` y reporte
  `dq_report_silver`. Corregidos 2 bugs de compatibilidad BigQuery: no se puede particionar una
  función de ventana por una columna FLOAT64, y RANGE con offset numérico exige ORDER BY
  numérico (se usa `unix_date()`, no DATE directo). Resultado real: 8/8 modelos, 21/21 tests en
  verde. Evidencia en `docs/evidencia/fase3-silver/`.
- 2026-08-25 — andresypm@gmail.com — Capa Gold (`/pipelines/dbt_finbank/models/marts`): 8
  modelos — `dim_clientes`, `dim_productos`, `dim_geografia`, `dim_canal` (dimensiones curadas
  que concilian código vs nombre de ciudad y punto físico vs canal digital), `fact_transacciones`
  (USD, horario hábil), `fact_cartera` (bucket_mora, calificación regulatoria A-E, provisión
  estimada), `fact_rentabilidad_cliente` (CLTV rolling 12 meses), `kpi_cartera_diaria`
  (materialización incremental, snapshot diario tipo Kimball). Linaje de 10 campos calculados
  en `/docs/linaje.md`. 43/43 pruebas dbt en verde (Silver + Gold). Evidencia con verificación
  matemática de negocio en `docs/evidencia/fase3-gold/`. **Fase 3 completa.**
- 2026-08-25 — andresypm@gmail.com — Fase 4 (Orquestación): 3 Cloud Run Jobs (bronze + transform
  reutilizada para silver/gold) desplegados vía Terraform (`infra/cloud_run.tf`), imágenes en
  Artifact Registry. Workflow real (`orchestration/pipeline_workflow.yaml`, reemplaza el
  placeholder de Fase 2): Bronze→Silver→Gold con dependencias explícitas, 3 reintentos con
  backoff exponencial por etapa, alertas de fallo/reporte diario/anomalía de volumen vía logging
  estructurado + `google_monitoring_alert_policy` (`infra/monitoring.tf`) — sin credenciales de
  correo en el código. Probado real: 2 ejecuciones exitosas end-to-end (528s, 404s) y 1 falla
  forzada deliberadamente (bronze roto temporalmente, workflow agotó reintentos y alertó
  correctamente, revertido con `terraform apply` detectando el drift). Evidencia completa en
  `docs/evidencia/fase4/`. **Fase 4 completa.**
- 2026-08-25 — andresypm@gmail.com — Fase 5 (Gobierno): 3 roles IAM reales con service account
  impersonable cada uno (`infra/governance.tf`) — Ingeniero de Datos (RW 3 capas), Analista
  (solo lectura Gold), Administrador (owner). Cloud Audit Logs (Data Access) habilitados sobre
  Storage/BigQuery. Catálogo de datos en `docs/catalogo-datos.md`. Las 3 alertas operacionales
  verificadas con log real (incluida anomalía de volumen, probada manipulando el histórico de
  comparación). **Bug real encontrado y corregido**: `generate_schema_name.sql` mandaba todos
  los modelos Gold a `finbank_silver_dev` desde Fase 3 por ignorar el `+schema` de la carpeta
  `marts` — se corrigió el macro, se reconstruyeron los 8 marts en `finbank_gold_dev`, se
  limpiaron las copias huérfanas en Silver, se corrigió la query de reporte del Workflow y el
  permiso del orquestador, se republicó la imagen `transform` y se redesplegaron los Cloud Run
  Jobs. Corrida completa de verificación post-fix: 464s, `SUCCEEDED`. Evidencia completa
  (matriz de acceso real por impersonación, log de anomalía de volumen) en
  `docs/evidencia/fase5/`. **Fase 5 completa — prueba técnica completa (Fases 0-5).**
