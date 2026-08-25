"""
Puente Bronze (Parquet en GCS) -> BigQuery, para que dbt tenga sources
nativos de BigQuery desde donde construir la capa Silver.

Estas tablas `raw_*` son deliberadamente crudas (mismo esquema y valores
que Bronze, solo aterrizadas en BigQuery) — la limpieza real (dedup,
tipado, integridad referencial, nulos, enmascaramiento) es responsabilidad
de los modelos dbt de `models/staging/`, no de este script.

Estrategia de carga por modo (debe coincidir con pipelines/bronze/config.yaml):
  - full: cada corrida de Bronze reescribe la tabla completa -> solo se
    carga el batch MÁS RECIENTE (si se cargaran todos los batches
    históricos se duplicaría la tabla completa por cada corrida de Bronze).
  - incremental: cada batch de Bronze contiene solo filas nuevas y sin
    solapamiento -> se cargan TODOS los batches acumulados (WRITE_TRUNCATE
    + wildcard sobre todos los archivos = reconstrucción completa y
    correcta del historial incremental en cada corrida de este loader).

Uso:
    python load_bronze_to_bq.py [--config config.yaml]
"""
from __future__ import annotations

import argparse
from pathlib import Path

import yaml
from google.cloud import bigquery, storage


def get_latest_blob_uri(gcs: storage.Client, bucket: str, table: str) -> str | None:
    blobs = list(gcs.list_blobs(bucket, prefix=f"{table}/"))
    blobs = [b for b in blobs if b.name.endswith(".parquet")]
    if not blobs:
        return None
    latest = max(blobs, key=lambda b: b.time_created)
    return f"gs://{bucket}/{latest.name}"


def load_table(bq: bigquery.Client, gcs: storage.Client, cfg: dict, table: str, mode: str) -> dict:
    bucket = cfg["bronze_bucket"]
    dataset = cfg["silver_dataset"]
    dest_table = f"{cfg['gcp']['project_id']}.{dataset}.raw_{table.lower()}"

    if mode == "full":
        uri = get_latest_blob_uri(gcs, bucket, table)
        if uri is None:
            return {"table": table, "status": "sin_datos"}
        uris = [uri]
    else:
        uris = [f"gs://{bucket}/{table}/*.parquet"]

    job_config = bigquery.LoadJobConfig(
        source_format=bigquery.SourceFormat.PARQUET,
        write_disposition=bigquery.WriteDisposition.WRITE_TRUNCATE,
    )
    job = bq.load_table_from_uri(uris, dest_table, job_config=job_config)
    job.result()  # espera a que termine, propaga error si falla

    table_ref = bq.get_table(dest_table)
    return {"table": table, "status": "ok", "bq_table": dest_table,
            "rows": table_ref.num_rows, "source_uris": uris}


def main(config_path: str):
    cfg = yaml.safe_load(Path(config_path).read_text(encoding="utf-8"))
    bq = bigquery.Client(project=cfg["gcp"]["project_id"])
    gcs = storage.Client(project=cfg["gcp"]["project_id"])

    dataset_id = f"{cfg['gcp']['project_id']}.{cfg['silver_dataset']}"
    bq.get_dataset(dataset_id)  # falla explícito si el dataset no existe (debe existir por Fase 2)

    print(f"=== Cargando Bronze -> BigQuery ({dataset_id}) ===")
    for table, table_cfg in cfg["tables"].items():
        result = load_table(bq, gcs, cfg, table, table_cfg["mode"])
        if result["status"] == "ok":
            print(f"  {table} ({table_cfg['mode']}): {result['rows']:,} filas -> {result['bq_table']}")
        else:
            print(f"  {table}: {result['status']}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", default=str(Path(__file__).parent / "config.yaml"))
    args = parser.parse_args()
    main(args.config)
