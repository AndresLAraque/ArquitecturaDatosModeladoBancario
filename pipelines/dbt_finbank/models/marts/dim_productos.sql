-- Gold: TB_PRODUCTOS_CAT -> dim_productos
-- Transformaciones clave (regla de negocio explícita del enunciado):
--   - Renombrar campos a nombres de negocio
--   - Calcular tasa mensual equivalente desde tasa_ea
--   - Clasificar en familia: crédito, ahorro o transaccional

select
    cod_prod,
    desc_prod as nombre_producto,
    tip_prod as tipo_producto,
    case
        when tip_prod in ('CRED_LIBRE_INVERSION', 'CRED_ROTATIVO', 'TARJETA_DIGITAL') then 'CREDITO'
        when tip_prod = 'CUENTA_AHORRO_DIGITAL' then 'AHORRO'
        else 'TRANSACCIONAL'
    end as familia_producto,
    tasa_ea as tasa_efectiva_anual,
    -- tasa mensual equivalente: (1 + tasa_ea)^(1/12) - 1, la conversión
    -- financiera estándar de una tasa efectiva anual a su equivalente mensual.
    round((power(1 + tasa_ea / 100, 1.0 / 12) - 1) * 100, 4) as tasa_mensual_equivalente,
    plazo_max_meses as plazo_maximo_meses,
    es_plazo_aplicable,
    cuota_min as cuota_minima,
    comision_admin as comision_administracion,
    estado_prod as estado_producto,
    ingestion_ts,
    source_system,
    batch_id
from {{ ref('stg_productos') }}
