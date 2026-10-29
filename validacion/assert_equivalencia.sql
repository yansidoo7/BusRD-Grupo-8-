USE BusRD;
GO
DECLARE @ViajeID INT = (SELECT ViajeID FROM dbo.ConfiguracionGrupo WHERE GrupoID=8);      -- misma configuración del grupo
DECLARE @Grupo INT = 8;            -- misma configuración del grupo
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
IF EXISTS (SELECT * FROM #c1a EXCEPT SELECT * FROM #c1b)
 OR EXISTS(SELECT * FROM #c1b EXCEPT SELECT * FROM #c1a)
 OR (SELECT COUNT(*) FROM #c1a)<>(SELECT COUNT(*) FROM #c1b)
 THROW 51201,'C1 original y optimizada difieren.',1;
IF EXISTS (SELECT * FROM #c3a EXCEPT SELECT * FROM #c3b)
 OR EXISTS(SELECT * FROM #c3b EXCEPT SELECT * FROM #c3a)
 THROW 51203,'C3 original y optimizada difieren.',1;
-- C2 puede proyectar filas idénticas: comparar también multiplicidades.
SELECT Nombre,Apellido,Origen,Destino,FechaSalida,NumeroAsiento,Precio,Estado,COUNT_BIG(*) n
INTO #c2ga FROM #c2a GROUP BY Nombre,Apellido,Origen,Destino,FechaSalida,NumeroAsiento,Precio,Estado;
SELECT Nombre,Apellido,Origen,Destino,FechaSalida,NumeroAsiento,Precio,Estado,COUNT_BIG(*) n
INTO #c2gb FROM #c2b GROUP BY Nombre,Apellido,Origen,Destino,FechaSalida,NumeroAsiento,Precio,Estado;
IF EXISTS(SELECT * FROM #c2ga EXCEPT SELECT * FROM #c2gb)
 OR EXISTS(SELECT * FROM #c2gb EXCEPT SELECT * FROM #c2ga)
 THROW 51202,'C2 original y optimizada difieren en valores o multiplicidades.',1;
PRINT 'OK: C1, C2 y C3 conservan exactamente sus resultados.';

GO
