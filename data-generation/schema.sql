-- Esquema de la base relacional origen de FinBank — replica exactamente la
-- nomenclatura del sistema legado (nombres de tabla y de campo tal como
-- exige el enunciado del Escenario A). Sirve tanto para el Postgres local
-- de desarrollo como para Cloud SQL PostgreSQL en la nube.
--
-- Nota deliberada sobre integridad referencial: TB_MOV_FINANCIEROS y
-- TB_COMISIONES_LOG NO declaran FOREIGN KEY hacia TB_CLIENTES_CORE /
-- TB_PRODUCTOS_CAT. Esto es intencional: el dataset sintético incluye
-- anomalías controladas (ver ANOMALIES.md) —duplicados e id_cli huérfanos—
-- que representan cómo llega el dato "tal cual" desde un sistema origen
-- real. Validar y sanear esa integridad referencial es una responsabilidad
-- explícita de la capa Silver del pipeline, no de la base fuente.

DROP TABLE IF EXISTS TB_MOV_FINANCIEROS CASCADE;
DROP TABLE IF EXISTS TB_OBLIGACIONES CASCADE;
DROP TABLE IF EXISTS TB_COMISIONES_LOG CASCADE;
DROP TABLE IF EXISTS TB_CLIENTES_CORE CASCADE;
DROP TABLE IF EXISTS TB_PRODUCTOS_CAT CASCADE;
DROP TABLE IF EXISTS TB_SUCURSALES_RED CASCADE;

CREATE TABLE TB_CLIENTES_CORE (
    id_cli        VARCHAR(10) PRIMARY KEY,
    nomb_cli      VARCHAR(100),
    apell_cli     VARCHAR(100),
    tip_doc       VARCHAR(15),
    num_doc       VARCHAR(20) NOT NULL,
    fec_nac       DATE NOT NULL,
    fec_alta      DATE NOT NULL,
    cod_segmento  VARCHAR(5),
    score_buro    INTEGER,
    ciudad_res    VARCHAR(60),
    depto_res     VARCHAR(60),
    estado_cli    VARCHAR(15),
    canal_adquis  VARCHAR(20)
);

CREATE TABLE TB_PRODUCTOS_CAT (
    cod_prod         VARCHAR(10) PRIMARY KEY,
    desc_prod        VARCHAR(100),
    tip_prod         VARCHAR(30),
    tasa_ea          NUMERIC(6,2),
    plazo_max_meses  INTEGER,
    cuota_min        NUMERIC(14,2),
    comision_admin   NUMERIC(14,2),
    estado_prod      VARCHAR(15)
);

CREATE TABLE TB_SUCURSALES_RED (
    cod_suc    VARCHAR(10) PRIMARY KEY,
    nom_suc    VARCHAR(100),
    tip_punto  VARCHAR(20),
    ciudad     VARCHAR(60),
    depto      VARCHAR(60),
    latitud    NUMERIC(9,6),
    longitud   NUMERIC(9,6),
    activo     BOOLEAN
);

-- id_mov NO es PRIMARY KEY a propósito: el dataset incluye duplicados
-- exactos intencionales (misma PK) para ejercitar la deduplicación en Silver.
CREATE TABLE TB_MOV_FINANCIEROS (
    id_mov          VARCHAR(12) NOT NULL,
    id_cli          VARCHAR(10),
    cod_prod        VARCHAR(10),
    num_cuenta      VARCHAR(15),
    fec_mov         DATE,
    hra_mov         VARCHAR(8),   -- se tipa formalmente en Silver (requisito explícito del enunciado)
    vr_mov          NUMERIC(16,2),
    tip_mov         VARCHAR(30),
    cod_canal       VARCHAR(20),
    cod_ciudad      VARCHAR(10),
    cod_estado_mov  VARCHAR(15),
    id_dispositivo  VARCHAR(20)
);

CREATE TABLE TB_OBLIGACIONES (
    id_oblig         VARCHAR(10) PRIMARY KEY,
    id_cli           VARCHAR(10),
    cod_prod         VARCHAR(10),
    vr_aprobado      NUMERIC(16,2),
    vr_desembolsado  NUMERIC(16,2),
    sdo_capital      NUMERIC(16,2),
    vr_cuota         NUMERIC(14,2),
    fec_desembolso   DATE,
    fec_venc         DATE,
    dias_mora_act    INTEGER,
    num_cuotas_pend  INTEGER,
    calif_riesgo     VARCHAR(20)
);

CREATE TABLE TB_COMISIONES_LOG (
    id_comision   VARCHAR(10) PRIMARY KEY,
    id_cli        VARCHAR(10),
    cod_prod      VARCHAR(10),
    fec_cobro     DATE,
    vr_comision   NUMERIC(14,2),
    tip_comision  VARCHAR(30),
    estado_cobro  VARCHAR(15)
);

CREATE INDEX idx_mov_id_cli ON TB_MOV_FINANCIEROS(id_cli);
CREATE INDEX idx_mov_fec ON TB_MOV_FINANCIEROS(fec_mov);
CREATE INDEX idx_oblig_id_cli ON TB_OBLIGACIONES(id_cli);
CREATE INDEX idx_com_id_cli ON TB_COMISIONES_LOG(id_cli);
