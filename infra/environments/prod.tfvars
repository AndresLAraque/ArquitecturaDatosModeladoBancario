# NOTA / supuesto documentado: este archivo demuestra el soporte de dos
# entornos vía archivos de variables separados (requisito explícito del
# enunciado), pero NO se aplica contra un proyecto GCP real en esta prueba
# técnica — el free trial cubre un único proyecto activo. En un escenario
# real, "prod" viviría en su propio proyecto GCP (aislamiento total de
# billing/IAM entre entornos), tal como está parametrizado aquí.

project_id  = "finbank-data-platform-prod" # proyecto de ejemplo, no creado
region      = "us-central1"
environment = "prod"

resource_prefix = "finbank"
cloud_sql_tier  = "db-custom-2-7680" # 2 vCPU / 7.5GB, dimensionado para carga real

cloud_sql_authorized_networks = []

alert_notification_email = "andresypm@gmail.com"

labels = {
  proyecto = "finbank-data-platform"
  prueba   = "dataknow-tecnica"
  ambiente = "prod"
}
