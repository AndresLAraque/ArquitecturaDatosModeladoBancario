{# BUG REAL encontrado en Fase 5 (no en Fase 3, cuando se escribió esto):
   la versión anterior de este macro devolvía SIEMPRE target.schema sin
   importar el "+schema" de cada carpeta — silenciosamente mandaba TODOS
   los modelos (incluidos los marts de Gold: dim_*, fact_*, kpi_*) al
   dataset finbank_silver_dev, dejando finbank_gold_dev vacío. Pasó
   desapercibido en Fase 3 porque las queries de verificación de esa fase
   apuntaban a finbank_silver_dev.fact_cartera etc. sin cuestionar por qué
   funcionaba — "corría sin error" no es lo mismo que "estaba bien", la
   lección que motivó revisar esto recién en Fase 5 al probar el acceso
   IAM del rol Analista (con permiso correcto sobre finbank_gold_dev, pero
   la tabla física ni siquiera estaba ahí).

   Comportamiento correcto (estándar de dbt): si el modelo define un
   "+schema" custom (ver dbt_project.yml — marts: +schema: finbank_gold_dev),
   usarlo TAL CUAL, sin concatenar target.schema como prefijo. Si no define
   uno, usar target.schema (finbank_silver_dev) por defecto. #}
{% macro generate_schema_name(custom_schema_name, node) -%}
    {%- if custom_schema_name is none -%}
        {{ target.schema }}
    {%- else -%}
        {{ custom_schema_name | trim }}
    {%- endif -%}
{%- endmacro %}
