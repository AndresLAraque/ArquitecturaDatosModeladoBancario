-- Test singular: ningún movimiento en Silver debe tener vr_mov <= 0
-- (la anomalía intencional de Fase 1 debe haber sido filtrada).
select *
from {{ ref('stg_movimientos') }}
where vr_mov <= 0
