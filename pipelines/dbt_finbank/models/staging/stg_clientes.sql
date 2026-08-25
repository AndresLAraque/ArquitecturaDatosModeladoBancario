-- Silver: TB_CLIENTES_CORE -> stg_clientes
--
-- Enmascaramiento PII (requisito explícito): nomb_cli, apell_cli y num_doc
-- quedan SOLO como hash desde esta capa en adelante — el valor original no
-- se conserva, así que el perfil Analista jamás puede acceder a él (ver
-- macro hash_pii.sql y Fase 5).
--
-- Estrategia de nulos:
--   score_buro NULL -> se conserva NULL + indicador binario (imputar un
--     score falso distorsionaría cualquier modelo de riesgo aguas abajo).
--   ciudad_res / canal_adquis NULL -> imputación con valor por defecto
--     ('DESCONOCIDA' / 'NO_REGISTRADO'): son campos descriptivos de baja
--     sensibilidad analítica, un valor centinela es preferible a perder
--     el registro completo.
--   num_doc / fec_nac NULL -> exclusión del registro (campos obligatorios
--     para identificar y segmentar al cliente; sin ellos el registro no
--     es utilizable en Silver/Gold).

with dedup as (
    select distinct * from {{ source('bronze_raw', 'raw_tb_clientes_core') }}
)

select
    id_cli,
    {{ hash_pii('nomb_cli') }} as nomb_cli_hash,
    {{ hash_pii('apell_cli') }} as apell_cli_hash,
    tip_doc,
    {{ hash_pii('num_doc') }} as num_doc_hash,
    cast(fec_nac as date) as fec_nac,
    cast(fec_alta as date) as fec_alta,
    cod_segmento,
    score_buro,
    score_buro is null as score_buro_es_nulo,
    coalesce(ciudad_res, 'DESCONOCIDA') as ciudad_res,
    ciudad_res is null as ciudad_res_imputada,
    depto_res,
    estado_cli,
    coalesce(canal_adquis, 'NO_REGISTRADO') as canal_adquis,
    ingestion_ts,
    source_system,
    batch_id
from dedup
where id_cli is not null
  and num_doc is not null
  and fec_nac is not null
