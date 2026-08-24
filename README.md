# FinBank — Plataforma de Datos (Prueba Técnica DataKnow)

## Sector y plataforma elegidos

- **Sector / escenario:** Escenario A — Banca y Servicios Financieros (FinBank S.A.)
- **Plataforma cloud:** Google Cloud Platform (capa de prueba gratuita, USD 300 / 90 días)

### Justificación

**Sector (Escenario A):** se eligió por ser el dominio con reglas de negocio más ricas para
demostrar modelado dimensional y lógica de riesgo/fraude (mora, provisión regulatoria,
detección de transacciones atípicas, CLTV), que ejercitan bien las tres capas de la
arquitectura Medallón.

**Plataforma (GCP):** se eligió GCP porque el candidato dispone de la capa de prueba gratuita
(USD 300 de crédito). Dentro de GCP se privilegiaron servicios **serverless / pay-per-use**
sobre servicios con costo fijo por hora, para maximizar la duración del crédito:

| Necesidad | Servicio elegido | Alternativa descartada | Motivo |
|---|---|---|---|
| Almacenamiento Bronze/Silver/Gold | Cloud Storage (buckets `bronze`, `silver`, `gold`) | — | Estándar de-facto para data lake, free tier de 5GB en regiones US |
| Procesamiento Silver/Gold | **BigQuery + dbt** | PySpark en Dataproc | BigQuery es serverless (sin clúster que facture por hora) y tiene free tier de 1TB de queries/mes; dbt aporta tests, documentación y linaje con poco esfuerzo adicional (recomendado explícitamente en el enunciado) |
| Orquestación | **Cloud Workflows + Cloud Scheduler + Cloud Run** | Cloud Composer (Airflow gestionado) | Composer cuesta ~300-450 USD/mes incluso en su tamaño mínimo, lo que agotaría el crédito de prueba en días. Workflows+Scheduler+Run es una combinación explícitamente válida en el enunciado, es serverless y permite dependencias, reintentos con backoff y alertas sin costo fijo |
| Base de datos origen | Cloud SQL (PostgreSQL) | — | Motor recomendado por el enunciado para GCP; se detiene (`activation policy: NEVER`) fuera de las ventanas de uso para minimizar costo de cómputo |
| IaC | Terraform | Pulumi / Deployment Manager | Estándar de facto, multi-cloud, soporta backend remoto en GCS nativamente |
| Secretos | Secret Manager | Variables de entorno | Requisito explícito: ninguna credencial en código |
| Notificaciones | Pub/Sub + Cloud Monitoring/Logging alerting | — | Integra nativamente con Workflows/Cloud Run y permite alertas por correo/canal |

> Estado del proyecto: en construcción por fases. Ver `PLAN.md` para el checklist detallado
> y el estado de avance por fase.

## Estructura del repositorio

```
/infra              Código Terraform (IaC) + README de despliegue
/data-generation     Scripts de generación de datos sintéticos + config YAML
/pipelines           Transformaciones Bronze / Silver / Gold
/orchestration       Definición de Cloud Workflows + Cloud Scheduler
/docs                Diagrama de arquitectura, ER, catálogo de datos
README.md            Este archivo
CHANGELOG.md         Historial de cambios
PLAN.md              Checklist de avance por fase
```

## Despliegue y ejecución

_Pendiente — se documentará a medida que cada fase quede implementada (ver `PLAN.md`)._
