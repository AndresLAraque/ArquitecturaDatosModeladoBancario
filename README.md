# FinBank — Plataforma de Datos

**Estado: completa (Fases 0-5).** Repositorio:
https://github.com/AndresLAraque/ArquitecturaDatosModeladoBancario

## Sector y plataforma elegidos

- **Sector / escenario:** Escenario A — Banca y Servicios Financieros (FinBank S.A.)
- **Plataforma cloud:** Google Cloud Platform (capa de prueba gratuita, USD 300 / 90 días)

### Justificación

**Sector (Escenario A):** elegí este escenario porque tiene las reglas de negocio más ricas
del sector bancario — mora, provisión regulatoria, transacciones atípicas, CLTV — y eso
ejercita bien las tres capas de la arquitectura Medallón.

**Plataforma (GCP):** elegí GCP porque tengo acceso a la capa de prueba gratuita (USD 300 de
crédito). Dentro de GCP prioricé servicios **serverless / pay-per-use** sobre servicios con
costo fijo por hora, para que el crédito rindiera lo más posible:

| Necesidad | Servicio elegido | Motivo |
|---|---|---|
| Almacenamiento Bronze | Cloud Storage (bucket `bronze`, Parquet particionado) | Bronze son archivos crudos en la nube |
| Almacenamiento Silver/Gold | **BigQuery** (`finbank_silver_dev` / `finbank_gold_dev`) | Serverless, sin clúster con costo por hora, 1TB de consultas gratis al mes. Los buckets `silver`/`gold` quedan aprovisionados igual, pero la data vive en BigQuery — ver "Arquitectura" abajo |
| Procesamiento Silver/Gold | **dbt + BigQuery** | Tests, documentación y linaje con poco esfuerzo extra |
| Orquestación | **Cloud Workflows + Cloud Scheduler + Cloud Run Jobs** | Serverless y sin costo fijo (Composer/Airflow gestionado cuesta ~300-450 USD/mes incluso mínimo, agotaría el crédito en días) |
| Base de datos origen | Cloud SQL (PostgreSQL 16) | Motor estándar para este tipo de carga transaccional |
| IaC | Terraform | Estándar del mercado, soporta backend remoto en GCS |
| Secretos | Secret Manager | Ninguna credencial en código |
| Notificaciones | Cloud Logging estructurado + Cloud Monitoring (alertas por log) → email | El Workflow y Bronze escriben logs estructurados y 3 políticas de Cloud Monitoring hacen match y envían el correo, sin necesitar un servicio adicional |

**Proyecto GCP:** `finbank-data-platform-dev` (región `us-central1`)

## Arquitectura y flujo de datos

```
Cloud SQL (Postgres 16, 6 tablas fuente)
        │  extract_to_bronze.py (Cloud Run Job)
        ▼
GCS bronze/  ─── Parquet particionado year/month/day, +3 cols de auditoría
        │  load_bronze_to_bq.py + dbt run --select tag:silver (Cloud Run Job)
        ▼
BigQuery finbank_silver_dev  ─── dedup, tipado, integridad referencial (tabla de
        │                        errores), nulos tratados, PII hasheada, ind_sospechoso
        │  dbt run --select tag:gold (Cloud Run Job)
        ▼
BigQuery finbank_gold_dev  ─── dim_*/fact_*/kpi_* con las reglas de negocio del
                                Escenario A (bucket_mora, provisión, CLTV, USD...)

Orquestado por Cloud Workflows (orchestration/pipeline_workflow.yaml), disparado
a diario por Cloud Scheduler (02:00 America/Bogota). Alertas de fallo/reporte
diario/anomalía de volumen vía Cloud Logging + Cloud Monitoring → email.
```

Los 3 roles de gobierno (Ingeniero de Datos / Analista / Administrador,
`infra/governance.tf`) controlan quién puede leer/escribir cada capa —
verificado con pruebas reales de acceso denegado, no solo declarado (ver
`docs/evidencia/fase5/`).

## Estructura del repositorio

```
/data-generation      Fase 1 — generador sintético (seed fija) + carga a Postgres/Cloud SQL
/infra                Fase 2 — Terraform completo (44+ recursos), README de despliegue
/pipelines
  /bronze              Fase 3 — extracción Cloud SQL -> GCS (Cloud Run Job)
  /silver              Puente Bronze (GCS) -> BigQuery para que dbt tenga sources
  /dbt_finbank         Fase 3 — proyecto dbt: modelos staging (Silver) y marts (Gold)
  /transform           Fase 4 — imagen Docker compartida por los Cloud Run Jobs silver/gold
  /common              Utilidad compartida de alertas (anomalía de volumen)
/orchestration         Fase 4 — DAG de Cloud Workflows + README
/docs                  Diagrama ER, linaje de campos calculados, catálogo de datos,
                        evidencia real de cada fase en /docs/evidencia/
README.md              Este archivo
PLAN.md                Checklist detallado de las 5 fases, con lo completado marcado
CHANGELOG.md           Historial de cambios con fecha, autor y descripción
```

## Cómo desplegar y ejecutar todo desde cero

Cada carpeta tiene su propio `README.md` con el detalle; esta es la secuencia
completa de punta a punta:

```bash
# 0. Prerrequisitos: cuenta GCP con free trial, proyecto creado, gcloud
#    autenticado (gcloud init + gcloud auth application-default login),
#    Terraform, Docker, Python 3.12.

# 1. Generar datos sintéticos y cargarlos (Postgres local o Cloud SQL)
cd data-generation

# 1a. Entorno virtual y variables locales
#   Windows (PowerShell/cmd):
python -m venv .venv && .venv\Scripts\activate
copy .env.example .env
#   macOS / Linux:
python3 -m venv .venv && source .venv/bin/activate
cp .env.example .env
#   (completar valores locales en .env, nunca commitear)

# 1b. El resto de comandos es igual en cualquier sistema operativo
pip install -r requirements.txt
docker compose up -d
python main.py
python load_to_postgres.py

# 2. Aprovisionar toda la infraestructura
cd ../infra
#   Windows (PowerShell/cmd):
copy environments\local.tfvars.example environments\local.tfvars
#   macOS / Linux:
cp environments/local.tfvars.example environments/local.tfvars
#   (completar con tu correo en local.tfvars, nunca commitear)
terraform init
terraform plan  -var-file environments/dev.tfvars -var-file environments/local.tfvars
terraform apply -var-file environments/dev.tfvars -var-file environments/local.tfvars

# 3. Construir y publicar las imágenes de los Cloud Run Jobs
cd ..
gcloud auth configure-docker us-central1-docker.pkg.dev
docker build -f pipelines/bronze/Dockerfile    -t <repo>/bronze:latest    pipelines/
docker build -f pipelines/transform/Dockerfile -t <repo>/transform:latest pipelines/
docker push <repo>/bronze:latest
docker push <repo>/transform:latest

# 4. Correr el pipeline completo (manual; también corre solo a diario vía Scheduler)
gcloud workflows run finbank-pipeline-dev --location=us-central1 --project=<PROJECT_ID>
```

`<repo>` = el output `artifact_registry_repo_url` de `terraform output`.

## Estado de la prueba, fase por fase

| Fase | Contenido | Evidencia real |
|---|---|---|
| 1 — Datos | 6 tablas sintéticas (seed fija), ~5% nulos, 4 anomalías intencionales, 3 formatos, ER | `docs/er-diagram.md`, `data-generation/output/load_evidence_*.txt` |
| 2 — IaC | 44+ recursos Terraform (Storage, BigQuery, Cloud SQL, IAM, Secret Manager, Pub/Sub, Artifact Registry, Workflows, Scheduler) | `infra/RESOURCES.md`, `docs/evidencia/fase2-terraform-apply.txt` |
| 3 — Medallón | Bronze (incremental + auditoría), Silver (21 tests dbt, PII hasheada), Gold (8 marts, linaje de 10 campos) | `docs/evidencia/fase3-{bronze,silver,gold}/` |
| 4 — Orquestación | Workflow real con dependencias, reintentos con backoff, 3 Cloud Run Jobs, alertas | `docs/evidencia/fase4/` (2 corridas exitosas + 1 falla forzada) |
| 5 — Gobierno | 3 roles IAM reales, audit logs, catálogo de datos, las 3 alertas verificadas | `docs/evidencia/fase5/` (matriz de acceso por impersonación real) |

Checklist detallado, con cada ítem del enunciado marcado: **`PLAN.md`**.

## Decisiones y supuestos clave (documentados en detalle donde se aplican)

- **Silver/Gold en BigQuery, no en los buckets:** los buckets `silver`/`gold` quedan
  aprovisionados (requisito de la tabla de recursos), pero dbt materializa Silver y Gold
  como tablas nativas de BigQuery — da upserts/tipado fuerte sin necesitar Delta/Iceberg
  aparte. Justificado en la tabla de arriba.
- **`ind_sospechoso` se calcula en Silver**, no en Gold (regla de negocio explícita del
  enunciado) — ver `pipelines/dbt_finbank/models/staging/stg_movimientos.sql`.
- **Tabla de provisión regulatoria (A-E) simplificada**, inspirada en el modelo de
  Superintendencia Financiera de Colombia — el enunciado no fija los % exactos. Ver
  `fact_cartera.sql`.
- **"Ingresos por intereses" aproximados** desde movimientos de crédito (avances/compras)
  × tasa mensual, porque el esquema fuente no registra una transacción de tipo "interés"
  explícita. Ver `fact_rentabilidad_cliente.sql`.
- **`kpi_cartera_diaria` es un modelo incremental** (snapshot diario acumulativo, patrón
  Kimball), no una tabla que se sobreescribe — coherente con que sea un KPI "diario".
- **No apliqué `prod.tfvars` contra un proyecto real** — el free trial solo cubre un
  proyecto activo; lo dejo documentado como ejercicio de soporte de 2 entornos.

## Notas de gobierno del repositorio

- Ningún `.tfstate` ni `.env` fue commiteado en ningún punto del historial (verificado con
  `git log --all`).
