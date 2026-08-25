-- Silver: TB_SUCURSALES_RED -> stg_sucursales
--
-- Estrategia de nulos: latitud/longitud NULL -> se conservan NULL (imputar
-- una coordenada falsa sería engañoso para cualquier análisis geográfico)
-- + indicador binario tiene_geolocalizacion.

with dedup as (
    select distinct * from {{ source('bronze_raw', 'raw_tb_sucursales_red') }}
)

select
    cod_suc,
    nom_suc,
    tip_punto,
    ciudad,
    depto,
    latitud,
    longitud,
    latitud is not null and longitud is not null as tiene_geolocalizacion,
    activo,
    ingestion_ts,
    source_system,
    batch_id
from dedup
where cod_suc is not null
