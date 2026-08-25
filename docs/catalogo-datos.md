# Catálogo de datos — Silver y Gold

Catálogo básico (requisito Fase 5): cada tabla de Silver y Gold, con la
descripción de cada campo, su tipo, su origen y si contiene información
sensible. Las columnas marcadas **Sí (hash)** contienen un hash SHA256
irreversible desde Silver en adelante — el valor original nunca se
persiste en estas capas (ver `pipelines/dbt_finbank/macros/hash_pii.sql`).

## Capa Silver

### `stg_clientes`
| Campo | Tipo | Origen | ¿Sensible? |
|---|---|---|---|
| `id_cli` | STRING | `TB_CLIENTES_CORE.id_cli` | No (identificador interno) |
| `nomb_cli_hash` | STRING | `TB_CLIENTES_CORE.nomb_cli` (hasheado) | **Sí (hash)** — nombre |
| `apell_cli_hash` | STRING | `TB_CLIENTES_CORE.apell_cli` (hasheado) | **Sí (hash)** — apellido |
| `tip_doc` | STRING | `TB_CLIENTES_CORE.tip_doc` | No |
| `num_doc_hash` | STRING | `TB_CLIENTES_CORE.num_doc` (hasheado) | **Sí (hash)** — documento de identidad |
| `fec_nac` | DATE | `TB_CLIENTES_CORE.fec_nac` | Sensible (dato personal), no hasheado — necesario para calcular edad en Gold |
| `fec_alta` | DATE | `TB_CLIENTES_CORE.fec_alta` | No |
| `cod_segmento` | STRING | `TB_CLIENTES_CORE.cod_segmento` | No |
| `score_buro` | INTEGER (nullable) | `TB_CLIENTES_CORE.score_buro` | Sensible (riesgo crediticio) |
| `score_buro_es_nulo` | BOOLEAN | Calculado (estrategia de nulos) | No |
| `ciudad_res` | STRING | `TB_CLIENTES_CORE.ciudad_res` (imputado si nulo) | No |
| `depto_res` | STRING | `TB_CLIENTES_CORE.depto_res` | No |
| `estado_cli` | STRING | `TB_CLIENTES_CORE.estado_cli` | No |
| `canal_adquis` | STRING | `TB_CLIENTES_CORE.canal_adquis` (imputado si nulo) | No |

### `stg_productos`
| Campo | Tipo | Origen | ¿Sensible? |
|---|---|---|---|
| `cod_prod` | STRING | `TB_PRODUCTOS_CAT.cod_prod` | No |
| `desc_prod` | STRING | `TB_PRODUCTOS_CAT.desc_prod` | No |
| `tip_prod` | STRING | `TB_PRODUCTOS_CAT.tip_prod` | No |
| `tasa_ea` | NUMERIC | `TB_PRODUCTOS_CAT.tasa_ea` | No |
| `plazo_max_meses` | INTEGER (nullable estructural) | `TB_PRODUCTOS_CAT.plazo_max_meses` | No |
| `cuota_min` | NUMERIC | `TB_PRODUCTOS_CAT.cuota_min` | No |
| `comision_admin` | NUMERIC | `TB_PRODUCTOS_CAT.comision_admin` (imputado si nulo) | No |
| `estado_prod` | STRING | `TB_PRODUCTOS_CAT.estado_prod` | No |

### `stg_sucursales`
Todos los campos no sensibles (ubicación de infraestructura del banco, no de personas): `cod_suc`, `nom_suc`, `tip_punto`, `ciudad`, `depto`, `latitud`, `longitud`, `tiene_geolocalizacion`, `activo`.

### `stg_movimientos`
| Campo | Tipo | Origen | ¿Sensible? |
|---|---|---|---|
| `id_mov` | STRING | `TB_MOV_FINANCIEROS.id_mov` | No |
| `id_cli` | STRING | `TB_MOV_FINANCIEROS.id_cli` (FK validada) | No (es un identificador, no un dato personal directo) |
| `cod_prod` | STRING | `TB_MOV_FINANCIEROS.cod_prod` (FK validada) | No |
| `num_cuenta` | STRING | `TB_MOV_FINANCIEROS.num_cuenta` | Sensible (dato de cuenta bancaria) |
| `fec_mov`, `hra_mov` | DATE, TIME | `TB_MOV_FINANCIEROS` | No |
| `vr_mov` | NUMERIC | `TB_MOV_FINANCIEROS.vr_mov` | Sensible (monto transaccional) |
| `tip_mov`, `cod_canal`, `cod_ciudad`, `cod_estado_mov` | STRING | `TB_MOV_FINANCIEROS` | No |
| `id_dispositivo` | STRING (nullable) | `TB_MOV_FINANCIEROS.id_dispositivo` | Sensible (identificador de dispositivo) |
| `promedio_movil_30d`, `stddev_movil_30d` | NUMERIC | Calculado (ventana móvil) | No |
| `ind_sospechoso` | BOOLEAN | Calculado (regla de negocio, Silver) | No |

### `stg_obligaciones`
Campos de negocio (`vr_aprobado`, `vr_desembolsado`, `sdo_capital`, `vr_cuota`, `dias_mora_act`, `calif_riesgo`) son **sensibles** (información crediticia/financiera del cliente). `id_oblig`, `id_cli`, `cod_prod`, fechas y `num_cuotas_pend` no se consideran sensibles por sí solos.

### `stg_comisiones`
`vr_comision` es sensible (monto financiero); el resto de campos (`id_comision`, `id_cli`, `cod_prod`, `fec_cobro`, `tip_comision`, `estado_cobro`) no.

### `err_calidad_datos` / `dq_report_silver`
Tablas de metadatos operacionales del pipeline (no contienen PII directamente, aunque `err_calidad_datos.id_registro` referencia registros de negocio). No sensibles en sí mismas.

## Capa Gold

### `dim_clientes`
Mismas columnas que `stg_clientes` más `nombre_completo_hash` (concatenación de los hashes) y `edad` (calculada desde `fec_nac`). Mismas marcas de sensibilidad que la tabla Silver de origen — la PII sigue hasheada, nunca en texto plano.

### `dim_productos`
No sensible — igual que `stg_productos`, con `familia_producto` y `tasa_mensual_equivalente` calculados.

### `dim_geografia` / `dim_canal`
No sensibles — dimensiones de referencia curadas (ciudades, canales), sin ningún dato personal.

### `fact_transacciones`
Mismas marcas que `stg_movimientos`, más `vr_mov_usd` (sensible, es un monto) y `horario_habil` (no sensible).

### `fact_cartera`
Sensible: `vr_aprobado`, `vr_desembolsado`, `sdo_capital`, `vr_cuota`, `provision_estimada` (información financiera/crediticia). No sensibles: `bucket_mora`, `calif_regulatoria`, `dias_mora_act` son clasificaciones derivadas, aunque reflejan indirectamente el comportamiento crediticio del cliente — tratar con el mismo cuidado de acceso que el resto de la tabla (por eso todo `fact_cartera` vive en Gold, con acceso restringido al rol Analista vía IAM, no público).

### `fact_rentabilidad_cliente`
Sensible: `ingreso_intereses`, `ingreso_comisiones`, `ingreso_total`, `cltv_12m` (información financiera del cliente).

### `kpi_cartera_diaria`
Datos agregados (no a nivel de cliente individual) — no sensible en el sentido de identificar una persona, pero sigue siendo información de negocio restringida (solo Gold, no pública).

## Resumen de controles aplicados

- **Enmascaramiento:** SHA256 irreversible sobre nombre/apellido/documento desde Silver en adelante (`hash_pii.sql`).
- **Control de acceso:** el rol Analista (`infra/governance.tf`) solo tiene `roles/bigquery.dataViewer` sobre el dataset Gold — cero acceso a Bronze o Silver, ni de lectura. Ver `docs/evidencia/fase5/` para la demostración real de acceso denegado.
- **Auditoría:** Cloud Audit Logs (Data Access) habilitados sobre Storage y BigQuery (`infra/governance.tf:google_project_iam_audit_config`) — responde "quién accedió a qué dato y cuándo".
