-- Test singular: dias_mora_act nunca debe ser negativo en Silver.
select *
from {{ ref('stg_obligaciones') }}
where dias_mora_act < 0
