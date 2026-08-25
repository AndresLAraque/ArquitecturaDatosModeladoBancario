-- Gold: TB_OBLIGACIONES -> fact_cartera
-- Reglas de negocio explícitas del enunciado:
--   - bucket_mora en 5 rangos a partir de dias_mora_act
--   - Clasificación regulatoria A/B/C/D/E
--   - Provisión estimada según tabla regulatoria
--
-- Supuesto documentado: el enunciado no fija los % de provisión exactos
-- ("según tabla regulatoria"), así que se usa una tabla simplificada
-- inspirada en el modelo de provisión de cartera de consumo de la
-- Superintendencia Financiera de Colombia (categorías A-E). No son los
-- porcentajes oficiales exactos — en un entorno real este mapeo vendría
-- parametrizado desde una tabla regulatoria versionada, no hardcodeado.

{{ config(
    partition_by={'field': 'fec_desembolso', 'data_type': 'date'},
    cluster_by=['calif_regulatoria', 'cod_prod']
) }}

with clasificado as (
    select
        *,
        case
            when dias_mora_act = 0 then 'Al día'
            when dias_mora_act between 1 and 30 then 'Rango 1'
            when dias_mora_act between 31 and 60 then 'Rango 2'
            when dias_mora_act between 61 and 90 then 'Rango 3'
            else 'Deteriorado'
        end as bucket_mora
    from {{ ref('stg_obligaciones') }}
),

con_calificacion as (
    select
        *,
        case bucket_mora
            when 'Al día' then 'A'
            when 'Rango 1' then 'B'
            when 'Rango 2' then 'C'
            when 'Rango 3' then 'D'
            else 'E'
        end as calif_regulatoria
    from clasificado
),

con_provision as (
    select
        *,
        case calif_regulatoria
            when 'A' then 0.01
            when 'B' then 0.032
            when 'C' then 0.10
            when 'D' then 0.20
            else 1.00
        end as provision_pct
    from con_calificacion
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
    bucket_mora,
    calif_regulatoria,
    calif_riesgo as calif_riesgo_fuente,  -- calificación cruda del origen, para comparar
    provision_pct,
    round(sdo_capital * provision_pct, 2) as provision_estimada,
    num_cuotas_pend,
    num_cuotas_pend_es_nulo,
    ingestion_ts,
    source_system,
    batch_id
from con_provision
