/* =========================================================
   06_indices_y_consultas_optimizadas.sql  -  E3 (Unidad II)
   En SSMS activar "Incluir plan de ejecución real" (Ctrl+M) y
   ejecutar cada sección por separado para capturar planes y
   los mensajes de STATISTICS IO / TIME.

   NOTA SOBRE LA LÍNEA BASE: el índice único filtrado de E1
   (UX_Boletos_AsientoActivo) también acelera C1. Para medir un
   "antes" honesto, la sección A lo DESHABILITA y luego lo
   reconstruye. La línea base más pura se obtiene corriendo
   03_consultas_lentas.sql (con tus parámetros) justo después de
   crear la base, ANTES de 01_integridad.sql.
   ========================================================= */
USE BusRD;
GO

/* =========================================================
   A. LÍNEA BASE (consultas originales)
   ========================================================= */
DROP INDEX IF EXISTS IX_Boletos_Cliente       ON dbo.Boletos;
DROP INDEX IF EXISTS IX_Boletos_Estado_Fecha  ON dbo.Boletos;
DROP INDEX IF EXISTS IX_Pagos_Boleto          ON dbo.Pagos;
ALTER INDEX UX_Boletos_AsientoActivo ON dbo.Boletos DISABLE;
GO
SET STATISTICS IO ON;
SET STATISTICS TIME ON;
GO

/* C1 original - viaje asignado al grupo */
DECLARE @ViajeID INT = 16000;      -- <<< CAMBIAR: viaje asignado al grupo
SELECT s.NumeroAsiento, s.Ubicacion
FROM dbo.Viajes v
JOIN dbo.Asientos s ON s.AutobusID = v.AutobusID
WHERE v.ViajeID = @ViajeID
  AND s.NumeroAsiento NOT IN (SELECT b.NumeroAsiento
                              FROM dbo.Boletos b
                              WHERE b.ViajeID = @ViajeID
                                AND b.Estado = 'Activo')
ORDER BY s.NumeroAsiento;
GO

/* C2 original - cliente N° (grupo x 1000) */
DECLARE @Grupo INT = 8;            -- <<< CAMBIAR: número de grupo
DECLARE @Cedula CHAR(11) = '402' + RIGHT('00000000' + CAST(@Grupo * 1000 AS VARCHAR(8)), 8);
SELECT c.Nombre, c.Apellido, r.Origen, r.Destino,
       v.FechaSalida, b.NumeroAsiento, b.Precio, b.Estado
FROM dbo.Clientes c
JOIN dbo.Boletos b ON b.ClienteID = c.ClienteID
JOIN dbo.Viajes  v ON v.ViajeID   = b.ViajeID
JOIN dbo.Rutas   r ON r.RutaID    = v.RutaID
WHERE LTRIM(RTRIM(c.Cedula)) = @Cedula
ORDER BY v.FechaSalida DESC;
GO

/* C3 original - ingresos mensuales 2025 */
SELECT r.Origen, r.Destino, MONTH(b.FechaVenta) AS Mes,
       COUNT(*) AS Boletos, SUM(p.Monto) AS Ingresos
FROM dbo.Boletos b
JOIN dbo.Pagos  p ON p.BoletoID = b.BoletoID
JOIN dbo.Viajes v ON v.ViajeID  = b.ViajeID
JOIN dbo.Rutas  r ON r.RutaID   = v.RutaID
WHERE YEAR(b.FechaVenta) = 2025
  AND b.Estado = 'Activo'
GROUP BY r.Origen, r.Destino, MONTH(b.FechaVenta)
ORDER BY r.Origen, r.Destino, Mes;
GO

SET STATISTICS IO OFF;
SET STATISTICS TIME OFF;
GO
ALTER INDEX UX_Boletos_AsientoActivo ON dbo.Boletos REBUILD;   -- se vuelve a activar la unicidad
GO

/* =========================================================
   B. ÍNDICES
   --------------------------------------------------------
   C1 -> Usa UX_Boletos_AsientoActivo (ViajeID, NumeroAsiento) WHERE Estado='Activo':
         la subconsulta busca por ViajeID (seek) y devuelve NumeroAsiento desde la
         propia llave, sin tocar la tabla (cubre la consulta). Al ser filtrado solo
         guarda boletos activos: es pequeño. Ya existe desde E1.
   C2 -> UQ_Clientes_Cedula (E1) permite buscar el cliente por cédula (seek).
         IX_Boletos_Cliente: llave ClienteID (el JOIN/filtro) + INCLUDE de las
         columnas que se devuelven, para evitar Key Lookups sobre el clustered.
   C3 -> IX_Boletos_Estado_Fecha: igualdad en Estado + rango en FechaVenta como
         llaves (seek por rango); INCLUDE ViajeID para el JOIN con Viajes.
         IX_Pagos_Boleto: llave BoletoID (JOIN) + INCLUDE Monto (lo que se suma),
         así Pagos no se lee completo.
   ========================================================= */
CREATE NONCLUSTERED INDEX IX_Boletos_Cliente
    ON dbo.Boletos (ClienteID)
    INCLUDE (ViajeID, NumeroAsiento, Precio, Estado);

CREATE NONCLUSTERED INDEX IX_Boletos_Estado_Fecha
    ON dbo.Boletos (Estado, FechaVenta)
    INCLUDE (ViajeID);

CREATE NONCLUSTERED INDEX IX_Pagos_Boleto
    ON dbo.Pagos (BoletoID)
    INCLUDE (Monto);
GO

/* =========================================================
   C. CONSULTAS REESCRITAS (después)
   C1: NOT IN -> NOT EXISTS (misma semántica: NumeroAsiento es NOT NULL).
   C2: se elimina LTRIM(RTRIM()) sobre la columna: una función sobre la
       columna impide el seek (no sargable). Cedula es CHAR(11) sin espacios.
   C3: se elimina YEAR() sobre la columna; se usa un rango semiabierto
       [2025-01-01, 2026-01-01).
   ========================================================= */
SET STATISTICS IO ON;
SET STATISTICS TIME ON;
GO

/* C1 optimizada */
DECLARE @ViajeID INT = 16000;      -- <<< CAMBIAR (mismo valor)
SELECT s.NumeroAsiento, s.Ubicacion
FROM dbo.Viajes v
JOIN dbo.Asientos s ON s.AutobusID = v.AutobusID
WHERE v.ViajeID = @ViajeID
  AND NOT EXISTS (SELECT 1
                  FROM dbo.Boletos b
                  WHERE b.ViajeID = @ViajeID
                    AND b.NumeroAsiento = s.NumeroAsiento
                    AND b.Estado = 'Activo')
ORDER BY s.NumeroAsiento;
GO

/* C2 optimizada */
DECLARE @Grupo INT = 8;            -- <<< CAMBIAR (mismo valor)
DECLARE @Cedula CHAR(11) = '402' + RIGHT('00000000' + CAST(@Grupo * 1000 AS VARCHAR(8)), 8);
SELECT c.Nombre, c.Apellido, r.Origen, r.Destino,
       v.FechaSalida, b.NumeroAsiento, b.Precio, b.Estado
FROM dbo.Clientes c
JOIN dbo.Boletos b ON b.ClienteID = c.ClienteID
JOIN dbo.Viajes  v ON v.ViajeID   = b.ViajeID
JOIN dbo.Rutas   r ON r.RutaID    = v.RutaID
WHERE c.Cedula = @Cedula
ORDER BY v.FechaSalida DESC;
GO

/* C3 optimizada */
SELECT r.Origen, r.Destino, MONTH(b.FechaVenta) AS Mes,
       COUNT(*) AS Boletos, SUM(p.Monto) AS Ingresos
FROM dbo.Boletos b
JOIN dbo.Pagos  p ON p.BoletoID = b.BoletoID
JOIN dbo.Viajes v ON v.ViajeID  = b.ViajeID
JOIN dbo.Rutas  r ON r.RutaID   = v.RutaID
WHERE b.Estado = 'Activo'
  AND b.FechaVenta >= '20250101'
  AND b.FechaVenta <  '20260101'
GROUP BY r.Origen, r.Destino, MONTH(b.FechaVenta)
ORDER BY r.Origen, r.Destino, Mes;
GO

SET STATISTICS IO OFF;
SET STATISTICS TIME OFF;
GO

/* =========================================================
   D. MISMO RESULTADO: original vs. optimizada
   Cada bloque debe devolver 0 en las dos columnas "Solo en..." y
   el mismo número de filas.
   ========================================================= */
DECLARE @ViajeID INT = 16000;      -- <<< CAMBIAR (mismo valor)
DECLARE @Grupo INT = 8;            -- <<< CAMBIAR (mismo valor)
DECLARE @Cedula CHAR(11) = '402' + RIGHT('00000000' + CAST(@Grupo * 1000 AS VARCHAR(8)), 8);

IF OBJECT_ID('tempdb..#c1a') IS NOT NULL DROP TABLE #c1a;
IF OBJECT_ID('tempdb..#c1b') IS NOT NULL DROP TABLE #c1b;
IF OBJECT_ID('tempdb..#c2a') IS NOT NULL DROP TABLE #c2a;
IF OBJECT_ID('tempdb..#c2b') IS NOT NULL DROP TABLE #c2b;
IF OBJECT_ID('tempdb..#c3a') IS NOT NULL DROP TABLE #c3a;
IF OBJECT_ID('tempdb..#c3b') IS NOT NULL DROP TABLE #c3b;

-- C1
SELECT s.NumeroAsiento, s.Ubicacion INTO #c1a
FROM dbo.Viajes v JOIN dbo.Asientos s ON s.AutobusID = v.AutobusID
WHERE v.ViajeID = @ViajeID
  AND s.NumeroAsiento NOT IN (SELECT b.NumeroAsiento FROM dbo.Boletos b
                              WHERE b.ViajeID = @ViajeID AND b.Estado = 'Activo');
SELECT s.NumeroAsiento, s.Ubicacion INTO #c1b
FROM dbo.Viajes v JOIN dbo.Asientos s ON s.AutobusID = v.AutobusID
WHERE v.ViajeID = @ViajeID
  AND NOT EXISTS (SELECT 1 FROM dbo.Boletos b
                  WHERE b.ViajeID = @ViajeID AND b.NumeroAsiento = s.NumeroAsiento AND b.Estado = 'Activo');

-- C2
SELECT c.Nombre, c.Apellido, r.Origen, r.Destino, v.FechaSalida, b.NumeroAsiento, b.Precio, b.Estado INTO #c2a
FROM dbo.Clientes c JOIN dbo.Boletos b ON b.ClienteID = c.ClienteID
JOIN dbo.Viajes v ON v.ViajeID = b.ViajeID JOIN dbo.Rutas r ON r.RutaID = v.RutaID
WHERE LTRIM(RTRIM(c.Cedula)) = @Cedula;
SELECT c.Nombre, c.Apellido, r.Origen, r.Destino, v.FechaSalida, b.NumeroAsiento, b.Precio, b.Estado INTO #c2b
FROM dbo.Clientes c JOIN dbo.Boletos b ON b.ClienteID = c.ClienteID
JOIN dbo.Viajes v ON v.ViajeID = b.ViajeID JOIN dbo.Rutas r ON r.RutaID = v.RutaID
WHERE c.Cedula = @Cedula;

-- C3
SELECT r.Origen, r.Destino, MONTH(b.FechaVenta) AS Mes, COUNT(*) AS Boletos, SUM(p.Monto) AS Ingresos INTO #c3a
FROM dbo.Boletos b JOIN dbo.Pagos p ON p.BoletoID = b.BoletoID
JOIN dbo.Viajes v ON v.ViajeID = b.ViajeID JOIN dbo.Rutas r ON r.RutaID = v.RutaID
WHERE YEAR(b.FechaVenta) = 2025 AND b.Estado = 'Activo'
GROUP BY r.Origen, r.Destino, MONTH(b.FechaVenta);
SELECT r.Origen, r.Destino, MONTH(b.FechaVenta) AS Mes, COUNT(*) AS Boletos, SUM(p.Monto) AS Ingresos INTO #c3b
FROM dbo.Boletos b JOIN dbo.Pagos p ON p.BoletoID = b.BoletoID
JOIN dbo.Viajes v ON v.ViajeID = b.ViajeID JOIN dbo.Rutas r ON r.RutaID = v.RutaID
WHERE b.Estado = 'Activo' AND b.FechaVenta >= '20250101' AND b.FechaVenta < '20260101'
GROUP BY r.Origen, r.Destino, MONTH(b.FechaVenta);

SELECT 'C1' AS Consulta,
       (SELECT COUNT(*) FROM #c1a) AS FilasOriginal, (SELECT COUNT(*) FROM #c1b) AS FilasOptimizada,
       (SELECT COUNT(*) FROM (SELECT * FROM #c1a EXCEPT SELECT * FROM #c1b) x) AS SoloEnOriginal,
       (SELECT COUNT(*) FROM (SELECT * FROM #c1b EXCEPT SELECT * FROM #c1a) x) AS SoloEnOptimizada
UNION ALL
SELECT 'C2',
       (SELECT COUNT(*) FROM #c2a), (SELECT COUNT(*) FROM #c2b),
       (SELECT COUNT(*) FROM (SELECT * FROM #c2a EXCEPT SELECT * FROM #c2b) x),
       (SELECT COUNT(*) FROM (SELECT * FROM #c2b EXCEPT SELECT * FROM #c2a) x)
UNION ALL
SELECT 'C3',
       (SELECT COUNT(*) FROM #c3a), (SELECT COUNT(*) FROM #c3b),
       (SELECT COUNT(*) FROM (SELECT * FROM #c3a EXCEPT SELECT * FROM #c3b) x),
       (SELECT COUNT(*) FROM (SELECT * FROM #c3b EXCEPT SELECT * FROM #c3a) x);
GO

/* =========================================================
   E. ¿LOS ÍNDICES AFECTAN A sp_VenderBoleto? (índices vs. escrituras)
   Se ejecutan 300 ventas dentro de una transacción externa que luego
   se REVIERTE (no deja datos). Se mide con los índices de E3 y sin ellos.
   Siempre permanece UX_Boletos_AsientoActivo (es de integridad).
   ========================================================= */
IF OBJECT_ID('tempdb..#Prueba') IS NOT NULL DROP TABLE #Prueba;
SELECT TOP (300)
       ROW_NUMBER() OVER (ORDER BY v.ViajeID) AS rn,
       v.ViajeID,
       (SELECT MAX(s.NumeroAsiento) FROM dbo.Asientos s
        WHERE s.AutobusID = v.AutobusID
          AND NOT EXISTS (SELECT 1 FROM dbo.Boletos b
                          WHERE b.ViajeID = v.ViajeID AND b.NumeroAsiento = s.NumeroAsiento
                            AND b.Estado = 'Activo')) AS Asiento
INTO #Prueba
FROM dbo.Viajes v
WHERE v.Estado = 'Programado'
ORDER BY v.ViajeID;
GO

-- E.1 CON los índices de E3
DECLARE @i INT = 1, @n INT = (SELECT COUNT(*) FROM #Prueba), @id INT, @v INT, @a INT;
DECLARE @t0 DATETIME2(7) = SYSDATETIME();
BEGIN TRAN;
WHILE @i <= @n
BEGIN
    SELECT @v = ViajeID, @a = Asiento FROM #Prueba WHERE rn = @i;
    EXEC dbo.sp_VenderBoleto @v, @a, 1, 'Taquilla', 'Efectivo', @id OUTPUT;
    SET @i += 1;
END
ROLLBACK;
SELECT 'CON índices de E3' AS Escenario, @n AS Ventas,
       DATEDIFF(MILLISECOND, @t0, SYSDATETIME()) AS Milisegundos;
GO

-- E.2 SIN los índices de E3
DROP INDEX IX_Boletos_Cliente      ON dbo.Boletos;
DROP INDEX IX_Boletos_Estado_Fecha ON dbo.Boletos;
DROP INDEX IX_Pagos_Boleto         ON dbo.Pagos;
GO
DECLARE @i INT = 1, @n INT = (SELECT COUNT(*) FROM #Prueba), @id INT, @v INT, @a INT;
DECLARE @t0 DATETIME2(7) = SYSDATETIME();
BEGIN TRAN;
WHILE @i <= @n
BEGIN
    SELECT @v = ViajeID, @a = Asiento FROM #Prueba WHERE rn = @i;
    EXEC dbo.sp_VenderBoleto @v, @a, 1, 'Taquilla', 'Efectivo', @id OUTPUT;
    SET @i += 1;
END
ROLLBACK;
SELECT 'SIN índices de E3' AS Escenario, @n AS Ventas,
       DATEDIFF(MILLISECOND, @t0, SYSDATETIME()) AS Milisegundos;
GO

-- E.3 Volver a crear los índices
CREATE NONCLUSTERED INDEX IX_Boletos_Cliente
    ON dbo.Boletos (ClienteID) INCLUDE (ViajeID, NumeroAsiento, Precio, Estado);
CREATE NONCLUSTERED INDEX IX_Boletos_Estado_Fecha
    ON dbo.Boletos (Estado, FechaVenta) INCLUDE (ViajeID);
CREATE NONCLUSTERED INDEX IX_Pagos_Boleto
    ON dbo.Pagos (BoletoID) INCLUDE (Monto);
GO
