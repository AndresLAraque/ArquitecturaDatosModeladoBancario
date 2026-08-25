# Contexto de build: pipelines/. Una sola imagen sirve tanto a Silver
# (load_bronze_to_bq.py + dbt --select tag:silver) como a Gold
# (dbt --select tag:gold) — ver entrypoint.sh y STAGE.
FROM python:3.12-slim
WORKDIR /app

COPY silver/requirements.txt /app/silver/requirements.txt
RUN pip install --no-cache-dir -r /app/silver/requirements.txt
COPY common/alerting.py /app/silver/
COPY silver/load_bronze_to_bq.py silver/config.yaml /app/silver/

COPY dbt_finbank/requirements.txt /app/dbt_finbank/requirements.txt
RUN pip install --no-cache-dir -r /app/dbt_finbank/requirements.txt
COPY dbt_finbank /app/dbt_finbank

COPY transform/entrypoint.sh /app/entrypoint.sh
RUN chmod +x /app/entrypoint.sh

ENTRYPOINT ["/app/entrypoint.sh"]
