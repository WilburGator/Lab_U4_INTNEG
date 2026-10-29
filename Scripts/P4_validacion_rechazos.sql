-- =====================================================================
-- Laboratorio ETL · Unidad 4 · Paso 4. Validación y rechazos
-- Aplica las reglas de validación: pedidos válidos a stg_pedidos e inválidos a
-- rechazos_pedidos con su motivo.
-- Requiere haber ejecutado antes: Paso 3 (usa stg_clientes y v_pedidos_norm).
-- Re-ejecutable: sí.
-- =====================================================================
USE u4_etl;

-- ===================== PASO 4: VALIDACIÓN Y RECHAZOS =====================
-- Decisión: los pedidos de clientes sin estado reconocido (NO_IDENT / SIN_CAT) se rechazan,
-- porque no pueden asignarse a ningún estado en el Data Mart. El cliente sí se conserva.

CREATE OR REPLACE VIEW v_pedidos_validacion AS
SELECT v.*,
       NULLIF(CONCAT_WS('; ',
         CASE WHEN v.id_pedido IS NULL THEN 'id_pedido nulo' END,
         CASE WHEN v.rn > 1 THEN CONCAT('Pedido duplicado (id_pedido ', v.id_pedido, ')') END,
         CASE WHEN v.cliente_encontrado IS NULL
              THEN CONCAT('Cliente inexistente (', COALESCE(v.id_cliente, 'NULL'), ')') END,
         CASE WHEN v.fecha_pedido IS NULL
              THEN CONCAT('Fecha inválida o vacía (''', COALESCE(v.fecha_original, 'NULL'), ''')') END,
         CASE WHEN v.importe IS NULL OR v.importe <= 0
              THEN CONCAT('Importe no positivo (', COALESCE(v.importe, 'NULL'), ')') END,
         CASE WHEN v.estado_pedido IS NULL
                OR v.estado_pedido NOT IN ('ENTREGADO','CANCELADO','ENVIADO','PENDIENTE')
              THEN CONCAT('Estatus no reconocido (', COALESCE(v.estado_pedido, 'NULL'), ')') END,
         CASE WHEN v.estado_cliente IN ('NO_IDENT','SIN_CAT')
              THEN CONCAT('Estado del cliente no reconocido (', v.estado_cliente, ')') END
       ), '') AS motivo
FROM (
  SELECT n.*,
         c.id_cliente      AS cliente_encontrado,
         c.estado_canonico AS estado_cliente,
         ROW_NUMBER() OVER (PARTITION BY n.id_pedido ORDER BY n.fila_id) AS rn
  FROM v_pedidos_norm n
  LEFT JOIN stg_clientes c ON c.id_cliente = n.id_cliente
) v;

TRUNCATE TABLE rechazos_pedidos;
INSERT INTO rechazos_pedidos (fila_id, id_pedido, motivo)
SELECT fila_id, id_pedido, motivo FROM v_pedidos_validacion WHERE motivo IS NOT NULL;

TRUNCATE TABLE stg_pedidos;
INSERT INTO stg_pedidos (id_pedido, id_cliente, fecha_pedido, estado_pedido, importe)
SELECT id_pedido, id_cliente, fecha_pedido, estado_pedido, importe
FROM v_pedidos_validacion WHERE motivo IS NULL;

-- Verificación
SELECT (SELECT COUNT(*) FROM raw_pedidos)      AS filas_raw,
       (SELECT COUNT(*) FROM stg_pedidos)      AS aceptadas,
       (SELECT COUNT(*) FROM rechazos_pedidos) AS rechazadas;

SELECT SUBSTRING_INDEX(motivo, ' (', 1) AS tipo_rechazo, COUNT(*) AS filas
FROM rechazos_pedidos GROUP BY tipo_rechazo ORDER BY filas DESC;

-- Filas que fallan más de una regla
SELECT * FROM rechazos_pedidos WHERE motivo LIKE '%;%';
