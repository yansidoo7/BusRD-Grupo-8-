/* =========================================================
   03_sp_AnularBoleto.sql  -  E2 (parte 5)
   Anula el boleto (libera el asiento) y registra el reverso
   del pago con monto NEGATIVO, todo en una transacción.
   ========================================================= */
USE BusRD;
GO
CREATE OR ALTER PROCEDURE dbo.sp_AnularBoleto
    @BoletoID INT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @Estado VARCHAR(10), @Neto DECIMAL(10,2), @Metodo VARCHAR(15);

    BEGIN TRY
        BEGIN TRAN;

        -- UPDLOCK evita que dos sesiones anulen el mismo boleto a la vez
        SELECT @Estado = Estado
        FROM dbo.Boletos WITH (UPDLOCK, HOLDLOCK)
        WHERE BoletoID = @BoletoID;

        IF @Estado IS NULL
            THROW 50010, 'El boleto no existe.', 1;
        IF @Estado = 'Anulado'
            THROW 50011, 'El boleto ya está anulado.', 1;

        UPDATE dbo.Boletos SET Estado = 'Anulado' WHERE BoletoID = @BoletoID;

        -- Neto cobrado hasta ahora (suma de pagos y reversos previos)
        SELECT @Neto = SUM(Monto), @Metodo = MIN(Metodo)
        FROM dbo.Pagos
        WHERE BoletoID = @BoletoID;

        IF @Neto IS NOT NULL AND @Neto > 0
            INSERT dbo.Pagos(BoletoID, Monto, Metodo, FechaPago)
            VALUES (@BoletoID, -@Neto, @Metodo, SYSDATETIME());   -- reverso

        COMMIT;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        THROW;
    END CATCH
END
GO
