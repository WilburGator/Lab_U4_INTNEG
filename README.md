# Laboratorio ETL · Data Mart de ventas por estado y fecha

Proyecto académico de la Unidad 4 (*Flujos de información y procesos de negocio*) del curso **Analítica e Inteligencia de Negocios**, FIME – UANL. Equipo #1.

Una tienda de comercio electrónico recibe `clientes.csv` y `pedidos.sql` con errores intencionales: duplicados, estados escritos de muchas formas, fechas en dos formatos, importes negativos y clientes que no existen. El objetivo es construir con **MySQL** un Data Mart de ventas por estado y fecha mediante un proceso ETL reproducible, sin modificar los datos originales y con trazabilidad de cada registro rechazado.

> Los datos son **ficticios** y fueron proporcionados para uso académico.

## Arquitectura

```
raw_*  (datos tal como llegaron, nunca se modifican)
   →  stg_*  (datos limpios y normalizados)
        ↘  rechazos_pedidos  (registros inválidos, con su motivo)
   →  dim_cliente / fact_ordenes  (modelo dimensional, carga UPSERT)
   →  v_kpi_ventas_estado_fecha  (ventas netas y pedidos entregados por estado y fecha)
```

## Estructura del repositorio

```
├── Recursos de la practica/          Archivos de origen proporcionados
│   ├── 01_creacion_bd.sql            Crea la base u4_etl y sus tablas
│   ├── pedidos.sql                   Carga raw_pedidos
│   ├── clientes.csv                  Clientes (con errores intencionales)
│   ├── catalogo_estados.csv          Catálogo de alias de estados
│   └── README_Alumnos.docx           Instrucciones de la práctica
├── 02_carga_clientes_catalogo.sql    Carga los dos CSV a las tablas raw
├── 03_etl_unidad4.sql                Proceso ETL completo en un solo script
└── Scripts/                          El mismo proceso, un script por paso
    ├── P1_perfilado.sql
    ├── P2_staging.sql
    ├── P3_normalizacion.sql
    ├── P4_validacion_rechazos.sql
    ├── P5_carga_incremental.sql
    ├── P6_conciliacion.sql
    └── P7_indicadores.sql
```

## Requisitos

- MySQL Server 8.0 o superior (se usó **8.4 LTS**).
- MySQL Workbench **8.0.x clásico** (se usó 8.0.47). La versión 26.x ya no incluye el *Table Data Import Wizard*.

## Cómo ejecutarlo

En MySQL Workbench: **File → Open SQL Script** y ejecutar todo con el rayo ⚡.

1. `Recursos de la practica/01_creacion_bd.sql`
2. `Recursos de la practica/pedidos.sql` (**una sola vez**; si se repite, se duplican las filas de origen)
3. `02_carga_clientes_catalogo.sql` (se puede re-ejecutar)
4. `03_etl_unidad4.sql`, o bien los scripts de `Scripts/` en orden, de P1 a P7.

Todos los pasos se pueden volver a ejecutar sin duplicar datos: las tablas de trabajo se vacían con `TRUNCATE` y las tablas finales se cargan con UPSERT. La excepción es P6, que agrega una fila a la bitácora `etl_auditoria` en cada ejecución.

> **¿Por qué `02_carga_clientes_catalogo.sql` y no el asistente de importación?** El *Table Data Import Wizard* dañaba los acentos de los CSV (`México` → `MÃ©xico`) aunque se seleccionara UTF-8. Por eso el script inserta los valores exactos de los archivos sin corregir nada.

## Pasos del proceso

| Paso | Qué hace |
|---|---|
| 1. Perfilado | Mide duplicados, variantes de escritura, fechas, importes y claves huérfanas; guarda los hallazgos en `perfil_observaciones`. |
| 2. Staging | Separa la zona `raw_*` (inmutable) de `stg_*` (normalizada) y toma un `CHECKSUM` del origen. |
| 3. Normalización | Asigna la clave estatal con el catálogo (`NO_IDENT` si el estado viene vacío, `SIN_CAT` si no está en el catálogo), deduplica clientes con `ROW_NUMBER()` y convierte fechas ISO y DD/MM/AAAA a `DATE`. |
| 4. Validación | Envía a `rechazos_pedidos`, con su motivo, los pedidos duplicados, con cliente inexistente, sin fecha válida, con importe ≤ 0, con estatus no reconocido o de clientes sin estado. |
| 5. Carga incremental | `INSERT … ON DUPLICATE KEY UPDATE` sobre las claves naturales; repetir la carga no duplica hechos (idempotencia). |
| 6. Conciliación | Comprueba que origen = aceptadas + rechazadas y que el importe de staging = hechos, y registra la ejecución en `etl_auditoria`. |
| 7. Indicadores | Ventas netas (pedidos ENTREGADOS) y pedidos entregados por estado y fecha. |

## Resultados

| Concepto | Valor |
|---|---|
| Pedidos de origen | 2,012 |
| Pedidos aceptados / rechazados | 1,883 / 129 |
| Total bruto | $6,023,923.87 |
| Total válido | $5,805,137.45 |
| Ventas netas (pedidos entregados) | $2,960,569.02 (975 pedidos) |

**Supuesto:** las ventas netas se definen como la suma de importes de los pedidos con estatus ENTREGADO. No se modelan descuentos, impuestos ni devoluciones, por lo que esta cifra no equivale a las ventas contables reales.
# Lab_U4_INTNEG
