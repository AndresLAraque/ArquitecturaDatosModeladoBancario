# Fase 5 — Gobierno: los 3 roles humanos exigidos por el enunciado, más
# auditoría de accesos.
#
# Importante: esto NO son las identidades del pipeline (sa-ingestion,
# sa-transform, sa-orchestrator de iam.tf) — esas son cuentas de servicio
# para que el pipeline mismo corra bajo su propia identidad de mínimo
# privilegio. Los 3 roles de acá representan a PERSONAS que interactúan
# con la plataforma: Ingeniero de Datos, Analista y Administrador.
#
# Como esta prueba corre con una sola cuenta humana real (la del
# candidato), se crea una service account POR ROL para poder demostrar
# el control de acceso de forma real e impersonable — no solo "en el
# papel". Ver docs/evidencia/fase5/ para la demostración real de
# impersonación (analista bloqueado en bronze/silver, con acceso a gold).

resource "google_service_account" "role_ingeniero_datos" {
  account_id   = "${var.resource_prefix}-role-ing-datos-${var.environment}"
  project      = var.project_id
  display_name = "Rol: Ingeniero de Datos"
  description  = "Lectura y escritura en las 3 capas (bronze/silver/gold) — para debugging y desarrollo humano, no para el pipeline en sí."
}

resource "google_service_account" "role_analista" {
  account_id   = "${var.resource_prefix}-role-analista-${var.environment}"
  project      = var.project_id
  display_name = "Rol: Analista"
  description  = "Solo lectura sobre la capa Gold. Sin ningún acceso a bronze/silver — ni siquiera de lectura."
}

resource "google_service_account" "role_administrador" {
  account_id   = "${var.resource_prefix}-role-admin-${var.environment}"
  project      = var.project_id
  display_name = "Rol: Administrador"
  description  = "Control total sobre los recursos del proyecto."
}

# --- Ingeniero de Datos: RW en las 3 capas -------------------------------
resource "google_storage_bucket_iam_member" "ing_datos_bronze_rw" {
  bucket = google_storage_bucket.layer["bronze"].name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.role_ingeniero_datos.email}"
}

resource "google_storage_bucket_iam_member" "ing_datos_silver_rw" {
  bucket = google_storage_bucket.layer["silver"].name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.role_ingeniero_datos.email}"
}

resource "google_storage_bucket_iam_member" "ing_datos_gold_rw" {
  bucket = google_storage_bucket.layer["gold"].name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.role_ingeniero_datos.email}"
}

resource "google_bigquery_dataset_iam_member" "ing_datos_silver_editor" {
  dataset_id = google_bigquery_dataset.silver.dataset_id
  project    = var.project_id
  role       = "roles/bigquery.dataEditor"
  member     = "serviceAccount:${google_service_account.role_ingeniero_datos.email}"
}

resource "google_bigquery_dataset_iam_member" "ing_datos_gold_editor" {
  dataset_id = google_bigquery_dataset.gold.dataset_id
  project    = var.project_id
  role       = "roles/bigquery.dataEditor"
  member     = "serviceAccount:${google_service_account.role_ingeniero_datos.email}"
}

resource "google_project_iam_member" "ing_datos_bq_job_user" {
  project = var.project_id
  role    = "roles/bigquery.jobUser"
  member  = "serviceAccount:${google_service_account.role_ingeniero_datos.email}"
}

# --- Analista: SOLO lectura en Gold. Nada en bronze/silver ---------------
resource "google_bigquery_dataset_iam_member" "analista_gold_viewer" {
  dataset_id = google_bigquery_dataset.gold.dataset_id
  project    = var.project_id
  role       = "roles/bigquery.dataViewer"
  member     = "serviceAccount:${google_service_account.role_analista.email}"
}

resource "google_project_iam_member" "analista_bq_job_user" {
  project = var.project_id
  role    = "roles/bigquery.jobUser" # necesario para poder ejecutar una consulta, no da acceso a datos por sí solo
  member  = "serviceAccount:${google_service_account.role_analista.email}"
}
# Deliberadamente NO hay ningún IAM binding de esta cuenta sobre los
# buckets bronze/silver, ni sobre el dataset silver — la ausencia de
# permiso es la política (denegación por defecto de GCP).

# --- Administrador: control total del proyecto ---------------------------
resource "google_project_iam_member" "administrador_owner" {
  project = var.project_id
  role    = "roles/owner"
  member  = "serviceAccount:${google_service_account.role_administrador.email}"
}

# --- Auditoría de accesos a los datos (requisito explícito) --------------
# Habilita los logs de Data Access (quién leyó/escribió qué y cuándo) para
# Storage y BigQuery — deshabilitados por defecto en GCP por su volumen.
resource "google_project_iam_audit_config" "storage_data_access" {
  project = var.project_id
  service = "storage.googleapis.com"

  audit_log_config {
    log_type = "DATA_READ"
  }
  audit_log_config {
    log_type = "DATA_WRITE"
  }
}

resource "google_project_iam_audit_config" "bigquery_data_access" {
  project = var.project_id
  service = "bigquery.googleapis.com"

  audit_log_config {
    log_type = "DATA_READ"
  }
  audit_log_config {
    log_type = "DATA_WRITE"
  }
}

# --- Permitir impersonar los 3 roles desde la cuenta humana real del
# candidato, únicamente para poder DEMOSTRAR el control de acceso
# (docs/evidencia/fase5/) — no es parte del modelo de permisos del
# pipeline en sí. -----------------------------------------------------
locals {
  demo_roles = {
    ingeniero_datos = google_service_account.role_ingeniero_datos.name
    analista        = google_service_account.role_analista.name
    administrador   = google_service_account.role_administrador.name
  }
}

resource "google_service_account_iam_member" "candidate_can_impersonate" {
  for_each           = local.demo_roles
  service_account_id = each.value
  role               = "roles/iam.serviceAccountTokenCreator"
  member             = "user:andresypm@gmail.com"
}
