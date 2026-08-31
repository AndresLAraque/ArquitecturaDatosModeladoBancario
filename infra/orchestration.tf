# Orquestación: Cloud Workflows + Cloud Scheduler (decisión documentada en
# el README raíz — se prefirió sobre Cloud Composer para no agotar el
# crédito del free trial con un ambiente Airflow gestionado de costo fijo).
# `source_contents` lee directamente de orchestration/pipeline_workflow.yaml,
# así que este recurso siempre despliega el contenido real de ese archivo:
# en Fase 2 era un placeholder mínimo; desde Fase 4 es el workflow completo
# (dependencias Bronze->Silver->Gold, reintentos, backoff, alertas).

resource "google_workflows_workflow" "pipeline" {
  name                = "${var.resource_prefix}-pipeline-${var.environment}"
  project             = var.project_id
  region              = var.region
  description         = "Orquesta Bronze -> Silver -> Gold del pipeline FinBank."
  service_account     = google_service_account.orchestrator.id
  source_contents     = file("${path.module}/../orchestration/pipeline_workflow.yaml")
  labels              = var.labels
  deletion_protection = var.environment != "dev" # en prod, protege de un destroy accidental

  depends_on = [google_project_service.apis]
}

resource "google_cloud_scheduler_job" "daily_run" {
  name        = "${var.resource_prefix}-pipeline-daily-${var.environment}"
  project     = var.project_id
  region      = var.region
  description = "Disparo diario del pipeline FinBank."
  # 02:00 hora local del proyecto (Colombia), requisito explícito del enunciado.
  schedule  = "0 2 * * *"
  time_zone = "America/Bogota"

  retry_config {
    retry_count          = 3
    min_backoff_duration = "10s"
    max_backoff_duration = "300s" # backoff exponencial entre reintentos
  }

  http_target {
    http_method = "POST"
    uri         = "https://workflowexecutions.googleapis.com/v1/${google_workflows_workflow.pipeline.id}/executions"
    oauth_token {
      service_account_email = google_service_account.orchestrator.email
    }
  }

  depends_on = [google_project_service.apis]
}
