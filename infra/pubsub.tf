# Topic de alertas operacionales del pipeline (fallo de tarea, reporte
# diario, anomalía de volumen — Fase 4/5). La suscripción que conecta esto
# a un correo/canal real se implementa en la Fase 4 junto con el workflow.
resource "google_pubsub_topic" "alerts" {
  name    = "${var.resource_prefix}-alerts-${var.environment}"
  project = var.project_id
  labels  = var.labels

  depends_on = [google_project_service.apis]
}
