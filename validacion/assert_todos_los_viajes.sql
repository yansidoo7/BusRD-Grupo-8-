/* Revisión global de datos tras la limpieza; ejecutar en base de pruebas. */
USE BusRD;
GO
SET NOCOUNT ON;
SELECT COUNT(*) AS TotalViajes,
       SUM(CASE WHEN Estado='Programado' THEN 1 ELSE 0 END) AS Programados,
       SUM(CASE WHEN Estado='Completado' THEN 1 ELSE 0 END) AS Completados,
       SUM(CASE WHEN Estado='Cancelado' THEN 1 ELSE 0 END) AS Cancelados
FROM dbo.Viajes;

SELECT COUNT(*) AS ViajesProgramadosConAsientosLibres
FROM dbo.Viajes v
WHERE v.Estado='Programado' AND EXISTS (
 SELECT 1 FROM dbo.Asientos s
 WHERE s.AutobusID=v.AutobusID AND NOT EXISTS (
  SELECT 1 FROM dbo.Boletos b WHERE b.ViajeID=v.ViajeID
   AND b.NumeroAsiento=s.NumeroAsiento AND b.Estado='Activo'));

IF EXISTS (SELECT 1 FROM dbo.Viajes v
 LEFT JOIN dbo.Rutas r ON r.RutaID=v.RutaID
 LEFT JOIN dbo.Autobuses a ON a.AutobusID=v.AutobusID
 WHERE r.RutaID IS NULL OR a.AutobusID IS NULL)
 THROW 51501, 'Hay viajes sin ruta o autobus.', 1;

IF EXISTS (SELECT 1 FROM dbo.Viajes v
 WHERE NOT EXISTS (SELECT 1 FROM dbo.Asientos s WHERE s.AutobusID=v.AutobusID))
 THROW 51502, 'Hay viajes cuyo autobus no tiene asientos.', 1;

IF EXISTS (SELECT 1 FROM dbo.Boletos b
 LEFT JOIN dbo.Viajes v ON v.ViajeID=b.ViajeID
 LEFT JOIN dbo.Clientes c ON c.ClienteID=b.ClienteID
 WHERE v.ViajeID IS NULL OR c.ClienteID IS NULL OR NOT EXISTS (
  SELECT 1 FROM dbo.Asientos s WHERE s.AutobusID=v.AutobusID
   AND s.NumeroAsiento=b.NumeroAsiento))
 THROW 51503, 'Hay boletos con viaje, cliente o asiento invalido.', 1;

IF EXISTS (SELECT 1 FROM dbo.Boletos WHERE Estado='Activo'
 GROUP BY ViajeID,NumeroAsiento HAVING COUNT(*)>1)
 THROW 51504, 'Hay asientos vendidos dos veces.', 1;

IF EXISTS (SELECT 1 FROM dbo.Pagos p LEFT JOIN dbo.Boletos b ON b.BoletoID=p.BoletoID
 WHERE b.BoletoID IS NULL)
 THROW 51505, 'Hay pagos huerfanos.', 1;

IF EXISTS (SELECT 1 FROM dbo.Viajes WHERE Estado NOT IN ('Programado','Completado','Cancelado'))
 OR EXISTS (SELECT 1 FROM dbo.Boletos WHERE Estado NOT IN ('Activo','Anulado') OR Canal NOT IN ('Taquilla','Web') OR Precio<=0)
 OR EXISTS (SELECT 1 FROM dbo.Pagos WHERE Metodo NOT IN ('Efectivo','Tarjeta','Transferencia') OR Monto=0)
 OR EXISTS (SELECT 1 FROM dbo.Autobuses WHERE Tipo NOT IN ('Estandar','Ejecutivo') OR Capacidad<=0)
 THROW 51506, 'Hay valores fuera de dominio.', 1;

PRINT 'OK: revision global de viajes, boletos y pagos.';
GO
