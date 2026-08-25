# Repositorio Docker para las imágenes de los jobs de Cloud Run (Bronze /
# Silver / Gold) que se construyen y despliegan en la Fase 3/4.
resource "google_artifact_registry_repository" "pipeline_images" {
  repository_id = "${var.resource_prefix}-pipeline-${var.environment}"
  project       = var.project_id
  location      = var.region
  format        = "DOCKER"
  description   = "Imágenes de los jobs de Cloud Run del pipeline Bronze/Silver/Gold."

  labels     = var.labels
  depends_on = [google_project_service.apis]
}
