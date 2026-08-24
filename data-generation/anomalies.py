"""
Inyección deliberada de anomalías de datos, documentadas en detalle en
ANOMALIES.md. Cada función recibe el/los DataFrame(s) ya 100% íntegros
(generados por generators.py) y devuelve:
  - el DataFrame modificado (o con filas adicionales, en el caso de duplicados)
  - una lista de filas de log (para trazabilidad / evidencia de que el
    pipeline de Silver efectivamente las puede detectar)

Las anomalías se aplican DESPUÉS de que toda la integridad referencial ya
fue garantizada por construcción — así el dataset "limpio" subyacente sigue
siendo válido y las anomalías son 100% controladas y contables.
"""
from __future__ import annotations

import numpy as np
import pandas as pd


def inject_duplicados_exactos(rng: np.random.Generator, df: pd.DataFrame, pct: float, tabla: str, pk_col: str):
    """ANOMALÍA 1 — Transacciones duplicadas exactas.
    Simula una re-ingesta accidental desde el origen: se duplica la fila
    completa (incluida la PK), tal como ocurriría si un job de extracción
    se reintenta sin idempotencia."""
    n = int(len(df) * pct)
    if n == 0:
        return df, []
    idx = rng.choice(df.index, size=n, replace=False)
    dupes = df.loc[idx].copy()
    log = [{"tabla": tabla, "id_registro": v, "tipo_anomalia": "DUPLICADO_EXACTO",
            "motivo": "Fila duplicada exacta (misma PK) para simular reintento de ingesta sin idempotencia"}
           for v in dupes[pk_col].tolist()]
    return pd.concat([df, dupes], ignore_index=True), log


def inject_fechas_fuera_rango(rng: np.random.Generator, df: pd.DataFrame, pct: float,
                               date_col: str, tabla: str, pk_col: str,
                               date_start: str, date_end: str):
    """ANOMALÍA 2 — Fechas fuera de rango.
    Mitad de los casos: fecha futura (posterior al fin de la ventana de
    carga, ej. error de reloj del sistema origen). Mitad: fecha anterior a
    la fundación del banco (2015), ej. error de migración de datos legados."""
    n = int(len(df) * pct)
    if n == 0:
        return df, []
    idx = rng.choice(df.index, size=n, replace=False)
    half = n // 2
    future_idx, past_idx = idx[:half], idx[half:]

    future_dates = pd.Timestamp(date_end) + pd.to_timedelta(rng.integers(30, 400, len(future_idx)), unit="D")
    past_dates = pd.Timestamp("2015-01-01") - pd.to_timedelta(rng.integers(30, 3650, len(past_idx)), unit="D")

    df = df.copy()
    df.loc[future_idx, date_col] = future_dates.strftime("%Y-%m-%d")
    df.loc[past_idx, date_col] = past_dates.strftime("%Y-%m-%d")

    log = [{"tabla": tabla, "id_registro": v, "tipo_anomalia": "FECHA_FUERA_DE_RANGO",
            "motivo": f"{date_col} posterior a la ventana de carga (posible error de reloj de origen)"}
           for v in df.loc[future_idx, pk_col].tolist()]
    log += [{"tabla": tabla, "id_registro": v, "tipo_anomalia": "FECHA_FUERA_DE_RANGO",
             "motivo": f"{date_col} anterior a la fundación del banco (posible error de migración)"}
            for v in df.loc[past_idx, pk_col].tolist()]
    return df, log


def inject_fk_huerfana(rng: np.random.Generator, df: pd.DataFrame, pct: float,
                        fk_col: str, tabla: str, pk_col: str):
    """ANOMALÍA 3 — Llave foránea huérfana.
    Reemplaza id_cli por un identificador con formato válido pero que no
    existe en TB_CLIENTES_CORE, ej. un cliente eliminado/migrado en el
    sistema origen sin borrado en cascada. Existe a propósito para que la
    validación de integridad referencial de la capa Silver tenga algo que
    detectar y enviar a la tabla de errores."""
    n = int(len(df) * pct)
    if n == 0:
        return df, []
    idx = rng.choice(df.index, size=n, replace=False)
    fake_ids = [f"CLI{900000 + i:06d}" for i in range(n)]  # fuera del rango real (CLI000001..CLI0{volumen})
    df = df.copy()
    df.loc[idx, fk_col] = fake_ids
    log = [{"tabla": tabla, "id_registro": r, "tipo_anomalia": "FK_HUERFANA",
            "motivo": f"{fk_col}={fid} no existe en TB_CLIENTES_CORE"}
           for r, fid in zip(df.loc[idx, pk_col].tolist(), fake_ids)]
    return df, log


def inject_campos_inconsistentes_movimientos(rng: np.random.Generator, df: pd.DataFrame, pct: float):
    """ANOMALÍA 4a — Montos con signo inconsistente en TB_MOV_FINANCIEROS.
    vr_mov negativo en un tipo de movimiento que siempre debería ser
    positivo (ej. error de signo en el sistema origen)."""
    n = int(len(df) * pct)
    if n == 0:
        return df, []
    idx = rng.choice(df.index, size=n, replace=False)
    df = df.copy()
    df.loc[idx, "vr_mov"] = -df.loc[idx, "vr_mov"].abs()
    log = [{"tabla": "TB_MOV_FINANCIEROS", "id_registro": v, "tipo_anomalia": "CAMPO_INCONSISTENTE",
            "motivo": "vr_mov negativo (signo inválido para el tipo de movimiento)"}
           for v in df.loc[idx, "id_mov"].tolist()]
    return df, log


def inject_campos_inconsistentes_obligaciones(rng: np.random.Generator, df: pd.DataFrame, pct: float):
    """ANOMALÍA 4b — Saldo de capital inconsistente en TB_OBLIGACIONES.
    sdo_capital queda por encima de vr_aprobado, algo imposible en la
    realidad de negocio (simula un error de cálculo/captura en el origen)."""
    n = int(len(df) * pct)
    if n == 0:
        return df, []
    idx = rng.choice(df.index, size=n, replace=False)
    df = df.copy()
    df.loc[idx, "sdo_capital"] = df.loc[idx, "vr_aprobado"] * rng.uniform(1.3, 1.8, n)
    log = [{"tabla": "TB_OBLIGACIONES", "id_registro": v, "tipo_anomalia": "CAMPO_INCONSISTENTE",
            "motivo": "sdo_capital > vr_aprobado (inconsistencia de negocio)"}
           for v in df.loc[idx, "id_oblig"].tolist()]
    return df, log
