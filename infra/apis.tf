# Habilitación de APIs como código (en vez de manual con gcloud), para que
# todo el aprovisionamiento sea reproducible desde cero con `terraform apply`.
locals {
  required_apis = [
    "storage.googleapis.com",
    "bigquery.googleapis.com",
    "sqladmin.googleapis.com",
    "workflows.googleapis.com",
    "cloudscheduler.googleapis.com",
    "run.googleapis.com",
    "secretmanager.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com",
    "pubsub.googleapis.com",
    "iam.googleapis.com",
    "artifactregistry.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "serviceusage.googleapis.com",
  ]
}

resource "google_project_service" "apis" {
  for_each = toset(local.required_apis)

  project            = var.project_id
  service            = each.value
  disable_on_destroy = false # no deshabilitar APIs de todo el proyecto al hacer destroy de este módulo
}
