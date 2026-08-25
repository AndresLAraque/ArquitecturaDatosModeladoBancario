"""
Carga los archivos generados por main.py hacia la base relacional origen
(Postgres local en Docker, o Cloud SQL PostgreSQL si se apuntan las
variables de entorno correspondientes).

Uso:
    python load_to_postgres.py [--config config.yaml]

Requiere que la base ya esté arriba (ver docker-compose.yml) y que las
variables de entorno de conexión estén disponibles (ver .env.example).
Reproducible / idempotente: recrea el esquema (DROP + CREATE vía schema.sql)
en cada corrida, así que se puede ejecutar las veces que haga falta sin
acumular datos duplicados entre corridas.
"""
from __future__ import annotations

import argparse
import os
from pathlib import Path

import pandas as pd
import yaml
from sqlalchemy import text

try:
    from dotenv import load_dotenv
    load_dotenv(Path(__file__).parent / ".env")
except ImportError:
    pass  # python-dotenv es opcional; sin él, se usan variables de entorno ya exportadas

from main import SCHEMA_COLUMNS  # reutiliza la misma definición de columnas que la generación

# Columnas INTEGER en schema.sql que además admiten NULL. pandas promueve
# automáticamente estas columnas a float64 en cuanto hay algún nulo mezclado
# (ej. plazo_max_meses = 44.0 en vez de 44), y pg8000 rechaza ese "44.0" al
# insertarlo contra una columna INTEGER (psycopg2 sí lo toleraba con cast
# implícito — de ahí que el problema no apareciera contra Postgres local).
# Se restauran a un entero nullable real (pandas "Int64") antes de insertar.
NULLABLE_INT_COLUMNS = {
    "TB_CLIENTES_CORE": ["score_buro"],
    "TB_PRODUCTOS_CAT": ["plazo_max_meses"],
    "TB_OBLIGACIONES": ["num_cuotas_pend"],
}


def _fetch_secret(project_id: str, secret_id: str) -> str:
    from google.cloud import secretmanager
    client = secretmanager.SecretManagerServiceClient()
    name = f"projects/{project_id}/secrets/{secret_id}/versions/latest"
    return client.access_secret_version(name=name).payload.data.decode("utf-8")


def build_engine(cfg: dict):
    """Construye el engine de SQLAlchemy contra Postgres local (Docker) o
    contra Cloud SQL, sin cambiar el resto del script.

    - Por defecto: TCP directo a host:port (Postgres local de Fase 1).
    - Si se exporta FINBANK_DB_INSTANCE_CONNECTION_NAME: usa el Cloud SQL
      Python Connector (túnel cifrado vía la Cloud SQL Admin API, sin
      necesidad de IP autorizada ni Cloud SQL Auth Proxy separado). La
      password se puede seguir pasando por FINBANK_DB_PASSWORD, o resolverse
      sola desde Secret Manager si se exportan FINBANK_GCP_PROJECT_ID y
      FINBANK_DB_SECRET_ID (así es como corre el pipeline real en Fase 3).
    """
    dbcfg = cfg["database"]
    env = dbcfg["env_vars"]
    defaults = dbcfg["defaults"]

    name = os.environ.get(env["name"], defaults["name"])
    user = os.environ.get(env["user"], defaults["user"])
    password = os.environ.get(env["password"])

    instance_connection_name = os.environ.get("FINBANK_DB_INSTANCE_CONNECTION_NAME")

    if not password:
        gcp_project = os.environ.get("FINBANK_GCP_PROJECT_ID")
        secret_id = os.environ.get("FINBANK_DB_SECRET_ID")
        if instance_connection_name and gcp_project and secret_id:
            password = _fetch_secret(gcp_project, secret_id)
        else:
            raise RuntimeError(
                f"Falta la variable de entorno {env['password']!r} "
                "(o FINBANK_GCP_PROJECT_ID + FINBANK_DB_SECRET_ID para leerla de Secret "
                "Manager). Copia .env.example a .env y complétala."
            )

    if instance_connection_name:
        from google.cloud.sql.connector import Connector
        from sqlalchemy import create_engine

        connector = Connector()

        def getconn():
            return connector.connect(
                instance_connection_name, "pg8000",
                user=user, password=password, db=name,
            )

        return create_engine("postgresql+pg8000://", creator=getconn)

    from sqlalchemy import create_engine
    host = os.environ.get(env["host"], defaults["host"])
    port = os.environ.get(env["port"], defaults["port"])
    return create_engine(f"{dbcfg['driver']}://{user}:{password}@{host}:{port}/{name}")


def bulk_insert(engine, table_name: str, columns: list, df: pd.DataFrame, chunksize: int = 5_000) -> None:
    """Carga un DataFrame vía `COPY ... FROM STDIN` sobre el cursor DBAPI crudo.

    Se evitó `df.to_sql(...)` (SQLAlchemy/pandas arma el INSERT multi-fila de
    forma incompatible con pg8000) y también `executemany` fila por fila
    (miles de round-trips sobre el túnel del Cloud SQL Python Connector —
    en la práctica el socket SSL se cayó a mitad de carga con solo 10.000
    filas: `SSLEOFError` / "network error"). `COPY FROM STDIN` envía todo en
    un único stream, mucho más rápido y sin miles de mensajes de protocolo
    sueltos — el mecanismo de carga masiva estándar de Postgres. Funciona
    igual para psycopg2 (Postgres local) y pg8000 (Cloud SQL): ambos
    implementan `cursor.execute(sql, stream=...)`.
    """
    import io
    buf = io.StringIO()
    df[columns].to_csv(buf, index=False, header=False, na_rep="")
    buf.seek(0)
    col_list = ",".join(columns)
    sql = f"COPY {table_name} ({col_list}) FROM STDIN WITH (FORMAT csv, NULL '')"

    raw_conn = engine.raw_connection()
    try:
        cur = raw_conn.cursor()
        if engine.dialect.driver == "pg8000":
            cur.execute(sql, stream=buf)
        else:
            # psycopg2 (Postgres local): API de COPY distinta a la de pg8000.
            cur.copy_expert(sql, buf)
        raw_conn.commit()
    finally:
        raw_conn.close()


def read_table_file(out_dir: Path, tabla: str, fmt: str) -> pd.DataFrame:
    path = out_dir / f"{tabla}.{fmt}"
    if fmt == "csv":
        return pd.read_csv(path)
    if fmt == "json":
        # dtype=False: pd.read_json por defecto re-infiere tipos "que parecen
        # numéricos" (ej. num_doc) y los convierte a int64, aunque el JSON los
        # haya escrito como string. Con drivers estrictos de tipos (pg8000,
        # usado por el Cloud SQL Python Connector) eso rompe el INSERT contra
        # una columna VARCHAR. dtype=False respeta el tipo tal como quedó
        # serializado en el JSON.
        return pd.read_json(path, orient="records", dtype=False)
    if fmt == "parquet":
        return pd.read_parquet(path, engine="pyarrow")
    raise ValueError(f"Formato no soportado: {fmt}")


def main(config_path: str):
    cfg = yaml.safe_load(Path(config_path).read_text(encoding="utf-8"))
    out_dir = Path(config_path).parent / cfg["output_dir"]

    engine = build_engine(cfg)

    schema_sql = (Path(config_path).parent / "schema.sql").read_text(encoding="utf-8")
    print("Aplicando schema.sql (DROP + CREATE, idempotente)...")
    with engine.begin() as conn:
        for statement in schema_sql.split(";"):
            statement = statement.strip()
            if statement:
                conn.execute(text(statement))

    load_order = ["TB_PRODUCTOS_CAT", "TB_SUCURSALES_RED", "TB_CLIENTES_CORE",
                  "TB_OBLIGACIONES", "TB_MOV_FINANCIEROS", "TB_COMISIONES_LOG"]

    evidence_lines = [f"Evidencia de carga — {pd.Timestamp.now().isoformat()}", ""]
    for tabla in load_order:
        fmt = cfg["output_formats"][tabla]
        df = read_table_file(out_dir, tabla, fmt)
        df = df[SCHEMA_COLUMNS[tabla]]
        for col in NULLABLE_INT_COLUMNS.get(tabla, []):
            df[col] = pd.to_numeric(df[col], errors="coerce").astype("Int64")
        print(f"Cargando {tabla} ({len(df):,} filas) desde {tabla}.{fmt} ...")
        bulk_insert(engine, tabla.lower(), SCHEMA_COLUMNS[tabla], df)

    print("\n=== SELECT COUNT(*) por tabla (evidencia de carga exitosa) ===")
    with engine.connect() as conn:
        for tabla in load_order:
            count = conn.execute(text(f"SELECT COUNT(*) FROM {tabla.lower()}")).scalar()
            line = f"{tabla}: {count:,} registros"
            print(line)
            evidence_lines.append(line)

    target_label = "cloudsql" if os.environ.get("FINBANK_DB_INSTANCE_CONNECTION_NAME") else "local"
    evidence_path = out_dir / f"load_evidence_{target_label}.txt"
    evidence_path.write_text("\n".join(evidence_lines), encoding="utf-8")
    print(f"\nEvidencia guardada en {evidence_path}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", default=str(Path(__file__).parent / "config.yaml"))
    args = parser.parse_args()
    main(args.config)
