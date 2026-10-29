-- =====================================================================
-- Laboratorio ETL · Unidad 4 · Paso 7. Indicadores
-- Crea la vista v_kpi_ventas_estado_fecha y obtiene ventas netas y pedidos
-- entregados por estado y fecha, con su control contra fact_ordenes.
-- Requiere haber ejecutado antes: Paso 5 (usa fact_ordenes y dim_cliente).
-- Re-ejecutable: sí.
-- =====================================================================
USE u4_etl;

-- ===================== PASO 7: INDICADORES =====================
-- SUPUESTO DOCUMENTADO: "ventas netas" = suma de importes de pedidos con estatus ENTREGADO.
-- No se modelan descuentos, impuestos ni devoluciones; NO equivale a ventas contables reales.
-- Pedidos CANCELADOS, PENDIENTES y ENVIADOS no cuentan como venta efectiva.
CREATE OR REPLACE VIEW v_kpi_ventas_estado_fecha AS
SELECT d.estado_canonico,
       e.nombre_oficial,
       f.fecha_pedido,
       COUNT(DISTINCT f.id_pedido) AS pedidos_entregados,
       SUM(f.importe)              AS ventas_netas
FROM fact_ordenes f
JOIN dim_cliente d ON d.id_cliente = f.id_cliente
LEFT JOIN (SELECT estado_canonico, MAX(nombre_oficial) AS nombre_oficial
           FROM catalogo_estados GROUP BY estado_canonico) e
       ON e.estado_canonico = d.estado_canonico
WHERE f.estado_pedido = 'ENTREGADO'
GROUP BY d.estado_canonico, e.nombre_oficial, f.fecha_pedido;

-- 7A. Consulta final: ventas netas y pedidos entregados por estado y fecha
SELECT * FROM v_kpi_ventas_estado_fecha
ORDER BY estado_canonico, fecha_pedido;

-- 7B. Resumen por estado (más fácil de leer)
SELECT estado_canonico, nombre_oficial,
       SUM(pedidos_entregados) AS pedidos_entregados,
       SUM(ventas_netas)       AS ventas_netas,
       ROUND(100 * SUM(ventas_netas) /
             (SELECT SUM(ventas_netas) FROM v_kpi_ventas_estado_fecha), 2) AS pct_ventas
FROM v_kpi_ventas_estado_fecha
GROUP BY estado_canonico, nombre_oficial
ORDER BY ventas_netas DESC;

-- 7C. Tendencia mensual por estado
SELECT estado_canonico,
       DATE_FORMAT(fecha_pedido, '%Y-%m') AS mes,
       SUM(pedidos_entregados) AS pedidos_entregados,
       SUM(ventas_netas)       AS ventas_netas
FROM v_kpi_ventas_estado_fecha
GROUP BY estado_canonico, mes
ORDER BY estado_canonico, mes;

-- 7D. Control: el indicador cuadra con la tabla de hechos
SELECT (SELECT SUM(pedidos_entregados) FROM v_kpi_ventas_estado_fecha) AS pedidos_kpi,
       (SELECT COUNT(*) FROM fact_ordenes WHERE estado_pedido = 'ENTREGADO') AS pedidos_fact,
       (SELECT SUM(ventas_netas) FROM v_kpi_ventas_estado_fecha) AS ventas_kpi,
       (SELECT SUM(importe) FROM fact_ordenes WHERE estado_pedido = 'ENTREGADO') AS ventas_fact;
