# Buckets del data lake — capas Bronze / Silver / Gold de la arquitectura
# Medallón (Fase 3). Nombrados con el project_id como prefijo porque el
# namespace de GCS es global (no basta con el nombre del proyecto/entorno).
locals {
  layers = ["bronze", "silver", "gold"]
}

resource "google_storage_bucket" "layer" {
  for_each = toset(local.layers)

  name                        = "${var.project_id}-${each.value}"
  project                     = var.project_id
  location                    = var.region
  storage_class               = "STANDARD"
  uniform_bucket_level_access = true
  force_destroy               = var.environment == "dev" # en prod, protege de un destroy accidental

  versioning {
    enabled = each.value == "bronze" # Bronze es la fuente de verdad reproducible: se versiona
  }

  lifecycle_rule {
    condition {
      age = 30
    }
    action {
      type          = "SetStorageClass"
      storage_class = "NEARLINE"
    }
  }

  labels = var.labels

  depends_on = [google_project_service.apis]
}
