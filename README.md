# BusRD — Grupo 8 · ISW-323

## Integrantes registrados

| Nombre | Matrícula |
|---|---|
| Yansiel Elías Silvestre Peña | A00157619 |
| José Manuel Carvajal Florentino | A00156381 |

La consigna indica grupos de tres (máximo cuatro). Confirmar autorización si el grupo tiene dos integrantes.

## Configuración y estado real

- Grupo: **8**.
- Cliente C2: **8000**, cédula **40200008000**.
- Viaje de prueba predeterminado: **16400**. **No es una asignación confirmada del docente.** Cambiar `scripts/00_configuracion.sql` o pasar el viaje al validador.
- Revisión basada en commit `8ffb466bf43e133bf75a0b27df3403a70838c214`.
- Validación ejecutada satisfactoriamente en SQL Server 2022 mediante GitHub Actions. Se usó el viaje 16400, elegido provisionalmente por el grupo. Ver `REVISION.md`.
- No se han generado métricas, planes, capturas ni restauraciones ficticias.

## Validación completa desde terminal

Requisitos: Docker en funcionamiento, Python 3 con venv y acceso a Internet. No requiere SSMS ni DBeaver. La instancia Docker es desechable y se elimina al terminar. Los registros quedan en `evidencias/FECHA-HORA/`.

```bash
# 16400 es un ejemplo para probar; sustituir por la asignación real.
./validacion/docker-terminal.sh 16400
```

El comando descarga SQL Server 2022 Developer, carga los scripts originales, captura la línea base, reproduce la doble venta en conexiones distintas, instala las correcciones, comprueba bloqueo/rechazo, atomicidad, anulación/reventa, equivalencia de consultas, permisos y restauración STOPAT. Cualquier error no esperado termina la validación con salida distinta de cero. El proceso puede tardar varios minutos.

Para una instancia SQL Server 2022 de pruebas ya disponible, sin Docker:

```bash
python3 -m venv .venv
. .venv/bin/activate
pip install -r validacion/requirements.txt
export BUSRD_HOST=127.0.0.1
export BUSRD_PORT=1433
export BUSRD_USER=sa
read -rs -p 'Contraseña SQL: ' BUSRD_PASSWORD; echo
export BUSRD_PASSWORD
python validacion/validar.py --recrear-base-pruebas --viaje 16400
```

**Ese último comando borra/recrea BusRD y BusRD_Recuperada en la instancia indicada. Usar exclusivamente una instancia de laboratorio.** No apuntar a producción. La cuenta necesita crear bases, respaldar/restaurar y ejecutar pruebas con usuarios impersonados.

## Orden manual por bloques SQL

1. `recursos/01_BusRD_base.sql`, `scripts/00_configuracion.sql`, `recursos/02_sp_VenderBoleto_v0.sql`.
2. Consultas originales para línea base con parámetros del grupo.
3. Bloque 1 de `04_demo_concurrencia_sesionA.sql` y bloque 1 de `05_demo_concurrencia_sesionB.sql` en otra conexión durante los diez segundos de demora. Capturar doble venta.
4. `01_integridad.sql`, `02_sp_VenderBoleto.sql`, `03_sp_AnularBoleto.sql`.
5. Bloque 2 de las sesiones A y B. Capturar espera y rechazo de B.
6. `06_indices_y_consultas_optimizadas.sql`, `07_seguridad.sql` y `08_respaldo_y_restauracion.sql`.

Las demos son interactivas: no ejecutar todos los bloques de A antes de abrir B. El validador automatiza sus pruebas equivalentes con dos conexiones y el mismo asiento fijado previamente.

## Entrega académica pendiente

Se requieren informe PDF (máximo diez páginas sin portada/anexos), capturas numeradas y la exposición de 15–20 minutos. Los registros de terminal y planes XML son evidencia técnica complementaria; confirmar con el docente cómo presentarlos en lugar de las capturas de SSMS que especifica la consigna.

El administrador tiene CONTROL completo de la base. La exigencia de dos accesos denegados *por rol* es ambigua para ese rol; documentar su alcance o aclararla con el docente. No se agregan restricciones contradictorias ni se inventan denegaciones.
