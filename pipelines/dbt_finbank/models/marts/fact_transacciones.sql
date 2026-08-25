-- Gold: TB_MOV_FINANCIEROS -> fact_transacciones
-- Transformaciones clave (regla de negocio explícita del enunciado):
--   - id_cli validado contra dim_clientes (ya garantizado desde Silver —
--     stg_movimientos solo contiene FKs válidas, ver err_calidad_datos)
--   - Monto en USD desde COP
--   - Flag de horario (hábil / no hábil)
--   - Promedio móvil de 30 días (ya calculado en Silver junto con
--     ind_sospechoso — se propaga, no se recalcula, para no duplicar lógica)

{{ config(
    partition_by={'field': 'fec_mov', 'data_type': 'date'},
    cluster_by=['cod_prod', 'cod_canal']
) }}

-- Tasa de cambio fija y documentada (misma constante que
-- data-generation/reference_data.py:USD_COP_RATE, para que el dato
-- sintético y la conversión de Gold sean consistentes). En producción
-- vendría de un servicio de tasas, no de una constante.
select
    m.id_mov,
    m.id_cli,
    m.cod_prod,
    p.familia_producto,
    m.num_cuenta,
    m.fec_mov,
    m.hra_mov,
    m.vr_mov,
    round(m.vr_mov / 4050.0, 2) as vr_mov_usd,
    m.tip_mov,
    m.cod_canal,
    m.cod_ciudad,
    -- horario hábil bancario: lunes(2) a viernes(6), 7am-9pm
    (extract(dayofweek from m.fec_mov) between 2 and 6
        and extract(hour from m.hra_mov) between 7 and 20) as horario_habil,
    m.cod_estado_mov,
    m.promedio_movil_30d,
    m.stddev_movil_30d,
    m.ind_sospechoso,
    m.ingestion_ts,
    m.source_system,
    m.batch_id
from {{ ref('stg_movimientos') }} m
inner join {{ ref('dim_productos') }} p on m.cod_prod = p.cod_prod
