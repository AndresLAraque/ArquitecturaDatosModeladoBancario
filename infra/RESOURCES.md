# Recursos desplegados — Fase 2 (entorno `dev`)

Desplegado el 2026-08-24 vía `terraform apply -var-file=environments/dev.tfvars`
contra el proyecto `finbank-data-platform-dev`. Salida completa del apply en
`/docs/evidencia/fase2-terraform-apply.txt`. 44 recursos creados, 0 errores
al final (1 ajuste de configuración durante el despliegue, documentado abajo).

| Recurso | Nombre | Región | Propósito |
|---|---|---|---|
| Storage bucket | `finbank-data-platform-dev-bronze` | us-central1 | Capa Bronze — datos crudos, versionado activo |
| Storage bucket | `finbank-data-platform-dev-silver` | us-central1 | Capa Silver — datos limpios/tipados |
| Storage bucket | `finbank-data-platform-dev-gold` | us-central1 | Capa Gold — modelo dimensional |
| BigQuery dataset | `finbank_silver_dev` | us-central1 | Tablas Silver (dbt staging) |
| BigQuery dataset | `finbank_gold_dev` | us-central1 | Tablas dim_/fact_ y KPIs (dbt marts) |
| Cloud SQL (PostgreSQL 16) | `finbank-sqlpg-dev` | us-central1 | Base relacional origen del pipeline (misma estructura que el Postgres local de Fase 1) |
| Cloud SQL database | `finbank` | — | Base de datos dentro de la instancia |
| Cloud SQL user | `finbank` | — | Usuario de aplicación (password solo en Secret Manager) |
| Secret Manager | `finbank-db-password-dev` | global (auto) | Password de Cloud SQL, generado por Terraform (`random_password`), nunca en código |
| Service Account | `finbank-sa-ingestion-dev` | — | Identidad del job de extracción/Bronze — RW solo en bucket bronze + Cloud SQL Client |
| Service Account | `finbank-sa-transform-dev` | — | Identidad de dbt/Silver-Gold — RO bronze, RW silver/gold (GCS + BigQuery) |
| Service Account | `finbank-sa-orchestrator-dev` | — | Identidad del Workflow — invoca Cloud Run, publica en Pub/Sub |
| Pub/Sub topic | `finbank-alerts-dev` | global (auto) | Alertas operacionales (fallo, reporte diario, anomalía de volumen — Fase 4/5) |
| Artifact Registry (Docker) | `finbank-pipeline-dev` | us-central1 | Imágenes de los jobs de Cloud Run (Fase 3/4) |
| Cloud Workflows | `finbank-pipeline-dev` | us-central1 | Orquestador Bronze→Silver→Gold (placeholder — contenido real en Fase 4) |
| Cloud Scheduler | `finbank-pipeline-daily-dev` | us-central1 | Dispara el workflow diario a las 02:00 `America/Bogota`, reintentos x3 con backoff exponencial |
| 14× `google_project_service` | ver `apis.tf` | — | Habilitación de APIs (Storage, BigQuery, SQL Admin, Workflows, Scheduler, Run, Secret Manager, Logging, Monitoring, Pub/Sub, IAM, Artifact Registry, Resource Manager, Service Usage) |
| ~12× IAM bindings granulares | ver `iam.tf` | — | Mínimo privilegio por bucket/dataset/secreto para cada service account |

## Outputs de conexión

```
cloudsql_instance_connection_name = finbank-data-platform-dev:us-central1:finbank-sqlpg-dev
cloudsql_public_ip                = 34.58.103.209
artifact_registry_repo_url        = us-central1-docker.pkg.dev/finbank-data-platform-dev/finbank-pipeline-dev
workflow_name                     = projects/finbank-data-platform-dev/locations/us-central1/workflows/finbank-pipeline-dev
```

## Incidente durante el despliegue (documentado, no oculto)

El primer `apply` falló al crear `google_sql_database_instance.postgres`:
GCP asigna por defecto la edición `ENTERPRISE_PLUS` a las instancias nuevas
de Cloud SQL, que no admite tiers compartidos como `db-f1-micro`. Se agregó
`edition = "ENTERPRISE"` explícito en `cloudsql.tf` y se re-aplicó — los
otros 41 recursos ya creados no se vieron afectados (Terraform es
incremental). Evidencia de ambos intentos en `/docs/evidencia/`.
