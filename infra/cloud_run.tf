# Cloud Run Jobs de las 3 etapas del pipeline (Fase 4). Diferidos hasta
# ahora a propósito: en Fase 2 no existían imágenes que desplegar. Los
# reintentos con backoff exponencial se manejan en el Workflow (Fase 4,
# orchestration/pipeline_workflow.yaml), no acá — por eso max_retries = 0:
# evita que el reintento nativo de Cloud Run Job y el del Workflow se
# combinen de forma confusa (dos mecanismos de retry sobre la misma falla).

locals {
  image_bronze    = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.pipeline_images.repository_id}/bronze:latest"
  image_transform = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.pipeline_images.repository_id}/transform:latest"
}

resource "google_cloud_run_v2_job" "bronze" {
  name                = "${var.resource_prefix}-bronze-${var.environment}"
  project             = var.project_id
  location            = var.region
  deletion_protection = var.environment != "dev" # en prod, protege de un destroy accidental

  template {
    template {
      service_account = google_service_account.ingestion.email
      timeout         = "900s" # 15 min — el volumen real (500k filas) tardó ~77s, margen amplio
      max_retries     = 0

      containers {
        image = local.image_bronze
        resources {
          limits = { cpu = "1", memory = "1Gi" }
        }
        env {
          name  = "FINBANK_GCP_PROJECT_ID"
          value = var.project_id
        }
      }
    }
  }

  depends_on = [google_project_service.apis]
}

resource "google_cloud_run_v2_job" "silver" {
  name                = "${var.resource_prefix}-silver-${var.environment}"
  project             = var.project_id
  location            = var.region
  deletion_protection = var.environment != "dev" # en prod, protege de un destroy accidental

  template {
    template {
      service_account = google_service_account.transform.email
      timeout         = "900s"
      max_retries     = 0

      containers {
        image = local.image_transform
        resources {
          limits = { cpu = "1", memory = "1Gi" }
        }
        env {
          name  = "STAGE"
          value = "silver"
        }
        env {
          name  = "FINBANK_GCP_PROJECT_ID"
          value = var.project_id
        }
      }
    }
  }

  depends_on = [google_project_service.apis]
}

resource "google_cloud_run_v2_job" "gold" {
  name                = "${var.resource_prefix}-gold-${var.environment}"
  project             = var.project_id
  location            = var.region
  deletion_protection = var.environment != "dev" # en prod, protege de un destroy accidental

  template {
    template {
      service_account = google_service_account.transform.email
      timeout         = "900s"
      max_retries     = 0

      containers {
        image = local.image_transform
        resources {
          limits = { cpu = "1", memory = "1Gi" }
        }
        env {
          name  = "STAGE"
          value = "gold"
        }
        env {
          name  = "FINBANK_GCP_PROJECT_ID"
          value = var.project_id
        }
      }
    }
  }

  depends_on = [google_project_service.apis]
}
