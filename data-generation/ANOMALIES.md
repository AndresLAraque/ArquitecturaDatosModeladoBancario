# Anomalías intencionales del dataset sintético

El generador (`main.py` + `anomalies.py`) construye primero un dataset
100% íntegro (toda FK válida, sin duplicados) y **después** inyecta, de
forma controlada y medible, las siguientes 4 anomalías — una más del
mínimo de 3 exigido por el enunciado. Los porcentajes son parámetros de
`config.yaml:anomalies` (reproducibles con la semilla fija).

Cada fila afectada queda registrada en `output/anomalies_log.csv` con la
tabla, el identificador del registro, el tipo de anomalía y el motivo —
esto es lo que la capa Silver del pipeline debe poder detectar y manejar
explícitamente (ver Fase 3).

| # | Anomalía | Tablas afectadas | % configurado | Cómo debe reaccionar Silver |
|---|---|---|---|---|
| 1 | **Duplicados exactos** — la fila completa (misma PK `id_mov`) aparece dos veces, simulando un reintento de ingesta sin idempotencia | `TB_MOV_FINANCIEROS` | `duplicados_exactos_pct` (0.3%) | Eliminar duplicados exactos (requisito explícito de Silver) |
| 2 | **Fechas fuera de rango** — la mitad de los casos con fecha futura (posterior a la ventana de carga, ej. error de reloj del origen), la otra mitad con fecha anterior a la fundación del banco (2015-01-01, ej. error de migración) | `TB_MOV_FINANCIEROS` (`fec_mov`), `TB_OBLIGACIONES` (`fec_desembolso`) | `fechas_fuera_rango_pct` (0.2%) | Rechazar o marcar el registro; documentar el motivo en el reporte de calidad |
| 3 | **Llave foránea huérfana** — `id_cli` con formato válido (`CLI9xxxxx`) pero que no existe en `TB_CLIENTES_CORE`, ej. cliente eliminado en origen sin borrado en cascada | `TB_MOV_FINANCIEROS`, `TB_COMISIONES_LOG` (`id_cli`) | `fk_huerfana_pct` (0.15%) | Enviar a la tabla de errores de integridad referencial con el motivo (requisito explícito de Silver) |
| 4 | **Campos inconsistentes** — `vr_mov` negativo en `TB_MOV_FINANCIEROS` (signo inválido); `sdo_capital > vr_aprobado` en `TB_OBLIGACIONES` (imposible en negocio) | `TB_MOV_FINANCIEROS`, `TB_OBLIGACIONES` | `campos_inconsistentes_pct` (0.2%) | Aplicar la estrategia de manejo de nulos/errores documentada; excluir o corregir según la regla definida |

## Por qué NO se declaran Foreign Keys en `schema.sql`

`TB_MOV_FINANCIEROS` y `TB_COMISIONES_LOG` se cargan en la base origen
**sin** restricción `FOREIGN KEY` hacia clientes/productos. Es deliberado:
el dataset debe llegar "tal cual" (con sus anomalías) a Bronze, para que la
validación de integridad referencial sea una responsabilidad explícita y
demostrable de la capa Silver — no algo que la base de datos rechace antes
de que el pipeline la vea.

## Reproducibilidad

Correr `python main.py` dos veces con el mismo `config.yaml` genera
exactamente el mismo `anomalies_log.csv` (mismo conteo, mismos IDs) porque
toda la aleatoriedad depende únicamente de `seed` y del orden fijo en que
`main.py` consume el generador de números aleatorios.
