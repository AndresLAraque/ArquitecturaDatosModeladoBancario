-- Gold: TB_SUCURSALES_RED -> dim_canal
--
-- Unifica dos conceptos que en las tablas fuente viven en columnas
-- distintas: tip_punto (TB_SUCURSALES_RED: OFICINA/CAJERO/CORRESPONSAL,
-- puntos físicos) y cod_canal (TB_MOV_FINANCIEROS: APP/WEB/CORRESPONSAL,
-- canal usado en la transacción) — el enunciado pide expresamente
-- "dim_canal con tipo de punto de atención y canal digital" en una sola
-- dimensión. fact_transacciones.cod_canal referencia esta tabla.

select * from unnest([
    struct('APP' as cod_canal, 'Aplicación móvil' as desc_canal, 'DIGITAL' as tipo_canal),
    struct('WEB', 'Portal web', 'DIGITAL'),
    struct('CORRESPONSAL', 'Corresponsal bancario', 'FISICO'),
    struct('OFICINA', 'Oficina', 'FISICO'),
    struct('CAJERO', 'Cajero automático', 'FISICO')
])
