#!/bin/sh
# Un solo contenedor sirve a Silver y Gold — cuál corre lo decide la
# variable de entorno STAGE, que Cloud Run Job recibe distinta por cada
# uno de los dos google_cloud_run_v2_job (mismo image, distinto --args/env
# en infra/cloud_run.tf). Evita mantener dos imágenes casi idénticas.
set -e

if [ "$STAGE" = "silver" ]; then
    echo "=== Silver: aterrizando Bronze -> BigQuery ==="
    python /app/silver/load_bronze_to_bq.py --config /app/silver/config.yaml

    echo "=== Silver: dbt run (tag:silver) ==="
    cd /app/dbt_finbank
    dbt run --profiles-dir . --select tag:silver

    echo "=== Silver: dbt test (tag:silver) ==="
    dbt test --profiles-dir . --select tag:silver

elif [ "$STAGE" = "gold" ]; then
    cd /app/dbt_finbank
    echo "=== Gold: dbt run (tag:gold) ==="
    dbt run --profiles-dir . --select tag:gold

    echo "=== Gold: dbt test (tag:gold) ==="
    dbt test --profiles-dir . --select tag:gold

else
    echo "STAGE debe ser 'silver' o 'gold', recibido: '$STAGE'" >&2
    exit 1
fi
