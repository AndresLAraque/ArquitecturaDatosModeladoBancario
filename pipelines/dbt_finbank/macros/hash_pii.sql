{# Enmascaramiento de columnas PII (requisito explícito: nombres, números
   de documento). Hash irreversible con salt — el valor original NO se
   conserva en Silver ni en capas posteriores, así que el perfil Analista
   nunca puede acceder a él, ni siquiera si tuviera permiso de lectura
   directo sobre la tabla (defensa adicional al control de IAM de Fase 5). #}
{% macro hash_pii(column_name) -%}
    TO_HEX(SHA256(CONCAT(CAST({{ column_name }} AS STRING), '{{ var("pii_salt") }}')))
{%- endmacro %}
