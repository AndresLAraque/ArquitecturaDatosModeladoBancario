# Plan de trabajo — FinBank Data Platform (Escenario A, GCP)

Decisiones cerradas: **Plataforma = GCP (free trial)** · **Sector = Escenario A (Banca)** ·
**Orquestación = Cloud Workflows + Cloud Scheduler + Cloud Run** ·
**Silver/Gold = BigQuery + dbt** · **IaC = Terraform**

---

## Fase 0 — Prerrequisitos (antes de escribir código)

### Cuenta y proyecto GCP (lo hace el usuario)
- [x] Crear/usar cuenta Google, activar **free trial** ($300 USD / 90 días) en https://console.cloud.google.com
- [x] Crear proyecto GCP dedicado: **`finbank-data-platform-dev`** (región `us-central1`)
- [x] Billing Account del trial (`01F9B4-329843-7DE70D`) vinculada y `billingEnabled: true`
      — nota: la cuenta se llama genéricamente "Mi cuenta de facturación" (COP), no
      "...Trial..."; hay una cuenta vieja `0187EC-7D6577-03A296` (USD) de un trial anterior
      que quedó `open: false` — esa no se usa, no confundir
- [ ] **Fijar un presupuesto y alerta de billing** (Billing → Budgets & alerts) en, p.ej., $50/$100/$200 — red de seguridad para no drenar el crédito sin darte cuenta
- [ ] Habilitar las APIs necesarias — se hará vía Terraform (`google_project_service`) en
      Fase 2 en vez de manualmente, para que quede como código: Cloud Storage, BigQuery,
      Cloud SQL Admin, Cloud Workflows, Cloud Scheduler, Cloud Run, Secret Manager,
      Cloud Logging/Monitoring, Pub/Sub, IAM, Artifact Registry

### Herramientas locales (verificado en esta máquina)
- [x] Git — instalado
- [x] Docker Desktop — instalado (para Postgres local de desarrollo)
- [x] **Python 3.12** — instalado vía `winget install Python.Python.3.12`
- [x] **Google Cloud SDK (`gcloud`)** — instalado, `gcloud init` completado, cuenta y
      proyecto configurados (ver arriba)
- [x] **Terraform 1.15.8** — instalado vía `winget install Hashicorp.Terraform`
- [ ] `dbt-bigquery` — se instala vía `pip` dentro del venv del proyecto en Fase 3
- [ ] Cuenta de GitHub/GitLab con el repo remoto creado (aún no vinculado — repo local ya
      inicializado con `git init`)

### Decisiones a mantener consistentes en todo el repo
- [x] Nombres de tablas fuente exactamente como en el enunciado (`TB_CLIENTES_CORE`, etc.)
- [x] Región GCP única para todos los recursos (sugerido: `us-central1`, entra en free tier de GCS)
- [ ] Convención de nombres de recursos: `finbank-<capa>-<entorno>` (ej. `finbank-bronze-dev`)

---

## Fase 1 — Generación de datos y modelo relacional ✅ COMPLETADA (2026-08-24)

**Carpeta:** `/data-generation`

- [x] `config.yaml`: semilla fija (42), volúmenes por tabla, rango de fechas (12 meses:
      2025-08-01 a 2026-07-31), % nulos (5%), % de cada anomalía
- [x] Generadores (pandas/numpy + Faker) para las 6 tablas con sus volúmenes mínimos:
  - `TB_CLIENTES_CORE` (10.000) — edad normal(38,12) acotada [18,85], `score_buro`
    correlacionado con `cod_segmento`, `fec_alta` ponderada a años recientes
  - `TB_PRODUCTOS_CAT` (50) — por familia crédito/ahorro/transaccional
  - `TB_MOV_FINANCIEROS` (500.000 + 1.500 duplicados intencionales) — pico horario
    almuerzo/noche, estacionalidad mensual + quincena de pago, montos log-normal por tipo,
    actividad por cliente log-normal (power users)
  - `TB_OBLIGACIONES` (30.000) — `dias_mora_act` 75% al día + cola exponencial
  - `TB_SUCURSALES_RED` (200) — coordenadas jitter alrededor de 14 ciudades en los 5 países
  - `TB_COMISIONES_LOG` (80.000)
- [x] Integridad referencial garantizada por construcción (dimensiones antes que hechos)
- [x] ~5% nulos controlados en campos no críticos (verificado: 0.4%-1.7% de nulos promedio
      por tabla, dependiendo de cuántos campos no-críticos tiene cada una — ver
      `output/generation_summary.json`)
- [x] **4 anomalías intencionales documentadas** en `ANOMALIES.md` y verificadas en la BD
      cargada: 1.500 duplicados exactos, 1.063 fechas fuera de rango, 872 FK huérfanas,
      1.063 campos inconsistentes (vr_mov negativo / sdo_capital > vr_aprobado)
- [x] Salida en 3 formatos (CSV + JSON + Parquet) — heterogeneidad de ingesta real
- [x] Postgres local en Docker (`docker-compose.yml`, puerto 5434 — el 5432 estaba ocupado
      por otros proyectos locales del usuario)
- [x] Script de carga (`load_to_postgres.py`, SQLAlchemy) parametrizado por variables de
      entorno — mismo código sirve para Postgres local o Cloud SQL
- [x] Diagrama ER en `/docs/er-diagram.md` (Mermaid, se renderiza nativo en GitHub)
- [x] Evidencia real de carga en `output/load_evidence.txt`: las 6 tablas cargaron con el
      conteo exacto esperado (10.000 / 50 / 200 / 501.500 / 30.000 / 80.000)

---

## Fase 2 — Infraestructura como código (Terraform)

**Carpeta:** `/infra` — ✅ COMPLETADA (2026-08-24), 44 recursos aplicados en `dev`

- [x] Backend remoto: `gs://finbank-data-platform-dev-tfstate` (bootstrap con `gcloud storage
      buckets create`, versionado activo, fuera de Terraform)
- [x] Recursos mínimos GCP (ver detalle completo en `infra/RESOURCES.md`):
  - [x] 3 buckets GCS: `bronze`, `silver`, `gold`
  - [x] BigQuery datasets: `finbank_silver_dev`, `finbank_gold_dev`
  - [x] Cloud SQL PostgreSQL 16 (`finbank-sqlpg-dev`, tier `db-f1-micro`, edición `ENTERPRISE`)
  - [x] Cloud Workflows (`finbank-pipeline-dev`, placeholder — contenido real en Fase 4)
  - [x] Cloud Scheduler (`finbank-pipeline-daily-dev`, cron `0 2 * * *` `America/Bogota`, 3
        reintentos con backoff exponencial)
  - [x] Service Accounts granulares: `sa-ingestion`, `sa-transform`, `sa-orchestrator`
  - [x] Secret Manager: password de Cloud SQL generado por `random_password`, nunca en código
  - [x] Pub/Sub topic `finbank-alerts-dev`
  - [x] Artifact Registry (`finbank-pipeline-dev`) — para imágenes de Cloud Run de Fase 3/4
  - [ ] `google_cloud_run_v2_job` — diferido a Fase 3/4 (no hay imagen que desplegar todavía)
- [x] Variables parametrizadas: `project_id`, `region`, `environment`, `cloud_sql_tier`, etc.
- [x] Dos entornos vía `environments/dev.tfvars` (aplicado) / `prod.tfvars` (documentado, no
      aplicado — solo un proyecto disponible en el free trial, ver nota en el archivo)
- [x] `outputs.tf`: nombres/URLs de todos los recursos
- [x] `.gitignore`: `*.tfstate*`, `.terraform/`, `*.tfvars` (con excepción explícita para
      `infra/environments/*.tfvars`, que no llevan secretos), `tfplan*`
- [x] Evidencia: `docs/evidencia/fase2-terraform-apply.txt` (+ intento 1 con el error de
      edición de Cloud SQL, documentado y corregido — ver `infra/RESOURCES.md`)

---

## Fase 3 — Pipeline Medallion ✅ COMPLETADA (2026-08-25)

**Carpeta:** `/pipelines`

### Bronze (`/pipelines/bronze`) ✅ COMPLETADA (2026-08-24)
- [x] Extracción Cloud SQL → GCS en Parquet, sin transformar esquema
- [x] 3 columnas de auditoría: `ingestion_ts`, `source_system`, `batch_id`
- [x] Particionado `year/month/day` por fecha de ingesta
- [x] Log de ejecución (registros procesados, tamaño, duración) en `gs://.../_logs/<batch_id>.json`
- [x] Modo incremental (watermark en GCS) sobre `fec_mov`/`fec_cobro` — demostrado con 2
      corridas reales: la 2ª detecta 0 filas nuevas en las tablas incrementales. Evidencia en
      `docs/evidencia/fase3-bronze/`

### Silver (`/pipelines/silver` + `/pipelines/dbt_finbank` — BigQuery + dbt) ✅ COMPLETADA (2026-08-25)
- [x] Puente Bronze (GCS Parquet) -> BigQuery (`raw_*`) vía `load_bronze_to_bq.py`, por modo
      (full = último batch, incremental = todos los batches acumulados)
- [x] Dedup de exactos (por columnas de negocio, no de auditoría) + exclusión de campos
      obligatorios nulos
- [x] Tipado estándar (fechas, decimales, hora)
- [x] Validación de integridad referencial → `err_calidad_datos` con motivo (FK_HUERFANA,
      FECHA_FUERA_DE_RANGO, CAMPO_INCONSISTENTE) — 3.008 filas reales, coincide con las
      anomalías inyectadas en Fase 1
- [x] Estrategia de nulos documentada por columna, las 3 modalidades representadas
      (imputación / exclusión / marcado binario) — tabla completa en `pipelines/dbt_finbank/README.md`
- [x] Hash SHA256+salt sobre `nomb_cli`, `apell_cli`, `num_doc` (macro `hash_pii.sql`) — valor
      original no se conserva en Silver
- [x] `ind_sospechoso` calculado en Silver (ventana móvil 30 días por cliente, > 3 desviaciones
      estándar) — 37.139/497.456 filas marcadas (~7.5%, observación documentada en el README)
- [x] Reporte de calidad `dq_report_silver`: % nulos por columna, rechazados, % conformes —
      99.45%-100% de conformidad por tabla
- [x] Tablas BigQuery nativas (materialización `table` de dbt)
- [x] 21 pruebas automatizadas de calidad (17 genéricas dbt + 2 singulares), 21/21 en verde —
      excede el mínimo de 5. Evidencia completa en `docs/evidencia/fase3-silver/`

### Gold (`/pipelines/dbt_finbank/models/marts` — dbt marts) ✅ COMPLETADA (2026-08-25)
- [x] `dim_clientes` — nombre completo (hash), edad calculada, segmento con etiqueta legible
- [x] `dim_productos` — nombres de negocio, tasa mensual equivalente (verificada matemáticamente),
      familia (crédito/ahorro/transaccional)
- [x] `dim_geografia`, `dim_canal` — dimensiones curadas que concilian código vs nombre de ciudad
      y tipo de punto físico vs canal digital (inconsistencia real entre TB_SUCURSALES_RED y
      TB_MOV_FINANCIEROS, documentada en el propio modelo)
- [x] `fact_transacciones` — FK validada (heredada de Silver), monto en USD, flag horario
      hábil/no hábil, `ind_sospechoso`/prom. móvil 30d propagados desde Silver
- [x] `fact_cartera` — `bucket_mora` (5 rangos), clasificación regulatoria A/B/C/D/E, provisión
      estimada (tabla simplificada tipo SFC, supuesto documentado en el modelo)
- [x] `fact_rentabilidad_cliente` — ingreso total (intereses aproximados + comisiones), CLTV
      rolling 12 meses por cliente
- [x] `kpi_cartera_diaria` — **materialización incremental** (snapshot diario tipo Kimball, no
      tabla completa) por fecha/producto/segmento/ciudad
- [x] Particionamiento por fecha (`fec_mov`, `fec_desembolso`, `fecha_corte`) + clustering por
      producto/canal/calificación regulatoria en los 3 modelos que más lo necesitan
- [x] Linaje de 10 campos calculados documentado en `/docs/linaje.md` (origen, transformación,
      propósito) — excede el mínimo de 3
- [x] 22 pruebas dbt adicionales sobre los marts (43 en total con Silver), 43/43 en verde.
      Evidencia real (conteos, sumas, verificación matemática) en `docs/evidencia/fase3-gold/`
- [x] Tabla de errores del pipeline con registros de prueba — ya satisfecho por
      `err_calidad_datos` (Silver), reutilizable/ampliable en Gold si aparecen nuevas reglas
- [x] 5+ pruebas de calidad — ya satisfecho por las 21 pruebas de Silver (superávit amplio);
      Gold puede sumar tests propios sobre `bucket_mora`/`calif_regulatoria` si aporta valor

---

## Fase 4 — Orquestación ✅ COMPLETADA (2026-08-25)

**Carpeta:** `/orchestration` + `/pipelines/bronze,transform` (contenedores) + `infra/cloud_run.tf`,
`infra/monitoring.tf`

- [x] 3 imágenes Docker (bronze + transform reutilizada para silver/gold) construidas y
      publicadas en Artifact Registry
- [x] 3 `google_cloud_run_v2_job` (bronze/silver/gold) desplegados, probados individualmente
      en la nube antes de orquestarlos (los 3 corrieron exitosos por separado)
- [x] Definición YAML de Cloud Workflows real (ya no placeholder): Bronze → Silver → Gold con
      dependencias explícitas — un `raise` sin capturar en cualquier etapa detiene el resto
- [x] Cloud Scheduler: cron `0 2 * * *`, zona horaria `America/Bogota` (desde Fase 2)
- [x] Reintentos: 3 intentos, backoff exponencial (10s/20s/40s, tope 180s) vía `retry` policy
      de Workflows — **verificado real**: la falla forzada agotó los 3 reintentos (~8.5 min)
      antes de fallar definitivamente
- [x] Timeout por tarea: 900s por Cloud Run Job (margen amplio sobre tiempos reales: Bronze ~80s,
      Silver/Gold varios minutos con dbt run+test)
- [x] Alerta de fallo: sin credenciales de correo en el código — `sys.log` estructurado +
      `google_monitoring_alert_policy` (log-based) + `google_monitoring_notification_channel`
      (email). **Verificado real**: log `TASK_FAILURE` con dag_name/task_name/error_message/timestamp
- [x] Reporte diario de éxito: `PIPELINE_SUCCESS_SUMMARY` con registros por capa, duración,
      # alertas de calidad — **verificado real** en 2 corridas exitosas
- [x] Alerta de anomalía de volumen (Fase 5, implementada aquí): `pipelines/common/alerting.py`,
      compara contra el promedio de las últimas 7 corridas (logs de Bronze en GCS)
- [x] Dashboard/log accesible sin código: Cloud Workflows Console + Cloud Logging
- [x] Evidencia real (no simulada): 2 ejecuciones completas exitosas (528s y 404s) + 1 falla
      forzada deliberadamente (rompiendo temporalmente el job de Bronze, revertido después con
      `terraform apply` — Terraform detectó y corrigió el drift solo). Todo en
      `docs/evidencia/fase4/`

---

## Fase 5 — Gobierno, seguridad y calidad

- [ ] 3 roles IAM: `data-engineer` (RW todas las capas), `analyst` (solo lectura en dataset Gold),
      `admin` (control total del proyecto) — vía Terraform (`google_project_iam_member` /
      roles custom)
- [ ] Principio de mínimo privilegio en cada Service Account del pipeline
- [ ] Cloud Audit Logs (Data Access) habilitados sobre BigQuery/GCS
- [ ] Evidencia de acceso denegado: analyst intentando leer bucket `bronze`/`silver` → 403
- [ ] Catálogo de datos `/docs/catalogo-datos.md`: tabla, campo, tipo, origen, ¿PII? (Silver + Gold)
- [ ] Enmascaramiento vigente desde Silver en adelante (ya cubierto en Fase 3)
- [ ] Evidencia de las 3 alertas: fallo, reporte diario, anomalía de volumen (>30% vs promedio
      últimas 7 ejecuciones)
- [ ] Linaje de 3+ campos (ya cubierto en Fase 3, referenciarlo aquí)
- [ ] `CHANGELOG.md` actualizado en cada hito

---

## Entrega final

- [ ] Repo remoto (GitHub/GitLab) creado y compartido con el evaluador
- [ ] README con sector + plataforma + justificación como **primera sección**
- [ ] Todos los entregables de cada fase presentes en sus carpetas
- [ ] Revisión final: sin credenciales en el historial de git, sin `.tfstate` commiteado
