project_id  = "finbank-data-platform-dev"
region      = "us-central1"
environment = "dev"

resource_prefix = "finbank"
cloud_sql_tier  = "db-f1-micro" # el más barato disponible, adecuado para dev/free trial

# Vacío: se recomienda conectar vía Cloud SQL Auth Proxy en vez de abrir IP pública.
cloud_sql_authorized_networks = []

# alert_notification_email e impersonator_email son datos personales del
# operador: se pasan aparte, vía environments/local.tfvars (no versionado,
# ver local.tfvars.example) en vez de quedar fijos aquí.

labels = {
  proyecto = "finbank-data-platform"
  prueba   = "dataknow-tecnica"
  ambiente = "dev"
}
