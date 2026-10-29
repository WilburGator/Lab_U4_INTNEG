-- =====================================================================
-- Laboratorio ETL · Unidad 4 · Paso 3. Normalización
-- Carga stg_clientes (estado canónico, NO_IDENT/SIN_CAT, deduplicación) y crea
-- la vista v_pedidos_norm (fechas a DATE, estatus homogéneo).
-- Requiere haber ejecutado antes: Paso 2.
-- Re-ejecutable: sí.
-- =====================================================================
USE u4_etl;

-- ===================== PASO 3: NORMALIZACIÓN =====================
-- 3A. Clientes: estado canónico + deduplicación

TRUNCATE TABLE stg_clientes;

INSERT INTO stg_clientes (id_cliente, nombre, email, estado_canonico)
SELECT id_cliente, nombre, email, estado_canonico
FROM (
  SELECT r.id_cliente,
         TRIM(r.nombre)            AS nombre,
         NULLIF(TRIM(r.email), '') AS email,
         COALESCE(c.estado_canonico,
                  CASE WHEN TRIM(COALESCE(r.estado,'')) = '' THEN 'NO_IDENT'
                       ELSE 'SIN_CAT' END) AS estado_canonico,
         ROW_NUMBER() OVER (PARTITION BY r.id_cliente ORDER BY r.fila_id DESC) AS rn
  FROM raw_clientes r
  LEFT JOIN catalogo_estados c ON c.alias = TRIM(r.estado)
  WHERE r.id_cliente IS NOT NULL
) t
WHERE rn = 1;

SELECT COUNT(*) AS clientes_stg FROM stg_clientes;
SELECT estado_canonico, COUNT(*) AS clientes
FROM stg_clientes GROUP BY estado_canonico ORDER BY clientes DESC;


-- 3B. Pedidos: fechas a DATE y estatus homogéneo

CREATE OR REPLACE VIEW v_pedidos_norm AS
SELECT p.fila_id,
       p.id_pedido,
       p.id_cliente,
       p.fecha_pedido AS fecha_original,
       CASE
         WHEN p.fecha_pedido REGEXP '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
              THEN STR_TO_DATE(p.fecha_pedido, '%Y-%m-%d')
         WHEN p.fecha_pedido REGEXP '^[0-9]{2}/[0-9]{2}/[0-9]{4}$'
              THEN STR_TO_DATE(p.fecha_pedido, '%d/%m/%Y')
         ELSE NULL
       END AS fecha_pedido,
       UPPER(TRIM(p.estado_pedido)) AS estado_pedido,
       p.importe
FROM raw_pedidos p;

-- Verificación
SELECT fecha_original, fecha_pedido FROM v_pedidos_norm
WHERE fecha_original LIKE '%/%' LIMIT 5;

SELECT estado_pedido, COUNT(*) AS pedidos
FROM v_pedidos_norm GROUP BY estado_pedido;

SELECT SUM(fecha_pedido IS NULL) AS sin_fecha_valida FROM v_pedidos_norm;
