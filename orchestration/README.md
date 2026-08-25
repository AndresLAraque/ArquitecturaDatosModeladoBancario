# Fase 4 — Orquestación

`pipeline_workflow.yaml` — el DAG principal, corrido por **Cloud Workflows**
(decisión documentada en el README raíz: se prefirió sobre Cloud Composer
para no agotar el crédito del free trial con un ambiente Airflow de costo
fijo). Desplegado por Terraform (`infra/orchestration.tf`), disparado a
diario por **Cloud Scheduler** a las 02:00 `America/Bogota`
(`infra/orchestration.tf:google_cloud_scheduler_job`).

## Qué hace, en orden (flujo esperado del enunciado)

```
Trigger (Scheduler diario o manual)
  -> Cloud Run Job "bronze"  (extracción Cloud SQL + validación de volumen)
  -> Cloud Run Job "silver"  (aterriza Bronze en BigQuery + dbt run/test tag:silver)
  -> Cloud Run Job "gold"    (dbt run/test tag:gold — incluye las verificaciones
                               de calidad sobre Gold)
  -> Consulta a BigQuery para armar el reporte diario
  -> Notificación de resultado (éxito con resumen, o fallo con detalle)
```

Dependencias explícitas: cada etapa es un paso secuencial de `main` — Silver
solo se dispara si el paso `run_bronze` no lanzó excepción; Gold solo si
`run_silver` no lanzó excepción.

## Reintentos y timeouts

Cada etapa (`run_stage`) se reintenta hasta 3 veces con backoff exponencial
(10s, 20s, 40s..., tope 180s) antes de considerarse fallida. El timeout por
tarea vive en el propio Cloud Run Job (`infra/cloud_run.tf`, 900s — margen
amplio sobre los tiempos reales observados: Bronze ~80s, Silver/Gold unos
minutos con dbt run+test incluido).

## Alertas — sin credenciales de correo en este repo

El workflow nunca conoce un email de destino: escribe logs estructurados
(`sys.log` con `json: {event_type: ...}`) y las políticas de Cloud
Monitoring (`infra/monitoring.tf`) hacen match sobre `jsonPayload.event_type`
y envían la notificación:

| `event_type` | Cuándo | Contenido |
|---|---|---|
| `TASK_FAILURE` | Una etapa agota sus 3 reintentos | `dag_name`, `task_name`, `error_message`, `timestamp` |
| `PIPELINE_SUCCESS_SUMMARY` | Gold termina sin errores | registros procesados por capa, `duration_seconds`, `quality_alerts_count` |
| `VOLUME_ANOMALY` | Bronze detecta >30% de desviación vs. promedio de 7 corridas | emitida por `pipelines/common/alerting.py`, no por el workflow |

## Evidencia real (no solo el código)

En `/docs/evidencia/fase4/`:
- 3 ejecuciones reales del workflow: `run1-success.txt`, `run2-success.txt`
  (2 corridas exitosas completas, ~7-9 min cada una) y
  `run3-forced-failure.txt` (falla de prueba forzada a propósito,
  ver más abajo)
- `execution-history.txt` — `gcloud workflows executions list`, historial
  visible sin tocar código
- `task_failure_log.json` / `pipeline_success_summary_log.json` — las
  entradas de log estructuradas reales que disparan las alertas

### Cómo se forzó la falla de prueba

Se sobreescribió temporalmente el comando del contenedor de
`finbank-bronze-dev` a `/bin/false` (`gcloud run jobs update`), se corrió
el workflow completo (agotó sus 3 reintentos con backoff, ~8.5 min, quedó
en `state: FAILED` deteniéndose en Bronze sin llegar a Silver/Gold — las
dependencias explícitas funcionando), se confirmó el log `TASK_FAILURE`, y
se revirtió el cambio con `terraform apply` (Terraform detectó el drift
manual y lo corrigió solo, sin tocar ningún otro recurso).

## Ejecutar manualmente

```bash
gcloud workflows run finbank-pipeline-dev --location=us-central1 --project=finbank-data-platform-dev
```

## Dashboard / log accesible sin código fuente

https://console.cloud.google.com/workflows/workflow/us-central1/finbank-pipeline-dev/executions?project=finbank-data-platform-dev
