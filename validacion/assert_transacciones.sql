USE BusRD;
GO
-- Inyección controlada de un fallo en Pagos para comprobar que no quede un boleto sin pago.
-- SOLO en instancia de pruebas, sin otros usuarios conectados.
CREATE OR ALTER TRIGGER dbo.tr_ValidacionFalloPago ON dbo.Pagos AFTER INSERT
AS
BEGIN
 SET NOCOUNT ON;
 THROW 51400,'Fallo de pago inyectado por la validación.',1;
END;
GO
DECLARE @v INT=(SELECT ViajeID FROM dbo.ConfiguracionGrupo WHERE GrupoID=8),@a INT,@id INT;
SELECT @a=MAX(s.NumeroAsiento) FROM dbo.Viajes v JOIN dbo.Asientos s ON s.AutobusID=v.AutobusID
WHERE v.ViajeID=@v AND NOT EXISTS(SELECT 1 FROM dbo.Boletos b WHERE b.ViajeID=@v AND b.NumeroAsiento=s.NumeroAsiento AND b.Estado='Activo');
IF @a IS NULL BEGIN DROP TRIGGER dbo.tr_ValidacionFalloPago; THROW 51401,'Sin asientos para probar atomicidad.',1; END;
DECLARE @antes INT=(SELECT COUNT(*) FROM dbo.Boletos),@error INT=0;
BEGIN TRY
 EXEC dbo.sp_VenderBoleto @v,@a,1,'Web','Tarjeta',@id OUTPUT;
END TRY
BEGIN CATCH
 SET @error=ERROR_NUMBER();
END CATCH;
DROP TRIGGER dbo.tr_ValidacionFalloPago;
IF @error<>51400 THROW 51402,'La venta no propagó el fallo del pago.',1;
IF @id IS NOT NULL OR @@TRANCOUNT<>0 OR (SELECT COUNT(*) FROM dbo.Boletos)<>@antes
 THROW 51403,'La venta dejó cambios parciales tras fallar el pago.',1;
PRINT 'OK: atomicidad real frente a fallo en el segundo INSERT.';
GO
-- La última defensa debe rechazar INSERT directo aunque no pase por el procedimiento.
DECLARE @error INT=0;
BEGIN TRY
 BEGIN TRAN;
 INSERT dbo.Boletos(ViajeID,NumeroAsiento,ClienteID,FechaVenta,Canal,Precio,Estado)
 SELECT TOP(1) ViajeID,NumeroAsiento,ClienteID,SYSDATETIME(),Canal,Precio,Estado
 FROM dbo.Boletos WHERE Estado='Activo';
 ROLLBACK;
END TRY
BEGIN CATCH
 IF @@TRANCOUNT>0 ROLLBACK;
 SET @error=ERROR_NUMBER();
END CATCH;
IF @error NOT IN (2601,2627) THROW 51404,'No se probó unicidad de boletos activos.',1;
PRINT 'OK: duplicado directo rechazado por el motor.';
GO
-- Las seis validaciones deben fallar con su código y sin insertar.
DECLARE @id INT,@v INT=(SELECT ViajeID FROM dbo.ConfiguracionGrupo WHERE GrupoID=8),@e INT;
SET @e=0;
BEGIN TRY EXEC dbo.sp_VenderBoleto 999999,1,1,'Web','Tarjeta',@id OUTPUT; END TRY
BEGIN CATCH SET @e=ERROR_NUMBER(); END CATCH;
IF @e<>50003 THROW 51410,'Falló validación de viaje inexistente.',1;
SET @e=0;
BEGIN TRY EXEC dbo.sp_VenderBoleto 1,1,1,'Web','Tarjeta',@id OUTPUT; END TRY
BEGIN CATCH SET @e=ERROR_NUMBER(); END CATCH;
IF @e<>50004 THROW 51411,'Falló validación de viaje no Programado.',1;
SET @e=0;
BEGIN TRY EXEC dbo.sp_VenderBoleto @v,999,1,'Web','Tarjeta',@id OUTPUT; END TRY
BEGIN CATCH SET @e=ERROR_NUMBER(); END CATCH;
IF @e<>50005 THROW 51412,'Falló validación de asiento.',1;
SET @e=0;
BEGIN TRY EXEC dbo.sp_VenderBoleto @v,1,99999999,'Web','Tarjeta',@id OUTPUT; END TRY
BEGIN CATCH SET @e=ERROR_NUMBER(); END CATCH;
IF @e<>50006 THROW 51413,'Falló validación de cliente.',1;
SET @e=0;
BEGIN TRY EXEC dbo.sp_VenderBoleto @v,1,1,NULL,'Tarjeta',@id OUTPUT; END TRY
BEGIN CATCH SET @e=ERROR_NUMBER(); END CATCH;
IF @e<>50001 THROW 51414,'Falló validación de canal.',1;
SET @e=0;
BEGIN TRY EXEC dbo.sp_VenderBoleto @v,1,1,'Web',NULL,@id OUTPUT; END TRY
BEGIN CATCH SET @e=ERROR_NUMBER(); END CATCH;
IF @e<>50002 THROW 51415,'Falló validación de método.',1;
PRINT 'OK: seis validaciones y códigos de error.';
GO
