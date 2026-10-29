/* Ejecutar por BLOQUES, en dos conexiones distintas.
   V0 se prueba ANTES de 01_integridad; nunca se elimina el índice de integridad.
   Bloque 1: preparar v0 y ejecutar A; durante WAITFOR ejecutar bloque 1 de B.
   Tras ambas ventas: capturar SELECT y ejecutar 01_integridad, 02 y 03.
   Bloque 2: preparar venta segura y ejecutar A; durante WAITFOR ejecutar bloque 2 de B.
   El asiento queda almacenado antes de empezar A: B nunca recalcula otro asiento. */
USE BusRD;
GO
-- BLOQUE 1 (seleccionar desde aquí hasta GO)
IF EXISTS (SELECT 1 FROM sys.indexes WHERE object_id=OBJECT_ID('dbo.Boletos')
           AND name='UX_Boletos_AsientoActivo')
    THROW 51100, 'La demo v0 debe hacerse antes de 01_integridad, sobre una base de prueba recién creada.', 1;
IF OBJECT_ID('tempdb.dbo.BusRD_DemoAsiento') IS NOT NULL DROP TABLE tempdb.dbo.BusRD_DemoAsiento;
CREATE TABLE tempdb.dbo.BusRD_DemoAsiento (Etapa VARCHAR(10) PRIMARY KEY, ViajeID INT, Asiento INT);
DECLARE @v INT=(SELECT ViajeID FROM dbo.ConfiguracionGrupo WHERE GrupoID=8), @a INT;
SELECT @a=MAX(s.NumeroAsiento) FROM dbo.Viajes v JOIN dbo.Asientos s ON s.AutobusID=v.AutobusID
WHERE v.ViajeID=@v AND NOT EXISTS(SELECT 1 FROM dbo.Boletos b
 WHERE b.ViajeID=@v AND b.NumeroAsiento=s.NumeroAsiento AND b.Estado='Activo');
IF @a IS NULL THROW 51101, 'No hay asiento libre para la demo.', 1;
INSERT tempdb.dbo.BusRD_DemoAsiento VALUES ('v0',@v,@a);
SELECT 'A v0' Sesion, @v ViajeID,@a Asiento,SYSDATETIME() Inicio;
EXEC dbo.sp_VenderBoleto_v0 @v,@a,1,'Taquilla','Efectivo';
SELECT SYSDATETIME() Fin;
GO
-- EVIDENCIA V0: ejecutar cuando hayan terminado A y B.
SELECT b.* FROM dbo.Boletos b JOIN tempdb.dbo.BusRD_DemoAsiento d
 ON b.ViajeID=d.ViajeID AND b.NumeroAsiento=d.Asiento WHERE d.Etapa='v0' AND b.Estado='Activo';
GO
-- AHORA ejecutar 01_integridad.sql, 02_sp_VenderBoleto.sql, 03_sp_AnularBoleto.sql.
-- BLOQUE 2 (seleccionar desde aquí hasta GO)
IF NOT EXISTS(SELECT 1 FROM sys.indexes WHERE object_id=OBJECT_ID('dbo.Boletos')
 AND name='UX_Boletos_AsientoActivo' AND is_disabled=0)
 THROW 51102, 'Ejecute primero integridad y los procedimientos nuevos.', 1;
IF OBJECT_ID('tempdb.dbo.BusRD_DemoAsiento') IS NULL
 CREATE TABLE tempdb.dbo.BusRD_DemoAsiento (Etapa VARCHAR(10) PRIMARY KEY, ViajeID INT, Asiento INT);
DELETE tempdb.dbo.BusRD_DemoAsiento WHERE Etapa='segura';
DECLARE @v INT=(SELECT ViajeID FROM dbo.ConfiguracionGrupo WHERE GrupoID=8), @a INT, @id INT;
SELECT @a=MAX(s.NumeroAsiento) FROM dbo.Viajes v JOIN dbo.Asientos s ON s.AutobusID=v.AutobusID
WHERE v.ViajeID=@v AND NOT EXISTS(SELECT 1 FROM dbo.Boletos b
 WHERE b.ViajeID=@v AND b.NumeroAsiento=s.NumeroAsiento AND b.Estado='Activo');
IF @a IS NULL THROW 51101, 'No hay asiento libre para la demo.', 1;
INSERT tempdb.dbo.BusRD_DemoAsiento VALUES ('segura',@v,@a);
SELECT 'A segura' Sesion,@v ViajeID,@a Asiento,SYSDATETIME() Inicio;
EXEC dbo.sp_VenderBoleto @v,@a,1,'Taquilla','Efectivo',@id OUTPUT,1;
SELECT @id BoletoID,SYSDATETIME() Fin;
GO
-- EVIDENCIA FINAL: debe haber un solo boleto activo del asiento compartido.
SELECT d.ViajeID,d.Asiento,COUNT(b.BoletoID) Activos
FROM tempdb.dbo.BusRD_DemoAsiento d LEFT JOIN dbo.Boletos b
 ON b.ViajeID=d.ViajeID AND b.NumeroAsiento=d.Asiento AND b.Estado='Activo'
WHERE d.Etapa='segura' GROUP BY d.ViajeID,d.Asiento;
GO
