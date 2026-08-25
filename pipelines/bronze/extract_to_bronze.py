"""
Capa Bronze — ingesta cruda desde Cloud SQL (fuente origen) hacia GCS.

Uso:
    python extract_to_bronze.py [--config config.yaml]

Qué hace, en orden (ver PLAN.md / docs/BITACORA-TECNICA-PERSONAL.md para el
detalle de las decisiones de diseño):
  1. Por cada tabla fuente, extrae "tal cual" desde Cloud SQL (full snapshot
     o incremental por watermark, según config.yaml) — CERO transformaciones
     de negocio, ese es el trabajo de Silver.
  2. Agrega 3 columnas de auditoría: ingestion_ts, source_system, batch_id.
  3. Escribe en Parquet, particionado año/mes/día de INGESTA (no de negocio).
  4. Registra un log de la corrida (filas, tamaño, duración) en GCS y stdout.
  5. Errores por tabla se capturan y se continúa con las demás (tareas
     independientes) — al final, si algo falló, el proceso termina con
     código de salida distinto de cero para que el orquestador lo detecte.

Reproducibilidad de "hasta dónde se llegó": el watermark de las tablas
incrementales se guarda en GCS (`_watermarks/<tabla>.json`), no en memoria,
así que una corrida incremental es correcta sin importar dónde ni cuándo se
ejecute el proceso.
"""
from __future__ import annotations

import argparse
import json
import time
import uuid
from datetime import datetime, timezone
from pathlib import Path

import pandas as pd
import yaml
from google.cloud import secretmanager, storage
from sqlalchemy import create_engine, text


def load_config(path: str) -> dict:
    return yaml.safe_load(Path(path).read_text(encoding="utf-8"))


def get_db_password(project_id: str, secret_id: str) -> str:
    client = secretmanager.SecretManagerServiceClient()
    name = f"projects/{project_id}/secrets/{secret_id}/versions/latest"
    return client.access_secret_version(name=name).payload.data.decode("utf-8")


def get_engine(cfg: dict):
    from google.cloud.sql.connector import Connector

    db = cfg["source_db"]
    password = get_db_password(cfg["gcp"]["project_id"], db["db_password_secret_id"])
    connector = Connector()

    def getconn():
        return connector.connect(
            db["instance_connection_name"], "pg8000",
            user=db["db_user"], password=password, db=db["db_name"],
        )

    return create_engine("postgresql+pg8000://", creator=getconn)


def read_watermark(gcs: storage.Client, bucket: str, table: str) -> str | None:
    blob = gcs.bucket(bucket).blob(f"_watermarks/{table}.json")
    if not blob.exists():
        return None
    data = json.loads(blob.download_as_text())
    return data.get("last_value")


def write_watermark(gcs: storage.Client, bucket: str, table: str, value: str, batch_id: str) -> None:
    blob = gcs.bucket(bucket).blob(f"_watermarks/{table}.json")
    payload = {
        "table": table,
        "last_value": value,
        "updated_at": datetime.now(timezone.utc).isoformat(),
        "batch_id": batch_id,
    }
    blob.upload_from_string(json.dumps(payload, indent=2), content_type="application/json")


def extract_table(engine, table: str, table_cfg: dict, gcs: storage.Client, bucket: str) -> tuple[pd.DataFrame, str | None]:
    """Devuelve (DataFrame, watermark_a_guardar_si_incremental_o_None)."""
    table_lc = table.lower()
    mode = table_cfg["mode"]

    if mode == "incremental":
        wm_col = table_cfg["watermark_column"]
        last_value = read_watermark(gcs, bucket, table)
        if last_value:
            query = text(f"SELECT * FROM {table_lc} WHERE {wm_col} > :last_value ORDER BY {wm_col}")
            df = pd.read_sql(query, engine, params={"last_value": last_value})
        else:
            query = text(f"SELECT * FROM {table_lc} ORDER BY {wm_col}")
            df = pd.read_sql(query, engine)
        new_watermark = str(df[wm_col].max()) if len(df) else last_value
        return df, new_watermark

    query = text(f"SELECT * FROM {table_lc}")
    return pd.read_sql(query, engine), None


def add_audit_columns(df: pd.DataFrame, batch_id: str, source_system: str, ingestion_ts: datetime) -> pd.DataFrame:
    df = df.copy()
    df["ingestion_ts"] = ingestion_ts.isoformat()
    df["source_system"] = source_system
    df["batch_id"] = batch_id
    return df


def write_partitioned_parquet(df: pd.DataFrame, gcs: storage.Client, bucket: str, table: str,
                               ingestion_ts: datetime, batch_id: str) -> tuple[str, int]:
    partition = f"year={ingestion_ts.year:04d}/month={ingestion_ts.month:02d}/day={ingestion_ts.day:02d}"
    blob_path = f"{table}/{partition}/{batch_id}.parquet"
    gcs_path = f"gs://{bucket}/{blob_path}"
    df.to_parquet(gcs_path, engine="pyarrow", index=False)

    size_bytes = gcs.bucket(bucket).get_blob(blob_path).size
    return gcs_path, size_bytes


def main(config_path: str):
    cfg = load_config(config_path)
    bucket = cfg["bronze_bucket"]
    source_system = cfg["source_system"]
    batch_id = f"batch-{uuid.uuid4().hex[:12]}"
    ingestion_ts = datetime.now(timezone.utc)

    print(f"=== Bronze ingestion — batch_id={batch_id} — {ingestion_ts.isoformat()} ===")

    engine = get_engine(cfg)
    gcs = storage.Client(project=cfg["gcp"]["project_id"])

    run_log = {"batch_id": batch_id, "started_at": ingestion_ts.isoformat(), "tables": {}, "errors": []}
    had_errors = False

    for table, table_cfg in cfg["tables"].items():
        t0 = time.time()
        try:
            df, new_watermark = extract_table(engine, table, table_cfg, gcs, bucket)
            n_rows = len(df)

            if n_rows == 0:
                print(f"  {table}: 0 filas nuevas (incremental al día), se omite escritura")
                run_log["tables"][table] = {"mode": table_cfg["mode"], "rows": 0, "duration_s": round(time.time() - t0, 2)}
                continue

            df = add_audit_columns(df, batch_id, source_system, ingestion_ts)
            gcs_path, size_bytes = write_partitioned_parquet(df, gcs, bucket, table, ingestion_ts, batch_id)

            if new_watermark is not None:
                write_watermark(gcs, bucket, table, new_watermark, batch_id)

            duration = round(time.time() - t0, 2)
            run_log["tables"][table] = {
                "mode": table_cfg["mode"], "rows": n_rows, "size_bytes": size_bytes,
                "duration_s": duration, "path": gcs_path,
            }
            print(f"  {table}: {n_rows:,} filas -> {gcs_path} ({size_bytes:,} bytes, {duration}s)")

        except Exception as e:  # noqa: BLE001 — se captura a propósito: una tabla fallida no debe tumbar las demás
            had_errors = True
            duration = round(time.time() - t0, 2)
            err = {"table": table, "error": str(e), "duration_s": duration}
            run_log["errors"].append(err)
            print(f"  {table}: FALLÓ ({duration}s) -> {e}")

    run_log["finished_at"] = datetime.now(timezone.utc).isoformat()
    run_log["success"] = not had_errors

    log_blob = gcs.bucket(bucket).blob(f"_logs/{batch_id}.json")
    log_blob.upload_from_string(json.dumps(run_log, indent=2, default=str), content_type="application/json")
    print(f"\nLog de ejecución: gs://{bucket}/_logs/{batch_id}.json")

    if had_errors:
        print(f"\nBronze terminó CON ERRORES en {len(run_log['errors'])} tabla(s).")
        raise SystemExit(1)
    print("\nBronze terminó exitosamente.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", default=str(Path(__file__).parent / "config.yaml"))
    args = parser.parse_args()
    main(args.config)
