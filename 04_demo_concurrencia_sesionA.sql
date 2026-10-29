/* =========================================================
   04_demo_concurrencia_sesionA.sql  -  E2 (partes 1 y 4)
   SESIÓN A. Abrir ESTE archivo en una ventana de SSMS y
   05_demo_concurrencia_sesionB.sql en otra.
   Ejecutar cada PARTE por separado (seleccionar y F5).
   Antes de empezar, definir en AMBOS archivos el mismo @ViajeGrupo
   (viaje asignado al grupo; debe estar 'Programado').
   ========================================================= */
USE BusRD;
GO

/* ---------- PARTE 0: quitar TEMPORALMENTE la defensa del motor ----------
   El enunciado exige reproducir la doble venta ANTES de la unicidad.
   (Se vuelve a crear en la PARTE 2.) */
IF EXISTS (SELECT 1 FROM sys.indexes
           WHERE name = 'UX_Boletos_AsientoActivo' AND object_id = OBJECT_ID('dbo.Boletos'))
    DROP INDEX UX_Boletos_AsientoActivo ON dbo.Boletos;
GO

/* ---------- PARTE 1: venta con el procedimiento DEFECTUOSO (v0) ----------
   1) Ejecutar esta parte en la sesión A.
   2) Dentro de los 10 s siguientes, ejecutar la PARTE 1 de la sesión B.
   3) Esperar a que ambas terminen (aprox. 10 s). */
DECLARE @ViajeGrupo INT = 16400;   -- <<< CAMBIAR: viaje asignado al grupo
DECLARE @Asiento INT =
    (SELECT MAX(s.NumeroAsiento)
     FROM dbo.Viajes v
     JOIN dbo.Asientos s ON s.AutobusID = v.AutobusID
     WHERE v.ViajeID = @ViajeGrupo
       AND NOT EXISTS (SELECT 1 FROM dbo.Boletos b
                       WHERE b.ViajeID = @ViajeGrupo
                         AND b.NumeroAsiento = s.NumeroAsiento
                         AND b.Estado = 'Activo'));
PRINT 'Sesión A - viaje ' + CAST(@ViajeGrupo AS VARCHAR(10)) + ', asiento ' + CAST(@Asiento AS VARCHAR(10))
      + ' - inicio ' + CONVERT(VARCHAR(12), SYSDATETIME(), 114);

EXEC dbo.sp_VenderBoleto_v0 @ViajeID = @ViajeGrupo, @NumeroAsiento = @Asiento,
                            @ClienteID = 1, @Canal = 'Taquilla', @Metodo = 'Efectivo';

PRINT 'Sesión A - fin ' + CONVERT(VARCHAR(12), SYSDATETIME(), 114);
GO

/* ---------- Evidencia de la doble venta (ejecutar cuando A y B terminaron) ---------- */
DECLARE @ViajeGrupo INT = 16400;   -- <<< CAMBIAR (mismo valor)
SELECT BoletoID, ViajeID, NumeroAsiento, ClienteID, Canal, FechaVenta, Estado
FROM dbo.Boletos
WHERE ViajeID = @ViajeGrupo
  AND Estado = 'Activo'
  AND NumeroAsiento IN (SELECT NumeroAsiento FROM dbo.Boletos
                        WHERE ViajeID = @ViajeGrupo AND Estado = 'Activo'
                        GROUP BY NumeroAsiento HAVING COUNT(*) > 1)
ORDER BY NumeroAsiento, BoletoID;
GO

/* ---------- PARTE 2: limpiar la doble venta y restaurar el índice único ---------- */
DECLARE @ViajeGrupo INT = 16400;   -- <<< CAMBIAR (mismo valor)
DECLARE @Duplicado INT =
    (SELECT MAX(BoletoID) FROM dbo.Boletos
     WHERE ViajeID = @ViajeGrupo AND Estado = 'Activo'
       AND NumeroAsiento IN (SELECT NumeroAsiento FROM dbo.Boletos
                             WHERE ViajeID = @ViajeGrupo AND Estado = 'Activo'
                             GROUP BY NumeroAsiento HAVING COUNT(*) > 1));
IF @Duplicado IS NOT NULL
    EXEC dbo.sp_AnularBoleto @BoletoID = @Duplicado;   -- anula el vendido más tarde
GO
CREATE UNIQUE NONCLUSTERED INDEX UX_Boletos_AsientoActivo
    ON dbo.Boletos (ViajeID, NumeroAsiento) WHERE Estado = 'Activo';
GO

/* ---------- PARTE 3: venta con el procedimiento NUEVO (con demora de 10 s) ----------
   1) Ejecutar esta parte en la sesión A.
   2) Dentro de los 10 s siguientes, ejecutar la PARTE 3 de la sesión B.
   Resultado esperado: A vende; B ESPERA hasta que A hace COMMIT y luego
   recibe "El asiento ya está vendido." */
DECLARE @ViajeGrupo INT = 16400;   -- <<< CAMBIAR (mismo valor)
DECLARE @Asiento INT =
    (SELECT MAX(s.NumeroAsiento)
     FROM dbo.Viajes v
     JOIN dbo.Asientos s ON s.AutobusID = v.AutobusID
     WHERE v.ViajeID = @ViajeGrupo
       AND NOT EXISTS (SELECT 1 FROM dbo.Boletos b
                       WHERE b.ViajeID = @ViajeGrupo
                         AND b.NumeroAsiento = s.NumeroAsiento
                         AND b.Estado = 'Activo'));
DECLARE @NuevoID INT;
PRINT 'Sesión A - asiento ' + CAST(@Asiento AS VARCHAR(10)) + ' - inicio ' + CONVERT(VARCHAR(12), SYSDATETIME(), 114);
BEGIN TRY
    EXEC dbo.sp_VenderBoleto @ViajeID = @ViajeGrupo, @NumeroAsiento = @Asiento,
                             @ClienteID = 1, @Canal = 'Taquilla', @Metodo = 'Efectivo',
                             @BoletoID = @NuevoID OUTPUT, @SimularDemora = 1;
    PRINT 'Sesión A - VENDIDO. BoletoID = ' + CAST(@NuevoID AS VARCHAR(10));
END TRY
BEGIN CATCH
    PRINT 'Sesión A - RECHAZADO: ' + ERROR_MESSAGE();
END CATCH;
PRINT 'Sesión A - fin ' + CONVERT(VARCHAR(12), SYSDATETIME(), 114);
GO

/* ---------- Evidencia final: ningún asiento con más de un boleto activo ---------- */
DECLARE @ViajeGrupo INT = 16400;   -- <<< CAMBIAR (mismo valor)
SELECT NumeroAsiento, COUNT(*) AS BoletosActivos
FROM dbo.Boletos
WHERE ViajeID = @ViajeGrupo AND Estado = 'Activo'
GROUP BY NumeroAsiento
HAVING COUNT(*) > 1;            -- debe devolver 0 filas

SELECT TOP (5) BoletoID, NumeroAsiento, ClienteID, Canal, FechaVenta, Estado
FROM dbo.Boletos WHERE ViajeID = @ViajeGrupo ORDER BY BoletoID DESC;
GO
