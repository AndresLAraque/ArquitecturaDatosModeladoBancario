"""
Orquestador de la generación sintética de datos de FinBank (Escenario A).

Uso:
    python main.py [--config config.yaml]

Reproducible: toda la aleatoriedad se deriva de `config.yaml:seed` a través
de un único `numpy.random.Generator`, consumido siempre en el mismo orden
(productos -> sucursales -> clientes -> obligaciones -> movimientos ->
comisiones -> anomalías), así que dos corridas con el mismo config producen
exactamente el mismo dataset byte a byte.
"""
from __future__ import annotations

import argparse
import json
import time
from pathlib import Path

import numpy as np
import pandas as pd
import yaml

import anomalies as anom
import generators as gen

SCHEMA_COLUMNS = {
    "TB_CLIENTES_CORE": ["id_cli", "nomb_cli", "apell_cli", "tip_doc", "num_doc", "fec_nac",
                          "fec_alta", "cod_segmento", "score_buro", "ciudad_res", "depto_res",
                          "estado_cli", "canal_adquis"],
    "TB_PRODUCTOS_CAT": ["cod_prod", "desc_prod", "tip_prod", "tasa_ea", "plazo_max_meses",
                         "cuota_min", "comision_admin", "estado_prod"],
    "TB_MOV_FINANCIEROS": ["id_mov", "id_cli", "cod_prod", "num_cuenta", "fec_mov", "hra_mov",
                            "vr_mov", "tip_mov", "cod_canal", "cod_ciudad", "cod_estado_mov",
                            "id_dispositivo"],
    "TB_OBLIGACIONES": ["id_oblig", "id_cli", "cod_prod", "vr_aprobado", "vr_desembolsado",
                         "sdo_capital", "vr_cuota", "fec_desembolso", "fec_venc",
                         "dias_mora_act", "num_cuotas_pend", "calif_riesgo"],
    "TB_SUCURSALES_RED": ["cod_suc", "nom_suc", "tip_punto", "ciudad", "depto", "latitud",
                           "longitud", "activo"],
    "TB_COMISIONES_LOG": ["id_comision", "id_cli", "cod_prod", "fec_cobro", "vr_comision",
                           "tip_comision", "estado_cobro"],
}


def write_table(df: pd.DataFrame, tabla: str, fmt: str, out_dir: Path) -> Path:
    out_dir.mkdir(parents=True, exist_ok=True)
    path = out_dir / f"{tabla}.{fmt}"
    if fmt == "csv":
        df.to_csv(path, index=False, encoding="utf-8")
    elif fmt == "json":
        df.to_json(path, orient="records", force_ascii=False, indent=2, date_format="iso")
    elif fmt == "parquet":
        df.to_parquet(path, engine="pyarrow", index=False)
    else:
        raise ValueError(f"Formato no soportado: {fmt}")
    return path


def main(config_path: str):
    t0 = time.time()
    cfg = yaml.safe_load(Path(config_path).read_text(encoding="utf-8"))
    rng = np.random.default_rng(cfg["seed"])

    date_start, date_end = cfg["date_range"]["start"], cfg["date_range"]["end"]
    vol = cfg["volumes"]
    null_pct = cfg["null_pct"]
    out_dir = Path(config_path).parent / cfg["output_dir"]

    print(f"[1/6] Generando TB_PRODUCTOS_CAT ({vol['productos']} filas)...")
    productos = gen.generate_productos(rng, vol["productos"], null_pct)

    print(f"[2/6] Generando TB_SUCURSALES_RED ({vol['sucursales']} filas)...")
    sucursales = gen.generate_sucursales(rng, vol["sucursales"], null_pct)

    print(f"[3/6] Generando TB_CLIENTES_CORE ({vol['clientes']} filas)...")
    clientes = gen.generate_clientes(rng, vol["clientes"], date_start, date_end, null_pct)

    print(f"[4/6] Generando TB_OBLIGACIONES ({vol['obligaciones']} filas)...")
    obligaciones = gen.generate_obligaciones(rng, vol["obligaciones"], clientes, productos,
                                              date_start, date_end, null_pct)

    print(f"[5/6] Generando TB_MOV_FINANCIEROS ({vol['movimientos']} filas)...")
    movimientos = gen.generate_movimientos(rng, vol["movimientos"], clientes, productos,
                                            date_start, date_end, null_pct)

    print(f"[6/6] Generando TB_COMISIONES_LOG ({vol['comisiones']} filas)...")
    comisiones = gen.generate_comisiones(rng, vol["comisiones"], clientes, productos,
                                          date_start, date_end, null_pct)

    # --- Anomalías intencionales, documentadas en ANOMALIES.md ------------
    print("Inyectando anomalías intencionales...")
    a_cfg = cfg["anomalies"]
    anomaly_log = []

    movimientos, log1 = anom.inject_duplicados_exactos(
        rng, movimientos, a_cfg["duplicados_exactos_pct"], "TB_MOV_FINANCIEROS", "id_mov")
    anomaly_log += log1

    movimientos, log2a = anom.inject_fechas_fuera_rango(
        rng, movimientos, a_cfg["fechas_fuera_rango_pct"], "fec_mov",
        "TB_MOV_FINANCIEROS", "id_mov", date_start, date_end)
    anomaly_log += log2a
    obligaciones, log2b = anom.inject_fechas_fuera_rango(
        rng, obligaciones, a_cfg["fechas_fuera_rango_pct"], "fec_desembolso",
        "TB_OBLIGACIONES", "id_oblig", date_start, date_end)
    anomaly_log += log2b

    movimientos, log3a = anom.inject_fk_huerfana(
        rng, movimientos, a_cfg["fk_huerfana_pct"], "id_cli", "TB_MOV_FINANCIEROS", "id_mov")
    anomaly_log += log3a
    comisiones, log3b = anom.inject_fk_huerfana(
        rng, comisiones, a_cfg["fk_huerfana_pct"], "id_cli", "TB_COMISIONES_LOG", "id_comision")
    anomaly_log += log3b

    movimientos, log4a = anom.inject_campos_inconsistentes_movimientos(
        rng, movimientos, a_cfg["campos_inconsistentes_pct"])
    anomaly_log += log4a
    obligaciones, log4b = anom.inject_campos_inconsistentes_obligaciones(
        rng, obligaciones, a_cfg["campos_inconsistentes_pct"])
    anomaly_log += log4b

    # --- Escritura a disco en los formatos configurados --------------------
    tables = {
        "TB_CLIENTES_CORE": clientes,
        "TB_PRODUCTOS_CAT": productos.drop(columns=["_familia"]),
        "TB_SUCURSALES_RED": sucursales,
        "TB_MOV_FINANCIEROS": movimientos,
        "TB_OBLIGACIONES": obligaciones,
        "TB_COMISIONES_LOG": comisiones,
    }

    summary = {"seed": cfg["seed"], "date_range": cfg["date_range"], "tables": {}}
    for tabla, df in tables.items():
        df = df[SCHEMA_COLUMNS[tabla]]  # aplica el orden de columnas del enunciado
        fmt = cfg["output_formats"][tabla]
        path = write_table(df, tabla, fmt, out_dir)
        summary["tables"][tabla] = {
            "filas": len(df),
            "formato": fmt,
            "archivo": str(path.name),
            "pct_nulos_promedio": round(float(df.isna().mean().mean()) * 100, 2),
        }
        print(f"  -> {tabla}: {len(df):,} filas -> {path.name}")

    anomaly_df = pd.DataFrame(anomaly_log)
    anomaly_path = out_dir / "anomalies_log.csv"
    anomaly_df.to_csv(anomaly_path, index=False, encoding="utf-8")
    summary["anomalias"] = {
        "total_filas_afectadas": len(anomaly_df),
        "por_tipo": anomaly_df["tipo_anomalia"].value_counts().to_dict() if len(anomaly_df) else {},
        "archivo": anomaly_path.name,
    }

    summary["duracion_segundos"] = round(time.time() - t0, 2)
    summary_path = out_dir / "generation_summary.json"
    summary_path.write_text(json.dumps(summary, indent=2, ensure_ascii=False), encoding="utf-8")

    print(f"\nListo en {summary['duracion_segundos']}s. Resumen: {summary_path}")
    print(f"Anomalías inyectadas: {len(anomaly_df)} filas -> {anomaly_path}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", default=str(Path(__file__).parent / "config.yaml"))
    args = parser.parse_args()
    main(args.config)
