# Infraestructura como Código (Terraform)

Aprovisiona **todos** los recursos GCP de la plataforma de datos de FinBank —
no solo lo de la Fase 2. Este módulo creció junto con el proyecto: nació en
Fase 2 con la infraestructura base (Storage, BigQuery, Cloud SQL, IAM del
pipeline, Workflows/Scheduler con contenido placeholder) y luego se le
agregaron los Cloud Run Jobs + alertas de monitoreo en Fase 4
(`cloud_run.tf`, `monitoring.tf`) y el gobierno de accesos en Fase 5
(`governance.tf`). Hoy es el único lugar con la infraestructura completa.

## Recursos que aprovisiona

| Recurso | Archivo | Cantidad | Propósito |
|---|---|---|---|
| `google_project_service` | `apis.tf` | 14 APIs | Habilita todo lo necesario (Storage, BigQuery, SQL Admin, Workflows, Scheduler, Run, Secret Manager, Logging, Monitoring, Pub/Sub, IAM, Artifact Registry) |
| `google_storage_bucket` | `storage.tf` | 3 | `bronze` / `silver` / `gold` — data lake, particionado por capa |
| `google_bigquery_dataset` | `bigquery.tf` | 2 | `finbank_silver_<env>`, `finbank_gold_<env>` |
| `google_sql_database_instance` (+ db + user) | `cloudsql.tf` | 1 | Postgres 16, base origen del pipeline |
| `random_password` + Secret Manager | `cloudsql.tf` | 1 | Password de la BD, generado por Terraform, nunca en código |
| `google_service_account` (pipeline) | `iam.tf` | 3 | `sa-ingestion`, `sa-transform`, `sa-orchestrator` — mínimo privilegio |
| IAM bindings del pipeline | `iam.tf` | 22 bloques | A nivel de bucket/dataset/secreto, no de proyecto, donde es posible |
| `google_pubsub_topic` | `pubsub.tf` | 1 | `finbank-alerts-<env>` (aprovisionado; la alerta final terminó resuelta vía Cloud Logging + Monitoring, ver README raíz) |
| `google_artifact_registry_repository` | `artifact_registry.tf` | 1 | Imágenes Docker de los 3 Cloud Run Jobs |
| `google_workflows_workflow` + `google_cloud_scheduler_job` | `orchestration.tf` | 1 + 1 | Orquestador Bronze→Silver→Gold (contenido real desde Fase 4), cron diario 02:00 `America/Bogota`, reintentos con backoff |
| `google_cloud_run_v2_job` | `cloud_run.tf` (Fase 4) | 3 | Bronze / Silver / Gold — cada uno corre bajo su propia service account, imagen desde Artifact Registry |
| `google_monitoring_notification_channel` + `google_monitoring_alert_policy` | `monitoring.tf` (Fase 4) | 1 + 3 | Canal de email + las 3 alertas log-based: fallo de tarea, reporte diario de éxito, anomalía de volumen |
| `google_service_account` (roles humanos) + IAM + audit config | `governance.tf` (Fase 5) | 17 recursos | 3 roles impersonables (Ingeniero de Datos / Analista / Administrador), sus bindings de mínimo privilegio, Data Access Audit Logs sobre Storage/BigQuery, y el permiso de impersonación para el candidato — ver detalle abajo |

El conteo exacto y actualizado de recursos vivos se obtiene con
`terraform state list \| wc -l` o `terraform plan` (sin diffs = infraestructura
al día); `docs/evidencia/fase2-terraform-apply.txt` documenta el primer
`apply` (44 recursos, solo Fase 2) como evidencia histórica, no como el
total final — los `apply` posteriores de Fase 4/5 no se volvieron a
capturar en un archivo aparte.

## Gobierno de accesos (`governance.tf`, Fase 5)

3 roles humanos, cada uno con su propia service account para poder
**demostrar** el control de acceso por impersonación real (no solo
declararlo) — la cuenta humana del candidato puede asumir cualquiera de
las 3 vía `roles/iam.serviceAccountTokenCreator`:

| Rol | Acceso | Nada de acceso a |
|---|---|---|
| Ingeniero de Datos | RW en bronze/silver/gold (Storage + BigQuery) | — (control total sobre las 3 capas de datos) |
| Analista | Solo lectura en el dataset Gold (BigQuery) | Bronze, Silver — ni siquiera lectura |
| Administrador | `roles/owner` del proyecto | — |

Más `google_project_iam_audit_config` (Data Access — `DATA_READ`/`DATA_WRITE`)
sobre `storage.googleapis.com` y `bigquery.googleapis.com`. Evidencia real de
la denegación de acceso (por impersonación, no simulada) en
`docs/evidencia/fase5/access-control-matrix.txt`.

Estas identidades son distintas de `sa-ingestion`/`sa-transform`/
`sa-orchestrator` (`iam.tf`), que son las identidades bajo las que corre el
pipeline mismo — los 3 roles de gobierno representan personas, no el propio
sistema.

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
