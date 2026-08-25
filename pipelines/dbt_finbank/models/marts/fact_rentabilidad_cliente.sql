-- Gold: TB_COMISIONES_LOG + TB_MOV_FINANCIEROS -> fact_rentabilidad_cliente
-- Grano: (id_cli, periodo mensual)
--
-- Regla de negocio explícita: "ingreso total = intereses + comisiones";
-- "CLTV = suma histórica de 12 meses calendario".
--
-- Supuesto documentado sobre "ingresos por intereses": el esquema fuente
-- no tiene una transacción de tipo "interés" explícita (TB_MOV_FINANCIEROS
-- registra pagos/transferencias/recargas/avances, no intereses cobrados
-- como línea aparte). Se aproxima el interés generado por cliente y
-- periodo aplicando la tasa mensual equivalente del producto (calculada en
-- dim_productos) sobre el volumen de movimientos de tipo avance de
-- efectivo / compra con tarjeta en productos de la familia CRÉDITO — son
-- los movimientos que generan interés real para el banco en un producto
-- de crédito. En un entorno real este valor vendría de una tabla contable
-- de intereses causados, no aproximado desde transacciones.

with intereses as (
    select
        m.id_cli,
        format_date('%Y-%m', m.fec_mov) as periodo,
        sum(m.vr_mov * (p.tasa_mensual_equivalente / 100)) as ingreso_intereses
    from {{ ref('stg_movimientos') }} m
    inner join {{ ref('dim_productos') }} p on m.cod_prod = p.cod_prod
    where p.familia_producto = 'CREDITO'
      and m.tip_mov in ('AVANCE_EFECTIVO', 'COMPRA_TARJETA')
    group by 1, 2
),

comisiones as (
    select
        id_cli,
        format_date('%Y-%m', fec_cobro) as periodo,
        sum(vr_comision) as ingreso_comisiones
    from {{ ref('stg_comisiones') }}
    where estado_cobro = 'EXITOSO'
    group by 1, 2
),

combinado as (
    select
        coalesce(i.id_cli, c.id_cli) as id_cli,
        coalesce(i.periodo, c.periodo) as periodo,
        coalesce(i.ingreso_intereses, 0) as ingreso_intereses,
        coalesce(c.ingreso_comisiones, 0) as ingreso_comisiones
    from intereses i
    full outer join comisiones c on i.id_cli = c.id_cli and i.periodo = c.periodo
)

select
    id_cli,
    periodo,
    round(ingreso_intereses, 2) as ingreso_intereses,
    round(ingreso_comisiones, 2) as ingreso_comisiones,
    round(ingreso_intereses + ingreso_comisiones, 2) as ingreso_total,
    -- CLTV: suma de ingreso_total de los últimos 12 periodos mensuales
    -- (incluido el actual) del mismo cliente.
    round(sum(ingreso_intereses + ingreso_comisiones) over (
        partition by id_cli order by periodo
        rows between 11 preceding and current row
    ), 2) as cltv_12m
from combinado
