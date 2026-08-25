# Contexto de build: pipelines/ (para poder copiar common/alerting.py,
# compartido con la imagen "transform"). Ver pipelines/README-docker.md.
FROM python:3.12-slim
WORKDIR /app

COPY bronze/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY common/alerting.py .
COPY bronze/extract_to_bronze.py bronze/config.yaml ./

ENTRYPOINT ["python", "extract_to_bronze.py"]
