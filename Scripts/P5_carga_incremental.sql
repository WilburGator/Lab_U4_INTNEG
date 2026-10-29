-- =====================================================================
-- Laboratorio ETL · Unidad 4 · Paso 5. Carga incremental (UPSERT)
-- Carga dim_cliente y fact_ordenes con INSERT ... ON DUPLICATE KEY UPDATE.
-- Ejecutarlo varias veces no duplica hechos (idempotencia). Estas tablas NO se vacían.
-- Requiere haber ejecutado antes: Paso 4 (usa stg_clientes y stg_pedidos).
-- Re-ejecutable: sí.
-- =====================================================================
USE u4_etl;

-- ===================== PASO 5: CARGA INCREMENTAL (UPSERT) =====================
-- dim_cliente: clave natural id_cliente (SCD Tipo 1: se sobrescribe con el valor actual)

INSERT INTO dim_cliente (id_cliente, nombre, estado_canonico)
SELECT s.id_cliente, s.nombre, s.estado_canonico
FROM stg_clientes s
ON DUPLICATE KEY UPDATE
  nombre          = s.nombre,
  estado_canonico = s.estado_canonico;
SELECT ROW_COUNT() AS filas_afectadas_dim;

-- fact_ordenes: clave natural id_pedido
INSERT INTO fact_ordenes (id_pedido, id_cliente, fecha_pedido, estado_pedido, importe, ultima_carga)
SELECT s.id_pedido, s.id_cliente, s.fecha_pedido, s.estado_pedido, s.importe, NOW()
FROM stg_pedidos s
ON DUPLICATE KEY UPDATE
  id_cliente    = s.id_cliente,
  fecha_pedido  = s.fecha_pedido,
  estado_pedido = s.estado_pedido,
  importe       = s.importe,
  ultima_carga  = NOW();
SELECT ROW_COUNT() AS filas_afectadas_fact;

SELECT (SELECT COUNT(*) FROM dim_cliente)  AS filas_dim,
       (SELECT COUNT(*) FROM fact_ordenes) AS filas_fact,
       (SELECT MAX(ultima_carga) FROM fact_ordenes) AS ultima_carga;
