/* Ejecutar después de la base. 16400 es un viaje de PRUEBA, no una asignación
   confirmada por el docente. Cambiar por el asignado antes de la entrega. */
USE BusRD;
GO
IF OBJECT_ID('dbo.ConfiguracionGrupo') IS NULL
CREATE TABLE dbo.ConfiguracionGrupo (
    GrupoID INT PRIMARY KEY,
    ViajeID INT NOT NULL,
    AsignacionConfirmada BIT NOT NULL DEFAULT 0
);
IF NOT EXISTS (SELECT 1 FROM dbo.ConfiguracionGrupo WHERE GrupoID=8)
    INSERT dbo.ConfiguracionGrupo VALUES (8,16400,0);
GO
IF NOT EXISTS (SELECT 1 FROM dbo.ConfiguracionGrupo c JOIN dbo.Viajes v
               ON v.ViajeID=c.ViajeID WHERE c.GrupoID=8 AND v.Estado='Programado')
    THROW 51080, 'Configure un viaje existente y Programado para el grupo 8.', 1;
SELECT c.*, '40200008000' AS CedulaC2 FROM dbo.ConfiguracionGrupo c WHERE GrupoID=8;
GO
