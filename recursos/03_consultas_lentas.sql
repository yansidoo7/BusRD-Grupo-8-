USE BusRD;
GO
SET STATISTICS IO ON;
SET STATISTICS TIME ON;
GO

/* C1 - Pantalla de taquilla: asientos disponibles de un viaje */
DECLARE @ViajeID INT = 16000;
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

/* C2 - Historial de viajes de un cliente por cédula */
DECLARE @Cedula CHAR(11) = '40200012345';
SELECT c.Nombre, c.Apellido, r.Origen, r.Destino,
       v.FechaSalida, b.NumeroAsiento, b.Precio, b.Estado
FROM dbo.Clientes c
JOIN dbo.Boletos b ON b.ClienteID = c.ClienteID
JOIN dbo.Viajes  v ON v.ViajeID   = b.ViajeID
JOIN dbo.Rutas   r ON r.RutaID    = v.RutaID
WHERE LTRIM(RTRIM(c.Cedula)) = @Cedula
ORDER BY v.FechaSalida DESC;
GO

/* C3 - Reporte mensual de ingresos por ruta (año 2025) */
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