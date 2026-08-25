# Identidades de servicio del PIPELINE (no confundir con los 3 roles humanos
# de gobierno de la Fase 5 — Ingeniero de Datos / Analista / Administrador,
# que se implementan aparte). Principio de mínimo privilegio: cada
# componente del pipeline corre bajo su propia service account, con permiso
# solo sobre lo que necesita tocar.

resource "google_service_account" "ingestion" {
  account_id   = "${var.resource_prefix}-sa-ingestion-${var.environment}"
  project      = var.project_id
  display_name = "FinBank Pipeline — Ingesta Bronze"
  description  = "Extrae de Cloud SQL y escribe únicamente en el bucket bronze."
}

resource "google_service_account" "transform" {
  account_id   = "${var.resource_prefix}-sa-transform-${var.environment}"
  project      = var.project_id
  display_name = "FinBank Pipeline — Transformación Silver/Gold"
  description  = "Lee bronze, escribe silver/gold en GCS y BigQuery (dbt)."
}

resource "google_service_account" "orchestrator" {
  account_id   = "${var.resource_prefix}-sa-orchestrator-${var.environment}"
  project      = var.project_id
  display_name = "FinBank Pipeline — Orquestador (Cloud Workflows)"
  description  = "Identidad del workflow: invoca los jobs de Cloud Run y publica alertas."
}

# --- sa-ingestion: solo bronze, solo Cloud SQL, solo su propio secreto -----
resource "google_storage_bucket_iam_member" "ingestion_bronze_admin" {
  bucket = google_storage_bucket.layer["bronze"].name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.ingestion.email}"
}

resource "google_project_iam_member" "ingestion_cloudsql_client" {
  project = var.project_id
  role    = "roles/cloudsql.client"
  member  = "serviceAccount:${google_service_account.ingestion.email}"
}

resource "google_secret_manager_secret_iam_member" "ingestion_db_secret" {
  secret_id = google_secret_manager_secret.db_password.secret_id
  project   = var.project_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.ingestion.email}"
}

# --- sa-transform: lee bronze, escribe silver/gold (GCS + BigQuery) -------
resource "google_storage_bucket_iam_member" "transform_bronze_viewer" {
  bucket = google_storage_bucket.layer["bronze"].name
  role   = "roles/storage.objectViewer"
  member = "serviceAccount:${google_service_account.transform.email}"
}

resource "google_storage_bucket_iam_member" "transform_silver_admin" {
  bucket = google_storage_bucket.layer["silver"].name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.transform.email}"
}

resource "google_storage_bucket_iam_member" "transform_gold_admin" {
  bucket = google_storage_bucket.layer["gold"].name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.transform.email}"
}

resource "google_bigquery_dataset_iam_member" "transform_silver_editor" {
  dataset_id = google_bigquery_dataset.silver.dataset_id
  project    = var.project_id
  role       = "roles/bigquery.dataEditor"
  member     = "serviceAccount:${google_service_account.transform.email}"
}

resource "google_bigquery_dataset_iam_member" "transform_gold_editor" {
  dataset_id = google_bigquery_dataset.gold.dataset_id
  project    = var.project_id
  role       = "roles/bigquery.dataEditor"
  member     = "serviceAccount:${google_service_account.transform.email}"
}

resource "google_project_iam_member" "transform_bq_job_user" {
  project = var.project_id
  role    = "roles/bigquery.jobUser"
  member  = "serviceAccount:${google_service_account.transform.email}"
}

# --- sa-orchestrator: solo invocar Cloud Run y publicar alertas -----------
resource "google_project_iam_member" "orchestrator_run_invoker" {
  project = var.project_id
  role    = "roles/run.invoker"
  member  = "serviceAccount:${google_service_account.orchestrator.email}"
}

resource "google_project_iam_member" "orchestrator_workflows_invoker" {
  project = var.project_id
  role    = "roles/workflows.invoker"
  member  = "serviceAccount:${google_service_account.orchestrator.email}"
}

resource "google_pubsub_topic_iam_member" "orchestrator_publisher" {
  topic  = google_pubsub_topic.alerts.name
  role   = "roles/pubsub.publisher"
  member = "serviceAccount:${google_service_account.orchestrator.email}"
}

# --- Logging estructurado (Fase 4/5): las 3 identidades escriben las
# alertas de TASK_FAILURE / PIPELINE_SUCCESS_SUMMARY / VOLUME_ANOMALY que
# consumen las políticas de Cloud Monitoring (infra/monitoring.tf) --------
resource "google_project_iam_member" "ingestion_log_writer" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.ingestion.email}"
}

resource "google_project_iam_member" "transform_log_writer" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.transform.email}"
}

resource "google_project_iam_member" "orchestrator_log_writer" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.orchestrator.email}"
}

# El orquestador necesita ver el estado (operations/executions) de los
# Cloud Run Jobs que dispara, para hacer polling hasta que terminen.
resource "google_project_iam_member" "orchestrator_run_viewer" {
  project = var.project_id
  role    = "roles/run.viewer"
  member  = "serviceAccount:${google_service_account.orchestrator.email}"
}

# Y consultar BigQuery de solo lectura para armar el reporte diario de
# éxito (registros procesados por capa).
resource "google_project_iam_member" "orchestrator_bq_job_user" {
  project = var.project_id
  role    = "roles/bigquery.jobUser"
  member  = "serviceAccount:${google_service_account.orchestrator.email}"
}

resource "google_bigquery_dataset_iam_member" "orchestrator_silver_viewer" {
  dataset_id = google_bigquery_dataset.silver.dataset_id
  project    = var.project_id
  role       = "roles/bigquery.dataViewer"
  member     = "serviceAccount:${google_service_account.orchestrator.email}"
}

resource "google_bigquery_dataset_iam_member" "orchestrator_gold_viewer" {
  dataset_id = google_bigquery_dataset.gold.dataset_id
  project    = var.project_id
  role       = "roles/bigquery.dataViewer"
  member     = "serviceAccount:${google_service_account.orchestrator.email}"
}
