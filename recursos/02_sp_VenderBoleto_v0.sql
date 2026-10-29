USE BusRD;
GO
CREATE OR ALTER PROCEDURE dbo.sp_VenderBoleto_v0
    @ViajeID       INT,
    @NumeroAsiento INT,
    @ClienteID     INT,
    @Canal         VARCHAR(10),
    @Metodo        VARCHAR(15)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @Precio DECIMAL(10,2), @BoletoID INT;

    IF EXISTS (SELECT 1 FROM dbo.Boletos
               WHERE ViajeID = @ViajeID
                 AND NumeroAsiento = @NumeroAsiento
                 AND Estado = 'Activo')
    BEGIN
        RAISERROR('El asiento ya está vendido.', 16, 1);
        RETURN;
    END

    WAITFOR DELAY '00:00:10';   -- simula el tiempo que tarda el cobro

    SELECT @Precio = r.PrecioBase
    FROM dbo.Viajes v JOIN dbo.Rutas r ON r.RutaID = v.RutaID
    WHERE v.ViajeID = @ViajeID;

    INSERT dbo.Boletos(ViajeID,NumeroAsiento,ClienteID,FechaVenta,Canal,Precio,Estado)
    VALUES (@ViajeID,@NumeroAsiento,@ClienteID,SYSDATETIME(),@Canal,@Precio,'Activo');

    SET @BoletoID = SCOPE_IDENTITY();

    INSERT dbo.Pagos(BoletoID,Monto,Metodo,FechaPago)
    VALUES (@BoletoID,@Precio,@Metodo,SYSDATETIME());
END
GO