-- =====================================================================
-- Laboratorio ETL · Unidad 4 · Paso 2. Staging
-- Revisa la estructura de las tablas stg_* y toma la huella (checksum) del
-- origen antes de transformar. Guarda la captura para compararla en el Paso 6.
-- Requiere haber ejecutado antes: la preparación (tablas raw cargadas).
-- Re-ejecutable: sí.
-- =====================================================================
USE u4_etl;

-- ===================== PASO 2: STAGING =====================
DESCRIBE stg_clientes;
DESCRIBE stg_pedidos;

CHECKSUM TABLE raw_clientes, raw_pedidos, catalogo_estados;
