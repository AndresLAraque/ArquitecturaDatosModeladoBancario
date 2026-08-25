# Fase 2 — Infraestructura como Código (Terraform)

Aprovisiona todos los recursos GCP de la plataforma de datos de FinBank.

## Recursos que aprovisiona

| Recurso | Cantidad | Propósito |
|---|---|---|
| `google_project_service` | 14 APIs | Habilita todo lo necesario (Storage, BigQuery, SQL Admin, Workflows, Scheduler, Run, Secret Manager, Logging, Monitoring, Pub/Sub, IAM, Artifact Registry) |
| `google_storage_bucket` | 3 | `bronze` / `silver` / `gold` — data lake, particionado por capa |
| `google_bigquery_dataset` | 2 | `finbank_silver_<env>`, `finbank_gold_<env>` |
| `google_sql_database_instance` (+ db + user) | 1 | Postgres 16, base origen del pipeline |
| `random_password` + Secret Manager | 1 | Password de la BD, generado por Terraform, nunca en código |
| `google_service_account` | 3 | `sa-ingestion`, `sa-transform`, `sa-orchestrator` — mínimo privilegio |
| IAM bindings granulares | ~12 | A nivel de bucket/dataset/secreto, no de proyecto, donde es posible |
| `google_pubsub_topic` | 1 | `finbank-alerts-<env>` |
| `google_artifact_registry_repository` | 1 | Imágenes Docker de los jobs de Cloud Run (Fase 3/4) |
| `google_workflows_workflow` + `google_cloud_scheduler_job` | 1 + 1 | Orquestación (placeholder de contenido — real en Fase 4), cron diario 02:00 `America/Bogota`, reintentos con backoff |

**Nota:** `google_cloud_run_v2_job` para los contenedores de Bronze/Silver/Gold
se agregan en la Fase 3/4, cuando ya existan imágenes que desplegar (no antes
— evita un recurso Terraform sin imagen válida).

## Por qué Cloud Workflows + Scheduler y no Cloud Composer

Ver la tabla de justificación en el `README.md` raíz del repositorio: un
ambiente Composer, incluso el más pequeño, cuesta ~300-450 USD/mes de forma
fija — agotaría el crédito del free trial en días. Workflows + Scheduler +
Run es serverless y una opción explícitamente válida en el enunciado para GCP.

## Dos entornos

Vía archivos de variables separados (`environments/dev.tfvars`,
`environments/prod.tfvars`), no vía Terraform workspaces — más explícito y
fácil de revisar en un PR. `prod.tfvars` es un ejemplo documentado, no se
aplica contra un proyecto real (ver nota dentro del archivo).

## Despliegue

### 0. Bootstrap del backend remoto (una sola vez, antes de `terraform init`)

```bash
gcloud storage buckets create gs://<PROJECT_ID>-tfstate \
  --project=<PROJECT_ID> --location=us-central1 --uniform-bucket-level-access
gcloud storage buckets update gs://<PROJECT_ID>-tfstate --versioning
```

Ya ejecutado para este proyecto (`finbank-data-platform-dev-tfstate`).
Si cambias de proyecto, actualiza también el nombre del bucket en `backend.tf`.

### 1. Init, plan, apply

```bash
cd infra
terraform init
terraform plan  -var-file=environments/dev.tfvars
terraform apply -var-file=environments/dev.tfvars
```

### 2. Verificar

```bash
terraform output
```

## Estándares aplicados (requisitos del enunciado)

- **Cero credenciales en código:** la contraseña de Cloud SQL se genera con
  `random_password` y solo se guarda en Secret Manager; ningún `.tf` ni
  `.tfvars` contiene un secreto.
- **Todo parametrizado:** nombre de recursos, región, entorno y tamaño de
  instancia vienen de `variables.tf` + `environments/*.tfvars`.
- **Backend remoto:** estado en GCS (`backend.tf`), nunca commiteado
  (`.gitignore` raíz excluye `*.tfstate*` y `.terraform/`).
- **Dos entornos:** `dev.tfvars` / `prod.tfvars`.
- **Outputs completos:** `outputs.tf` exporta nombres/URLs de todos los
  recursos para que los scripts de Fase 3/4 no tengan que hardcodear nada.
