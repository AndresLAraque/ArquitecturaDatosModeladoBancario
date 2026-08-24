"""
Generadores por tabla fuente de FinBank. Cada función recibe un
`numpy.random.Generator` ya inicializado con la semilla del config y
devuelve un `pandas.DataFrame` con exactamente los campos declarados en el
enunciado para esa tabla (mismos nombres, mismo orden de negocio).

Principio de integridad referencial: las dimensiones (clientes, productos,
sucursales) se generan primero; los hechos (movimientos, obligaciones,
comisiones) siempre muestrean sus llaves foráneas desde esas dimensiones ya
generadas, así que por construcción son 100% válidas ANTES de que
`anomalies.py` inyecte deliberadamente las excepciones documentadas.
"""
from __future__ import annotations

import numpy as np
import pandas as pd
from faker import Faker

import reference_data as ref

fake = Faker("es_ES")


def weighted_choice(rng: np.random.Generator, options, weights, size):
    p = np.asarray(weights, dtype=float)
    p = p / p.sum()
    return rng.choice(np.asarray(options, dtype=object), size=size, p=p)


def _build_daily_weights(date_start: str, date_end: str):
    """Pesos diarios con estacionalidad mensual (pico en diciembre / mitad
    de año) + efecto quincena de pago (1-2, 15-16 y últimos días del mes
    concentran más movimiento, comportamiento típico de un banco digital)."""
    dates = pd.date_range(date_start, date_end, freq="D")
    month_seasonal = {1: 0.90, 2: 0.85, 3: 0.95, 4: 0.95, 5: 1.00, 6: 1.15,
                       7: 1.00, 8: 1.00, 9: 0.95, 10: 1.00, 11: 1.05, 12: 1.35}
    weights = np.empty(len(dates))
    for i, d in enumerate(dates):
        w = month_seasonal.get(d.month, 1.0)
        dim = d.days_in_month
        if d.day in (1, 2, 15, 16) or d.day >= dim - 1:
            w *= 1.6
        weights[i] = w
    return dates, weights


# Concentración horaria: picos en horas de almuerzo (12-13h) y noche (19-20h),
# mínimo en la madrugada — refleja el uso real de una app bancaria.
_HOUR_WEIGHTS = np.array([1, 1, 1, 1, 1, 2, 4, 8, 10, 7, 5, 6,
                           9, 8, 5, 5, 6, 7, 9, 10, 8, 5, 3, 2], dtype=float)


def sample_datetimes(rng: np.random.Generator, n: int, date_start: str, date_end: str):
    dates, weights = _build_daily_weights(date_start, date_end)
    idx = rng.choice(len(dates), size=n, p=weights / weights.sum())
    chosen_dates = dates[idx]
    hours = rng.choice(24, size=n, p=_HOUR_WEIGHTS / _HOUR_WEIGHTS.sum())
    minutes = rng.integers(0, 60, size=n)
    seconds = rng.integers(0, 60, size=n)
    fechas = pd.Series(chosen_dates).dt.strftime("%Y-%m-%d").to_numpy()
    horas = np.array([f"{h:02d}:{m:02d}:{s:02d}" for h, m, s in zip(hours, minutes, seconds)])
    return fechas, horas


def _hex_device_ids(rng: np.random.Generator, n: int):
    ints = rng.integers(0, 2**62, size=n, dtype=np.int64)
    return np.array([format(int(v), "x").zfill(16) for v in ints])


def _apply_null_mask(rng: np.random.Generator, series: pd.Series, pct: float) -> pd.Series:
    mask = rng.random(len(series)) < pct
    out = series.astype(object)
    out[mask] = None
    return out


# --------------------------------------------------------------------------- #
# TB_PRODUCTOS_CAT
# --------------------------------------------------------------------------- #
def generate_productos(rng: np.random.Generator, n: int, null_pct: float) -> pd.DataFrame:
    families = ref.PRODUCT_FAMILIES
    fam_names = list(families.keys())
    fam_weights = np.array([families[f]["peso"] for f in fam_names], dtype=float)
    fam_counts = np.floor(fam_weights / fam_weights.sum() * n).astype(int)
    fam_counts[-1] += n - fam_counts.sum()  # ajuste de redondeo para sumar exactamente n

    rows = []
    suffixes = ["Clásico", "Plus", "Digital", "Max", "Esencial", "Total"]
    seq = 1
    for fam, count in zip(fam_names, fam_counts):
        tipos = list(families[fam]["tipos"].keys())
        for i in range(count):
            tipo = tipos[i % len(tipos)]
            tasa_min, tasa_max = families[fam]["tipos"][tipo]
            suf = suffixes[i % len(suffixes)]
            desc = f"{tipo.replace('_', ' ').title()} {suf}"
            tasa_ea = 0.0 if tasa_max == 0 else round(rng.uniform(tasa_min, tasa_max), 2)
            if fam == "CREDITO" and tipo == "CRED_LIBRE_INVERSION":
                plazo = int(rng.integers(12, 61))
                cuota_min = round(rng.uniform(80_000, 300_000), 0)
                comision = round(rng.uniform(15_000, 60_000), 0)
            elif fam == "CREDITO":
                plazo = None  # rotativo / tarjeta digital: cupo revolvente, sin plazo fijo
                cuota_min = round(rng.uniform(40_000, 150_000), 0)
                comision = round(rng.uniform(10_000, 45_000), 0)
            elif fam == "AHORRO":
                plazo = None
                cuota_min = 0.0
                comision = round(rng.uniform(0, 8_000), 0)
            else:  # TRANSACCIONAL
                plazo = None
                cuota_min = 0.0
                comision = round(rng.uniform(1_500, 9_000), 0)
            estado = "ACTIVO" if rng.random() < 0.9 else "INACTIVO"
            rows.append({
                "cod_prod": f"PRD{seq:03d}",
                "desc_prod": desc,
                "tip_prod": tipo,
                "tasa_ea": tasa_ea,
                "plazo_max_meses": plazo,
                "cuota_min": cuota_min,
                "comision_admin": comision,
                "estado_prod": estado,
                "_familia": fam,  # columna auxiliar interna, no forma parte del esquema fuente
            })
            seq += 1

    df = pd.DataFrame(rows)
    df["comision_admin"] = _apply_null_mask(rng, df["comision_admin"], null_pct)
    return df


# --------------------------------------------------------------------------- #
# TB_SUCURSALES_RED
# --------------------------------------------------------------------------- #
def generate_sucursales(rng: np.random.Generator, n: int, null_pct: float) -> pd.DataFrame:
    city_idx = rng.choice(len(ref.CITIES), size=n, p=np.array(ref.CITY_WEIGHTS) / sum(ref.CITY_WEIGHTS))
    tipos = weighted_choice(rng, ref.TIPOS_PUNTO_SUCURSAL, ref.TIPOS_PUNTO_SUCURSAL_WEIGHTS, n)

    rows = []
    for i in range(n):
        city = ref.CITIES[city_idx[i]]
        tipo = tipos[i]
        prefijo = {"OFICINA": "Oficina", "CAJERO": "Cajero", "CORRESPONSAL": "Punto Aliado"}[tipo]
        rows.append({
            "cod_suc": f"SUC{i + 1:04d}",
            "nom_suc": f"{prefijo} {city['ciudad']} {i % 50 + 1}",
            "tip_punto": tipo,
            "ciudad": city["ciudad"],
            "depto": city["depto"],
            "latitud": round(city["lat"] + rng.uniform(-0.05, 0.05), 6),
            "longitud": round(city["lon"] + rng.uniform(-0.05, 0.05), 6),
            "activo": bool(rng.random() < 0.95),
        })
    df = pd.DataFrame(rows)
    df["latitud"] = _apply_null_mask(rng, df["latitud"], null_pct)
    df["longitud"] = _apply_null_mask(rng, df["longitud"], null_pct)
    return df


# --------------------------------------------------------------------------- #
# TB_CLIENTES_CORE
# --------------------------------------------------------------------------- #
def generate_clientes(rng: np.random.Generator, n: int, date_start: str, date_end: str, null_pct: float) -> pd.DataFrame:
    ref_date = pd.Timestamp(date_end)
    bank_founded = pd.Timestamp("2015-01-01")

    edades = np.clip(rng.normal(38, 12, n), 18, 85).astype(int)
    fec_nac = [ref_date - pd.DateOffset(years=int(e), days=int(rng.integers(0, 365))) for e in edades]

    segmentos = weighted_choice(rng, ref.SEGMENTOS, ref.SEGMENTOS_WEIGHTS, n)
    score_buro = np.empty(n)
    for seg in ref.SEGMENTOS:
        mask = segmentos == seg
        mean, std = ref.SEGMENTO_SCORE_PARAMS[seg]
        score_buro[mask] = np.clip(rng.normal(mean, std, mask.sum()), 150, 950)
    score_buro = score_buro.round().astype(int)

    # fec_alta: ponderada hacia años recientes (crecimiento de la base de clientes)
    year_weights = {2015: 2, 2016: 3, 2017: 4, 2018: 5, 2019: 6, 2020: 7,
                    2021: 9, 2022: 11, 2023: 13, 2024: 15, 2025: 16, 2026: 9}
    years = np.array(list(year_weights.keys()))
    yw = np.array(list(year_weights.values()), dtype=float)
    chosen_years = rng.choice(years, size=n, p=yw / yw.sum())
    fec_alta = []
    for i, y in enumerate(chosen_years):
        upper = ref_date if y == ref_date.year else pd.Timestamp(f"{y}-12-31")
        start = max(bank_founded, pd.Timestamp(f"{y}-01-01"))
        day_offset = int(rng.integers(0, max((upper - start).days, 1) + 1))
        candidate = start + pd.Timedelta(days=day_offset)
        min_valid = fec_nac[i] + pd.DateOffset(years=18)
        fec_alta.append(max(candidate, min_valid))

    city_idx = rng.choice(len(ref.CITIES), size=n, p=np.array(ref.CITY_WEIGHTS) / sum(ref.CITY_WEIGHTS))

    df = pd.DataFrame({
        "id_cli": [f"CLI{i + 1:06d}" for i in range(n)],
        "nomb_cli": [fake.first_name() for _ in range(n)],
        "apell_cli": [fake.last_name() for _ in range(n)],
        "tip_doc": weighted_choice(rng, ref.TIPOS_DOC, ref.TIPOS_DOC_WEIGHTS, n),
        "num_doc": [str(rng.integers(10_000_000, 1_000_000_000)) for _ in range(n)],
        "fec_nac": pd.Series(fec_nac).dt.strftime("%Y-%m-%d"),
        "fec_alta": pd.Series(fec_alta).dt.strftime("%Y-%m-%d"),
        "cod_segmento": segmentos,
        "score_buro": score_buro,
        "ciudad_res": [ref.CITIES[c]["ciudad"] for c in city_idx],
        "depto_res": [ref.CITIES[c]["depto"] for c in city_idx],
        "estado_cli": weighted_choice(rng, ref.ESTADOS_CLIENTE, ref.ESTADOS_CLIENTE_WEIGHTS, n),
        "canal_adquis": weighted_choice(rng, ref.CANALES_ADQUISICION, ref.CANALES_ADQUISICION_WEIGHTS, n),
    })

    # Nulos controlados solo en campos no críticos (nunca en id_cli/num_doc/fec_nac)
    df["score_buro"] = _apply_null_mask(rng, df["score_buro"], null_pct)
    df["ciudad_res"] = _apply_null_mask(rng, df["ciudad_res"], null_pct)
    df["canal_adquis"] = _apply_null_mask(rng, df["canal_adquis"], null_pct)
    return df


def _make_num_cuenta(id_cli: pd.Series, cod_prod: pd.Series) -> pd.Series:
    cli_num = id_cli.str.extract(r"(\d+)")[0].str.zfill(6)
    prod_num = cod_prod.str.extract(r"(\d+)")[0].str.zfill(3)
    return "8" + cli_num + prod_num


# --------------------------------------------------------------------------- #
# TB_OBLIGACIONES
# --------------------------------------------------------------------------- #
def generate_obligaciones(rng: np.random.Generator, n: int, clientes: pd.DataFrame,
                           productos: pd.DataFrame, date_start: str, date_end: str,
                           null_pct: float) -> pd.DataFrame:
    credit_products = productos[productos["_familia"] == "CREDITO"].reset_index(drop=True)
    ref_date = pd.Timestamp(date_end)

    id_cli = rng.choice(clientes["id_cli"].to_numpy(), size=n)
    prod_idx = rng.choice(len(credit_products), size=n)
    cod_prod = credit_products["cod_prod"].to_numpy()[prod_idx]
    tip_prod = credit_products["tip_prod"].to_numpy()[prod_idx]

    vr_aprobado = np.where(
        tip_prod == "CRED_LIBRE_INVERSION",
        np.round(rng.lognormal(15.7, 0.55, n), -3),
        np.round(rng.lognormal(14.5, 0.5, n), -3),
    )
    vr_desembolsado = np.round(vr_aprobado * rng.uniform(0.85, 1.0, n), -3)

    # fec_desembolso: puede ser anterior a la ventana de 12 meses de movimientos
    # (las obligaciones vigentes suelen originarse antes del periodo de análisis)
    window_days = (ref_date - pd.Timestamp("2015-01-01")).days
    offsets = rng.triangular(0, window_days * 0.85, window_days, n).astype(int)
    fec_desembolso = pd.Timestamp("2015-01-01") + pd.to_timedelta(offsets, unit="D")

    plazo = np.where(pd.isna(credit_products["plazo_max_meses"].to_numpy()[prod_idx]),
                      24, credit_products["plazo_max_meses"].to_numpy()[prod_idx])
    plazo = np.nan_to_num(plazo.astype(float), nan=24.0)
    fec_venc = fec_desembolso + pd.to_timedelta((plazo * 30).astype(int), unit="D")

    al_dia = rng.random(n) < 0.75
    dias_mora_act = np.where(
        al_dia, 0,
        np.clip(rng.exponential(40, n), 1, 400).astype(int),
    )

    base_fraction = np.where(
        dias_mora_act > 60,
        rng.uniform(0.4, 1.05, n),
        rng.uniform(0.05, 0.9, n),
    )
    sdo_capital = np.round(np.clip(vr_desembolsado * base_fraction, 0, None), -3)
    vr_cuota = np.round(vr_aprobado / np.clip(plazo, 12, None) * rng.uniform(1.05, 1.15, n), -2)
    num_cuotas_pend = np.clip(np.round(sdo_capital / np.clip(vr_cuota, 1, None)), 0, None).astype(int)

    calif = np.full(n, "NORMAL", dtype=object)
    calif[dias_mora_act > 30] = "VIGILANCIA"
    calif[dias_mora_act > 90] = "INCUMPLIMIENTO"
    # ruido deliberado: la calificación de la fuente no siempre está sincronizada
    # con dias_mora_act (dato legado, se recalcula formalmente en Gold)
    noise_mask = rng.random(n) < 0.05
    calif[noise_mask] = rng.choice(ref.CALIFICACIONES_RIESGO_FUENTE, size=noise_mask.sum())

    df = pd.DataFrame({
        "id_oblig": [f"OBL{i + 1:06d}" for i in range(n)],
        "id_cli": id_cli,
        "cod_prod": cod_prod,
        "vr_aprobado": vr_aprobado,
        "vr_desembolsado": vr_desembolsado,
        "sdo_capital": sdo_capital,
        "vr_cuota": vr_cuota,
        "fec_desembolso": fec_desembolso.strftime("%Y-%m-%d"),
        "fec_venc": fec_venc.strftime("%Y-%m-%d"),
        "dias_mora_act": dias_mora_act,
        "num_cuotas_pend": num_cuotas_pend,
        "calif_riesgo": calif,
    })
    df["num_cuotas_pend"] = _apply_null_mask(rng, df["num_cuotas_pend"], null_pct)
    return df


# --------------------------------------------------------------------------- #
# TB_MOV_FINANCIEROS
# --------------------------------------------------------------------------- #
def generate_movimientos(rng: np.random.Generator, n: int, clientes: pd.DataFrame,
                          productos: pd.DataFrame, date_start: str, date_end: str,
                          null_pct: float) -> pd.DataFrame:
    client_ids = clientes["id_cli"].to_numpy()
    # Actividad transaccional desigual entre clientes (power users) — log-normal
    activity = rng.lognormal(0, 1.0, len(client_ids))
    activity_p = activity / activity.sum()
    id_cli = rng.choice(client_ids, size=n, p=activity_p)

    prod_idx = rng.choice(len(productos), size=n)
    cod_prod = productos["cod_prod"].to_numpy()[prod_idx]

    fechas, horas = sample_datetimes(rng, n, date_start, date_end)

    tip_mov = weighted_choice(rng, ref.TIPOS_MOVIMIENTO, ref.TIPOS_MOVIMIENTO_WEIGHTS, n)
    vr_mov = np.empty(n)
    for tipo in ref.TIPOS_MOVIMIENTO:
        mask = tip_mov == tipo
        mu, sigma = ref.TIPO_MOVIMIENTO_MONTO_PARAMS[tipo]
        vr_mov[mask] = np.round(rng.lognormal(mu, sigma, mask.sum()), -2)

    cod_canal = weighted_choice(rng, ref.CANALES_MOV, ref.CANALES_MOV_WEIGHTS, n)
    city_idx = rng.choice(len(ref.CITIES), size=n, p=np.array(ref.CITY_WEIGHTS) / sum(ref.CITY_WEIGHTS))
    cod_ciudad = np.array([ref.CITIES[c]["cod_ciudad"] for c in city_idx])
    cod_estado_mov = weighted_choice(rng, ref.ESTADOS_MOV, ref.ESTADOS_MOV_WEIGHTS, n)
    id_dispositivo = _hex_device_ids(rng, n).astype(object)
    id_dispositivo[cod_canal == "CORRESPONSAL"] = None  # un corresponsal no usa el dispositivo del cliente

    df = pd.DataFrame({
        "id_mov": [f"MOV{i + 1:08d}" for i in range(n)],
        "id_cli": id_cli,
        "cod_prod": cod_prod,
        "num_cuenta": _make_num_cuenta(pd.Series(id_cli), pd.Series(cod_prod)),
        "fec_mov": fechas,
        "hra_mov": horas,
        "vr_mov": vr_mov,
        "tip_mov": tip_mov,
        "cod_canal": cod_canal,
        "cod_ciudad": cod_ciudad,
        "cod_estado_mov": cod_estado_mov,
        "id_dispositivo": id_dispositivo,
    })
    df["cod_ciudad"] = _apply_null_mask(rng, df["cod_ciudad"], null_pct)
    return df


# --------------------------------------------------------------------------- #
# TB_COMISIONES_LOG
# --------------------------------------------------------------------------- #
def generate_comisiones(rng: np.random.Generator, n: int, clientes: pd.DataFrame,
                         productos: pd.DataFrame, date_start: str, date_end: str,
                         null_pct: float) -> pd.DataFrame:
    client_ids = clientes["id_cli"].to_numpy()
    activity = rng.lognormal(0, 1.0, len(client_ids))
    activity_p = activity / activity.sum()
    id_cli = rng.choice(client_ids, size=n, p=activity_p)

    prod_idx = rng.choice(len(productos), size=n)
    cod_prod = productos["cod_prod"].to_numpy()[prod_idx]

    fechas, _ = sample_datetimes(rng, n, date_start, date_end)
    tip_comision = weighted_choice(rng, ref.TIPOS_COMISION, ref.TIPOS_COMISION_WEIGHTS, n)
    vr_comision = np.round(rng.lognormal(9.5, 0.5, n), -2)
    estado_cobro = weighted_choice(rng, ref.ESTADOS_COBRO, ref.ESTADOS_COBRO_WEIGHTS, n)

    df = pd.DataFrame({
        "id_comision": [f"COM{i + 1:06d}" for i in range(n)],
        "id_cli": id_cli,
        "cod_prod": cod_prod,
        "fec_cobro": fechas,
        "vr_comision": vr_comision,
        "tip_comision": tip_comision,
        "estado_cobro": estado_cobro,
    })
    df["tip_comision"] = _apply_null_mask(rng, df["tip_comision"], null_pct)
    return df
