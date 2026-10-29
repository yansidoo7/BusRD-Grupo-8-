/* =========================================================
   05_demo_concurrencia_sesionB.sql  -  E2 (partes 1 y 4)
   SESIÓN B. Ejecutar cada parte DENTRO de los 10 s posteriores
   a la misma parte en la sesión A (04_demo_concurrencia_sesionA.sql).
   Usar el mismo @ViajeGrupo que en la sesión A.
   ========================================================= */
USE BusRD;
GO

/* ---------- PARTE 1: venta con el procedimiento DEFECTUOSO (v0) ---------- */
DECLARE @ViajeGrupo INT = 16400;   -- <<< CAMBIAR (mismo valor que en A)
DECLARE @Asiento INT =
    (SELECT MAX(s.NumeroAsiento)
     FROM dbo.Viajes v
     JOIN dbo.Asientos s ON s.AutobusID = v.AutobusID
     WHERE v.ViajeID = @ViajeGrupo
       AND NOT EXISTS (SELECT 1 FROM dbo.Boletos b
                       WHERE b.ViajeID = @ViajeGrupo
                         AND b.NumeroAsiento = s.NumeroAsiento
                         AND b.Estado = 'Activo'));
PRINT 'Sesión B - viaje ' + CAST(@ViajeGrupo AS VARCHAR(10)) + ', asiento ' + CAST(@Asiento AS VARCHAR(10))
      + ' - inicio ' + CONVERT(VARCHAR(12), SYSDATETIME(), 114);

EXEC dbo.sp_VenderBoleto_v0 @ViajeID = @ViajeGrupo, @NumeroAsiento = @Asiento,
                            @ClienteID = 2, @Canal = 'Web', @Metodo = 'Tarjeta';

PRINT 'Sesión B - fin ' + CONVERT(VARCHAR(12), SYSDATETIME(), 114);
GO

/* ---------- PARTE 3: venta con el procedimiento NUEVO ---------- */
DECLARE @ViajeGrupo INT = 16400;   -- <<< CAMBIAR (mismo valor que en A)
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
PRINT 'Sesión B - asiento ' + CAST(@Asiento AS VARCHAR(10)) + ' - inicio ' + CONVERT(VARCHAR(12), SYSDATETIME(), 114);
BEGIN TRY
    EXEC dbo.sp_VenderBoleto @ViajeID = @ViajeGrupo, @NumeroAsiento = @Asiento,
                             @ClienteID = 2, @Canal = 'Web', @Metodo = 'Tarjeta',
                             @BoletoID = @NuevoID OUTPUT, @SimularDemora = 1;
    PRINT 'Sesión B - VENDIDO. BoletoID = ' + CAST(@NuevoID AS VARCHAR(10));
END TRY
BEGIN CATCH
    PRINT 'Sesión B - RECHAZADO: ' + ERROR_MESSAGE();
END CATCH;
PRINT 'Sesión B - fin ' + CONVERT(VARCHAR(12), SYSDATETIME(), 114);   -- ~10 s después de su inicio: estuvo esperando
GO
