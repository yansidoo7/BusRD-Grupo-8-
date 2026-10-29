/* =========================================================
   02_sp_VenderBoleto.sql  -  E2 (parte 3): venta transaccional
   ========================================================= */
USE BusRD;
GO
CREATE OR ALTER PROCEDURE dbo.sp_VenderBoleto
    @ViajeID        INT,
    @NumeroAsiento  INT,
    @ClienteID      INT,
    @Canal          VARCHAR(10),
    @Metodo         VARCHAR(15),
    @BoletoID       INT OUTPUT,
    @SimularDemora  BIT = 0
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;   -- cualquier error de ejecución aborta y revierte la transacción

    DECLARE @AutobusID INT, @EstadoViaje VARCHAR(15), @Precio DECIMAL(10,2);
    SET @BoletoID = NULL;

    BEGIN TRY
        /* ---- Validaciones de parámetros (no requieren leer tablas) ---- */
        IF @Canal  IS NULL OR @Canal  NOT IN ('Taquilla','Web')
            THROW 50001, 'Canal inválido. Use Taquilla o Web.', 1;
        IF @Metodo IS NULL OR @Metodo NOT IN ('Efectivo','Tarjeta','Transferencia')
            THROW 50002, 'Método de pago inválido.', 1;

        BEGIN TRAN;

        /* ---- Validaciones contra la base de datos ---- */
        SELECT @AutobusID   = v.AutobusID,
               @EstadoViaje = v.Estado,
               @Precio      = r.PrecioBase
        FROM dbo.Viajes v
        JOIN dbo.Rutas  r ON r.RutaID = v.RutaID
        WHERE v.ViajeID = @ViajeID;

        IF @AutobusID IS NULL
            THROW 50003, 'El viaje no existe.', 1;
        IF @EstadoViaje <> 'Programado'
            THROW 50004, 'El viaje no está Programado; no se pueden vender boletos.', 1;
        IF NOT EXISTS (SELECT 1 FROM dbo.Asientos
                       WHERE AutobusID = @AutobusID AND NumeroAsiento = @NumeroAsiento)
            THROW 50005, 'El asiento no existe en el autobús de este viaje.', 1;
        IF NOT EXISTS (SELECT 1 FROM dbo.Clientes WHERE ClienteID = @ClienteID)
            THROW 50006, 'El cliente no existe.', 1;

        /* ---- Control de concurrencia ----
           UPDLOCK: la lectura toma un bloqueo de ACTUALIZACIÓN (no de lectura
                    compartida). Dos sesiones no pueden tenerlo a la vez, lo que
                    evita el deadlock de convertir S -> X.
           HOLDLOCK (= SERIALIZABLE solo para esta tabla): toma bloqueos de RANGO
                    sobre la llave (ViajeID, NumeroAsiento), incluso si la fila
                    todavía NO existe, y los mantiene hasta el COMMIT. Así se
                    bloquea el "hueco" donde otro insertaría el mismo asiento
                    (evita la fila fantasma). */
        IF EXISTS (SELECT 1
                   FROM dbo.Boletos WITH (UPDLOCK, HOLDLOCK)
                   WHERE ViajeID = @ViajeID
                     AND NumeroAsiento = @NumeroAsiento
                     AND Estado = 'Activo')
            THROW 50007, 'El asiento ya está vendido.', 1;

        IF @SimularDemora = 1
            WAITFOR DELAY '00:00:10';   -- simula el cobro, DENTRO de la transacción

        /* ---- Boleto y pago en la misma transacción (atomicidad) ---- */
        INSERT dbo.Boletos(ViajeID, NumeroAsiento, ClienteID, FechaVenta, Canal, Precio, Estado)
        VALUES (@ViajeID, @NumeroAsiento, @ClienteID, SYSDATETIME(), @Canal, @Precio, 'Activo');

        SET @BoletoID = SCOPE_IDENTITY();

        INSERT dbo.Pagos(BoletoID, Monto, Metodo, FechaPago)
        VALUES (@BoletoID, @Precio, @Metodo, SYSDATETIME());

        COMMIT;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        SET @BoletoID = NULL;
        THROW;   -- re-lanza el error original al llamador
    END CATCH
END
GO

/* ---------------------------------------------------------
   Pruebas rápidas de validaciones (ninguna inserta datos).
   Cada una debe imprimir el mensaje de error esperado.
   --------------------------------------------------------- */
DECLARE @id INT;

BEGIN TRY EXEC dbo.sp_VenderBoleto 999999, 1, 1, 'Web', 'Tarjeta', @id OUTPUT;
END TRY BEGIN CATCH PRINT 'Viaje inexistente      -> ' + ERROR_MESSAGE(); END CATCH;

BEGIN TRY EXEC dbo.sp_VenderBoleto 1, 1, 1, 'Web', 'Tarjeta', @id OUTPUT;   -- viaje antiguo (no Programado)
END TRY BEGIN CATCH PRINT 'Viaje no Programado    -> ' + ERROR_MESSAGE(); END CATCH;

DECLARE @ViajeProg INT = (SELECT TOP 1 ViajeID FROM dbo.Viajes WHERE Estado = 'Programado' ORDER BY ViajeID DESC);

BEGIN TRY EXEC dbo.sp_VenderBoleto @ViajeProg, 999, 1, 'Web', 'Tarjeta', @id OUTPUT;
END TRY BEGIN CATCH PRINT 'Asiento inexistente    -> ' + ERROR_MESSAGE(); END CATCH;

BEGIN TRY EXEC dbo.sp_VenderBoleto @ViajeProg, 1, 99999999, 'Web', 'Tarjeta', @id OUTPUT;
END TRY BEGIN CATCH PRINT 'Cliente inexistente    -> ' + ERROR_MESSAGE(); END CATCH;

BEGIN TRY EXEC dbo.sp_VenderBoleto @ViajeProg, 1, 1, 'Correo', 'Tarjeta', @id OUTPUT;
END TRY BEGIN CATCH PRINT 'Canal inválido         -> ' + ERROR_MESSAGE(); END CATCH;

BEGIN TRY EXEC dbo.sp_VenderBoleto @ViajeProg, 1, 1, 'Web', 'Bitcoin', @id OUTPUT;
END TRY BEGIN CATCH PRINT 'Método inválido        -> ' + ERROR_MESSAGE(); END CATCH;
GO
