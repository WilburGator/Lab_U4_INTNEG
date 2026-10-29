USE u4_etl;
-- ===================== PASO 1A: Exploracion =====================

#1-. Estructura: ¿Qué columnas y tipos hay?
DESCRIBE raw_clientes;
DESCRIBE raw_pedidos;

#2-. Conteos: Total contra únicos
SELECT 'clientes' AS tabla, COUNT(*) AS filas, COUNT(DISTINCT id_cliente) AS ids_unicos FROM raw_clientes
UNION ALL
SELECT 'pedidos', COUNT(*), COUNT(DISTINCT id_pedido) FROM raw_pedidos;

#3-. ¿Cuáles están repetidos?
SELECT id_cliente, COUNT(*) AS veces FROM raw_clientes
GROUP BY id_cliente HAVING COUNT(*) > 1;

SELECT id_pedido, COUNT(*) AS veces FROM raw_pedidos
GROUP BY id_pedido HAVING COUNT(*) > 1;

#4-. Estados: variantes y los que no están en el catálogo
-- Todas las formas en que viene escrito el estado
SELECT estado, COUNT(*) AS clientes FROM raw_clientes
GROUP BY estado ORDER BY estado;

-- Estados que NO tienen equivalencia en el catálogo
SELECT r.estado, COUNT(*) AS clientes
FROM raw_clientes r
LEFT JOIN catalogo_estados c ON TRIM(r.estado) = c.alias
WHERE c.alias IS NULL
GROUP BY r.estado;

-- Estatus de pedido (también vienen sin estandarizar)
SELECT estado_pedido, COUNT(*) AS pedidos FROM raw_pedidos
GROUP BY estado_pedido ORDER BY estado_pedido;

SELECT estado COLLATE utf8mb4_bin AS estado_exacto, COUNT(*) AS clientes
FROM raw_clientes GROUP BY estado_exacto ORDER BY estado_exacto;

SELECT estado_pedido COLLATE utf8mb4_bin AS estatus_exacto, COUNT(*) AS pedidos
FROM raw_pedidos GROUP BY estatus_exacto ORDER BY estatus_exacto;

#5-. Fechas: formatos y vacías
SELECT CASE
         WHEN fecha_pedido IS NULL OR TRIM(fecha_pedido) = '' THEN 'vacía'
         WHEN fecha_pedido REGEXP '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' THEN 'ISO (AAAA-MM-DD)'
         WHEN fecha_pedido REGEXP '^[0-9]{2}/[0-9]{2}/[0-9]{4}$' THEN 'DD/MM/AAAA'
         ELSE 'otro formato'
       END AS formato,
       COUNT(*) AS pedidos
FROM raw_pedidos
GROUP BY formato;

#6-. Montos no positivos
SELECT SUM(importe IS NULL) AS importe_nulo,
       SUM(importe <= 0)    AS importe_no_positivo,
       MIN(importe) AS minimo, MAX(importe) AS maximo
FROM raw_pedidos;

#7-. Pedidos de clientes que no existen
SELECT p.id_cliente, COUNT(*) AS pedidos
FROM raw_pedidos p
WHERE NOT EXISTS (SELECT 1 FROM raw_clientes c WHERE c.id_cliente = p.id_cliente)
GROUP BY p.id_cliente;

-- ===================== PASO 1B: TABLA DE OBSERVACIONES =====================

CREATE TABLE IF NOT EXISTS perfil_observaciones (
  id              INT AUTO_INCREMENT PRIMARY KEY,
  fecha_perfilado DATETIME DEFAULT CURRENT_TIMESTAMP,
  tabla           VARCHAR(50),
  columna         VARCHAR(50),
  prueba          VARCHAR(150),
  resultado       DECIMAL(14,2),
  comentario      VARCHAR(255)
);
TRUNCATE TABLE perfil_observaciones;   -- re-ejecutable: deja solo el perfilado más reciente

INSERT INTO perfil_observaciones (tabla, columna, prueba, resultado, comentario)
-- ---------- CLIENTES ----------
SELECT 'raw_clientes','*','Total de filas', COUNT(*), 'Filas recibidas de clientes.csv' FROM raw_clientes
UNION ALL
SELECT 'raw_clientes','id_cliente','IDs con más de una fila', COUNT(*), 'Clave natural repetida'
FROM (SELECT id_cliente FROM raw_clientes GROUP BY id_cliente HAVING COUNT(*) > 1) d
UNION ALL
SELECT 'raw_clientes','estado','Variantes de escritura (exactas)', COUNT(DISTINCT CAST(estado AS BINARY)), 'Mayúsculas, acentos y abreviaturas distintas'
FROM raw_clientes
UNION ALL
SELECT 'raw_clientes','estado','Estado vacío', SUM(TRIM(COALESCE(estado,'')) = ''), 'Sin dato de ubicación'
FROM raw_clientes
UNION ALL
SELECT 'raw_clientes','estado','Sin equivalencia en catálogo', COUNT(*), 'No se puede asignar clave estatal'
FROM raw_clientes r LEFT JOIN catalogo_estados c ON TRIM(r.estado) = c.alias WHERE c.alias IS NULL
UNION ALL
SELECT 'raw_clientes','email','Email vacío', SUM(TRIM(COALESCE(email,'')) = ''), 'Dato de contacto incompleto'
FROM raw_clientes
-- ---------- PEDIDOS ----------
UNION ALL
SELECT 'raw_pedidos','*','Total de filas', COUNT(*), 'Filas cargadas por pedidos.sql' FROM raw_pedidos
UNION ALL
SELECT 'raw_pedidos','id_pedido','IDs con más de una fila', COUNT(*), 'Pedido duplicado: riesgo de doble conteo'
FROM (SELECT id_pedido FROM raw_pedidos GROUP BY id_pedido HAVING COUNT(*) > 1) d
UNION ALL
SELECT 'raw_pedidos','fecha_pedido','Fecha vacía', SUM(TRIM(COALESCE(fecha_pedido,'')) = ''), 'No se puede ubicar en el tiempo'
FROM raw_pedidos
UNION ALL
SELECT 'raw_pedidos','fecha_pedido','Formato ISO AAAA-MM-DD', SUM(fecha_pedido REGEXP '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'), NULL
FROM raw_pedidos
UNION ALL
SELECT 'raw_pedidos','fecha_pedido','Formato DD/MM/AAAA', SUM(fecha_pedido REGEXP '^[0-9]{2}/[0-9]{2}/[0-9]{4}$'), 'Requiere conversión a DATE'
FROM raw_pedidos
UNION ALL
SELECT 'raw_pedidos','importe','Importe <= 0', SUM(importe <= 0), '¿Error o devolución? Pendiente de confirmar con negocio'
FROM raw_pedidos
UNION ALL
SELECT 'raw_pedidos','estado_pedido','Variantes de escritura (exactas)', COUNT(DISTINCT CAST(estado_pedido AS BINARY)), 'entregado / ENTREGADO / Entregado'
FROM raw_pedidos
UNION ALL
SELECT 'raw_pedidos','id_cliente','Cliente inexistente', COUNT(*), 'Pedido sin cliente en raw_clientes'
FROM raw_pedidos p WHERE NOT EXISTS (SELECT 1 FROM raw_clientes c WHERE c.id_cliente = p.id_cliente);

SELECT * FROM perfil_observaciones;


-- ===================== PASO 2: STAGING =====================
DESCRIBE stg_clientes;
DESCRIBE stg_pedidos;

CHECKSUM TABLE raw_clientes, raw_pedidos, catalogo_estados;

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