# Cómo se probó la alerta de anomalía de volumen (evidencia real)

1. Se subieron 3 archivos de log históricos SINTÉTICOS a
   `gs://finbank-data-platform-dev-bronze/_logs/` con un conteo de
   `TB_CLIENTES_CORE` artificialmente bajo (~500 filas) para simular un
   histórico de 7 corridas con promedio distinto al real.
2. Se corrió el Cloud Run Job `finbank-bronze-dev` una vez
   (`gcloud run jobs execute finbank-bronze-dev --wait`), que extrajo los
   10.000 clientes reales de Cloud SQL como siempre.
3. `pipelines/common/alerting.py:check_volume_anomaly` comparó el conteo
   real (10.000) contra el promedio de las últimas 7 corridas detectadas
   (5.929,43 — mezcla de las sintéticas y las reales anteriores), una
   desviación de 68,65% — muy por encima del umbral de 30% del enunciado.
4. Se confirmó el log `VOLUME_ANOMALY` real (`volume_anomaly_log.json`) y
   se limpiaron los 3 archivos sintéticos del bucket después de la prueba.

Esta es la única de las 3 alertas que no pudo probarse "orgánicamente"
corriendo el pipeline normal dos veces (los volúmenes reales de los datos
sintéticos de Fase 1 son estables entre corridas) — se requirió manipular
el histórico de comparación a propósito, técnica válida y no invasiva para
la data real del pipeline.
