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
from sqlalchemy import create_engine, text

try:
    from dotenv import load_dotenv
    load_dotenv(Path(__file__).parent / ".env")
except ImportError:
    pass  # python-dotenv es opcional; sin él, se usan variables de entorno ya exportadas

from main import SCHEMA_COLUMNS  # reutiliza la misma definición de columnas que la generación


def build_db_url(cfg: dict) -> str:
    dbcfg = cfg["database"]
    env = dbcfg["env_vars"]
    defaults = dbcfg["defaults"]

    host = os.environ.get(env["host"], defaults["host"])
    port = os.environ.get(env["port"], defaults["port"])
    name = os.environ.get(env["name"], defaults["name"])
    user = os.environ.get(env["user"], defaults["user"])
    password = os.environ.get(env["password"])
    if not password:
        raise RuntimeError(
            f"Falta la variable de entorno {env['password']!r}. "
            "Copia .env.example a .env y complétala (o expórtala en tu shell)."
        )
    return f"{dbcfg['driver']}://{user}:{password}@{host}:{port}/{name}"


def read_table_file(out_dir: Path, tabla: str, fmt: str) -> pd.DataFrame:
    path = out_dir / f"{tabla}.{fmt}"
    if fmt == "csv":
        return pd.read_csv(path)
    if fmt == "json":
        return pd.read_json(path, orient="records")
    if fmt == "parquet":
        return pd.read_parquet(path, engine="pyarrow")
    raise ValueError(f"Formato no soportado: {fmt}")


def main(config_path: str):
    cfg = yaml.safe_load(Path(config_path).read_text(encoding="utf-8"))
    out_dir = Path(config_path).parent / cfg["output_dir"]

    db_url = build_db_url(cfg)
    engine = create_engine(db_url)

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
        print(f"Cargando {tabla} ({len(df):,} filas) desde {tabla}.{fmt} ...")
        df.to_sql(tabla.lower(), engine, if_exists="append", index=False,
                  chunksize=10_000, method="multi")

    print("\n=== SELECT COUNT(*) por tabla (evidencia de carga exitosa) ===")
    with engine.connect() as conn:
        for tabla in load_order:
            count = conn.execute(text(f"SELECT COUNT(*) FROM {tabla.lower()}")).scalar()
            line = f"{tabla}: {count:,} registros"
            print(line)
            evidence_lines.append(line)

    evidence_path = out_dir / "load_evidence.txt"
    evidence_path.write_text("\n".join(evidence_lines), encoding="utf-8")
    print(f"\nEvidencia guardada en {evidence_path}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", default=str(Path(__file__).parent / "config.yaml"))
    args = parser.parse_args()
    main(args.config)
