-- Gold: TB_CLIENTES_CORE -> dim_clientes
-- Transformaciones clave (regla de negocio explícita del enunciado):
--   - Unificar nombre completo desde nomb_cli + apell_cli (ya hasheados en
--     Silver por PII — se concatenan los hashes, el resultado sigue sin
--     ser reversible a datos personales reales)
--   - Calcular edad desde fec_nac
--   - Mapear cod_segmento a etiqueta legible

select
    id_cli,
    concat(nomb_cli_hash, '|', apell_cli_hash) as nombre_completo_hash,
    tip_doc,
    num_doc_hash,
    fec_nac,
    date_diff(current_date(), fec_nac, year) as edad,
    fec_alta,
    cod_segmento,
    case cod_segmento
        when 'BAS' then 'Básico'
        when 'STD' then 'Estándar'
        when 'PRM' then 'Premium'
        when 'ELT' then 'Elite'
        else 'Sin clasificar'
    end as segmento_desc,
    score_buro,
    score_buro_es_nulo,
    ciudad_res,
    depto_res,
    estado_cli,
    canal_adquis,
    ingestion_ts,
    source_system,
    batch_id
from {{ ref('stg_clientes') }}
