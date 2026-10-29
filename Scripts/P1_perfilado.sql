-- =====================================================================
-- Laboratorio ETL · Unidad 4 · Paso 1. Perfilado
-- Explora estructura, conteos, duplicados, estados, fechas, montos y clientes
-- inexistentes; guarda los hallazgos en perfil_observaciones.
-- Requiere haber ejecutado antes: 01_creacion_bd.sql, pedidos.sql y 02_carga_clientes_catalogo.sql.
-- Re-ejecutable: sí.
-- =====================================================================
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
