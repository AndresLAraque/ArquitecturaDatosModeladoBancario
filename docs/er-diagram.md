# Diagrama Entidad-Relación — Tablas fuente FinBank (Escenario A)

Modelo de la base relacional origen (Fase 1), tal como se genera y se
carga en `data-generation/`. Nomenclatura idéntica a la del sistema legado
de FinBank, según el enunciado.

```mermaid
erDiagram
    TB_CLIENTES_CORE ||--o{ TB_MOV_FINANCIEROS : genera
    TB_CLIENTES_CORE ||--o{ TB_OBLIGACIONES : adquiere
    TB_CLIENTES_CORE ||--o{ TB_COMISIONES_LOG : paga
    TB_PRODUCTOS_CAT ||--o{ TB_MOV_FINANCIEROS : "asociado_a"
    TB_PRODUCTOS_CAT ||--o{ TB_OBLIGACIONES : "asociado_a"
    TB_PRODUCTOS_CAT ||--o{ TB_COMISIONES_LOG : "asociado_a"

    TB_CLIENTES_CORE {
        varchar id_cli PK
        varchar nomb_cli
        varchar apell_cli
        varchar tip_doc
        varchar num_doc
        date fec_nac
        date fec_alta
        varchar cod_segmento
        int score_buro
        varchar ciudad_res
        varchar depto_res
        varchar estado_cli
        varchar canal_adquis
    }
    TB_PRODUCTOS_CAT {
        varchar cod_prod PK
        varchar desc_prod
        varchar tip_prod
        numeric tasa_ea
        int plazo_max_meses
        numeric cuota_min
        numeric comision_admin
        varchar estado_prod
    }
    TB_SUCURSALES_RED {
        varchar cod_suc PK
        varchar nom_suc
        varchar tip_punto
        varchar ciudad
        varchar depto
        numeric latitud
        numeric longitud
        boolean activo
    }
    TB_MOV_FINANCIEROS {
        varchar id_mov "NOT NULL, no es PK (ver nota)"
        varchar id_cli FK
        varchar cod_prod FK
        varchar num_cuenta
        date fec_mov
        varchar hra_mov
        numeric vr_mov
        varchar tip_mov
        varchar cod_canal
        varchar cod_ciudad
        varchar cod_estado_mov
        varchar id_dispositivo
    }
    TB_OBLIGACIONES {
        varchar id_oblig PK
        varchar id_cli FK
        varchar cod_prod FK
        numeric vr_aprobado
        numeric vr_desembolsado
        numeric sdo_capital
        numeric vr_cuota
        date fec_desembolso
        date fec_venc
        int dias_mora_act
        int num_cuotas_pend
        varchar calif_riesgo
    }
    TB_COMISIONES_LOG {
        varchar id_comision PK
        varchar id_cli FK
        varchar cod_prod FK
        date fec_cobro
        numeric vr_comision
        varchar tip_comision
        varchar estado_cobro
    }
```

## Notas del modelo

- **`TB_SUCURSALES_RED` no tiene FK entrante desde las tablas de hechos**
  en el modelo fuente (los movimientos se relacionan por `cod_canal` /
  `cod_ciudad`, no por `cod_suc`). En la capa Gold se deriva de aquí
  `dim_geografia` y `dim_canal` de forma independiente — ver
  `PLAN.md`, Fase 3.
- **`id_mov` no es llave primaria a nivel de base de datos.** Es
  intencional: el dataset sintético incluye duplicados exactos (misma PK)
  como una de las anomalías controladas (ver `data-generation/ANOMALIES.md`),
  para ejercitar la deduplicación en la capa Silver.
- **No se declaran `FOREIGN KEY` en `TB_MOV_FINANCIEROS` ni
  `TB_COMISIONES_LOG`** hacia clientes/productos — el dataset incluye
  `id_cli` huérfanos a propósito, y su detección es responsabilidad
  explícita de la validación de integridad referencial en Silver.
- Cardinalidad `||--o{`: un cliente/producto puede tener cero o muchos
  movimientos/obligaciones/comisiones; cada movimiento/obligación/comisión
  pertenece exactamente a un cliente y a un producto (cuando el dato es
  íntegro).
