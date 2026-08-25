-- Silver: TB_OBLIGACIONES -> stg_obligaciones
--
-- Excluye: fechas fuera de rango y sdo_capital > vr_aprobado (con 5% de
-- tolerancia por intereses/mora capitalizada legítimos — el anómalo
-- inyectado en Fase 1 excede eso por mucho). Todo lo excluido queda en
-- err_calidad_datos.
--
-- Estrategia de nulos: num_cuotas_pend NULL -> se conserva NULL + indicador
-- binario (imputar 0 sugeriría "obligación pagada", que sería incorrecto).

with dedup as (
    select distinct * from {{ source('bronze_raw', 'raw_tb_obligaciones') }}
),

filtrado as (
    select *
    from dedup
    where id_oblig is not null
      and fec_desembolso between date('2015-01-01') and current_date()
      and sdo_capital <= vr_aprobado * 1.05
),

fk_valido as (
    select f.*
    from filtrado f
    inner join {{ ref('stg_clientes') }} c on f.id_cli = c.id_cli
    inner join {{ ref('stg_productos') }} p on f.cod_prod = p.cod_prod
)

select
    id_oblig,
    id_cli,
    cod_prod,
    vr_aprobado,
    vr_desembolsado,
    sdo_capital,
    vr_cuota,
    fec_desembolso,
    fec_venc,
    dias_mora_act,
    num_cuotas_pend,
    num_cuotas_pend is null as num_cuotas_pend_es_nulo,
    calif_riesgo,
    ingestion_ts,
    source_system,
    batch_id
from fk_valido
