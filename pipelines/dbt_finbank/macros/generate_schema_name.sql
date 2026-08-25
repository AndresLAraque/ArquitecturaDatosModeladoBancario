{# Todos los modelos aterrizan en el dataset por defecto del target
   (finbank_silver_dev), sin importar el subfolder (staging/errors/quality).
   Sin este override, dbt-bigquery concatenaría un sufijo por cada
   "+schema" custom (ej. finbank_silver_dev_staging), fragmentando el
   dataset sin necesidad para un proyecto de este tamaño. #}
{% macro generate_schema_name(custom_schema_name, node) -%}
    {{ target.schema }}
{%- endmacro %}
