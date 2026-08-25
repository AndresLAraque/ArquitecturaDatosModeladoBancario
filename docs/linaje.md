# Linaje de campos calculados — Capa Gold

Documentación manual de linaje (requisito explícito de Fase 3/5) para los
campos calculados más relevantes del modelo Gold. `dbt docs generate`
también produce un grafo de linaje automático a partir de los `ref()`/
`source()` de cada modelo — este documento complementa esa vista con el
"por qué" de negocio detrás de cada cálculo.

| Campo calculado | Tabla destino | Tabla(s) origen | Transformación | Propósito de negocio |
|---|---|---|---|---|
| `edad` | `dim_clientes` | `TB_CLIENTES_CORE.fec_nac` | `DATE_DIFF(CURRENT_DATE(), fec_nac, YEAR)` | Segmentación demográfica para análisis de riesgo y oferta comercial |
| `segmento_desc` | `dim_clientes` | `TB_CLIENTES_CORE.cod_segmento` | Mapeo de código (`BAS`/`STD`/`PRM`/`ELT`) a etiqueta legible | Legibilidad en dashboards y reportes para negocio, sin exponer códigos internos |
| `tasa_mensual_equivalente` | `dim_productos` | `TB_PRODUCTOS_CAT.tasa_ea` | `(POWER(1 + tasa_ea/100, 1/12) - 1) * 100` — conversión financiera estándar de tasa efectiva anual a mensual | Comparabilidad de tasas entre productos con distinta periodicidad de cobro; insumo de `fact_rentabilidad_cliente` |
| `vr_mov_usd` | `fact_transacciones` | `TB_MOV_FINANCIEROS.vr_mov` | `vr_mov / 4050.0` (tasa fija documentada, misma constante que el generador sintético) | Reportería consolidada multi-país en una sola moneda (el banco opera en 5 países con monedas distintas, pero las transacciones sintéticas se generan en COP) |
| `horario_habil` | `fact_transacciones` | `TB_MOV_FINANCIEROS.fec_mov`, `hra_mov` | `TRUE` si lunes-viernes y hora entre 7am-8pm | Insumo para el motor de fraude: transacciones fuera de horario hábil son una señal de riesgo adicional |
| `ind_sospechoso` | `stg_movimientos` (Silver) → propagado a `fact_transacciones` | `TB_MOV_FINANCIEROS.vr_mov`, ventana móvil 30 días por cliente | `vr_mov > promedio_móvil_30d + 3 × desviación_estándar_móvil_30d` | Señal de comportamiento atípico para el motor de prevención de fraude (regla de negocio explícita del enunciado) |
| `bucket_mora` | `fact_cartera` | `TB_OBLIGACIONES.dias_mora_act` | 5 rangos: Al día (0) / Rango 1 (1-30) / Rango 2 (31-60) / Rango 3 (61-90) / Deteriorado (>90) | Segmentación estándar de mora para seguimiento de cartera del equipo de Riesgo |
| `calif_regulatoria` | `fact_cartera` | `fact_cartera.bucket_mora` | Mapeo bucket_mora → categoría A-E | Insumo para el cálculo de provisiones regulatorias exigidas por la Superintendencia Financiera |
| `provision_estimada` | `fact_cartera` | `fact_cartera.sdo_capital`, `calif_regulatoria` | `sdo_capital × provision_pct` (tabla simplificada por categoría A-E, documentada como supuesto en el propio modelo) | Estimación del monto que el banco debe provisionar contablemente por riesgo de no pago |
| `ingreso_intereses` | `fact_rentabilidad_cliente` | `TB_MOV_FINANCIEROS` (avances/compras en productos de crédito) × `dim_productos.tasa_mensual_equivalente` | Suma de `vr_mov × tasa_mensual_equivalente` para movimientos de crédito, por cliente y mes | Aproximación del interés generado por cliente (supuesto documentado: el esquema fuente no registra "interés cobrado" como transacción explícita) |
| `cltv_12m` | `fact_rentabilidad_cliente` | `fact_rentabilidad_cliente.ingreso_total` | Suma móvil de 12 periodos mensuales (`SUM() OVER (... ROWS BETWEEN 11 PRECEDING AND CURRENT ROW)`) | Customer Lifetime Value — insumo para decisiones comerciales de oferta y retención |

## Cómo regenerar el linaje automático de dbt

```bash
cd pipelines/dbt_finbank
dbt docs generate --profiles-dir .
dbt docs serve --profiles-dir .
```

Esto abre un explorador interactivo con el DAG completo (`source` → `stg_*`
→ `dim_*`/`fact_*`) y la documentación de cada columna definida en los
`.yml` de `models/staging/` y `models/marts/`.
