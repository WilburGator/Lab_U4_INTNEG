-- =====================================================================
-- Laboratorio ETL · Unidad 4 · Paso 6. Conciliación
-- Cuadra filas e importes (raw = aceptadas + rechazadas; stg = fact), registra la
-- ejecución en etl_auditoria y compara el checksum con el del Paso 2.
-- Requiere haber ejecutado antes: Paso 5.
-- Re-ejecutable: sí.
-- =====================================================================
USE u4_etl;

-- ===================== PASO 6: CONCILIACIÓN =====================
-- 6A. Cuadre de filas: origen = aceptadas + rechazadas

SELECT (SELECT COUNT(*) FROM raw_pedidos)      AS filas_raw,
       (SELECT COUNT(*) FROM stg_pedidos)      AS aceptadas_unicas,
       (SELECT COUNT(*) FROM rechazos_pedidos) AS rechazadas,
       (SELECT COUNT(*) FROM raw_pedidos)
         - (SELECT COUNT(*) FROM stg_pedidos)
         - (SELECT COUNT(*) FROM rechazos_pedidos) AS diferencia;   -- debe ser 0

-- 6B. Cuadre de importes: bruto = válido + rechazado, y staging = hechos
SELECT (SELECT SUM(importe) FROM raw_pedidos)  AS total_bruto,
       (SELECT SUM(importe) FROM stg_pedidos)  AS total_valido_stg,
       (SELECT SUM(importe) FROM fact_ordenes) AS total_fact,
       (SELECT SUM(p.importe) FROM raw_pedidos p
          JOIN rechazos_pedidos r ON r.fila_id = p.fila_id) AS total_rechazado;

-- 6C. ¿De dónde viene la diferencia entre bruto y válido?
SELECT SUBSTRING_INDEX(r.motivo, ' (', 1) AS tipo_rechazo,
       COUNT(*) AS filas, SUM(p.importe) AS importe
FROM rechazos_pedidos r
JOIN raw_pedidos p ON p.fila_id = r.fila_id
GROUP BY tipo_rechazo ORDER BY importe DESC;

-- 6D. Registrar la ejecución en la bitácora de auditoría
INSERT INTO etl_auditoria
  (fecha_ejecucion, filas_origen, filas_validas, filas_rechazadas, filas_fact, ventas_validas, nota)
SELECT NOW(), o.n, v.n, r.n, f.n, v.imp,
       CASE WHEN o.n = v.n + r.n AND v.imp = f.imp
            THEN 'OK: origen = válidas + rechazadas; importe stg = fact'
            ELSE 'REVISAR: descuadre de filas o importes' END
FROM       (SELECT COUNT(*) AS n FROM raw_pedidos) o
CROSS JOIN (SELECT COUNT(*) AS n, COALESCE(SUM(importe),0) AS imp FROM stg_pedidos) v
CROSS JOIN (SELECT COUNT(*) AS n FROM rechazos_pedidos) r
CROSS JOIN (SELECT COUNT(*) AS n, COALESCE(SUM(importe),0) AS imp FROM fact_ordenes) f;

SELECT * FROM etl_auditoria ORDER BY id DESC;

-- 6E. Prueba de que raw no cambió (compara con tu captura del Paso 2)
CHECKSUM TABLE raw_clientes, raw_pedidos, catalogo_estados;
