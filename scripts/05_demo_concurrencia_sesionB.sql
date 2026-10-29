/* Ejecutar cada bloque durante la demora de A. Usar una segunda conexión. */
USE BusRD;
GO
-- BLOQUE 1: V0, antes de integridad.
DECLARE @v INT,@a INT;
SELECT @v=ViajeID,@a=Asiento FROM tempdb.dbo.BusRD_DemoAsiento WHERE Etapa='v0';
IF @a IS NULL THROW 51103, 'Primero prepare y ejecute la sesión A.',1;
SELECT 'B v0' Sesion,@v ViajeID,@a Asiento,SYSDATETIME() Inicio;
EXEC dbo.sp_VenderBoleto_v0 @v,@a,2,'Web','Tarjeta';
SELECT SYSDATETIME() Fin;
GO
-- BLOQUE 2: segura, después de integridad y procedimientos nuevos.
DECLARE @v INT,@a INT,@id INT;
SELECT @v=ViajeID,@a=Asiento FROM tempdb.dbo.BusRD_DemoAsiento WHERE Etapa='segura';
IF @a IS NULL THROW 51103, 'Primero prepare y ejecute la sesión A.',1;
SELECT 'B segura' Sesion,@v ViajeID,@a Asiento,SYSDATETIME() Inicio;
BEGIN TRY
 EXEC dbo.sp_VenderBoleto @v,@a,2,'Web','Tarjeta',@id OUTPUT,1;
 THROW 51104,'PRUEBA FALLIDA: la segunda venta fue aceptada.',1;
END TRY
BEGIN CATCH
 IF ERROR_NUMBER()<>50007 THROW;
 SELECT ERROR_NUMBER() ErrorEsperado,ERROR_MESSAGE() Mensaje,SYSDATETIME() Fin;
END CATCH;
GO
