"""
Datos de referencia estáticos para la generación sintética de FinBank:
geografía de los 5 países donde opera el banco y catálogos de códigos
usados por las tablas fuente. Centralizar esto aquí evita "números mágicos"
repetidos en los generadores de cada tabla.
"""

# Ciudades donde FinBank tiene presencia, con su departamento/estado, país,
# código corto (usado en cod_ciudad) y coordenadas aproximadas del centro
# de la ciudad (para TB_SUCURSALES_RED). El peso relativo favorece a
# Colombia (país de origen del banco) sobre el resto de la operación.
CITIES = [
    {"ciudad": "Bogotá",            "depto": "Cundinamarca",         "pais": "Colombia",  "cod_ciudad": "BOG",  "lat": 4.7110,   "lon": -74.0721, "peso": 18},
    {"ciudad": "Medellín",          "depto": "Antioquia",            "pais": "Colombia",  "cod_ciudad": "MED",  "lat": 6.2442,   "lon": -75.5812, "peso": 10},
    {"ciudad": "Cali",              "depto": "Valle del Cauca",      "pais": "Colombia",  "cod_ciudad": "CAL",  "lat": 3.4516,   "lon": -76.5320, "peso": 8},
    {"ciudad": "Barranquilla",      "depto": "Atlántico",            "pais": "Colombia",  "cod_ciudad": "BAQ",  "lat": 10.9639,  "lon": -74.7964, "peso": 6},
    {"ciudad": "Bucaramanga",       "depto": "Santander",            "pais": "Colombia",  "cod_ciudad": "BGA",  "lat": 7.1193,   "lon": -73.1227, "peso": 5},
    {"ciudad": "Ciudad de México",  "depto": "CDMX",                 "pais": "México",    "cod_ciudad": "CDMX", "lat": 19.4326,  "lon": -99.1332, "peso": 12},
    {"ciudad": "Guadalajara",       "depto": "Jalisco",              "pais": "México",    "cod_ciudad": "GDL",  "lat": 20.6597,  "lon": -103.3496, "peso": 6},
    {"ciudad": "Monterrey",         "depto": "Nuevo León",           "pais": "México",    "cod_ciudad": "MTY",  "lat": 25.6866,  "lon": -100.3161, "peso": 5},
    {"ciudad": "Lima",              "depto": "Lima",                 "pais": "Perú",      "cod_ciudad": "LIM",  "lat": -12.0464, "lon": -77.0428, "peso": 10},
    {"ciudad": "Arequipa",          "depto": "Arequipa",             "pais": "Perú",      "cod_ciudad": "AQP",  "lat": -16.4090, "lon": -71.5375, "peso": 4},
    {"ciudad": "Santiago",          "depto": "Región Metropolitana", "pais": "Chile",     "cod_ciudad": "SCL",  "lat": -33.4489, "lon": -70.6693, "peso": 8},
    {"ciudad": "Valparaíso",        "depto": "Valparaíso",           "pais": "Chile",     "cod_ciudad": "VAP",  "lat": -33.0472, "lon": -71.6127, "peso": 3},
    {"ciudad": "Buenos Aires",      "depto": "CABA",                 "pais": "Argentina", "cod_ciudad": "BUE",  "lat": -34.6037, "lon": -58.3816, "peso": 4},
    {"ciudad": "Córdoba",           "depto": "Córdoba",              "pais": "Argentina", "cod_ciudad": "COR",  "lat": -31.4201, "lon": -64.1888, "peso": 1},
]

CITY_WEIGHTS = [c["peso"] for c in CITIES]

# tip_doc: tipos de documento de identidad usados a lo largo de los 5 países.
TIPOS_DOC = ["CC", "CE", "PASAPORTE", "DNI"]
TIPOS_DOC_WEIGHTS = [70, 8, 4, 18]

SEGMENTOS = ["BAS", "STD", "PRM", "ELT"]  # básico/estándar/premium/elite (código fuente, no legible)
SEGMENTOS_WEIGHTS = [45, 34, 15, 6]
# score_buro objetivo (media, desviación) por segmento — rango típico 150-950
SEGMENTO_SCORE_PARAMS = {
    "BAS": (550, 80),
    "STD": (650, 70),
    "PRM": (760, 55),
    "ELT": (840, 45),
}

ESTADOS_CLIENTE = ["ACTIVO", "INACTIVO", "BLOQUEADO"]
ESTADOS_CLIENTE_WEIGHTS = [90, 7, 3]

CANALES_ADQUISICION = ["APP", "WEB", "CORRESPONSAL", "REFERIDO"]
CANALES_ADQUISICION_WEIGHTS = [45, 30, 15, 10]

# Catálogo de productos: familia de negocio -> tipos de producto que
# se generan dentro de esa familia, con su rango de tasa efectiva anual (EA).
PRODUCT_FAMILIES = {
    "CREDITO": {
        "tipos": {
            "CRED_LIBRE_INVERSION": (18.0, 32.0),
            "CRED_ROTATIVO": (24.0, 36.0),
            "TARJETA_DIGITAL": (26.0, 38.0),
        },
        "peso": 45,
    },
    "AHORRO": {
        "tipos": {
            "CUENTA_AHORRO_DIGITAL": (0.5, 4.0),
        },
        "peso": 15,
    },
    "TRANSACCIONAL": {
        "tipos": {
            "PAGO_PSE": (0.0, 0.0),
            "TRANSFERENCIA_ACH": (0.0, 0.0),
            "CORRESPONSALIA": (0.0, 0.0),
            "RECARGA": (0.0, 0.0),
        },
        "peso": 40,
    },
}

TIPOS_MOVIMIENTO = [
    "PAGO_PSE", "TRANSFERENCIA_ACH", "RECARGA", "AVANCE_EFECTIVO",
    "COMPRA_TARJETA", "RETIRO_CORRESPONSAL", "ABONO_CUENTA",
]
TIPOS_MOVIMIENTO_WEIGHTS = [18, 20, 12, 6, 22, 10, 12]
# Rango típico de monto (COP) por tipo de movimiento: (media_log, sigma_log)
# usando distribución log-normal para reflejar que la mayoría de montos son
# pequeños/medios y unos pocos son grandes (comportamiento típico transaccional).
TIPO_MOVIMIENTO_MONTO_PARAMS = {
    "PAGO_PSE": (12.5, 0.7),
    "TRANSFERENCIA_ACH": (13.0, 0.9),
    "RECARGA": (10.0, 0.5),
    "AVANCE_EFECTIVO": (13.3, 0.6),
    "COMPRA_TARJETA": (11.5, 0.8),
    "RETIRO_CORRESPONSAL": (12.0, 0.6),
    "ABONO_CUENTA": (13.5, 0.9),
}

CANALES_MOV = ["APP", "WEB", "CORRESPONSAL"]
CANALES_MOV_WEIGHTS = [60, 25, 15]

ESTADOS_MOV = ["EXITOSA", "FALLIDA", "PENDIENTE"]
ESTADOS_MOV_WEIGHTS = [94, 4, 2]

TIPOS_COMISION = ["MANEJO", "RETIRO", "TRANSFERENCIA", "SEGURO_VOLUNTARIO", "SMS_ALERTA"]
TIPOS_COMISION_WEIGHTS = [35, 20, 20, 15, 10]

ESTADOS_COBRO = ["EXITOSO", "REVERSADO"]
ESTADOS_COBRO_WEIGHTS = [95, 5]

TIPOS_PUNTO_SUCURSAL = ["OFICINA", "CAJERO", "CORRESPONSAL"]
TIPOS_PUNTO_SUCURSAL_WEIGHTS = [15, 20, 65]  # coherente con "red de corresponsales bancarios"

CALIFICACIONES_RIESGO_FUENTE = ["NORMAL", "VIGILANCIA", "INCUMPLIMIENTO"]

# USD/COP aproximado usado únicamente para el cálculo `monto en USD desde COP`
# que pide el enunciado en fact_transacciones (capa Silver/Gold, no en Fase 1,
# pero se documenta aquí para que la tasa quede centralizada y versionada).
USD_COP_RATE = 4050.0
