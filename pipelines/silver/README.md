# Puente Bronze -> BigQuery

`load_bronze_to_bq.py` aterriza los Parquet de Bronze (GCS) en tablas
`raw_*` nativas de BigQuery (dataset `finbank_silver_dev`), para que el
proyecto dbt en `../dbt_finbank/` tenga sources desde donde construir la
capa Silver real (limpieza, dedup, integridad referencial, masking).

## Por qué un paso intermedio y no external tables directo sobre GCS

Se evaluó usar BigQuery external tables apuntando directo a los Parquet de
Bronze, pero las tablas `full` (snapshot completo en cada corrida de
Bronze) acumulan un archivo nuevo por corrida en el bucket — una external
table sobre todo el prefijo duplicaría la tabla completa por cada corrida
histórica. Este loader resuelve eso explícitamente por modo:
- `full`: carga solo el batch **más reciente** (WRITE_TRUNCATE)
- `incremental`: carga **todos** los batches acumulados (correcto porque
  Bronze ya garantiza que no se solapan)

## Ejecutar

```bash
python -m venv .venv && .venv\Scripts\activate
pip install -r requirements.txt
python load_bronze_to_bq.py
```
