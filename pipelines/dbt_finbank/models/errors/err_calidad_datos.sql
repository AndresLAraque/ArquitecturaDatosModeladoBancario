-- Tabla de errores del pipeline (requisito transversal de Fase 3 +
-- integridad referencial explícita de Silver). Une los distintos motivos
-- de rechazo detectados al construir cada modelo staging, para que quede
-- un registro auditable de qué se excluyó y por qué — sin necesidad de
-- adivinar comparando conteos entre Bronze y Silver.

with mov_fk_huerfana as (
    select
        'TB_MOV_FINANCIEROS' as tabla, m.id_mov as id_registro,
        'FK_HUERFANA' as tipo_error,
        concat('id_cli=', m.id_cli, ' o cod_prod=', m.cod_prod, ' no existen en las dimensiones') as motivo
    from {{ source('bronze_raw', 'raw_tb_mov_financieros') }} m
    where not exists (select 1 from {{ ref('stg_clientes') }} c where c.id_cli = m.id_cli)
       or not exists (select 1 from {{ ref('stg_productos') }} p where p.cod_prod = m.cod_prod)
),

mov_fecha_invalida as (
    select
        'TB_MOV_FINANCIEROS' as tabla, id_mov as id_registro,
        'FECHA_FUERA_DE_RANGO' as tipo_error,
        concat('fec_mov=', cast(fec_mov as string), ' fuera del rango válido') as motivo
    from {{ source('bronze_raw', 'raw_tb_mov_financieros') }}
    where fec_mov not between date('2015-01-01') and current_date()
),

mov_monto_invalido as (
    select
        'TB_MOV_FINANCIEROS' as tabla, id_mov as id_registro,
        'CAMPO_INCONSISTENTE' as tipo_error,
        concat('vr_mov=', cast(vr_mov as string), ' (monto inválido)') as motivo
    from {{ source('bronze_raw', 'raw_tb_mov_financieros') }}
    where vr_mov <= 0
),

oblig_fk_huerfana as (
    select
        'TB_OBLIGACIONES' as tabla, o.id_oblig as id_registro,
        'FK_HUERFANA' as tipo_error,
        concat('id_cli=', o.id_cli, ' o cod_prod=', o.cod_prod, ' no existen en las dimensiones') as motivo
    from {{ source('bronze_raw', 'raw_tb_obligaciones') }} o
    where not exists (select 1 from {{ ref('stg_clientes') }} c where c.id_cli = o.id_cli)
       or not exists (select 1 from {{ ref('stg_productos') }} p where p.cod_prod = o.cod_prod)
),

oblig_saldo_inconsistente as (
    select
        'TB_OBLIGACIONES' as tabla, id_oblig as id_registro,
        'CAMPO_INCONSISTENTE' as tipo_error,
        concat('sdo_capital=', cast(sdo_capital as string), ' > vr_aprobado=', cast(vr_aprobado as string)) as motivo
    from {{ source('bronze_raw', 'raw_tb_obligaciones') }}
    where sdo_capital > vr_aprobado * 1.05
),

oblig_fecha_invalida as (
    select
        'TB_OBLIGACIONES' as tabla, id_oblig as id_registro,
        'FECHA_FUERA_DE_RANGO' as tipo_error,
        concat('fec_desembolso=', cast(fec_desembolso as string), ' fuera del rango válido') as motivo
    from {{ source('bronze_raw', 'raw_tb_obligaciones') }}
    where fec_desembolso not between date('2015-01-01') and current_date()
),

com_fk_huerfana as (
    select
        'TB_COMISIONES_LOG' as tabla, co.id_comision as id_registro,
        'FK_HUERFANA' as tipo_error,
        concat('id_cli=', co.id_cli, ' o cod_prod=', co.cod_prod, ' no existen en las dimensiones') as motivo
    from {{ source('bronze_raw', 'raw_tb_comisiones_log') }} co
    where not exists (select 1 from {{ ref('stg_clientes') }} c where c.id_cli = co.id_cli)
       or not exists (select 1 from {{ ref('stg_productos') }} p where p.cod_prod = co.cod_prod)
)

select tabla, id_registro, tipo_error, motivo, current_timestamp() as fecha_deteccion from mov_fk_huerfana
union all
select tabla, id_registro, tipo_error, motivo, current_timestamp() from mov_fecha_invalida
union all
select tabla, id_registro, tipo_error, motivo, current_timestamp() from mov_monto_invalido
union all
select tabla, id_registro, tipo_error, motivo, current_timestamp() from oblig_fk_huerfana
union all
select tabla, id_registro, tipo_error, motivo, current_timestamp() from oblig_saldo_inconsistente
union all
select tabla, id_registro, tipo_error, motivo, current_timestamp() from oblig_fecha_invalida
union all
select tabla, id_registro, tipo_error, motivo, current_timestamp() from com_fk_huerfana
