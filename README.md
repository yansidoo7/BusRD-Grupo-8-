BusRD – Trabajo Final ISW-323 (Taller de Base de Datos III)
Integrantes
Nombre	Apellidos	ID
Yansiel Elias	Silvestre Peña	A00157619
JOSE MANUEL	CARVAJAL FLORENTINO	A00156381
		
Datos asignados al grupo
Grupo N°: 8
Viaje asignado (C1, demo y respaldo): (Santo Domingo, `ViajeID`)
Cédula usada en C2: 40200008000 (cliente N° 8000 = grupo 8 × 1000)
Requisitos
SQL Server 2022 (Developer/Express) + SSMS. Carpeta `C:\\Backups\\BusRD\\` con permiso de escritura para el servicio de SQL Server.
Orden de ejecución
Paso	Script	Qué hace
0	`01\_BusRD\_base.sql` (del docente)	Crea la base y los datos (1–3 min)
0	`02\_sp\_VenderBoleto\_v0.sql`, `03\_consultas\_lentas.sql` (del docente)	Procedimiento defectuoso y consultas lentas (línea base)
1	`scripts/01\_integridad.sql`	Detecta y limpia datos sucios; FKs, CHECK, unicidades, índice único filtrado
2	`scripts/02\_sp\_VenderBoleto.sql`	Procedimiento de venta seguro (transacción + UPDLOCK/HOLDLOCK)
3	`scripts/03\_sp\_AnularBoleto.sql`	Anulación con reverso de pago negativo
4	`scripts/04\_demo\_concurrencia\_sesionA.sql`	Demo de doble venta (v0) y bloqueo (nuevo) – ventana A
5	`scripts/05\_demo\_concurrencia\_sesionB.sql`	Ídem – ventana B (ejecutar a menos de 10 s de A)
6	`scripts/06\_indices\_y\_consultas\_optimizadas.sql`	Índices, consultas reescritas, comparación y efecto en escrituras
7	`scripts/07\_seguridad.sql`	Roles, vistas, usuarios de prueba y pruebas permitido/denegado
8	`scripts/08\_respaldo\_y\_restauracion.sql`	FULL → DIFF → LOG → tail-log → restauración con STOPAT
> Los scripts 4 y 5 se ejecutan manualmente en dos ventanas de SSMS (ver comentarios dentro de cada archivo).
> El script 4 elimina temporalmente el índice único para reproducir el problema y lo vuelve a crear.
Evidencias
Capturas numeradas en `evidencias/` (ver lista en la guía).
