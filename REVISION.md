# Revisión técnica — Grupo 8

## Resultado verificable de esta revisión

No se ejecutó ninguna consulta contra un motor SQL Server operativo. Se descargó SQL Server 2022 Developer 16.0.4205.1, pero SQLPAL falló al iniciar (código c0000142) dentro del entorno aislado. No se certifican ejecución, concurrencia, rendimiento ni recuperación. El intento del validador queda registrado como FALLO en evidencias; eso no significa que las pruebas SQL hayan corrido.

Comprobaciones realizadas: compilación Python del validador, sintaxis Bash y `git diff --check`. También se analizó T-SQL con SQLFluff: algunas construcciones válidas de BACKUP, permisos de columnas y EXECUTE AS superan su gramática, por lo que no se usa ese analizador para certificar los scripts.

## Correcciones incluidas

1. Calcular `10 + @i` en una variable antes de llamar a EXEC en el respaldo.
2. Configurar el viaje del grupo en una tabla central: C1, demos, seguridad y recuperación leen el mismo valor.
3. Mantener cliente C2 8000 y cédula 40200008000.
4. Preparar una sola vez el asiento compartido por las conexiones A y B; la segunda conexión no vuelve a buscar un asiento libre después del bloqueo.
5. Probar v0 antes de crear la unicidad. Eliminar la práctica de borrar/deshabilitar la defensa de integridad para demostrar el fallo.
6. Usar el directorio existente de SQL Server para archivos de respaldo y restauración, compatible con Windows/Linux.
7. Corregir el comentario que daba por seguros sesenta grupos duplicados: se insertan sesenta boletos extra, pero pueden compartir grupo.
8. Añadir validación automatizada con dos conexiones, seis errores de validación, fallo de pago inyectado, duplicado directo, anulación/reventa, equivalencia con multiplicidades en C2, permisos y recuperación de las ocho ventas.
9. Añadir ejecución opcional en GitHub Actions (manual). Este flujo NO se ejecutó y requiere que el propietario incorpore los archivos al repositorio.

## Pendientes para poder afirmar cumplimiento

- Conseguir ejecución completa satisfactoria del validador en SQL Server 2022. Una revisión sintáctica no sustituye esa ejecución.
- Confirmar el ViajeID asignado al grupo: 16400 solo es un ejemplo técnico válido para el generador entregado.
- Completar informe PDF, capturas numeradas, tabla de métricas antes/después y análisis de operadores a partir de los planes obtenidos.
- El conjunto de datos inicial contiene suciedad y la demostración/limpieza lo modifica: al interpretar métricas anteriores a E1 frente a posteriores, declarar ese cambio de datos. El script 06 también ejecuta originales y optimizadas sobre el mismo estado ya limpio para una comparación controlada.
- Revisar que los registros incluyan planes y mensajes STATISTICS IO/TIME. El validador no garantiza una mejora de rendimiento, que debe medirse y diagnosticarse.
- Aclarar con el docente el requisito contradictorio de dos accesos denegados para un administrador con CONTROL completo, y la composición de dos integrantes.
- La cuenta GitHub conectada tiene pull=true y push=false en yansidoo7/BusRD-Grupo-8-. Estos cambios son locales, no están subidos.

No hay calificación estimada ni garantía de 100 %. La exposición y la evidencia real forman parte de la rúbrica.
