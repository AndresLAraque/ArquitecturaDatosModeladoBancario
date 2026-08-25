# Base de datos relacional origen (Fase 1) desplegada en la nube. La
# contraseña se genera aleatoriamente en el plan de Terraform y SOLO se
# guarda en Secret Manager — nunca aparece en código ni en un output plano
# (requisito explícito del enunciado: cero credenciales en el repo).
resource "random_password" "db_password" {
  length  = 24
  special = false # evita problemas de escape en cadenas de conexión
}

resource "google_sql_database_instance" "postgres" {
  name             = "${var.resource_prefix}-sqlpg-${var.environment}"
  project          = var.project_id
  region           = var.region
  database_version = "POSTGRES_16"

  # dev: se puede destruir sin fricción para ahorrar crédito del free trial.
  # prod: protegido contra un `terraform destroy` accidental.
  deletion_protection = var.environment == "prod"

  settings {
    edition           = "ENTERPRISE" # requerido para poder usar tiers compartidos tipo db-f1-micro
    tier              = var.cloud_sql_tier
    availability_type = "ZONAL"
    disk_size         = 10
    disk_autoresize   = true
    disk_type         = "PD_SSD"

    backup_configuration {
      enabled    = true
      start_time = "07:00" # madrugada UTC ~ 02:00 hora Colombia, fuera de la ventana del pipeline
    }

    ip_configuration {
      ipv4_enabled = true

      dynamic "authorized_networks" {
        for_each = toset(var.cloud_sql_authorized_networks)
        content {
          name  = "authorized-${replace(authorized_networks.value, "/[.\\/]/", "-")}"
          value = authorized_networks.value
        }
      }
    }

    user_labels = var.labels
  }

  depends_on = [google_project_service.apis]
}

resource "google_sql_database" "finbank" {
  name     = "finbank"
  project  = var.project_id
  instance = google_sql_database_instance.postgres.name
}

resource "google_sql_user" "finbank" {
  name     = "finbank"
  project  = var.project_id
  instance = google_sql_database_instance.postgres.name
  password = random_password.db_password.result
}

resource "google_secret_manager_secret" "db_password" {
  secret_id = "${var.resource_prefix}-db-password-${var.environment}"
  project   = var.project_id

  replication {
    auto {}
  }

  labels     = var.labels
  depends_on = [google_project_service.apis]
}

resource "google_secret_manager_secret_version" "db_password" {
  secret      = google_secret_manager_secret.db_password.id
  secret_data = random_password.db_password.result
}
