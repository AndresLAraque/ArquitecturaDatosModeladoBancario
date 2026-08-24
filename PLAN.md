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

**Carpeta:** `/infra`

- [ ] Backend remoto: bucket GCS dedicado para `terraform.tfstate` (creado *fuera* de Terraform,
      con un `gcloud storage buckets create` inicial, o en un módulo bootstrap aparte)
- [ ] Recursos mínimos GCP:
  - [ ] 3 buckets GCS: `bronze`, `silver`, `gold` (o prefijos dentro de uno con IAM por prefijo)
  - [ ] BigQuery dataset(s): `finbank_silver`, `finbank_gold` (uno por capa, o por entorno)
  - [ ] Cloud SQL instance PostgreSQL (tier pequeño, `activation_policy = ALWAYS` solo cuando se use)
  - [ ] Cloud Run services/jobs para las tareas del pipeline (bronze extract, silver dbt run, gold dbt run)
  - [ ] Cloud Workflows definition (referenciado, definido en `/orchestration`)
  - [ ] Cloud Scheduler job (cron diario 02:00 hora local)
  - [ ] Service Accounts granulares: `sa-ingestion`, `sa-transform`, `sa-orchestrator` (mínimo privilegio)
  - [ ] Secret Manager: credenciales de Cloud SQL, no expuestas en variables planas
  - [ ] Cloud Logging (sink si aplica) + Cloud Monitoring alerting policy
  - [ ] Pub/Sub topic `finbank-alerts` (fallo de tarea, anomalía de volumen, reporte diario)
- [ ] Variables parametrizadas: `project_id`, `region`, `environment` (`dev`/`prod`), tamaños
- [ ] Dos entornos vía `dev.tfvars` / `prod.tfvars` (o workspaces)
- [ ] `outputs.tf`: nombres de buckets, dataset IDs, URLs de Cloud Run, emails de SAs
- [ ] `.gitignore` con `*.tfstate*`, `.terraform/`, `*.tfvars` si contienen datos sensibles
- [ ] Evidencia: salida de `terraform apply` + capturas del portal

---

## Fase 3 — Pipeline Medallion

**Carpeta:** `/pipelines`

### Bronze (`/pipelines/bronze`)
- [ ] Extracción Cloud SQL → GCS en Parquet, sin transformar esquema
- [ ] 3 columnas de auditoría: `ingestion_ts`, `source_system`, `batch_id`
- [ ] Particionado `year/month/day` por fecha de ingesta
- [ ] Log de ejecución (registros procesados, tamaño, duración) — tabla o archivo JSON de logs
- [ ] Modo incremental: watermark sobre `fec_mov`/`fec_cobro`/etc. o columna de última modificación

### Silver (`/pipelines/silver` — BigQuery + dbt, staging models)
- [ ] Dedup de exactos + descarte de nulos en campos obligatorios
- [ ] Tipado estándar (fechas, decimales, etc.)
- [ ] Validación de integridad referencial → tabla `errores_integridad` con motivo
- [ ] Estrategia de nulos documentada por columna (imputación / exclusión / flag binario)
- [ ] Hash/enmascaramiento de PII: `num_doc`, `nomb_cli`, `apell_cli`, datos de contacto
      (`SHA256` con salt desde Secret Manager)
- [ ] `ind_sospechoso` calculado aquí (ventana móvil 30 días, > 3 desviaciones estándar) — **debe
      quedar en Silver, no en Gold**, según regla de negocio explícita
- [ ] Reporte de calidad por ejecución: % nulos por columna, rechazados, % conformes
- [ ] Formato: tablas BigQuery nativas (dan upsert/MERGE sin necesitar Delta/Iceberg aparte)

### Gold (`/pipelines/gold` — dbt marts)
- [ ] `dim_clientes` — nombre completo, edad calculada, segmento con etiqueta legible
- [ ] `dim_productos` — nombres de negocio, tasa mensual equivalente, familia (crédito/ahorro/transaccional)
- [ ] `dim_geografia`, `dim_canal` — separados desde `TB_SUCURSALES_RED`
- [ ] `fact_transacciones` — FK validada, monto en USD, flag horario hábil/no hábil, prom. móvil 30d
- [ ] `fact_cartera` — `bucket_mora` (5 rangos), clasificación regulatoria A/B/C/D/E, provisión estimada
- [ ] `fact_rentabilidad_cliente` — ingreso total, CLTV 12 meses (join comisiones + movimientos)
- [ ] `kpi_cartera_diaria` — agregado por fecha/producto/segmento/ciudad (obligaciones activas,
      monto cartera, monto mora, tasa mora %, clientes en mora)
- [ ] Particionamiento Gold por fecha; clustering por segmento/ciudad donde aplique
- [ ] Documentar linaje de 3+ campos calculados (origen, transformación, propósito) — dbt docs
      o `docs/linaje.md`
- [ ] Tabla de errores del pipeline con al menos 1 registro de prueba
- [ ] 5+ pruebas de calidad (dbt tests / Great Expectations): not_null, unique, relationships,
      accepted_values (`bucket_mora`), rango de fechas

---

## Fase 4 — Orquestación

**Carpeta:** `/orchestration`

- [ ] Definición YAML de Cloud Workflows: Bronze → Silver → Gold con dependencias explícitas
      (Silver espera éxito de Bronze; Gold espera éxito de Silver)
- [ ] Cloud Scheduler: cron `0 2 * * *`, zona horaria local del proyecto (`America/Bogota`)
- [ ] Reintentos: 3 intentos, backoff exponencial (soportado nativamente por Workflows `retry` policy)
- [ ] Timeout por paso coherente con volumen (ej. 15-30 min para Silver/Gold)
- [ ] Alerta de fallo → Pub/Sub → Cloud Function/Monitoring → email, con DAG/tarea/fecha/error
- [ ] Reporte diario de éxito → registros por capa, tiempo total, # alertas de calidad
- [ ] Dashboard/log accesible: Cloud Logging + un panel simple en Cloud Monitoring, o vista en
      BigQuery sobre la tabla de logs de ejecución
- [ ] Evidencia: captura de ejecución exitosa, captura de alerta de fallo (forzar un error de prueba),
      captura del reporte diario, historial de 2+ ejecuciones

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
