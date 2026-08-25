-- Silver: TB_MOV_FINANCIEROS -> stg_movimientos
--
-- 1) Dedup exacto sobre las columnas de NEGOCIO (no las de auditoría —
--    ingestion_ts/batch_id pueden diferir legítimamente entre corridas sin
--    que la transacción deje de ser un duplicado real).
-- 2) Excluye: fechas fuera de rango, montos <= 0 (anomalías intencionales
--    de Fase 1) y filas con FK huérfana — todo lo excluido queda
--    registrado en err_calidad_datos con su motivo.
-- 3) Calcula ind_sospechoso ANTES de Gold (regla de negocio explícita del
--    enunciado): vr_mov supera en más de 3 desviaciones estándar el
--    promedio móvil de los 30 días previos del mismo cliente.
--    NOTA (observación honesta, ver docs/evidencia/fase3-silver/): esto
--    marca ~7.5% de las transacciones, más de lo típico para "3 sigma".
--    El promedio/desviación es POR CLIENTE mezclando todos los tip_mov —
--    un cliente que alterna recargas pequeñas con avances grandes genera
--    una media "mixta" que hace ver atípica una transacción normal para
--    su tipo. Es una lectura fiel a la regla tal como está escrita (no
--    pide segmentar por tipo); segmentar por (id_cli, tip_mov) sería una
--    mejora razonable a futuro para bajar falsos positivos.

with numerado as (
    select
        *,
        -- vr_mov (FLOAT64) queda fuera del PARTITION BY a propósito: BigQuery
        -- no permite particionar funciones de ventana por tipos de punto
        -- flotante (igualdad de FLOAT64 no es confiable, ej. NaN). El resto
        -- de columnas ya forman una clave de negocio más que suficiente para
        -- detectar el duplicado exacto inyectado en Fase 1.
        row_number() over (
            partition by id_mov, id_cli, cod_prod, num_cuenta, fec_mov, hra_mov,
                         tip_mov, cod_canal, cod_estado_mov
            order by ingestion_ts
        ) as rn
    from {{ source('bronze_raw', 'raw_tb_mov_financieros') }}
),

dedup as (
    select * except(rn) from numerado where rn = 1
),

filtrado as (
    select *
    from dedup
    where id_mov is not null
      and fec_mov between date('2015-01-01') and current_date()
      and vr_mov > 0
),

fk_valido as (
    select f.*
    from filtrado f
    inner join {{ ref('stg_clientes') }} c on f.id_cli = c.id_cli
    inner join {{ ref('stg_productos') }} p on f.cod_prod = p.cod_prod
),

con_estadisticas as (
    -- BigQuery exige que la clave de ORDER BY de un RANGE con offset
    -- numérico (N PRECEDING) sea numérica, no DATE directamente — de ahí
    -- unix_date(fec_mov) (días desde época) en vez de "RANGE INTERVAL 30 DAY".
    select
        *,
        avg(vr_mov) over (
            partition by id_cli order by unix_date(fec_mov)
            range between 30 preceding and 1 preceding
        ) as promedio_movil_30d,
        stddev(vr_mov) over (
            partition by id_cli order by unix_date(fec_mov)
            range between 30 preceding and 1 preceding
        ) as stddev_movil_30d
    from fk_valido
)

select
    id_mov,
    id_cli,
    cod_prod,
    num_cuenta,
    fec_mov,
    cast(hra_mov as time) as hra_mov,
    vr_mov,
    tip_mov,
    cod_canal,
    coalesce(cod_ciudad, 'DESCONOCIDA') as cod_ciudad,
    cod_ciudad is null as cod_ciudad_imputada,
    cod_estado_mov,
    id_dispositivo,
    id_dispositivo is null as sin_dispositivo_registrado,
    promedio_movil_30d,
    stddev_movil_30d,
    case
        when stddev_movil_30d is not null and stddev_movil_30d > 0
             and vr_mov > promedio_movil_30d + 3 * stddev_movil_30d
        then true
        else false
    end as ind_sospechoso,
    ingestion_ts,
    source_system,
    batch_id
from con_estadisticas
