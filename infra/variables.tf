variable "project_id" {
  description = "ID del proyecto GCP donde se aprovisiona todo (mismo proyecto para todos los recursos, documentado en el README raíz)."
  type        = string
}

variable "region" {
  description = "Región GCP por defecto para todos los recursos (buckets, BigQuery, Cloud SQL, Cloud Run, Workflows)."
  type        = string
  default     = "us-central1"
}

variable "environment" {
  description = "Entorno de despliegue: dev o prod. Determina prefijos de nombre y tamaños de instancia (ver environments/*.tfvars)."
  type        = string
  validation {
    condition     = contains(["dev", "prod"], var.environment)
    error_message = "environment debe ser \"dev\" o \"prod\"."
  }
}

variable "resource_prefix" {
  description = "Prefijo aplicado a los nombres de recursos que no requieren namespace global único (datasets, instancias, service accounts, topics)."
  type        = string
  default     = "finbank"
}

variable "cloud_sql_tier" {
  description = "Tier de la instancia Cloud SQL. db-f1-micro para dev (más barato); algo mayor para prod."
  type        = string
  default     = "db-f1-micro"
}

variable "cloud_sql_authorized_networks" {
  description = "Rangos CIDR autorizados a conectar por IP pública a Cloud SQL. Vacío por defecto: se recomienda conectar vía Cloud SQL Auth Proxy (usa la Cloud SQL Admin API, no requiere abrir IP) en vez de listar redes aquí."
  type        = list(string)
  default     = []
}

variable "alert_notification_email" {
  description = "Correo al que se envían las alertas operacionales del pipeline (fallo, reporte diario, anomalía de volumen — Fase 4/5). Se usa para crear el canal de notificación de Cloud Monitoring. Valor personal: se pasa en environments/local.tfvars (no versionado), no en dev.tfvars/prod.tfvars."
  type        = string
}

variable "impersonator_email" {
  description = "Cuenta de Google real a la que se le permite impersonar los 3 roles de gobierno (Fase 5), solo para poder demostrar el control de acceso (docs/evidencia/fase5/) — no es parte del modelo de permisos del pipeline en sí. Valor personal: se pasa en environments/local.tfvars (no versionado), no en dev.tfvars/prod.tfvars."
  type        = string
}

variable "labels" {
  description = "Labels aplicados a todos los recursos que los soportan, para trazabilidad de costo/propósito."
  type        = map(string)
  default = {
    proyecto = "finbank-data-platform"
    prueba   = "dataknow-tecnica"
  }
}
