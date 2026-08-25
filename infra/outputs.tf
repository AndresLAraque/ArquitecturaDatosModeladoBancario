# Outputs consumidos por los scripts de Fase 3/4 (nombres, no secretos —
# la contraseña de la BD se lee de Secret Manager en tiempo de ejecución,
# nunca de un output de Terraform).

output "bucket_names" {
  description = "Nombre de los buckets bronze/silver/gold."
  value       = { for k, b in google_storage_bucket.layer : k => b.name }
}

output "bucket_urls" {
  description = "URL gs:// de los buckets bronze/silver/gold."
  value       = { for k, b in google_storage_bucket.layer : k => b.url }
}

output "bigquery_dataset_silver" {
  description = "Dataset ID de la capa Silver."
  value       = google_bigquery_dataset.silver.dataset_id
}

output "bigquery_dataset_gold" {
  description = "Dataset ID de la capa Gold."
  value       = google_bigquery_dataset.gold.dataset_id
}

output "cloudsql_instance_connection_name" {
  description = "Connection name para Cloud SQL Auth Proxy (project:region:instance)."
  value       = google_sql_database_instance.postgres.connection_name
}

output "cloudsql_public_ip" {
  description = "IP pública de la instancia Cloud SQL."
  value       = google_sql_database_instance.postgres.public_ip_address
}

output "db_password_secret_id" {
  description = "ID del secreto en Secret Manager que contiene la contraseña de la BD (leer el valor, no exponerlo aquí)."
  value       = google_secret_manager_secret.db_password.secret_id
}

output "service_account_emails" {
  description = "Emails de las service accounts del pipeline."
  value = {
    ingestion    = google_service_account.ingestion.email
    transform    = google_service_account.transform.email
    orchestrator = google_service_account.orchestrator.email
  }
}

output "pubsub_alerts_topic" {
  description = "Nombre completo del topic de alertas."
  value       = google_pubsub_topic.alerts.id
}

output "artifact_registry_repo_url" {
  description = "URL del repositorio Docker para las imágenes del pipeline."
  value       = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.pipeline_images.repository_id}"
}

output "workflow_name" {
  description = "Nombre completo del workflow de orquestación."
  value       = google_workflows_workflow.pipeline.id
}

output "scheduler_job_name" {
  description = "Nombre del job de Cloud Scheduler que dispara el pipeline diario."
  value       = google_cloud_scheduler_job.daily_run.name
}
