-- Reporte de calidad de datos de la corrida de Silver (requisito explícito
-- de Fase 3): % de nulos por columna, registros rechazados y % de
-- registros conformes por tabla. Formato largo (tabla, métrica, valor)
-- para que una sola tabla sirva de reporte de todas las tablas fuente.

with totales as (
    select 'TB_CLIENTES_CORE' as tabla, count(*) as filas_totales from {{ source('bronze_raw','raw_tb_clientes_core') }}
    union all select 'TB_PRODUCTOS_CAT', count(*) from {{ source('bronze_raw','raw_tb_productos_cat') }}
    union all select 'TB_SUCURSALES_RED', count(*) from {{ source('bronze_raw','raw_tb_sucursales_red') }}
    union all select 'TB_MOV_FINANCIEROS', count(*) from {{ source('bronze_raw','raw_tb_mov_financieros') }}
    union all select 'TB_OBLIGACIONES', count(*) from {{ source('bronze_raw','raw_tb_obligaciones') }}
    union all select 'TB_COMISIONES_LOG', count(*) from {{ source('bronze_raw','raw_tb_comisiones_log') }}
),

rechazadas as (
    select tabla, count(distinct id_registro) as filas_rechazadas
    from {{ ref('err_calidad_datos') }}
    group by tabla
),

resumen as (
    select
        t.tabla,
        t.filas_totales,
        coalesce(r.filas_rechazadas, 0) as filas_rechazadas,
        round(100 - safe_divide(coalesce(r.filas_rechazadas, 0), t.filas_totales) * 100, 2) as pct_conformes
    from totales t
    left join rechazadas r using (tabla)
),

nulos as (
    select 'TB_CLIENTES_CORE.score_buro' as columna, round(safe_divide(countif(score_buro is null), count(*)) * 100, 2) as pct_nulos
    from {{ source('bronze_raw', 'raw_tb_clientes_core') }}
    union all
    select 'TB_CLIENTES_CORE.ciudad_res', round(safe_divide(countif(ciudad_res is null), count(*)) * 100, 2)
    from {{ source('bronze_raw', 'raw_tb_clientes_core') }}
    union all
    select 'TB_CLIENTES_CORE.canal_adquis', round(safe_divide(countif(canal_adquis is null), count(*)) * 100, 2)
    from {{ source('bronze_raw', 'raw_tb_clientes_core') }}
    union all
    select 'TB_PRODUCTOS_CAT.comision_admin', round(safe_divide(countif(comision_admin is null), count(*)) * 100, 2)
    from {{ source('bronze_raw', 'raw_tb_productos_cat') }}
    union all
    select 'TB_SUCURSALES_RED.latitud', round(safe_divide(countif(latitud is null), count(*)) * 100, 2)
    from {{ source('bronze_raw', 'raw_tb_sucursales_red') }}
    union all
    select 'TB_MOV_FINANCIEROS.id_dispositivo', round(safe_divide(countif(id_dispositivo is null), count(*)) * 100, 2)
    from {{ source('bronze_raw', 'raw_tb_mov_financieros') }}
    union all
    select 'TB_MOV_FINANCIEROS.cod_ciudad', round(safe_divide(countif(cod_ciudad is null), count(*)) * 100, 2)
    from {{ source('bronze_raw', 'raw_tb_mov_financieros') }}
    union all
    select 'TB_OBLIGACIONES.num_cuotas_pend', round(safe_divide(countif(num_cuotas_pend is null), count(*)) * 100, 2)
    from {{ source('bronze_raw', 'raw_tb_obligaciones') }}
    union all
    select 'TB_COMISIONES_LOG.tip_comision', round(safe_divide(countif(tip_comision is null), count(*)) * 100, 2)
    from {{ source('bronze_raw', 'raw_tb_comisiones_log') }}
)

select tabla, 'filas_totales' as metrica, cast(filas_totales as numeric) as valor, current_timestamp() as corrida_ts
from resumen
union all
select tabla, 'filas_rechazadas', cast(filas_rechazadas as numeric), current_timestamp()
from resumen
union all
select tabla, 'pct_conformes', cast(pct_conformes as numeric), current_timestamp()
from resumen
union all
select columna as tabla, 'pct_nulos', cast(pct_nulos as numeric), current_timestamp()
from nulos
