-- Gold: TB_SUCURSALES_RED -> dim_geografia
--
-- Dimensión curada (no derivada por SELECT DISTINCT de una sola tabla a
-- propósito): fact_transacciones referencia la ciudad por CÓDIGO
-- (cod_ciudad, ej. "BOG") mientras que TB_SUCURSALES_RED la guarda como
-- NOMBRE completo ("Bogotá") — son sistemas distintos con nomenclatura
-- distinta, un caso real de inconsistencia entre sistemas de origen. Esta
-- dimensión concilia ambos con la misma tabla de referencia usada para
-- generar los datos sintéticos (data-generation/reference_data.py),
-- documentado aquí como una dimensión conformada mantenida por el equipo
-- de datos, no auto-derivada.

select * from unnest([
    struct('BOG' as cod_ciudad, 'Bogotá' as ciudad, 'Cundinamarca' as depto, 'Colombia' as pais),
    struct('MED', 'Medellín', 'Antioquia', 'Colombia'),
    struct('CAL', 'Cali', 'Valle del Cauca', 'Colombia'),
    struct('BAQ', 'Barranquilla', 'Atlántico', 'Colombia'),
    struct('BGA', 'Bucaramanga', 'Santander', 'Colombia'),
    struct('CDMX', 'Ciudad de México', 'CDMX', 'México'),
    struct('GDL', 'Guadalajara', 'Jalisco', 'México'),
    struct('MTY', 'Monterrey', 'Nuevo León', 'México'),
    struct('LIM', 'Lima', 'Lima', 'Perú'),
    struct('AQP', 'Arequipa', 'Arequipa', 'Perú'),
    struct('SCL', 'Santiago', 'Región Metropolitana', 'Chile'),
    struct('VAP', 'Valparaíso', 'Valparaíso', 'Chile'),
    struct('BUE', 'Buenos Aires', 'CABA', 'Argentina'),
    struct('COR', 'Córdoba', 'Córdoba', 'Argentina')
])
