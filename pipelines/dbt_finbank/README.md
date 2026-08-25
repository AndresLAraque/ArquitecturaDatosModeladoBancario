# Capa Silver — dbt + BigQuery

Transforma las tablas `raw_*` (aterrizadas desde Bronze por
`pipelines/silver/load_bronze_to_bq.py`) en los modelos `stg_*` limpios,
tipados, deduplicados, con integridad referencial validada y PII
enmascarada — la "capa de confianza" para analítica.

## Pasos

```bash
# 1. Aterrizar Bronze -> BigQuery (tablas raw_*)
cd ../silver
python -m venv .venv && .venv\Scripts\activate
pip install -r requirements.txt
python load_bronze_to_bq.py

# 2. Correr dbt
cd ../dbt_finbank
python -m venv .venv && .venv\Scripts\activate
pip install -r requirements.txt
dbt deps          # no hay paquetes externos, pero no falla si se corre igual
dbt run  --profiles-dir .
dbt test --profiles-dir .
dbt docs generate --profiles-dir .   # documentación + linaje automático
```

## Qué construye

| Modelo | Capa | Qué hace |
|---|---|---|
| `stg_clientes` | Silver | Dedup, tipado, PII hasheada (nombre/apellido/num_doc), nulos tratados |
| `stg_productos` | Silver | Dedup, tipado, nulos tratados |
| `stg_sucursales` | Silver | Dedup, tipado, nulos tratados |
| `stg_movimientos` | Silver | Dedup exacto, filtra fechas/montos inválidos, valida FK, calcula `ind_sospechoso` |
| `stg_obligaciones` | Silver | Dedup, filtra fechas/saldos inconsistentes, valida FK |
| `stg_comisiones` | Silver | Dedup, valida FK, nulos tratados |
| `err_calidad_datos` | — | Tabla de errores del pipeline: FK huérfana, fecha fuera de rango, campo inconsistente — con motivo |
| `dq_report_silver` | — | Reporte de calidad por corrida: filas totales/rechazadas, % conformes, % nulos por columna clave |

## Estrategia de manejo de nulos (documentada por columna)

| Tabla | Columna | Estrategia | Por qué |
|---|---|---|---|
| `TB_CLIENTES_CORE` | `score_buro` | Marcado binario (`score_buro_es_nulo`), se conserva NULL | Imputar un score falso distorsionaría cualquier modelo de riesgo aguas abajo |
| `TB_CLIENTES_CORE` | `ciudad_res` | Imputación (`'DESCONOCIDA'`) | Campo descriptivo, bajo riesgo de sesgar análisis |
| `TB_CLIENTES_CORE` | `canal_adquis` | Imputación (`'NO_REGISTRADO'`) | Ídem |
| `TB_CLIENTES_CORE` | `num_doc`, `fec_nac` | **Exclusión del registro** | Campos obligatorios para identificar/segmentar al cliente |
| `TB_PRODUCTOS_CAT` | `plazo_max_meses` | Marcado binario (`es_plazo_aplicable`), se conserva NULL | Nulo **estructural** (producto revolvente), no es un problema de calidad |
| `TB_PRODUCTOS_CAT` | `comision_admin` | Imputación (`0`) | Ausencia se interpreta como "no cobra" |
| `TB_SUCURSALES_RED` | `latitud`/`longitud` | Marcado binario (`tiene_geolocalizacion`), se conserva NULL | Imputar coordenadas falsas sería engañoso en un mapa |
| `TB_MOV_FINANCIEROS` | `id_dispositivo` | Marcado binario (`sin_dispositivo_registrado`) | Nulo esperado en canal corresponsal, no es error |
| `TB_MOV_FINANCIEROS` | `cod_ciudad` | Imputación (`'DESCONOCIDA'`) | Campo descriptivo |
| `TB_OBLIGACIONES` | `num_cuotas_pend` | Marcado binario (`num_cuotas_pend_es_nulo`), se conserva NULL | Imputar 0 sugeriría "obligación pagada" — incorrecto |
| `TB_COMISIONES_LOG` | `tip_comision` | Imputación (`'SIN_CLASIFICAR'`) | Campo descriptivo, no afecta el cálculo de CLTV |

Las 3 estrategias que pide el enunciado (imputación / exclusión / marcado
binario) están representadas, cada una donde tiene sentido de negocio —
no aplicadas de forma uniforme sin criterio.

## Resultado de la corrida real (2026-08-25)

8/8 modelos creados, 21/21 tests en verde. Contenido verificado por query
directa (no solo "corrió sin error"):

| Métrica | Valor |
|---|---|
| `err_calidad_datos` | 3.008 filas: 2.006 fechas fuera de rango, 1.063 campos inconsistentes, 872 FK huérfanas (coincide con las anomalías inyectadas en Fase 1) |
| `dq_report_silver` | % conformes por tabla entre 99.45% y 100% |
| `ind_sospechoso` | 37.139 de 497.456 movimientos (~7.5%) — ver nota abajo |

**Nota honesta sobre `ind_sospechoso`:** 7.5% es más alto de lo típico para
un umbral de "3 sigma". El promedio/desviación de 30 días se calcula **por
cliente**, mezclando todos los tipos de movimiento — un cliente que alterna
recargas pequeñas con avances de efectivo grandes genera una media "mixta"
que hace ver atípica una transacción normal para su tipo. Es una lectura
fiel a la regla tal como está escrita en el enunciado (no pide segmentar
por tipo); segmentar por `(id_cli, tip_mov)` sería una mejora razonable a
futuro para bajar falsos positivos. Detalle completo en
`/docs/evidencia/fase3-silver/query_results_sample.txt`.

## Pruebas de calidad (>= 5 requeridas)

`_staging.yml` declara 19 tests genéricos de dbt (`not_null`, `unique`,
`accepted_values`, `relationships`) + 2 tests singulares en `tests/`
(`vr_mov` siempre positivo, `dias_mora_act` nunca negativo) — **21 en
total**, 21/21 en verde (`Done. PASS=21 WARN=0 ERROR=0 SKIP=0 TOTAL=21`).
Resultado de la corrida real en
`/docs/evidencia/fase3-silver/dbt_run_and_test_output.txt`.

## Enmascaramiento de PII

`macros/hash_pii.sql` — `SHA256(valor || salt)`, irreversible. El valor
original **no se conserva** en Silver ni en capas posteriores: el perfil
Analista no puede acceder a él ni siquiera con un permiso de lectura mal
configurado (defensa adicional a los controles de IAM de Fase 5). El salt
es una variable de dbt (`pii_salt`), no un secreto de producción — en un
entorno real vendría de Secret Manager.
