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

`load_to_postgres.py` lee la conexión de variables de entorno
(`FINBANK_DB_HOST`, `FINBANK_DB_PORT`, `FINBANK_DB_NAME`, `FINBANK_DB_USER`,
`FINBANK_DB_PASSWORD`). Para apuntar a Cloud SQL en vez de al Postgres
local, basta con exportar esas variables (la contraseña debería venir del
Secret Manager de GCP, nunca escrita en un archivo) antes de correr el
script — el código no cambia.
