/* =========================================================
   07_seguridad.sql  -  E4. Seguridad (Unidad III)
   Roles: rol_taquilla, rol_reportes, rol_admin
   Se usan usuarios SIN login y EXECUTE AS USER / REVERT.
   Ejecutar en SSMS con "Resultados en cuadrícula" y capturar
   los resultados y mensajes de cada prueba.
   ========================================================= */
USE BusRD;
GO

/* ---------- 1. Vistas (la única superficie de lectura permitida) ---------- */
CREATE OR ALTER VIEW dbo.vw_AsientosDisponibles
AS
SELECT v.ViajeID, r.Origen, r.Destino, v.FechaSalida,
       s.NumeroAsiento, s.Ubicacion
FROM dbo.Viajes  v
JOIN dbo.Rutas   r ON r.RutaID    = v.RutaID
JOIN dbo.Asientos s ON s.AutobusID = v.AutobusID
WHERE v.Estado = 'Programado'
  AND NOT EXISTS (SELECT 1 FROM dbo.Boletos b
                  WHERE b.ViajeID = v.ViajeID
                    AND b.NumeroAsiento = s.NumeroAsiento
                    AND b.Estado = 'Activo');
GO

CREATE OR ALTER VIEW dbo.vw_VentasMensuales
AS
SELECT r.Origen, r.Destino,
       YEAR(b.FechaVenta)  AS Anio,
       MONTH(b.FechaVenta) AS Mes,
       COUNT(*)            AS Boletos,
       SUM(p.Monto)        AS Ingresos
FROM dbo.Boletos b
JOIN dbo.Pagos  p ON p.BoletoID = b.BoletoID
JOIN dbo.Viajes v ON v.ViajeID  = b.ViajeID
JOIN dbo.Rutas  r ON r.RutaID   = v.RutaID
WHERE b.Estado = 'Activo'
GROUP BY r.Origen, r.Destino, YEAR(b.FechaVenta), MONTH(b.FechaVenta);
GO

/* ---------- 2. Roles ---------- */
CREATE ROLE rol_taquilla;
CREATE ROLE rol_reportes;
CREATE ROLE rol_admin;
GO

/* ---------- 3. Permisos (mínimo privilegio) ---------- */
-- Taquilla: solo ejecutar los procedimientos y leer la vista. Nada de tablas.
GRANT EXECUTE ON dbo.sp_VenderBoleto TO rol_taquilla;
GRANT EXECUTE ON dbo.sp_AnularBoleto TO rol_taquilla;
GRANT SELECT  ON dbo.vw_AsientosDisponibles TO rol_taquilla;

-- Reportes: solo la vista de ventas; además DENY explícito a datos personales.
GRANT SELECT ON dbo.vw_VentasMensuales TO rol_reportes;
DENY  SELECT ON dbo.Clientes (Email, Telefono) TO rol_reportes;

-- Admin: control total de la base de datos.
GRANT CONTROL ON DATABASE::BusRD TO rol_admin;
GO

/* ---------- 4. Usuarios de prueba (sin login) ---------- */
CREATE USER u_taquilla WITHOUT LOGIN;
CREATE USER u_reportes WITHOUT LOGIN;
CREATE USER u_admin    WITHOUT LOGIN;

ALTER ROLE rol_taquilla ADD MEMBER u_taquilla;
ALTER ROLE rol_reportes ADD MEMBER u_reportes;
ALTER ROLE rol_admin    ADD MEMBER u_admin;
GO

/* =========================================================
   5. PRUEBAS
   ========================================================= */

/* ---------- 5.1 rol_taquilla ---------- */
-- (preparación como dbo: viaje y asiento libres para la prueba)
DECLARE @ViajeGrupo INT = 16400;   -- <<< CAMBIAR: viaje asignado (se evita para no alterar E5)
DECLARE @ViajeTest INT =
    (SELECT TOP (1) ViajeID FROM dbo.Viajes
     WHERE Estado = 'Programado' AND ViajeID <> @ViajeGrupo ORDER BY ViajeID DESC);
DECLARE @AsientoTest INT =
    (SELECT MAX(s.NumeroAsiento)
     FROM dbo.Viajes v JOIN dbo.Asientos s ON s.AutobusID = v.AutobusID
     WHERE v.ViajeID = @ViajeTest
       AND NOT EXISTS (SELECT 1 FROM dbo.Boletos b
                       WHERE b.ViajeID = @ViajeTest AND b.NumeroAsiento = s.NumeroAsiento
                         AND b.Estado = 'Activo'));
DECLARE @BoletoTest INT;

EXECUTE AS USER = 'u_taquilla';
SELECT USER_NAME() AS UsuarioActual;

-- PERMITIDO 1: vender (INSERT en Boletos/Pagos vía ownership chaining)
EXEC dbo.sp_VenderBoleto @ViajeTest, @AsientoTest, 1, 'Taquilla', 'Efectivo', @BoletoTest OUTPUT;
SELECT @BoletoTest AS BoletoVendido_Taquilla;

-- PERMITIDO 2: leer la vista de asientos disponibles
SELECT TOP (5) * FROM dbo.vw_AsientosDisponibles ORDER BY ViajeID, NumeroAsiento;

-- PERMITIDO 3: anular el boleto de prueba (deja la base como estaba)
EXEC dbo.sp_AnularBoleto @BoletoTest;

-- DENEGADO 1: leer la tabla directamente
BEGIN TRY SELECT TOP (5) * FROM dbo.Boletos;
END TRY BEGIN CATCH PRINT 'DENEGADO (taquilla, SELECT Boletos): ' + ERROR_MESSAGE(); END CATCH;

-- DENEGADO 2: borrar boletos directamente
BEGIN TRY DELETE FROM dbo.Boletos WHERE BoletoID = -1;
END TRY BEGIN CATCH PRINT 'DENEGADO (taquilla, DELETE Boletos): ' + ERROR_MESSAGE(); END CATCH;

-- DENEGADO 3: ver datos personales de clientes
BEGIN TRY SELECT TOP (5) Email, Telefono FROM dbo.Clientes;
END TRY BEGIN CATCH PRINT 'DENEGADO (taquilla, SELECT Clientes): ' + ERROR_MESSAGE(); END CATCH;

REVERT;
SELECT USER_NAME() AS UsuarioActual_DespuesDeRevert;
GO

/* ---------- 5.2 rol_reportes ---------- */
EXECUTE AS USER = 'u_reportes';
SELECT USER_NAME() AS UsuarioActual;

-- PERMITIDO 1: leer la vista de ventas
SELECT TOP (10) * FROM dbo.vw_VentasMensuales ORDER BY Anio, Mes, Origen, Destino;

-- PERMITIDO 2: agregar sobre la vista
SELECT Anio, SUM(Ingresos) AS IngresosAnio FROM dbo.vw_VentasMensuales GROUP BY Anio ORDER BY Anio;

-- DENEGADO 1: Email y Teléfono
BEGIN TRY SELECT TOP (5) Email, Telefono FROM dbo.Clientes;
END TRY BEGIN CATCH PRINT 'DENEGADO (reportes, Email/Telefono): ' + ERROR_MESSAGE(); END CATCH;

-- DENEGADO 2: tabla de boletos
BEGIN TRY SELECT TOP (5) * FROM dbo.Boletos;
END TRY BEGIN CATCH PRINT 'DENEGADO (reportes, SELECT Boletos): ' + ERROR_MESSAGE(); END CATCH;

-- DENEGADO 3: vender
BEGIN TRY DECLARE @x INT; EXEC dbo.sp_VenderBoleto 1, 1, 1, 'Web', 'Tarjeta', @x OUTPUT;
END TRY BEGIN CATCH PRINT 'DENEGADO (reportes, EXEC sp_VenderBoleto): ' + ERROR_MESSAGE(); END CATCH;

REVERT;
GO

/* ---------- 5.3 rol_admin ---------- */
EXECUTE AS USER = 'u_admin';
SELECT USER_NAME() AS UsuarioActual;

-- PERMITIDO 1: leer cualquier tabla
SELECT COUNT(*) AS TotalBoletos FROM dbo.Boletos;

-- PERMITIDO 2: administrar objetos
CREATE TABLE dbo.PruebaAdmin (Id INT);
DROP TABLE dbo.PruebaAdmin;
PRINT 'Admin pudo crear y borrar una tabla.';

REVERT;
GO

/* ---------- 6. Matriz de permisos efectivos (para el informe) ---------- */
SELECT dp.name AS Principal, p.permission_name AS Permiso, p.state_desc AS Estado,
       COALESCE(OBJECT_NAME(p.major_id), DB_NAME()) AS Objeto
FROM sys.database_permissions p
JOIN sys.database_principals dp ON dp.principal_id = p.grantee_principal_id
WHERE dp.name IN ('rol_taquilla','rol_reportes','rol_admin')
ORDER BY dp.name, Objeto;
GO
