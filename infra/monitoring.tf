# Alertas operacionales (Fase 4/5). Diseño: el pipeline (Workflow +
# contenedores) nunca maneja credenciales de correo — escribe entradas de
# Cloud Logging estructuradas (`jsonPayload.event_type = ...`), y estas
# políticas de alerta de Cloud Monitoring (basadas en logs) hacen match y
# envían el correo. El pipeline no sabe ni le importa que exista un canal
# de email; solo loguea.

resource "google_monitoring_notification_channel" "email" {
  display_name = "FinBank Pipeline Alerts (${var.environment})"
  project      = var.project_id
  type         = "email"
  labels = {
    email_address = var.alert_notification_email
  }
}

# ALERTA 1 — fallo de tarea del pipeline. Emitida por el Workflow (sys.log)
# con el nombre del DAG, la tarea, la fecha/hora y el mensaje de error.
resource "google_monitoring_alert_policy" "task_failure" {
  display_name = "FinBank — Fallo de tarea del pipeline (${var.environment})"
  project      = var.project_id
  combiner     = "OR"
  severity     = "ERROR"

  conditions {
    display_name = "Log con event_type=TASK_FAILURE"
    condition_matched_log {
      filter = "jsonPayload.event_type=\"TASK_FAILURE\""
    }
  }

  notification_channels = [google_monitoring_notification_channel.email.id]

  alert_strategy {
    notification_rate_limit {
      period = "300s" # como máximo 1 correo cada 5 min por esta política, evita spam en fallos en cascada
    }
  }

  documentation {
    content   = "Una tarea del pipeline FinBank falló. El log completo (jsonPayload) incluye dag_name, task_name, error_message y timestamp."
    mime_type = "text/markdown"
  }

  depends_on = [google_project_service.apis]
}

# ALERTA 2 — reporte diario de éxito. Emitida por el Workflow al terminar
# Gold sin errores: registros procesados por capa, tiempo total, # alertas
# de calidad.
resource "google_monitoring_alert_policy" "success_summary" {
  display_name = "FinBank — Reporte diario de ejecución exitosa (${var.environment})"
  project      = var.project_id
  combiner     = "OR"
  severity     = "WARNING" # Monitoring exige ERROR/WARNING/CRITICAL, no tiene "NOTICE"; el log en sí queda con severity=NOTICE

  conditions {
    display_name = "Log con event_type=PIPELINE_SUCCESS_SUMMARY"
    condition_matched_log {
      filter = "jsonPayload.event_type=\"PIPELINE_SUCCESS_SUMMARY\""
    }
  }

  notification_channels = [google_monitoring_notification_channel.email.id]

  alert_strategy {
    notification_rate_limit {
      period = "300s"
    }
  }

  documentation {
    content   = "El pipeline FinBank completó su ejecución diaria con éxito. Ver jsonPayload.records_by_layer, duration_seconds y quality_alerts_count en el log."
    mime_type = "text/markdown"
  }

  depends_on = [google_project_service.apis]
}

# ALERTA 3 — anomalía de volumen. Emitida por Bronze (pipelines/common/alerting.py)
# ANTES de continuar el pipeline si el volumen difiere > 30% del promedio
# de las últimas 7 corridas.
resource "google_monitoring_alert_policy" "volume_anomaly" {
  display_name = "FinBank — Anomalía de volumen (${var.environment})"
  project      = var.project_id
  combiner     = "OR"
  severity     = "WARNING"

  conditions {
    display_name = "Log con event_type=VOLUME_ANOMALY"
    condition_matched_log {
      filter = "jsonPayload.event_type=\"VOLUME_ANOMALY\""
    }
  }

  notification_channels = [google_monitoring_notification_channel.email.id]

  alert_strategy {
    notification_rate_limit {
      period = "300s"
    }
  }

  documentation {
    content   = "El volumen de una tabla en Bronze difiere más de 30% del promedio de las últimas 7 corridas. Ver jsonPayload.table, current_rows, avg_last_7_runs y pct_diff en el log."
    mime_type = "text/markdown"
  }

  depends_on = [google_project_service.apis]
}
