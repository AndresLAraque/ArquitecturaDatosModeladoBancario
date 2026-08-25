# Capa Bronze — Ingesta cruda (Cloud SQL → GCS)

## Qué hace

Copia las 6 tablas fuente desde Cloud SQL hacia `gs://finbank-data-platform-dev-bronze/`
en Parquet, sin transformar el esquema original, con:

- 3 columnas de auditoría por registro: `ingestion_ts`, `source_system`, `batch_id`
- Particionado por fecha de **ingesta** (no de negocio): `<TABLA>/year=YYYY/month=MM/day=DD/<batch_id>.parquet`
- Log de cada corrida (filas, tamaño, duración) en `gs://.../_logs/<batch_id>.json`
- Modo incremental para tablas append-only (`TB_MOV_FINANCIEROS`, `TB_COMISIONES_LOG`),
  con watermark persistido en `gs://.../_watermarks/<tabla>.json`

## Por qué algunas tablas son "full" y no "incremental"

`TB_CLIENTES_CORE`, `TB_PRODUCTOS_CAT`, `TB_SUCURSALES_RED` y `TB_OBLIGACIONES`
se re-extraen completas en cada corrida. Es una decisión, no un descuido:
el esquema fuente sintético (fiel al enunciado) no incluye una columna de
"última modificación" en el sistema origen, y estas tablas SÍ pueden mutar
(`dias_mora_act`, `sdo_capital`, `estado_cli`, etc. cambian con el tiempo
para el mismo registro). Sin una columna de modificación no hay forma
honesta de hacer CDC incremental sobre ellas — un snapshot completo es la
alternativa correcta. `TB_MOV_FINANCIEROS` y `TB_COMISIONES_LOG` sí son
logs transaccionales append-only por naturaleza (una vez ocurre un
movimiento no cambia), así que sobre `fec_mov`/`fec_cobro` el watermark es
válido.

## Ejecutar

```bash
cd pipelines/bronze
python -m venv .venv && .venv\Scripts\activate
pip install -r requirements.txt
python extract_to_bronze.py
```

Requiere estar autenticado (`gcloud auth application-default login`) con
permisos `roles/cloudsql.client`, `roles/secretmanager.secretAccessor` y
`roles/storage.objectAdmin` sobre el bucket bronze — en producción corre
bajo la identidad de `sa-ingestion` (ver `/infra/iam.tf`), no bajo un
usuario humano.

## Evidencia de dos corridas reales

Ver `/docs/evidencia/fase3-bronze/`:
- `run1-full-log.txt` / `.json` — primera corrida: las 6 tablas cargan completas
- `run2-incremental-log.txt` / `.json` — segunda corrida: `TB_MOV_FINANCIEROS` y
  `TB_COMISIONES_LOG` detectan **0 filas nuevas** (incrementalidad funcionando),
  las demás se re-extraen completas
- `bucket-listing.txt` — estructura real de partición en el bucket

## Manejo de errores

Cada tabla se extrae en su propio `try/except` — si una falla, las demás
siguen (tareas independientes, requisito explícito del enunciado). Los
errores quedan en el log de la corrida (`errors: [...]`) y el proceso
termina con código de salida distinto de cero para que el orquestador
(Fase 4) lo detecte y reintente/alerte.
