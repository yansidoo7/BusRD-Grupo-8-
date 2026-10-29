USE BusRD;
GO
EXECUTE AS USER='u_taquilla';
IF COALESCE(HAS_PERMS_BY_NAME('dbo.sp_VenderBoleto','OBJECT','EXECUTE'),0)<>1
 OR COALESCE(HAS_PERMS_BY_NAME('dbo.sp_AnularBoleto','OBJECT','EXECUTE'),0)<>1
 OR COALESCE(HAS_PERMS_BY_NAME('dbo.vw_AsientosDisponibles','OBJECT','SELECT'),0)<>1
 THROW 51301,'Faltan permisos de taquilla.',1;
IF COALESCE(HAS_PERMS_BY_NAME('dbo.Boletos','OBJECT','SELECT'),0)<>0
 OR COALESCE(HAS_PERMS_BY_NAME('dbo.Boletos','OBJECT','DELETE'),0)<>0
 THROW 51302,'Taquilla tiene acceso directo a Boletos.',1;
REVERT;
GO
EXECUTE AS USER='u_reportes';
IF COALESCE(HAS_PERMS_BY_NAME('dbo.vw_VentasMensuales','OBJECT','SELECT'),0)<>1
 THROW 51303,'Reportes no puede leer la vista.',1;
IF COALESCE(HAS_PERMS_BY_NAME('dbo.Clientes','OBJECT','SELECT','Email','COLUMN'),0)<>0
 OR COALESCE(HAS_PERMS_BY_NAME('dbo.Clientes','OBJECT','SELECT','Telefono','COLUMN'),0)<>0
 OR COALESCE(HAS_PERMS_BY_NAME('dbo.sp_VenderBoleto','OBJECT','EXECUTE'),0)<>0
 THROW 51304,'Reportes tiene permisos indebidos.',1;
REVERT;
GO
EXECUTE AS USER='u_admin';
IF COALESCE(HAS_PERMS_BY_NAME('BusRD','DATABASE','CONTROL'),0)<>1
 THROW 51305,'Admin no tiene CONTROL sobre BusRD.',1;
REVERT;
GO
