# Fase 1 — Generación de datos y modelo relacional

Genera los datos sintéticos de FinBank (Escenario A) y los carga en la base
relacional origen del pipeline.

## Requisitos

- Python 3.12
- Docker (para el Postgres local de desarrollo)

## Pasos

```bash
cd data-generation
python -m venv .venv
.venv\Scripts\activate        # Windows PowerShell: .venv\Scripts\Activate.ps1
pip install -r requirements.txt

# 1. Configurar credenciales locales (nunca se commitean)
copy .env.example .env
# editar .env si se quiere otra contraseña

# 2. Levantar Postgres local
docker compose up -d
docker compose ps             # esperar healthy

# 3. Generar los datos sintéticos (reproducible, semilla fija en config.yaml)
python main.py

# 4. Cargar a Postgres (idempotente: recrea el esquema en cada corrida)
python load_to_postgres.py
```

## Qué genera `main.py`

Las 6 tablas fuente de FinBank, con los nombres de campo exactos del
enunciado, en `output/`:

| Tabla | Filas | Formato de salida |
|---|---|---|
| `TB_CLIENTES_CORE` | 10.000 | JSON |
| `TB_PRODUCTOS_CAT` | 50 | CSV |
| `TB_SUCURSALES_RED` | 200 | JSON |
| `TB_MOV_FINANCIEROS` | 500.000 (+ duplicados) | Parquet |
| `TB_OBLIGACIONES` | 30.000 | Parquet |
| `TB_COMISIONES_LOG` | 80.000 | Parquet |

Formatos deliberadamente heterogéneos (CSV + JSON + Parquet) para simular
un escenario de ingesta real con múltiples fuentes. Configurable en
`config.yaml:output_formats`.

También se generan:
- `output/anomalies_log.csv` — detalle fila por fila de las 4 anomalías
  intencionales (ver `ANOMALIES.md`)
- `output/generation_summary.json` — resumen de la corrida (filas por
  tabla, % de nulos, duración)
- `output/load_evidence.txt` — resultado de `SELECT COUNT(*)` por tabla
  tras la carga (evidencia de Fase 1)

## Reproducibilidad y configuración

Todo lo que varía entre corridas está en `config.yaml`: semilla aleatoria,
volumen por tabla, rango de fechas, % de nulos y % de cada anomalía. Con la
misma semilla, dos corridas producen exactamente el mismo dataset.

## Distribuciones aplicadas (no son datos puramente aleatorios)

- **Edad de clientes:** normal (μ=38, σ=12), acotada a [18, 85]
- **Score de buró:** normal por segmento (básico/estándar/premium/elite),
  acotado a [150, 950] — a mayor segmento, mayor media
- **Hora de transacción:** distribución ponderada con picos en horario de
  almuerzo (12-13h) y noche (19-20h), mínimo en la madrugada
- **Día de transacción:** estacionalidad mensual (pico en diciembre) +
  efecto quincena de pago (1-2, 15-16 y últimos días del mes concentran
  más movimiento)
- **Monto de transacción:** log-normal, con parámetros propios por tipo de
  movimiento (una recarga y un avance de efectivo no tienen la misma escala)
- **Actividad transaccional por cliente:** log-normal (algunos clientes
  transan mucho más que otros — comportamiento realista, no uniforme)
- **Días de mora:** ~75% de las obligaciones al día (0 días); el resto
  sigue una exponencial acotada a 400 días (cola larga hacia el deterioro)

## Nulos controlados

~5% en campos no críticos (nunca en llaves primarias/foráneas ni en campos
obligatorios de negocio como `fec_nac`), configurable en `config.yaml:null_pct`.

## Apuntar a Cloud SQL en vez del Postgres local

Ya cargado y verificado (`output/load_evidence_cloudsql.txt`) contra
`finbank-sqlpg-dev` (Fase 2). Para reproducirlo, en vez de las variables
`FINBANK_DB_HOST/PORT`, exportar:

```bash
export FINBANK_DB_INSTANCE_CONNECTION_NAME="<project>:<region>:<instance>"
export FINBANK_GCP_PROJECT_ID="<project>"
export FINBANK_DB_SECRET_ID="finbank-db-password-dev"
export FINBANK_DB_USER="finbank"
export FINBANK_DB_NAME="finbank"
export FINBANK_DB_PASSWORD=""   # IMPORTANTE: vacía, si no pisa el fallback a Secret Manager
```

`build_engine()` detecta `FINBANK_DB_INSTANCE_CONNECTION_NAME` y usa el
**Cloud SQL Python Connector** (`pg8000`) en vez de TCP directo — túnel
cifrado vía la Cloud SQL Admin API, sin IP autorizada ni Auth Proxy aparte.
La contraseña se resuelve sola desde Secret Manager si no se exporta
`FINBANK_DB_PASSWORD` (o si se exporta vacía).

La carga masiva usa `COPY ... FROM STDIN` (no `INSERT`/`executemany`): con
500k+ filas, miles de round-trips uno por uno sobre el túnel del connector
llegaron a tumbar la conexión SSL a mitad de carga. `COPY` manda todo en un
solo stream — mismo resultado con psycopg2 (local) y pg8000 (Cloud SQL).
