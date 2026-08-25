-- Gold: tabla de KPIs ejecutivos — cartera diaria
-- Regla de negocio explícita: agregar por fecha, producto, segmento y
-- ciudad: total de obligaciones activas, monto total de cartera, monto en
-- mora, tasa de mora (%) y clientes con alguna obligación en mora.
--
-- Materialización incremental a propósito: esta es una "periodic snapshot
-- fact table" (patrón Kimball) — cada corrida diaria del pipeline agrega
-- una fila por (fecha_corte, producto, segmento, ciudad) con el estado de
-- la cartera EN ESE MOMENTO. Sin `incremental` + `unique_key`, un `dbt run`
-- en modo `table` sobreescribiría el historial completo en cada corrida y
-- se perdería la serie de tiempo que el propio nombre "KPI diario" implica.

{{ config(
    materialized='incremental',
    unique_key=['fecha_corte', 'cod_prod', 'cod_segmento', 'ciudad'],
    partition_by={'field': 'fecha_corte', 'data_type': 'date'},
    cluster_by=['cod_prod', 'cod_segmento']
) }}

select
    current_date() as fecha_corte,
    c.cod_prod,
    cl.cod_segmento,
    cl.ciudad_res as ciudad,
    count(distinct c.id_oblig) as total_obligaciones_activas,
    round(sum(c.sdo_capital), 2) as monto_total_cartera,
    round(sum(case when c.dias_mora_act > 0 then c.sdo_capital else 0 end), 2) as monto_en_mora,
    round(safe_divide(
        sum(case when c.dias_mora_act > 0 then c.sdo_capital else 0 end),
        sum(c.sdo_capital)
    ) * 100, 2) as tasa_mora_pct,
    count(distinct case when c.dias_mora_act > 0 then c.id_cli end) as clientes_con_mora
from {{ ref('fact_cartera') }} c
inner join {{ ref('dim_clientes') }} cl on c.id_cli = cl.id_cli
group by 1, 2, 3, 4
