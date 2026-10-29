/* =========================================================
   01_integridad.sql  -  E1. Integridad del modelo (Unidad I)
   Ejecutar DESPUÉS del script base 01_BusRD_base.sql
   y de 02_sp_VenderBoleto_v0.sql / 03_consultas_lentas.sql.
   ========================================================= */
USE BusRD;
GO
SET NOCOUNT ON;
GO

/* ---------------------------------------------------------
   1. DETECCIÓN DE DATOS SUCIOS
   --------------------------------------------------------- */

-- 1.1 Boletos ACTIVOS duplicados (mismo viaje y mismo asiento)  -> cantidad medida; el generador inserta 60 boletos extra
SELECT ViajeID, NumeroAsiento,
       COUNT(*)       AS Cantidad,
       MIN(BoletoID)  AS BoletoOriginal,
       MAX(BoletoID)  AS BoletoDuplicado
FROM dbo.Boletos
WHERE Estado = 'Activo'
GROUP BY ViajeID, NumeroAsiento
HAVING COUNT(*) > 1
ORDER BY ViajeID, NumeroAsiento;

-- 1.2 Pagos huérfanos (BoletoID que no existe en Boletos)       -> esperado: 15 filas
SELECT p.*
FROM dbo.Pagos p
LEFT JOIN dbo.Boletos b ON b.BoletoID = p.BoletoID
WHERE b.BoletoID IS NULL;

-- 1.3 Otras verificaciones previas a las llaves foráneas (todas deben dar 0)
SELECT 'Boletos sin viaje' AS Verificacion, COUNT(*) AS Filas
FROM dbo.Boletos b WHERE NOT EXISTS (SELECT 1 FROM dbo.Viajes v WHERE v.ViajeID = b.ViajeID)
UNION ALL
SELECT 'Boletos sin cliente', COUNT(*)
FROM dbo.Boletos b WHERE NOT EXISTS (SELECT 1 FROM dbo.Clientes c WHERE c.ClienteID = b.ClienteID)
UNION ALL
SELECT 'Boletos con asiento inexistente en el autobús del viaje', COUNT(*)
FROM dbo.Boletos b
WHERE NOT EXISTS (SELECT 1 FROM dbo.Viajes v
                  JOIN dbo.Asientos s ON s.AutobusID = v.AutobusID
                  WHERE v.ViajeID = b.ViajeID AND s.NumeroAsiento = b.NumeroAsiento)
UNION ALL
SELECT 'Viajes sin ruta', COUNT(*)
FROM dbo.Viajes v WHERE NOT EXISTS (SELECT 1 FROM dbo.Rutas r WHERE r.RutaID = v.RutaID)
UNION ALL
SELECT 'Viajes sin autobús', COUNT(*)
FROM dbo.Viajes v WHERE NOT EXISTS (SELECT 1 FROM dbo.Autobuses a WHERE a.AutobusID = v.AutobusID)
UNION ALL
SELECT 'Asientos sin autobús', COUNT(*)
FROM dbo.Asientos s WHERE NOT EXISTS (SELECT 1 FROM dbo.Autobuses a WHERE a.AutobusID = s.AutobusID)
UNION ALL
SELECT 'Cédulas duplicadas', COUNT(*)
FROM (SELECT Cedula FROM dbo.Clientes GROUP BY Cedula HAVING COUNT(*) > 1) x
UNION ALL
SELECT 'Placas duplicadas', COUNT(*)
FROM (SELECT Placa FROM dbo.Autobuses GROUP BY Placa HAVING COUNT(*) > 1) x
UNION ALL
SELECT 'Valores fuera de dominio (Estado/Canal/Metodo/Tipo)', 
       (SELECT COUNT(*) FROM dbo.Boletos   WHERE Estado NOT IN ('Activo','Anulado') OR Canal NOT IN ('Taquilla','Web'))
     + (SELECT COUNT(*) FROM dbo.Pagos     WHERE Metodo NOT IN ('Efectivo','Tarjeta','Transferencia'))
     + (SELECT COUNT(*) FROM dbo.Viajes    WHERE Estado NOT IN ('Programado','Completado','Cancelado'))
     + (SELECT COUNT(*) FROM dbo.Autobuses WHERE Tipo NOT IN ('Estandar','Ejecutivo'))
UNION ALL
SELECT 'Precios/montos/capacidades inválidos',
       (SELECT COUNT(*) FROM dbo.Boletos   WHERE Precio <= 0)
     + (SELECT COUNT(*) FROM dbo.Pagos     WHERE Monto  <= 0 AND BoletoID < 900000)
     + (SELECT COUNT(*) FROM dbo.Autobuses WHERE Capacidad <= 0)
     + (SELECT COUNT(*) FROM dbo.Rutas     WHERE PrecioBase <= 0 OR DistanciaKm <= 0);
GO

/* ---------------------------------------------------------
   2. LIMPIEZA (en una sola transacción)
   Regla 1 - Pagos huérfanos: no se borran sin dejar rastro; se mueven a
             dbo.Pagos_Cuarentena (auditoría) y se eliminan de Pagos, porque
             no pertenecen a ningún boleto y rompen la FK Pagos -> Boletos.
   Regla 2 - Duplicados: se conserva el boleto vendido PRIMERO (menor
             FechaVenta, desempate por BoletoID) porque el pasajero ya tenía
             el asiento; los demás se ANULAN (un boleto anulado libera el
             asiento) y su pago se REVIERTE con un pago de monto negativo,
             igual que hará sp_AnularBoleto. No se borra nada: queda historial.
   --------------------------------------------------------- */
SET XACT_ABORT ON;
BEGIN TRAN;

-- 2.1 Pagos huérfanos -> cuarentena
SELECT p.*,
       CAST('Pago sin boleto (huérfano)' AS VARCHAR(100)) AS Motivo,
       SYSDATETIME() AS FechaCuarentena
INTO dbo.Pagos_Cuarentena
FROM dbo.Pagos p
WHERE NOT EXISTS (SELECT 1 FROM dbo.Boletos b WHERE b.BoletoID = p.BoletoID);

DELETE p
FROM dbo.Pagos p
WHERE NOT EXISTS (SELECT 1 FROM dbo.Boletos b WHERE b.BoletoID = p.BoletoID);

-- 2.2 Boletos duplicados -> anular el vendido más tarde y revertir su pago
SELECT BoletoID
INTO #DupAnular
FROM (SELECT BoletoID,
             rn = ROW_NUMBER() OVER (PARTITION BY ViajeID, NumeroAsiento
                                     ORDER BY FechaVenta, BoletoID)
      FROM dbo.Boletos
      WHERE Estado = 'Activo') x
WHERE rn > 1;

UPDATE b SET Estado = 'Anulado'
FROM dbo.Boletos b
JOIN #DupAnular d ON d.BoletoID = b.BoletoID;

INSERT dbo.Pagos(BoletoID, Monto, Metodo, FechaPago)
SELECT p.BoletoID, -SUM(p.Monto), MIN(p.Metodo), SYSDATETIME()
FROM dbo.Pagos p
JOIN #DupAnular d ON d.BoletoID = p.BoletoID
GROUP BY p.BoletoID
HAVING SUM(p.Monto) > 0;

COMMIT;
GO

-- 2.3 Comprobación de la limpieza (todo debe dar 0 / los reversos suman 0)
SELECT 'Duplicados activos restantes' AS Verificacion, COUNT(*) AS Filas
FROM (SELECT 1 AS x FROM dbo.Boletos WHERE Estado = 'Activo'
      GROUP BY ViajeID, NumeroAsiento HAVING COUNT(*) > 1) d
UNION ALL
SELECT 'Pagos huérfanos restantes', COUNT(*)
FROM dbo.Pagos p WHERE NOT EXISTS (SELECT 1 FROM dbo.Boletos b WHERE b.BoletoID = p.BoletoID)
UNION ALL
SELECT 'Pagos en cuarentena (esperado 15)', COUNT(*) FROM dbo.Pagos_Cuarentena
UNION ALL
SELECT 'Boletos anulados sin neto cero en Pagos (debe ser 0)', COUNT(*)
FROM (SELECT b.BoletoID FROM dbo.Boletos b JOIN dbo.Pagos p ON p.BoletoID = b.BoletoID
      WHERE b.Estado = 'Anulado' GROUP BY b.BoletoID HAVING SUM(p.Monto) <> 0) z;
GO

/* ---------------------------------------------------------
   3. LLAVES FORÁNEAS
   (Boletos -> Asientos no es posible como FK porque Boletos no tiene
    AutobusID; esa validación la hace sp_VenderBoleto.)
   --------------------------------------------------------- */
ALTER TABLE dbo.Asientos ADD CONSTRAINT FK_Asientos_Autobuses
    FOREIGN KEY (AutobusID) REFERENCES dbo.Autobuses(AutobusID);
ALTER TABLE dbo.Viajes   ADD CONSTRAINT FK_Viajes_Rutas
    FOREIGN KEY (RutaID)    REFERENCES dbo.Rutas(RutaID);
ALTER TABLE dbo.Viajes   ADD CONSTRAINT FK_Viajes_Autobuses
    FOREIGN KEY (AutobusID) REFERENCES dbo.Autobuses(AutobusID);
ALTER TABLE dbo.Boletos  ADD CONSTRAINT FK_Boletos_Viajes
    FOREIGN KEY (ViajeID)   REFERENCES dbo.Viajes(ViajeID);
ALTER TABLE dbo.Boletos  ADD CONSTRAINT FK_Boletos_Clientes
    FOREIGN KEY (ClienteID) REFERENCES dbo.Clientes(ClienteID);
ALTER TABLE dbo.Pagos    ADD CONSTRAINT FK_Pagos_Boletos
    FOREIGN KEY (BoletoID)  REFERENCES dbo.Boletos(BoletoID);
GO

/* ---------------------------------------------------------
   4. RESTRICCIONES CHECK (dominio y rango)
   Nota: Pagos.Monto admite negativos porque el reverso de un pago
   (anulación) se registra con monto negativo; lo que se prohíbe es 0.
   --------------------------------------------------------- */
ALTER TABLE dbo.Autobuses ADD CONSTRAINT CK_Autobuses_Tipo
    CHECK (Tipo IN ('Estandar','Ejecutivo'));
ALTER TABLE dbo.Autobuses ADD CONSTRAINT CK_Autobuses_Capacidad
    CHECK (Capacidad BETWEEN 1 AND 80);
ALTER TABLE dbo.Asientos  ADD CONSTRAINT CK_Asientos_Ubicacion
    CHECK (Ubicacion IN ('Ventana','Pasillo'));
ALTER TABLE dbo.Asientos  ADD CONSTRAINT CK_Asientos_Numero
    CHECK (NumeroAsiento > 0);
ALTER TABLE dbo.Rutas     ADD CONSTRAINT CK_Rutas_Precio
    CHECK (PrecioBase > 0 AND DistanciaKm > 0);
ALTER TABLE dbo.Rutas     ADD CONSTRAINT CK_Rutas_OrigenDestino
    CHECK (Origen <> Destino);
ALTER TABLE dbo.Viajes    ADD CONSTRAINT CK_Viajes_Estado
    CHECK (Estado IN ('Programado','Completado','Cancelado'));
ALTER TABLE dbo.Boletos   ADD CONSTRAINT CK_Boletos_Estado
    CHECK (Estado IN ('Activo','Anulado'));
ALTER TABLE dbo.Boletos   ADD CONSTRAINT CK_Boletos_Canal
    CHECK (Canal IN ('Taquilla','Web'));
ALTER TABLE dbo.Boletos   ADD CONSTRAINT CK_Boletos_Precio
    CHECK (Precio > 0 AND Precio <= 50000);
ALTER TABLE dbo.Pagos     ADD CONSTRAINT CK_Pagos_Metodo
    CHECK (Metodo IN ('Efectivo','Tarjeta','Transferencia'));
ALTER TABLE dbo.Pagos     ADD CONSTRAINT CK_Pagos_Monto
    CHECK (Monto <> 0 AND Monto BETWEEN -50000 AND 50000);
GO

/* ---------------------------------------------------------
   5. UNICIDAD
   --------------------------------------------------------- */
ALTER TABLE dbo.Clientes  ADD CONSTRAINT UQ_Clientes_Cedula UNIQUE (Cedula);
ALTER TABLE dbo.Autobuses ADD CONSTRAINT UQ_Autobuses_Placa UNIQUE (Placa);
GO

/* ---------------------------------------------------------
   6. UN SOLO BOLETO ACTIVO POR ASIENTO Y VIAJE
   Índice único FILTRADO: solo los boletos 'Activo' participan en la
   unicidad, así que un boleto 'Anulado' libera el asiento y se puede
   volver a vender. Es la última línea de defensa a nivel de motor.
   --------------------------------------------------------- */
CREATE UNIQUE NONCLUSTERED INDEX UX_Boletos_AsientoActivo
    ON dbo.Boletos (ViajeID, NumeroAsiento)
    WHERE Estado = 'Activo';
GO

/* ---------------------------------------------------------
   7. PRUEBA: el motor ya rechaza la doble venta
   (se intenta duplicar un boleto activo existente; debe fallar y revertirse)
   --------------------------------------------------------- */
BEGIN TRY
    BEGIN TRAN;
    INSERT dbo.Boletos(ViajeID,NumeroAsiento,ClienteID,FechaVenta,Canal,Precio,Estado)
    SELECT TOP (1) ViajeID, NumeroAsiento, ClienteID, SYSDATETIME(), 'Web', Precio, 'Activo'
    FROM dbo.Boletos WHERE Estado = 'Activo';
    COMMIT;
    PRINT 'ERROR: el duplicado fue aceptado.';
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK;
    PRINT 'OK - Duplicado rechazado: ' + ERROR_MESSAGE();
END CATCH;
GO
