# Contenedor "transform" — Silver y Gold (Cloud Run Job)

Una sola imagen Docker sirve a los Cloud Run Jobs `finbank-silver-dev` y
`finbank-gold-dev` (`infra/cloud_run.tf`) — cuál corre lo decide la
variable de entorno `STAGE` (`silver` o `gold`), ver `entrypoint.sh`.
Evita mantener dos imágenes casi idénticas para dos etapas que comparten
el mismo proyecto dbt.

- `STAGE=silver` → `pipelines/silver/load_bronze_to_bq.py` + `dbt run/test --select tag:silver`
- `STAGE=gold` → `dbt run/test --select tag:gold`

## Build (contexto = `pipelines/`, no `pipelines/transform/`)

```bash
docker build -f pipelines/transform/Dockerfile -t <repo>/transform:latest pipelines/
docker push <repo>/transform:latest
```

Necesita el contexto en `pipelines/` (no en `pipelines/transform/`) porque
copia archivos de `silver/`, `dbt_finbank/` y `common/` — tres carpetas
hermanas, no solo la suya.
