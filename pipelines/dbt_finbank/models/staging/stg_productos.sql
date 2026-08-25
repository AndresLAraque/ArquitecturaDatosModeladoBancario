-- Silver: TB_PRODUCTOS_CAT -> stg_productos
--
-- Estrategia de nulos (documentada en README.md):
--   plazo_max_meses NULL es ESTRUCTURAL (producto revolvente/transaccional,
--   no aplica plazo fijo) -> se conserva NULL, se marca con indicador
--   binario (no se imputa: imputar un plazo falso sería incorrecto).
--   comision_admin NULL es calidad de dato -> se imputa 0 (valor por
--   defecto razonable: ausencia de dato de comisión se interpreta como
--   "no cobra", no como desconocido).

with dedup as (
    select distinct * from {{ source('bronze_raw', 'raw_tb_productos_cat') }}
)

select
    cod_prod,
    desc_prod,
    tip_prod,
    cast(tasa_ea as numeric) as tasa_ea,
    plazo_max_meses,
    plazo_max_meses is not null as es_plazo_aplicable,
    cast(cuota_min as numeric) as cuota_min,
    coalesce(cast(comision_admin as numeric), 0) as comision_admin,
    comision_admin is null as comision_admin_imputada,
    estado_prod,
    ingestion_ts,
    source_system,
    batch_id
from dedup
where cod_prod is not null  -- exclusión: PK nula es campo obligatorio corrompido
