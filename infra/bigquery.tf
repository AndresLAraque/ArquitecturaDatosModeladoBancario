# Datasets BigQuery — destino de las transformaciones Silver y Gold (Fase 3,
# vía dbt). No se crea un dataset "bronze": Bronze vive como archivos
# Parquet en GCS (requisito explícito del enunciado), BigQuery solo entra
# a partir de Silver.
resource "google_bigquery_dataset" "silver" {
  dataset_id  = "${var.resource_prefix}_silver_${var.environment}"
  project     = var.project_id
  location    = var.region
  description = "Capa Silver: datos limpios, tipados, con integridad referencial validada y PII enmascarada."

  delete_contents_on_destroy = var.environment == "dev" # en prod, protege de un destroy accidental

  labels = var.labels

  depends_on = [google_project_service.apis]
}

resource "google_bigquery_dataset" "gold" {
  dataset_id  = "${var.resource_prefix}_gold_${var.environment}"
  project     = var.project_id
  location    = var.region
  description = "Capa Gold: modelo dimensional de negocio (dim_/fact_) y KPIs ejecutivos."

  delete_contents_on_destroy = var.environment == "dev" # en prod, protege de un destroy accidental

  labels = var.labels

  depends_on = [google_project_service.apis]
}
