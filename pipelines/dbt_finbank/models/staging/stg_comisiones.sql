-- Silver: TB_COMISIONES_LOG -> stg_comisiones
--
-- Estrategia de nulos: tip_comision NULL -> imputación con valor por
-- defecto ('SIN_CLASIFICAR') — es un campo descriptivo de baja
-- sensibilidad, no justifica excluir la comisión del cálculo de CLTV.

with dedup as (
    select distinct * from {{ source('bronze_raw', 'raw_tb_comisiones_log') }}
),

filtrado as (
    select * from dedup where id_comision is not null
),

fk_valido as (
    select f.*
    from filtrado f
    inner join {{ ref('stg_clientes') }} c on f.id_cli = c.id_cli
    inner join {{ ref('stg_productos') }} p on f.cod_prod = p.cod_prod
)

select
    id_comision,
    id_cli,
    cod_prod,
    cast(fec_cobro as date) as fec_cobro,
    vr_comision,
    coalesce(tip_comision, 'SIN_CLASIFICAR') as tip_comision,
    tip_comision is null as tip_comision_imputado,
    estado_cobro,
    ingestion_ts,
    source_system,
    batch_id
from fk_valido
