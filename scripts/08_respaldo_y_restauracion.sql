/* =========================================================
   08_respaldo_y_restauracion.sql  -  E5 (Unidad III)
   Requisitos: la cuenta del servicio de SQL Server debe poder
   escribir en C:\Backups\BusRD\ (el script intenta crearla).
   Ejecutar PASO por PASO y anotar la hora del Paso 6.
   Usar el mismo @ViajeGrupo en todos los pasos; debe estar
   'Programado' y tener al menos 8 asientos libres.
   ========================================================= */
USE master;
GO
EXEC master.sys.xp_create_subdir N'C:\Backups\BusRD\';
GO
USE BusRD;
GO

/* ---------- PASO 1: modelo de recuperación FULL ----------
   Con SIMPLE el log se trunca solo en cada checkpoint: no hay backups de log
   ni recuperación a un punto en el tiempo. Con FULL el log se conserva hasta
   respaldarlo, lo que permite STOPAT y perder como máximo lo ocurrido desde
   el último backup de log. Una venta de boletos es dato crítico y transaccional. */
ALTER DATABASE BusRD SET RECOVERY FULL;
GO
SELECT name, recovery_model_desc FROM sys.databases WHERE name = 'BusRD';
GO

/* ---------- PASO 2: backup FULL (inicia la cadena de log) ---------- */
BACKUP DATABASE BusRD
TO DISK = N'C:\Backups\BusRD\BusRD_full.bak'
WITH INIT, CHECKSUM, STATS = 10, NAME = N'BusRD Full';
GO

/* ---------- PASO 3: vender 5 boletos ---------- */
DECLARE @ViajeGrupo INT = 16400;   -- <<< CAMBIAR: viaje asignado al grupo
IF NOT EXISTS (SELECT 1 FROM dbo.Viajes WHERE ViajeID = @ViajeGrupo AND Estado = 'Programado')
    THROW 51000, 'El viaje del grupo no existe o no está Programado.', 1;

IF OBJECT_ID('tempdb.dbo.BusRD_VentasPrueba') IS NOT NULL DROP TABLE tempdb.dbo.BusRD_VentasPrueba;
CREATE TABLE tempdb.dbo.BusRD_VentasPrueba (Lote VARCHAR(20), BoletoID INT, ViajeID INT, NumeroAsiento INT);

DECLARE @i INT = 1, @a INT, @id INT;
WHILE @i <= 5
BEGIN
    SELECT @a = MAX(s.NumeroAsiento)
    FROM dbo.Viajes v JOIN dbo.Asientos s ON s.AutobusID = v.AutobusID
    WHERE v.ViajeID = @ViajeGrupo
      AND NOT EXISTS (SELECT 1 FROM dbo.Boletos b
                      WHERE b.ViajeID = @ViajeGrupo AND b.NumeroAsiento = s.NumeroAsiento
                        AND b.Estado = 'Activo');
    EXEC dbo.sp_VenderBoleto @ViajeGrupo, @a, @i, 'Taquilla', 'Efectivo', @id OUTPUT;
    INSERT tempdb.dbo.BusRD_VentasPrueba VALUES ('Antes del DIFF', @id, @ViajeGrupo, @a);
    SET @i += 1;
END
SELECT * FROM tempdb.dbo.BusRD_VentasPrueba;
GO

/* ---------- PASO 4: backup DIFERENCIAL ---------- */
BACKUP DATABASE BusRD
TO DISK = N'C:\Backups\BusRD\BusRD_diff.bak'
WITH DIFFERENTIAL, INIT, CHECKSUM, STATS = 10, NAME = N'BusRD Diferencial';
GO

/* ---------- PASO 5: vender 3 boletos más ---------- */
DECLARE @ViajeGrupo INT = 16400;   -- <<< CAMBIAR (mismo valor)
DECLARE @i INT = 1, @a INT, @id INT;
WHILE @i <= 3
BEGIN
    SELECT @a = MAX(s.NumeroAsiento)
    FROM dbo.Viajes v JOIN dbo.Asientos s ON s.AutobusID = v.AutobusID
    WHERE v.ViajeID = @ViajeGrupo
      AND NOT EXISTS (SELECT 1 FROM dbo.Boletos b
                      WHERE b.ViajeID = @ViajeGrupo AND b.NumeroAsiento = s.NumeroAsiento
                        AND b.Estado = 'Activo');
    EXEC dbo.sp_VenderBoleto @ViajeGrupo, @a, 10 + @i, 'Web', 'Tarjeta', @id OUTPUT;
    INSERT tempdb.dbo.BusRD_VentasPrueba VALUES ('Despues del DIFF', @id, @ViajeGrupo, @a);
    SET @i += 1;
END
SELECT * FROM tempdb.dbo.BusRD_VentasPrueba;
GO

/* ---------- PASO 6: backup de LOG y hora exacta ---------- */
BACKUP LOG BusRD
TO DISK = N'C:\Backups\BusRD\BusRD_log1.trn'
WITH INIT, CHECKSUM, STATS = 10, NAME = N'BusRD Log 1';
GO

-- Se anota la hora (y se guarda en tempdb para usarla en el STOPAT). Capturar el resultado.
IF OBJECT_ID('tempdb.dbo.BusRD_StopAt') IS NOT NULL DROP TABLE tempdb.dbo.BusRD_StopAt;
CREATE TABLE tempdb.dbo.BusRD_StopAt (Hora DATETIME NOT NULL);
INSERT tempdb.dbo.BusRD_StopAt VALUES (GETDATE());
SELECT Hora AS HoraAnotada_AntesDelDelete FROM tempdb.dbo.BusRD_StopAt;

-- Copia de referencia de los boletos del viaje, para comparar luego (vive fuera de BusRD)
IF OBJECT_ID('tempdb.dbo.BusRD_SnapshotBoletos') IS NOT NULL DROP TABLE tempdb.dbo.BusRD_SnapshotBoletos;
SELECT * INTO tempdb.dbo.BusRD_SnapshotBoletos
FROM dbo.Boletos WHERE ViajeID = 16400;   -- <<< CAMBIAR (mismo valor)
SELECT COUNT(*) AS BoletosDelViaje_AntesDelDelete FROM tempdb.dbo.BusRD_SnapshotBoletos;

WAITFOR DELAY '00:00:03';   -- separa la hora anotada del DELETE
GO

/* ---------- PASO 7: el "error humano" ---------- */
DECLARE @ViajeGrupo INT = 16400;   -- <<< CAMBIAR (mismo valor)

-- 7.1 Un DELETE directo falla gracias a la FK Pagos -> Boletos (la integridad ya protege)
BEGIN TRY
    DELETE FROM dbo.Boletos WHERE ViajeID = @ViajeGrupo;
END TRY
BEGIN CATCH
    PRINT 'El DELETE directo fue bloqueado por la FK: ' + ERROR_MESSAGE();
END CATCH;

-- 7.2 El empleado borra pagos y boletos del viaje (el desastre)
BEGIN TRAN;
DELETE p FROM dbo.Pagos p JOIN dbo.Boletos b ON b.BoletoID = p.BoletoID WHERE b.ViajeID = @ViajeGrupo;
DELETE FROM dbo.Boletos WHERE ViajeID = @ViajeGrupo;
COMMIT;

SELECT COUNT(*) AS BoletosDelViaje_DespuesDelDelete FROM dbo.Boletos WHERE ViajeID = @ViajeGrupo;  -- 0
GO

/* ---------- PASO 8: backup del LOG DE COLA ----------
   Captura lo ocurrido desde el último backup de log, incluido el DELETE. */
BACKUP LOG BusRD
TO DISK = N'C:\Backups\BusRD\BusRD_log_cola.trn'
WITH NO_TRUNCATE, INIT, CHECKSUM, STATS = 10, NAME = N'BusRD Log de cola';
GO

/* ---------- PASO 9: restaurar en BusRD_Recuperada hasta antes del DELETE ---------- */
USE master;
GO
IF DB_ID('BusRD_Recuperada') IS NOT NULL
BEGIN
    ALTER DATABASE BusRD_Recuperada SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE BusRD_Recuperada;
END
GO

DECLARE @lDatos SYSNAME, @lLog SYSNAME, @dir NVARCHAR(260), @sql NVARCHAR(MAX);
DECLARE @hora DATETIME = (SELECT Hora FROM tempdb.dbo.BusRD_StopAt);

SELECT @lDatos = name FROM sys.master_files WHERE database_id = DB_ID('BusRD') AND type = 0;
SELECT @lLog   = name FROM sys.master_files WHERE database_id = DB_ID('BusRD') AND type = 1;
SELECT @dir = LEFT(physical_name, LEN(physical_name) - CHARINDEX('\', REVERSE(physical_name)) + 1)
FROM sys.master_files WHERE database_id = DB_ID('BusRD') AND type = 0;

-- FULL
SET @sql = N'RESTORE DATABASE BusRD_Recuperada FROM DISK = N''C:\Backups\BusRD\BusRD_full.bak'' '
         + N'WITH MOVE N''' + @lDatos + N''' TO N''' + @dir + N'BusRD_Recuperada.mdf'', '
         + N'MOVE N''' + @lLog + N''' TO N''' + @dir + N'BusRD_Recuperada_log.ldf'', NORECOVERY, STATS = 10;';
EXEC (@sql);

-- DIFERENCIAL
RESTORE DATABASE BusRD_Recuperada FROM DISK = N'C:\Backups\BusRD\BusRD_diff.bak' WITH NORECOVERY;

-- LOG 1 (incluye las 3 ventas posteriores al diferencial)
RESTORE LOG BusRD_Recuperada FROM DISK = N'C:\Backups\BusRD\BusRD_log1.trn' WITH NORECOVERY;

-- LOG DE COLA, detenido justo antes del DELETE
SET @sql = N'RESTORE LOG BusRD_Recuperada FROM DISK = N''C:\Backups\BusRD\BusRD_log_cola.trn'' '
         + N'WITH STOPAT = ''' + CONVERT(VARCHAR(23), @hora, 121) + N''', RECOVERY;';
EXEC (@sql);
GO

/* ---------- PASO 10: verificación ---------- */
SELECT name, state_desc FROM sys.databases WHERE name IN ('BusRD','BusRD_Recuperada');

DECLARE @ViajeGrupo INT = 16400;   -- <<< CAMBIAR (mismo valor)

-- 10.1 En BusRD (producción) los boletos del viaje siguen borrados; en la recuperada no
SELECT 'BusRD (con el DELETE)' AS Base, COUNT(*) AS Boletos FROM BusRD.dbo.Boletos WHERE ViajeID = @ViajeGrupo
UNION ALL
SELECT 'BusRD_Recuperada', COUNT(*) FROM BusRD_Recuperada.dbo.Boletos WHERE ViajeID = @ViajeGrupo
UNION ALL
SELECT 'Referencia previa al DELETE', COUNT(*) FROM tempdb.dbo.BusRD_SnapshotBoletos;

-- 10.2 Los 8 boletos vendidos existen en la recuperada
SELECT v.Lote, v.BoletoID, v.NumeroAsiento,
       CASE WHEN EXISTS (SELECT 1 FROM BusRD_Recuperada.dbo.Boletos b WHERE b.BoletoID = v.BoletoID)
            THEN 'EXISTE' ELSE 'FALTA' END AS EnRecuperada
FROM tempdb.dbo.BusRD_VentasPrueba v
ORDER BY v.BoletoID;

-- 10.3 La recuperada es idéntica a la referencia (ambas columnas deben dar 0)
SELECT
  (SELECT COUNT(*) FROM (SELECT * FROM tempdb.dbo.BusRD_SnapshotBoletos
                         EXCEPT
                         SELECT * FROM BusRD_Recuperada.dbo.Boletos WHERE ViajeID = @ViajeGrupo) x) AS FaltanEnRecuperada,
  (SELECT COUNT(*) FROM (SELECT * FROM BusRD_Recuperada.dbo.Boletos WHERE ViajeID = @ViajeGrupo
                         EXCEPT
                         SELECT * FROM tempdb.dbo.BusRD_SnapshotBoletos) x) AS SobranEnRecuperada;
GO

/* ---------- PASO 11: política de respaldos propuesta (para el informe) ----------
   | Tipo        | Frecuencia                  | Retención                          |
   |-------------|-----------------------------|------------------------------------|
   | FULL        | Semanal (domingo 02:00)     | 4 semanas + 1 por mes durante 12 m |
   | DIFERENCIAL | Diario (02:00, lun-sáb)     | 2 semanas                          |
   | LOG         | Cada 15 min (cada 5 en pico)| 7 días (hasta tener otro FULL)     |
   Además: CHECKSUM en cada backup, copia fuera del servidor (nube/otro sitio),
   prueba de restauración mensual y backup de log inmediato antes de cambios masivos. */
