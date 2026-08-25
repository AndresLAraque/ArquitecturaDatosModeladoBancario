"""
Utilidad compartida de logging estructurado para la alerta de anomalía de
volumen (Fase 4/5). Las otras dos alertas (fallo de tarea, reporte diario
de éxito) las emite directamente el orquestador (Cloud Workflows, vía
`sys.log`) porque es quien conoce de forma nativa el nombre del DAG, la
tarea que falló y el tiempo total de ejecución — centralizar el reporte de
esas dos ahí evita duplicar esa información en cada contenedor.

La anomalía de volumen, en cambio, necesita comparar el conteo de la
corrida actual contra el histórico de las últimas 7 corridas — ese
histórico vive en los logs de Bronze (`_logs/*.json` en GCS), así que es
más natural calcularlo aquí, en Python, donde ya se tiene ese archivo a
mano.

Diseño: se escribe como una entrada de Cloud Logging con
`jsonPayload.event_type = "VOLUME_ANOMALY"`; la política de alerta de
Cloud Monitoring (infra/monitoring.tf) hace match sobre ese campo y envía
el correo — el pipeline nunca maneja credenciales de correo directamente.
"""
from __future__ import annotations

import json
import os
from datetime import datetime, timezone

import google.cloud.logging

_PROJECT_ID = os.environ.get("FINBANK_GCP_PROJECT_ID", "finbank-data-platform-dev")
_LOG_NAME = "finbank-pipeline-alerts"


def log_volume_anomaly(table: str, current_rows: int, avg_last_7: float, pct_diff: float) -> None:
    """Se dispara ANTES de continuar el pipeline si el volumen de una
    ejecución difiere > 30% del promedio de las últimas 7 ejecuciones
    (requisito explícito del enunciado)."""
    payload = {
        "event_type": "VOLUME_ANOMALY",
        "table": table,
        "current_rows": current_rows,
        "avg_last_7_runs": round(avg_last_7, 2),
        "pct_diff": round(pct_diff, 2),
        "timestamp": datetime.now(timezone.utc).isoformat(),
    }
    client = google.cloud.logging.Client(project=_PROJECT_ID)
    client.logger(_LOG_NAME).log_struct(payload, severity="WARNING")
    print(f"[ALERTA:VOLUME_ANOMALY] {json.dumps(payload, ensure_ascii=False)}")


def check_volume_anomaly(gcs_client, bucket: str, table: str, current_rows: int, threshold_pct: float = 30.0) -> None:
    """Lee hasta las últimas 7 corridas de `_logs/*.json` en el bucket
    Bronze, calcula el promedio de filas procesadas para `table`, y llama
    a `log_volume_anomaly` si la desviación supera `threshold_pct`."""
    blobs = sorted(
        gcs_client.list_blobs(bucket, prefix="_logs/"),
        key=lambda b: b.time_created,
        reverse=True,
    )
    historicos = []
    for blob in blobs[:7]:
        if not blob.name.endswith(".json"):
            continue
        try:
            data = json.loads(blob.download_as_text())
            rows = data.get("tables", {}).get(table, {}).get("rows")
            if isinstance(rows, (int, float)):
                historicos.append(rows)
        except Exception:  # noqa: BLE001 — un log corrupto no debe tumbar el pipeline
            continue

    if len(historicos) < 3:  # muy poco historial todavía para que la comparación sea significativa
        return

    avg_last_7 = sum(historicos) / len(historicos)
    if avg_last_7 == 0:
        return

    pct_diff = abs(current_rows - avg_last_7) / avg_last_7 * 100
    if pct_diff > threshold_pct:
        log_volume_anomaly(table, current_rows, avg_last_7, pct_diff)
